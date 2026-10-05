import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'audio_pcm_decoder.dart';
import 'bpm_detector.dart';
import 'id3_tag_writer.dart';
import 'log_service.dart';
import 'music_library_service.dart';
import 'music_online_metadata.dart';

/// What the enricher has already done for one track, persisted so a song
/// is looked up / analyzed once, not on every launch.
class EnrichmentEntry {
  EnrichmentEntry({
    this.onlineAt,
    this.found,
    this.detectedAt,
    this.detectedBpm,
    this.taggedAt,
    this.tagFailures = 0,
  });

  /// When the online lookup ran (ms since epoch); null = not yet.
  int? onlineAt;

  /// What it found (null/empty = no match).
  OnlineTrackMetadata? found;

  /// When on-device BPM detection ran; null = not yet.
  int? detectedAt;
  int? detectedBpm;

  /// When what's known was written into the file's own tags (or found not
  /// writable, e.g. not an mp3); null = still to do. Reset whenever new
  /// data arrives.
  int? taggedAt;

  /// Failed write attempts (I/O errors) — given up after
  /// [MusicMetadataEnricher.maxTagFailures].
  int tagFailures;

  bool get hasData => (found != null && !found!.isEmpty) || detectedBpm != null;

  Map<String, dynamic> toJson() => {
        if (onlineAt != null) 'onlineAt': onlineAt,
        if (found != null && !found!.isEmpty) 'found': found!.toJson(),
        if (detectedAt != null) 'detectedAt': detectedAt,
        if (detectedBpm != null) 'detectedBpm': detectedBpm,
        if (taggedAt != null) 'taggedAt': taggedAt,
        if (tagFailures != 0) 'tagFailures': tagFailures,
      };

  factory EnrichmentEntry.fromJson(Map<String, dynamic> json) => EnrichmentEntry(
        onlineAt: (json['onlineAt'] as num?)?.round(),
        found: json['found'] is Map
            ? OnlineTrackMetadata.fromJson(
                Map<String, dynamic>.from(json['found'] as Map))
            : null,
        detectedAt: (json['detectedAt'] as num?)?.round(),
        detectedBpm: (json['detectedBpm'] as num?)?.round(),
        taggedAt: (json['taggedAt'] as num?)?.round(),
        tagFailures: (json['tagFailures'] as num?)?.round() ?? 0,
      );

  /// Everything this entry knows, as one gap-fill for
  /// [MusicLibraryService.fillMissingMetadata] — a detected BPM only when
  /// the online lookup didn't have one.
  OnlineTrackMetadata get fill {
    final f = found;
    return OnlineTrackMetadata(
      title: f?.title,
      artist: f?.artist,
      album: f?.album,
      genre: f?.genre,
      year: f?.year,
      bpm: f?.bpm ?? detectedBpm,
    );
  }
}

/// Best Music's hands-off metadata filler. Runs entirely in the background
/// once [start]ed (see `main_music.dart`): whenever the library changes
/// (launch, rescan, a finished download) it
/// 1. looks every song with a missing artist/album/genre/year/BPM up
///    online ([MusicOnlineMetadataLookup] — Deezer, iTunes, MusicBrainz),
///    one song at a time, and fills in only the gaps;
/// 2. then, if online sources left fewer than [bpmCoverageTarget] (90%) of
///    the songs with a BPM, analyzes the rest on the device itself
///    ([AudioPcmDecoder] + [estimateBpm] in a background isolate).
///
/// Results live in `music_enrichment.json` and are re-applied after every
/// rescan, so each song is only ever looked up/analyzed once (a song with
/// no online match is retried after [retryAfter]). Offline or rate-limited
/// → pauses and tries again [offlineRetry] later. [status] is a one-line
/// summary for the Metadata Scan page.
class MusicMetadataEnricher {
  MusicMetadataEnricher({
    MusicLibraryService? library,
    MusicOnlineMetadataLookup? lookup,
    Future<int?> Function(Track track)? detectBpm,
    Future<Id3WriteResult> Function(String path, Id3Fields fields)? writeTags,
    Future<Directory> Function()? storageDir,
    Future<void> Function()? initialRescan,
    this.debounce = const Duration(seconds: 3),
    this.offlineRetry = const Duration(minutes: 15),
  })  : _library = library ?? MusicLibraryService.instance,
        _lookupOverride = lookup,
        _detectBpm = detectBpm ?? _defaultDetectBpm,
        _writeTags = writeTags ?? Id3TagWriter.addMissing,
        _storageDir = storageDir ?? getApplicationDocumentsDirectory,
        _initialRescan = initialRescan;

  static final MusicMetadataEnricher instance = MusicMetadataEnricher();

  static const String fileName = 'music_enrichment.json';
  static const double bpmCoverageTarget = 0.9;
  static const Duration retryAfter = Duration(days: 30);

  final MusicLibraryService _library;
  final MusicOnlineMetadataLookup? _lookupOverride;
  MusicOnlineMetadataLookup? _defaultLookup;
  MusicOnlineMetadataLookup get _lookup =>
      _lookupOverride ?? (_defaultLookup ??= MusicOnlineMetadataLookup());
  final Future<int?> Function(Track track) _detectBpm;
  final Future<Id3WriteResult> Function(String path, Id3Fields fields)
      _writeTags;
  static const int maxTagFailures = 3;
  final Future<Directory> Function() _storageDir;
  final Future<void> Function()? _initialRescan;

  /// Marker file: the one-time rescan after 0.3.9's ID3 read fix (before
  /// it, every cached track was missing its tags) has been done.
  static const String rescanMarker = 'music_enrichment_rescan_v1';
  final Duration debounce;
  final Duration offlineRetry;

  final ValueNotifier<String> status = ValueNotifier<String>('');
  final Map<String, EnrichmentEntry> _entries = {};
  bool _loaded = false;
  bool _started = false;
  bool _running = false;
  bool _rerun = false;
  bool _applying = false;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Completer<void>? _idle;

  @visibleForTesting
  Map<String, EnrichmentEntry> get entries => _entries;

  /// Begins watching the library and works through it in the background.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    await _rescanOnceAfterTagFix();
    await _applyCache();
    _library.tracks.addListener(_onLibraryChanged);
    _schedule(Duration.zero);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _library.tracks.removeListener(_onLibraryChanged);
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
  }

  /// Completes once the current (and any queued) pass is done. For tests.
  @visibleForTesting
  Future<void> whenIdle() async {
    while (_running || (_debounceTimer?.isActive ?? false)) {
      _idle ??= Completer<void>();
      await _idle!.future;
    }
  }

  void _onLibraryChanged() {
    if (_applying || !_started) return;
    // A rescan rebuilds every Track from the file tags: put back what was
    // already found before anyone notices it gone, then look at new songs.
    unawaited(_applyCache());
    _schedule(debounce);
  }

  void _schedule(Duration delay) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () => unawaited(_run()));
  }

  static bool _eligible(Track t) =>
      t.source == TrackSource.local && (t.filePath?.isNotEmpty ?? false);

  static Set<MetadataField> missingFields(Track t) => {
        if (t.artist.isEmpty) MetadataField.artist,
        if (t.album.isEmpty) MetadataField.album,
        if (t.genre.isEmpty) MetadataField.genre,
        if (t.year == null) MetadataField.year,
        if (t.bpm == null) MetadataField.bpm,
      };

  bool _due(int? doneAt, {required bool hadResult}) {
    if (doneAt == null) return true;
    if (hadResult) return false;
    return DateTime.now().millisecondsSinceEpoch - doneAt >
        retryAfter.inMilliseconds;
  }

  bool _needsOnline(Track t) {
    if (!_eligible(t) || missingFields(t).isEmpty) return false;
    final e = _entries[t.id];
    return _due(e?.onlineAt, hadResult: e?.found != null);
  }

  bool _needsDetection(Track t) {
    if (!_eligible(t) || t.bpm != null) return false;
    final e = _entries[t.id];
    return _due(e?.detectedAt, hadResult: e?.detectedBpm != null);
  }

  Future<void> _run() async {
    if (!_started) return;
    if (_running) {
      _rerun = true;
      return;
    }
    _running = true;
    try {
      var paused = false;
      do {
        _rerun = false;
        paused = !await _onlinePass();
        if (paused || !_started) break;
        await _bpmPass();
        if (!_started) break;
        await _tagPass();
      } while (_rerun && _started);
      // Keep the "paused" line up until the retry.
      if (!paused) _updateSummary();
    } catch (e, st) {
      debugPrint('MusicMetadataEnricher: $e\n$st');
      LogService.add('Music', 'enricher failed: $e');
    } finally {
      _running = false;
      if (!(_debounceTimer?.isActive ?? false)) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Returns false when it had to stop early (offline / rate-limited).
  Future<bool> _onlinePass() async {
    final todo = _library.tracks.value.where(_needsOnline).toList();
    if (todo.isEmpty) return true;
    LogService.add('Music', 'enricher: looking up ${todo.length} song(s) online');
    final pending = <String, OnlineTrackMetadata>{};
    var found = 0;
    for (var i = 0; i < todo.length; i++) {
      if (!_started) break;
      // The library may have been rescanned/edited meanwhile.
      final track = _library.byId(todo[i].id);
      if (track == null || !_needsOnline(track)) continue;
      status.value = 'Looking up song info online… ${i + 1}/${todo.length}';
      final OnlineTrackMetadata result;
      try {
        result = await _lookup.lookup(
          TrackQuery(
            title: track.title.isNotEmpty ? track.title : track.fileBaseName,
            artist: track.artist,
            durationMs: track.durationMs,
          ),
          missingFields(track),
        );
      } on MetadataLookupUnavailable catch (e) {
        LogService.add('Music', 'enricher: paused — $e');
        status.value = 'Song info lookup paused (offline?) — retrying soon';
        await _flush(pending);
        _retryTimer?.cancel();
        _retryTimer = Timer(offlineRetry, () => _schedule(Duration.zero));
        return false;
      }
      final entry = _entries.putIfAbsent(track.id, EnrichmentEntry.new);
      entry.onlineAt = DateTime.now().millisecondsSinceEpoch;
      entry.found = result.isEmpty ? null : result;
      entry.taggedAt = null;
      if (!result.isEmpty) {
        found++;
        pending[track.id] = entry.fill;
      }
      if (pending.length >= 10 || (i + 1) % 10 == 0) await _flush(pending);
    }
    await _flush(pending);
    LogService.add('Music',
        'enricher: online lookup done — matched $found of ${todo.length}');
    return true;
  }

  Future<void> _bpmPass() async {
    final eligible = _library.tracks.value.where(_eligible).toList();
    if (eligible.isEmpty) return;
    final withBpm = eligible.where((t) => t.bpm != null).length;
    if (withBpm / eligible.length >= bpmCoverageTarget) return;
    final todo = eligible.where(_needsDetection).toList();
    if (todo.isEmpty) return;
    LogService.add(
        'Music',
        'enricher: only $withBpm of ${eligible.length} songs have a BPM — '
            'detecting ${todo.length} on device');
    final pending = <String, OnlineTrackMetadata>{};
    var detected = 0;
    for (var i = 0; i < todo.length; i++) {
      if (!_started) break;
      final track = _library.byId(todo[i].id);
      if (track == null || !_needsDetection(track)) continue;
      status.value = 'Detecting BPM on device… ${i + 1}/${todo.length}';
      int? bpm;
      try {
        bpm = await _detectBpm(track);
      } catch (_) {
        bpm = null;
      }
      final entry = _entries.putIfAbsent(track.id, EnrichmentEntry.new);
      entry.detectedAt = DateTime.now().millisecondsSinceEpoch;
      entry.detectedBpm = bpm;
      entry.taggedAt = null;
      if (bpm != null) {
        detected++;
        pending[track.id] = entry.fill;
      }
      if (pending.length >= 10 || (i + 1) % 10 == 0) await _flush(pending);
    }
    await _flush(pending);
    LogService.add('Music',
        'enricher: BPM detected on device for $detected of ${todo.length}');
  }

  /// Writes what was found into each file's own tags (fill-only — see
  /// [Id3TagWriter]), using the library's current value for every field
  /// the enricher supplied, so the file agrees with what the app shows.
  Future<void> _tagPass() async {
    var written = 0;
    var dirty = false;
    for (final track in List<Track>.of(_library.tracks.value)) {
      if (!_started) break;
      final entry = _entries[track.id];
      final path = track.filePath;
      if (entry == null ||
          path == null ||
          !_eligible(track) ||
          !entry.hasData ||
          entry.taggedAt != null ||
          entry.tagFailures >= maxTagFailures) {
        continue;
      }
      final fill = entry.fill;
      final result = await _writeTags(
        path,
        Id3Fields(
          title: fill.title != null && track.title == fill.title
              ? track.title
              : null,
          artist: fill.artist != null ? track.artist : null,
          album: fill.album != null ? track.album : null,
          genre: fill.genre != null ? track.genre : null,
          year: fill.year != null ? track.year : null,
          bpm: fill.bpm != null ? track.bpm : null,
        ),
      );
      dirty = true;
      if (result == Id3WriteResult.failed) {
        entry.tagFailures++;
      } else {
        entry.taggedAt = DateTime.now().millisecondsSinceEpoch;
        if (result == Id3WriteResult.written) written++;
      }
    }
    if (dirty) await _save();
    if (written > 0) {
      LogService.add('Music', 'enricher: wrote tags into $written file(s)');
    }
  }

  void _updateSummary() {
    final eligible = _library.tracks.value.where(_eligible).toList();
    if (eligible.isEmpty) {
      status.value = '';
      return;
    }
    final withBpm = eligible.where((t) => t.bpm != null).length;
    final complete = eligible.where((t) => missingFields(t).isEmpty).length;
    status.value = 'Song info filled in automatically — $complete of '
        '${eligible.length} complete, $withBpm with a BPM';
  }

  Future<void> _flush(Map<String, OnlineTrackMetadata> pending) async {
    await _save();
    if (pending.isEmpty) return;
    final batch = Map<String, OnlineTrackMetadata>.of(pending);
    pending.clear();
    _applying = true;
    try {
      await _library.fillMissingMetadata(batch);
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyCache() async {
    if (_entries.isEmpty) return;
    final fills = <String, OnlineTrackMetadata>{};
    for (final t in _library.tracks.value) {
      final e = _entries[t.id];
      if (e == null || missingFields(t).isEmpty) continue;
      fills[t.id] = e.fill;
    }
    if (fills.isEmpty) return;
    _applying = true;
    try {
      await _library.fillMissingMetadata(fills);
    } finally {
      _applying = false;
    }
  }

  /// Libraries scanned before 0.3.9 never had their tags read; rescan once
  /// so the files' own tags are used before anything is looked up online.
  Future<void> _rescanOnceAfterTagFix() async {
    try {
      final marker = File('${(await _storageDir()).path}/$rescanMarker');
      if (await marker.exists()) return;
      await marker.writeAsString('1', flush: true);
      if (_library.tracks.value.isEmpty || _library.scanning) return;
      LogService.add('Music', 'enricher: one-time rescan to read ID3 tags');
      await (_initialRescan ?? _library.rescan)();
    } catch (_) {}
  }

  Future<File> _file() async => File('${(await _storageDir()).path}/$fileName');

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      data.forEach((key, value) {
        if (value is Map) {
          _entries['$key'] =
              EnrichmentEntry.fromJson(Map<String, dynamic>.from(value));
        }
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
          jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
          flush: true);
    } catch (_) {}
  }

  static const AudioPcmDecoder _decoder = AudioPcmDecoder();

  /// Decodes 45 s from 30 s in (past most intros; the decoder slides the
  /// window back for shorter songs) and estimates the tempo off the UI
  /// isolate.
  static Future<int?> _defaultDetectBpm(Track track) async {
    final path = track.filePath;
    if (path == null) return null;
    final duration = track.durationMs;
    final start = duration != null && duration < 75000 ? 0 : 30000;
    final pcm = await _decoder.decode(path, startMs: start, durationMs: 45000);
    if (pcm == null || pcm.length < AudioPcmDecoder.sampleRate * 8) return null;
    return compute(estimateBpmMessage, <Object>[pcm, AudioPcmDecoder.sampleRate]);
  }

  @visibleForTesting
  void resetForTest() {
    stop();
    _entries.clear();
    _loaded = false;
    _running = false;
    _rerun = false;
    status.value = '';
  }
}
