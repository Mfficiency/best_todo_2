import 'package:flutter/foundation.dart';

/// Simple in-memory logger to track app interactions and widget updates.
class LogService {
  // ValueNotifier so UI can listen to log updates.
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>(<String>[]);

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

    logs.value = List<String>.from(recent)
      ..add('$timestamp [$source] $message');
  }

  /// Clear all log entries.
  static void clear() {
    logs.value = <String>[];
  }
}
