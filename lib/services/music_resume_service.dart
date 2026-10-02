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
  });

  final List<String> queueIds;
  final int index;
  final Duration position;

  /// Full copy of the track at [index], so the last-played song can still
  /// be shown (and played) even if it isn't in the cached library.
  final Track? current;

  Map<String, dynamic> toJson() => {
        'queue': queueIds,
        'index': index,
        'positionMs': position.inMilliseconds,
        if (current != null) 'current': current!.toJson(),
      };

  static MusicResumeState? fromJson(Map<String, dynamic> json) {
    final ids = (json['queue'] as List?)?.whereType<String>().toList() ?? [];
    final currentJson = json['current'];
    final current = currentJson is Map
        ? Track.fromJson(Map<String, dynamic>.from(currentJson))
        : null;
    if (ids.isEmpty && current == null) return null;
    return MusicResumeState(
      queueIds: ids,
      index: (json['index'] as num?)?.round() ?? 0,
      position: Duration(
          milliseconds: (json['positionMs'] as num?)?.round() ?? 0),
      current: current,
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

  static Future<void> save(MusicResumeState state) {
    _pending = _pending.then((_) async {
      try {
        final file = await _file();
        await file.writeAsString(jsonEncode(state.toJson()), flush: true);
      } catch (_) {}
    });
    return _pending;
  }

  static Future<MusicResumeState?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return null;
      return MusicResumeState.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }
}
