import 'package:flutter/foundation.dart';

/// Simple in-memory logger to track app interactions and widget updates.
class LogService {
  // ValueNotifier so UI can listen to log updates.
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>(<String>[]);

  /// Add a log entry with a timestamp and source.
  static void add(String source, String message) {
    final timestamp = DateTime.now().toIso8601String();
    logs.value = List<String>.from(logs.value)
      ..add('$timestamp [$source] $message');
  }

  /// Clear all log entries.
  static void clear() {
    logs.value = <String>[];
  }
}
