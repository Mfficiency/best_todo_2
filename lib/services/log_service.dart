import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Simple in-memory logger to track app interactions and widget updates.
class LogService {
  // ValueNotifier so UI can listen to log updates.
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>(<String>[]);

  static File? _logFile;

  /// Load existing log entries from disk.
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/app_logs.txt');
    if (await _logFile!.exists()) {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 1));
      final lines = await _logFile!.readAsLines();
      final recent = lines.where((entry) {
        final spaceIndex = entry.indexOf(' ');
        if (spaceIndex == -1) return false;
        final entryTime = DateTime.tryParse(entry.substring(0, spaceIndex));
        return entryTime != null && !entryTime.isBefore(cutoff);
      }).toList();
      logs.value = recent;
    }
  }

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

    final entry = '$timestamp [$source] $message';
    logs.value = List<String>.from(recent)..add(entry);

    try {
      _logFile?.writeAsStringSync('$entry\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Ignore file write errors.
    }
  }

  /// Clear all log entries.
  static void clear() {
    logs.value = <String>[];
    try {
      _logFile?.writeAsStringSync('', flush: true);
    } catch (_) {
      // Ignore file write errors.
    }
  }
}

