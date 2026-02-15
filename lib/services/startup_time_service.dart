import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

/// Records and persists application startup durations.
class StartupTimeService {
  static const _fileName = 'startup_times.json';
  static final Stopwatch _stopwatch = Stopwatch();

  /// Start measuring the startup time.
  static void start() {
    _stopwatch
      ..reset()
      ..start();
  }

  /// Stop the timer, log the result and persist it.
  static Future<void> record() async {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
    }
    final ms = _stopwatch.elapsedMilliseconds;
    LogService.add('Startup', 'App ready in ${ms}ms');
    final times = await _loadTimes();
    times.add(ms);
    if (times.length > 100) {
      times.removeRange(0, times.length - 100);
    }
    await _saveTimes(times);
  }

  /// Retrieve the persisted list of startup times in milliseconds.
  static Future<List<int>> getStartupTimes() => _loadTimes();

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<int>> _loadTimes() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return <int>[];
      final data = jsonDecode(await file.readAsString()) as List<dynamic>;
      return data.cast<int>();
    } catch (_) {
      return <int>[];
    }
  }

  static Future<void> _saveTimes(List<int> times) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(times), flush: true);
    } catch (_) {}
  }
}

