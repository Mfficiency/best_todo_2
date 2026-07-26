import 'package:flutter/foundation.dart';

/// In-memory rolling logger for app interactions. Backs the App Logs page via
/// a [ValueNotifier] so the UI updates live. Entries older than 24h are pruned
/// on each add, keeping the buffer small without any persistence.
class LogService {
  static final ValueNotifier<List<String>> logs =
      ValueNotifier<List<String>>(<String>[]);

  /// Adds a timestamped entry: `<iso8601> [source] message`.
  static void add(String source, String message) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 1));

    final recent = logs.value.where((entry) {
      final spaceIndex = entry.indexOf(' ');
      if (spaceIndex == -1) return false;
      final entryTime = DateTime.tryParse(entry.substring(0, spaceIndex));
      return entryTime != null && !entryTime.isBefore(cutoff);
    });

    logs.value = List<String>.from(recent)
      ..add('${now.toIso8601String()} [$source] $message');
  }

  static void clear() => logs.value = <String>[];
}
