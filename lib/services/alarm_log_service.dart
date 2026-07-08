import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent, human-readable log of everything the alarm pipeline does.
///
/// Written to `alarm_log.txt` in the application documents directory so it
/// survives app restarts, process kills and reboots — when an alarm doesn't
/// ring, this file is the record of which step failed and why. Viewable (and
/// copyable) in-app from Alarms → log icon.
///
/// Levels:
///   OK    the step worked
///   FAIL  the step failed — the message says what and, where known, how to fix it
///   WARN  suspicious state that can make alarms unreliable
///   INFO  context (device, versions, what is being attempted)
///
/// Stages (second column) group entries by pipeline step:
///   ENV       device / OS / app state
///   PERM      permission checks and requests
///   SCHEDULE  handing alarms to the OS
///   VERIFY    confirming the OS actually accepted them
///   BACKUP    the independent watchdog delivery path
///   FIRE      alarm delivery time — did it actually ring?
///   ACTION    user interaction (tap / snooze / dismiss)
///
/// Safe to call from background isolates (widget toggles, alarm callbacks,
/// notification action handlers): each isolate appends to the same file.
class AlarmLog {
  AlarmLog._();

  static const String _fileName = 'alarm_log.txt';

  // Trim the file when it grows past _maxBytes, keeping the newest _keepBytes.
  static const int _maxBytes = 400 * 1024;
  static const int _keepBytes = 250 * 1024;

  static const String _header = '''
BestToDo ALARM LOG — how to read this file
  [OK]   step worked        [FAIL] step failed (message says why + fix)
  [WARN] risky state        [INFO] context
  Stages: ENV device/OS · PERM permissions · SCHEDULE handing alarms to the OS
          VERIFY OS accepted them · BACKUP watchdog path · FIRE delivery · ACTION user input
  If an alarm did not ring, look for [FAIL]/[WARN] lines around its time.
''';

  /// Bumped after every write so the in-app viewer can live-refresh.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // Writes are chained on this future so concurrent log calls within one
  // isolate can't interleave half-written lines.
  static Future<void> _pending = Future<void>.value();
  static bool _checkedTrim = false;

  static Future<File?> _file() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  /// Absolute path of the log file (for display in the viewer), or null when
  /// unavailable on this platform.
  static Future<String?> path() async => (await _file())?.path;

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _timestamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';

  static Future<void> _append(String text) {
    _pending = _pending.then((_) async {
      try {
        final file = await _file();
        if (file == null) return;
        if (!_checkedTrim) {
          _checkedTrim = true;
          await _trimIfNeeded(file);
        }
        if (!await file.exists()) {
          await file.writeAsString(_header, flush: true);
        }
        await file.writeAsString(text, mode: FileMode.append, flush: true);
        revision.value++;
      } catch (_) {
        // Logging must never break the alarm pipeline itself.
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
        '$_header(older entries trimmed)\n${content.substring(cut)}',
        flush: true,
      );
    } catch (_) {}
  }

  static Future<void> _line(String level, String stage, String message) {
    // Mirror to logcat/console so `adb logcat` debugging sees the same trail.
    debugPrint('ALARMLOG [$level] $stage | $message');
    final ts = _timestamp(DateTime.now());
    return _append('$ts [${level.padRight(4)}] ${stage.padRight(8)}| $message\n');
  }

  static Future<void> ok(String stage, String message) =>
      _line('OK', stage, message);

  static Future<void> fail(String stage, String message) =>
      _line('FAIL', stage, message);

  static Future<void> warn(String stage, String message) =>
      _line('WARN', stage, message);

  static Future<void> info(String stage, String message) =>
      _line('INFO', stage, message);

  /// A visual banner separating major events (app start, reschedule runs).
  static Future<void> section(String title) {
    debugPrint('ALARMLOG ==== $title ====');
    final ts = _timestamp(DateTime.now());
    return _append('\n════════ $title — $ts ════════\n');
  }

  /// Full current contents of the log file.
  static Future<String> read() async {
    try {
      final file = await _file();
      if (file == null) return 'Alarm log is not available on this platform.';
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (e) {
      return 'Could not read alarm log: $e';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) {
        await file.writeAsString(_header, flush: true);
      }
      revision.value++;
    } catch (_) {}
  }
}
