import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// What was playing when the app last saved: the queue (by track id), the
/// position in it and how far into that track.
class MusicResumeState {
  const MusicResumeState({
    required this.queueIds,
    required this.index,
    required this.position,
    this.current,
    this.tracks,
  });

  final List<String> queueIds;
  final int index;
  final Duration position;

  /// Full copy of the track at [index], so the last-played song can still
  /// be shown (and played) even if it isn't in the cached library.
  final Track? current;

  /// Full copies of the whole queue — set for a Subscriptions-video
  /// session, whose videos aren't in the library for [queueIds] to be
  /// looked up in. Music sessions leave it null (a shuffled library queue
  /// can be thousands of tracks; ids keep the file small).
  final List<Track>? tracks;

  Map<String, dynamic> toJson() => {
        'queue': queueIds,
        'index': index,
        'positionMs': position.inMilliseconds,
        if (current != null) 'current': current!.toJson(),
        if (tracks != null) 'tracks': [for (final t in tracks!) t.toJson()],
      };

  static MusicResumeState? fromJson(Map<String, dynamic> json) {
    final ids = (json['queue'] as List?)?.whereType<String>().toList() ?? [];
    final currentJson = json['current'];
    final current = currentJson is Map
        ? Track.fromJson(Map<String, dynamic>.from(currentJson))
        : null;
    final tracksJson = json['tracks'];
    final tracks = tracksJson is List
        ? [
            for (final t in tracksJson)
              if (t is Map) Track.fromJson(Map<String, dynamic>.from(t)),
          ]
        : null;
    if (ids.isEmpty && current == null) return null;
    return MusicResumeState(
      queueIds: ids,
      index: (json['index'] as num?)?.round() ?? 0,
      position: Duration(
          milliseconds: (json['positionMs'] as num?)?.round() ?? 0),
      current: current,
      tracks: tracks,
    );
  }
}

/// Persists the Music Player's last queue/track/position to
/// `music_resume.json` in the app documents dir, so the mini player can
/// offer "play where you left off" after an app restart, a phone reboot or
/// an app update (the documents dir survives all three). Errors are
/// swallowed like the other music stores — tests and platforms without a
/// documents dir just don't remember anything.
class MusicResumeService {
  MusicResumeService._();

  static const fileName = 'music_resume.json';

  /// Writes are chained so a frequent position save can never interleave
  /// with (and truncate) the previous one.
  static Future<void> _pending = Future.value();

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Saves the active session ([state]) and, if any, the *other* kind's
  /// paused session ([other]: the last song while a video plays, or the
  /// last video while music plays) for the one-tap switch back.
  static Future<void> save(MusicResumeState state, {MusicResumeState? other}) {
    _pending = _pending.then((_) async {
      try {
        final file = await _file();
        await file.writeAsString(
            jsonEncode({
              ...state.toJson(),
              if (other != null) 'other': other.toJson(),
            }),
            flush: true);
      } catch (_) {}
    });
    return _pending;
  }

  static Future<Map<String, dynamic>?> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<MusicResumeState?> load() async {
    final data = await _read();
    return data == null ? null : MusicResumeState.fromJson(data);
  }

  /// The other kind's session saved by [save], if any.
  static Future<MusicResumeState?> loadOther() async {
    final other = (await _read())?['other'];
    return other is Map
        ? MusicResumeState.fromJson(Map<String, dynamic>.from(other))
        : null;
  }
}
