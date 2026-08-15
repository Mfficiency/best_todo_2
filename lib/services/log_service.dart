import 'dart:async' show unawaited;
import 'dart:io' show File, FileMode;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Simple logger for app interactions, widget taps and render diagnostics.
///
/// Entries live in [logs] for the App Logs page **and** are appended to
/// `app_log.txt` in the application documents directory. The file is what
/// makes the log useful for the widget black-screen bug: the only way out of
/// that state is a force-close, which used to take the in-memory log with it —
/// the evidence was destroyed by the very act of recovering. Now the next
/// launch restores it ([restore]) and the page can hand the whole file over
/// with the copy button.
class LogService {
  // ValueNotifier so UI can listen to log updates.
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>(<String>[]);

  static const String fileName = 'app_log.txt';

  /// Trim the file when it grows past [_maxBytes], keeping the newest
  /// [_keepBytes] — same approach as the alarm log.
  static const int _maxBytes = 256 * 1024;
  static const int _keepBytes = 160 * 1024;

  /// How many of the file's trailing lines come back into the in-memory list
  /// on [restore]. Enough to cover the launch before the force-close.
  static const int _restoreLines = 400;

  /// Writes are chained so concurrent adds can't interleave half-written
  /// lines, exactly like the alarm log.
  static Future<void> _pending = Future<void>.value();
  static bool _checkedTrim = false;

  /// Set once [restore] has run, so it can't double-load the file.
  static bool _restored = false;

  /// Add a log entry with a timestamp and source.
  static void add(String source, String message) {
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    final cutoff = now.subtract(const Duration(days: 1));

    // Keep only entries from the last 24 hours before adding the new one.
    final recent = logs.value.where((entry) {
      final spaceIndex = entry.indexOf(' ');
      if (spaceIndex == -1) return false;
      final entryTime = DateTime.tryParse(entry.substring(0, spaceIndex));
      return entryTime != null && !entryTime.isBefore(cutoff);
    });

    final line = '$timestamp [$source] $message';
    logs.value = List<String>.from(recent)..add(line);
    debugPrint('APPLOG $line');
    unawaited(_append('$line\n'));
  }

  /// Clear all log entries, in memory and on disk.
  static void clear() {
    logs.value = <String>[];
    unawaited(_pending = _pending.then((_) async {
      try {
        final file = await _file();
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    }));
  }

  /// Pulls the tail of `app_log.txt` back into [logs], so the page opens
  /// showing what happened before the last force-close/crash. Called once at
  /// startup; entries already added in this run stay newest-last.
  static Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final lines = (await file.readAsString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final tail = lines.length > _restoreLines
          ? lines.sublist(lines.length - _restoreLines)
          : lines;
      if (tail.isEmpty) return;
      // Entries this run already added are in the file too (the restore
      // reads the file after the first frame, by which time the home page
      // has logged its load) — keep them once.
      final live = logs.value.toSet();
      final older = tail.where((line) => !live.contains(line)).toList();
      if (older.isEmpty) return;
      logs.value = <String>[...older, ...logs.value];
    } catch (_) {}
  }

  /// Full file contents — what the copy button on the App Logs page shares.
  /// Falls back to the in-memory list when the file is unavailable (web,
  /// tests, storage error).
  static Future<String> readFile() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) return await file.readAsString();
    } catch (_) {}
    return logs.value.join('\n');
  }

  /// Completes once every queued write has hit the disk. Tests await this;
  /// the app never needs to, adds are fire-and-forget by design.
  @visibleForTesting
  static Future<void> flush() => _pending;

  /// Test hook: forget that the file was already restored.
  @visibleForTesting
  static void resetForTest() {
    logs.value = <String>[];
    _restored = false;
    _checkedTrim = false;
  }

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _append(String text) {
    _pending = _pending.then((_) async {
      try {
        final file = await _file();
        if (file == null) return;
        if (!_checkedTrim) {
          _checkedTrim = true;
          await _trimIfNeeded(file);
        }
        await file.writeAsString(text, mode: FileMode.append, flush: true);
      } catch (_) {
        // Logging must never break what it is logging about.
      }
    });
    return _pending;
  }

  static Future<void> _trimIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      if (await file.length() <= _maxBytes) return;
      final content = await file.readAsString();
      var cut = content.length - _keepBytes;
      final nl = content.indexOf('\n', cut);
      if (nl != -1) cut = nl + 1;
      await file.writeAsString(
        '(older entries trimmed)\n${content.substring(cut)}',
        flush: true,
      );
    } catch (_) {}
  }
}
