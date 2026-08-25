import 'dart:async';

import 'package:flutter/services.dart';

import '../models/task.dart';
import '../models/task_change_source.dart';
import '../utils/label_utils.dart';
import '../utils/task_utils.dart';
import 'item_repository.dart';
import 'log_service.dart';

/// Turns text shared into the app (Android share sheet: links, selected
/// text, email addresses, ...) into tasks due today.
///
/// Native side: ShareActivity receives the ACTION_SEND intent and forwards
/// the text to MainActivity, which queues it. Delivery to Dart is always
/// pull-with-clear (`takeSharedTexts`), so a text is never handled twice:
/// the initial pull in [init] covers a cold start, and a
/// `sharedTextsPending` poke triggers another pull when a share arrives
/// while the app is already running.
///
/// Consumption has two paths. While a home page is alive it registers
/// itself via [registerConsumer] and adds the task through its own
/// in-memory list (no second writer to `tasks.json`, mirroring how every
/// other task creation works). Without a consumer — the configured start
/// page is Settings or App Logs — texts wait [flushDelay] for a home page
/// to claim them, then are persisted straight through [ItemRepository].
class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  static const MethodChannel _channel = MethodChannel('besttodo/share');
  static const String sharedLabel = 'shared';

  /// How long a shared text waits for a home page to register before it is
  /// written to storage directly. Overridable so tests don't sleep.
  static Duration flushDelay = const Duration(seconds: 3);

  void Function(String text)? _consumer;
  final List<String> _pending = [];
  Timer? _flushTimer;
  bool _initialized = false;

  /// Hooks up the platform channel and drains any text queued before the
  /// Flutter engine was ready. Android-only; elsewhere the channel has no
  /// implementation and the pull simply fails silently.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedTextsPending') await _pull();
    });
    await _pull();
  }

  Future<void> _pull() async {
    List<Object?>? texts;
    try {
      texts = await _channel.invokeListMethod<Object?>('takeSharedTexts');
    } catch (_) {
      return;
    }
    for (final text in texts ?? const <Object?>[]) {
      if (text is String) handleSharedText(text);
    }
  }

  /// Routes one shared text to the registered consumer, or queues it for
  /// the delayed direct-to-storage flush. Exposed for tests.
  void handleSharedText(String text) {
    if (text.trim().isEmpty) return;
    final consumer = _consumer;
    if (consumer != null) {
      consumer(text);
      return;
    }
    _pending.add(text);
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      _flushToStorage();
    });
  }

  /// The home page claims all shared texts — queued ones are handed over
  /// immediately, later ones as they arrive.
  void registerConsumer(void Function(String text) consumer) {
    _consumer = consumer;
    _flushTimer?.cancel();
    _flushTimer = null;
    final queued = List.of(_pending);
    _pending.clear();
    for (final text in queued) {
      consumer(text);
    }
  }

  /// Detaches [consumer] if it is still the active one, so a disposed home
  /// page never receives texts (a newer registration stays untouched).
  void unregisterConsumer(void Function(String text) consumer) {
    if (_consumer == consumer) _consumer = null;
  }

  Future<void> _flushToStorage() async {
    if (_consumer != null || _pending.isEmpty) return;
    final texts = List.of(_pending);
    _pending.clear();
    try {
      final repository = ItemRepository.instance;
      final tasks = await repository.loadItems();
      for (final text in texts) {
        tasks.add(buildTask(text));
      }
      applyDefaultDeadlineTimes(tasks);
      await repository.saveItems(tasks, source: TaskChangeSource.share);
      LogService.add('ShareIntentService',
          'Created ${texts.length} task(s) from share (no home page open)');
    } catch (_) {}
  }

  /// Builds the task a shared [text] becomes: due today, first line as the
  /// title (capped at 120 characters), and the full text preserved in the
  /// description whenever the title alone doesn't carry all of it.
  static Task buildTask(String text, {DateTime? now}) {
    final trimmed = text.trim();
    final firstLine = trimmed
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => trimmed);
    var title = firstLine;
    if (title.length > 120) {
      title = '${title.substring(0, 119)}…';
    }
    final timestamp = now ?? DateTime.now();
    return Task(
      title: title,
      description: title == trimmed ? '' : trimmed,
      label: joinLabelTokens(<String>[sharedLabel]),
      createdAt: timestamp,
      dueDate: DateTime(timestamp.year, timestamp.month, timestamp.day),
    );
  }

  /// Clears all singleton state between tests.
  void resetForTest() {
    _consumer = null;
    _pending.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    _initialized = false;
    _channel.setMethodCallHandler(null);
    flushDelay = const Duration(seconds: 3);
  }
}
