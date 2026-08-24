import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/share_intent_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('besttodo/share');

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ShareIntentService.instance.resetForTest();
  });

  tearDown(() {
    ShareIntentService.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('buildTask', () {
    test('single-line text becomes the title of a task due today', () {
      final now = DateTime(2026, 8, 8, 14, 30);
      final task = ShareIntentService.buildTask(
        'https://example.com/article',
        now: now,
      );
      expect(task.title, 'https://example.com/article');
      expect(task.description, '');
      expect(task.label, ShareIntentService.sharedLabel);
      expect(task.dueDate, DateTime(2026, 8, 8));
      expect(task.createdAt, now);
      expect(task.isDone, false);
    });

    test('multi-line text: first line titles, full text kept as description',
        () {
      final task = ShareIntentService.buildTask(
        'Great article\nhttps://example.com/article',
      );
      expect(task.title, 'Great article');
      expect(task.description, 'Great article\nhttps://example.com/article');
    });

    test('surrounding whitespace and blank leading lines are dropped', () {
      final task = ShareIntentService.buildTask('  \n\n  mail@example.com  \n');
      expect(task.title, 'mail@example.com');
      expect(task.description, '');
    });

    test('overlong first line is capped at 120 chars with full text kept', () {
      final longText = 'a' * 200;
      final task = ShareIntentService.buildTask(longText);
      expect(task.title.length, 120);
      expect(task.title.endsWith('…'), true);
      expect(task.description, longText);
    });
  });

  group('consumer routing', () {
    test('registered consumer receives shared texts directly', () {
      final received = <String>[];
      ShareIntentService.instance.registerConsumer(received.add);
      ShareIntentService.instance.handleSharedText('buy milk');
      expect(received, ['buy milk']);
    });

    test('texts queued before registration are drained on register', () {
      ShareIntentService.instance.handleSharedText('first');
      ShareIntentService.instance.handleSharedText('second');
      final received = <String>[];
      ShareIntentService.instance.registerConsumer(received.add);
      expect(received, ['first', 'second']);
      // Draining is one-shot: a re-register hands over nothing again.
      final again = <String>[];
      ShareIntentService.instance.registerConsumer(again.add);
      expect(again, isEmpty);
    });

    test('blank shared text is ignored', () {
      final received = <String>[];
      ShareIntentService.instance.registerConsumer(received.add);
      ShareIntentService.instance.handleSharedText('   \n ');
      expect(received, isEmpty);
    });

    test('unregister detaches the consumer, later texts queue again', () {
      final received = <String>[];
      void consumer(String text) => received.add(text);
      ShareIntentService.instance.registerConsumer(consumer);
      ShareIntentService.instance.unregisterConsumer(consumer);
      ShareIntentService.instance.handleSharedText('queued');
      expect(received, isEmpty);
      final lateReceived = <String>[];
      ShareIntentService.instance.registerConsumer(lateReceived.add);
      expect(lateReceived, ['queued']);
    });

    test('unregister of a stale consumer keeps the newer one attached', () {
      void stale(String text) {}
      final received = <String>[];
      ShareIntentService.instance.registerConsumer(stale);
      ShareIntentService.instance.registerConsumer(received.add);
      ShareIntentService.instance.unregisterConsumer(stale);
      ShareIntentService.instance.handleSharedText('still delivered');
      expect(received, ['still delivered']);
    });
  });

  test(
      'without a consumer, shared text is persisted to storage after the '
      'flush delay', () async {
    ShareIntentService.flushDelay = Duration.zero;
    ShareIntentService.instance.handleSharedText('shared into storage');

    // loadTaskList also merges the one-time Todo.md wishlist import into an
    // empty store, so match the shared task by title instead of expecting it
    // to be alone in the list.
    final storage = StorageService();
    var tries = 0;
    var shared = <Task>[];
    while (tries < 100) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      shared = (await storage.loadTaskList())
          .where((t) => t.title == 'shared into storage')
          .toList();
      if (shared.isNotEmpty) break;
      tries++;
    }
    expect(shared.length, 1);

    final saved = shared.single;
    expect(saved.isWish, false);
    expect(saved.label, ShareIntentService.sharedLabel);
    final now = DateTime.now();
    expect(saved.dueDate!.year, now.year);
    expect(saved.dueDate!.month, now.month);
    expect(saved.dueDate!.day, now.day);
    // The direct-to-storage path normalizes the deadline time like the home
    // page does on save.
    expect(saved.dueDate!.hour, 18);
  });

  test('init pulls texts queued on the platform side', () async {
    final pulls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      pulls.add(call.method);
      if (call.method == 'takeSharedTexts') {
        return <Object?>['from cold start'];
      }
      return null;
    });
    final received = <String>[];
    ShareIntentService.instance.registerConsumer(received.add);
    await ShareIntentService.instance.init();
    expect(pulls, ['takeSharedTexts']);
    expect(received, ['from cold start']);
    // init is once-only; a second call must not pull (and duplicate) again.
    await ShareIntentService.instance.init();
    expect(pulls, ['takeSharedTexts']);
  });
}
