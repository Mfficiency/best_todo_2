import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

/// One recorded launch: when it happened and how long startup took.
class StartupRecord {
  final DateTime at;
  final int ms;

  const StartupRecord({required this.at, required this.ms});

  factory StartupRecord.fromJson(Map<String, dynamic> json) => StartupRecord(
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        ms: (json['ms'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'ms': ms};
}

/// Measures and persists real app startup durations. Call [start] at the very
/// top of `main()` and [record] in a post-first-frame callback. The Startup
/// Times page reads [getStartupHistory]. These are genuine measurements — the
/// template never fabricates timings.
class StartupTimeService {
  static const _fileName = 'startup_times.json';
  static const _historyFileName = 'startup_history.json';
  static const _maxHistoryEntries = 5000;
  static final Stopwatch _stopwatch = Stopwatch();

  static void start() => _stopwatch
    ..reset()
    ..start();

  /// Stops the timer, logs the result and appends it to history.
  static Future<void> record() async {
    if (_stopwatch.isRunning) _stopwatch.stop();
    final ms = _stopwatch.elapsedMilliseconds;
    LogService.add('Startup', 'App ready in ${ms}ms');
    final times = await _loadTimes();
    times.add(ms);
    if (times.length > 100) times.removeRange(0, times.length - 100);
    await _saveTimes(times);
    await _appendHistory(StartupRecord(at: DateTime.now(), ms: ms));
  }

  static Future<List<int>> getStartupTimes() => _loadTimes();

  /// Timestamped launch history, oldest first.
  static Future<List<StartupRecord>> getStartupHistory() => _loadHistory();

  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  static Future<List<int>> _loadTimes() async {
    try {
      final file = await _file(_fileName);
      if (!await file.exists()) return <int>[];
      return (jsonDecode(await file.readAsString()) as List).cast<int>();
    } catch (_) {
      return <int>[];
    }
  }

  static Future<void> _saveTimes(List<int> times) async {
    try {
      await (await _file(_fileName)).writeAsString(jsonEncode(times),
          flush: true);
    } catch (_) {}
  }

  static Future<List<StartupRecord>> _loadHistory() async {
    try {
      final file = await _file(_historyFileName);
      if (!await file.exists()) return <StartupRecord>[];
      return (jsonDecode(await file.readAsString()) as List)
          .whereType<Map>()
          .map((e) => StartupRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <StartupRecord>[];
    }
  }

  static Future<void> _appendHistory(StartupRecord record) async {
    try {
      final history = await _loadHistory()
        ..add(record);
      if (history.length > _maxHistoryEntries) {
        history.removeRange(0, history.length - _maxHistoryEntries);
      }
      await (await _file(_historyFileName)).writeAsString(
        jsonEncode(history.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (_) {}
  }
}
