import 'dart:io';

import 'package:besttodo/models/attachment.dart';
import 'package:besttodo/models/shared_payload.dart';
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

  group('SharedPayload.fromMap', () {
    test('parses text, subject and files', () {
      final payload = SharedPayload.fromMap({
        'text': ' https://example.com/article ',
        'subject': ' An article ',
        'files': [
          {'path': '/tmp/a.jpg', 'mimeType': 'image/jpeg'},
          {'path': '/tmp/b.pdf', 'mimeType': 'application/pdf'},
        ],
      });
      expect(payload.text, 'https://example.com/article');
      expect(payload.subject, 'An article');
      expect(payload.files, hasLength(2));
      expect(payload.files[0].isImage, true);
      expect(payload.files[1].isPdf, true);
    });

    test('missing keys default to empty', () {
      final payload = SharedPayload.fromMap(const {});
      expect(payload.text, '');
      expect(payload.files, isEmpty);
      expect(payload.isEmpty, true);
    });
  });

  group('buildDraftTask', () {
    test('single-line text becomes the title', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(text: 'https://example.com/article'),
      );
      expect(task.title, 'https://example.com/article');
      expect(task.description, '');
      expect(task.label, ShareIntentService.sharedLabel);
    });

    test('multi-line text: first line titles, full text kept as description',
        () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(text: 'Great article\nhttps://example.com/article'),
      );
      expect(task.title, 'Great article');
      expect(task.description, 'Great article\nhttps://example.com/article');
    });

    test('blank leading lines are dropped', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(text: '  \n\n  mail@example.com  \n'),
      );
      expect(task.title, 'mail@example.com');
      expect(task.description, '');
    });

    test('overlong first line is capped at 120 chars with full text kept',
        () {
      final longText = 'a' * 200;
      final task =
          ShareIntentService.buildDraftTask(SharedPayload(text: longText));
      expect(task.title.length, 120);
      expect(task.title.endsWith('…'), true);
      expect(task.description, longText);
    });

    test('falls back to the subject when there is no text', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(text: '', subject: 'Order confirmation'),
      );
      expect(task.title, 'Order confirmation');
    });

    test('a named file with no text titles itself from the file name', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(files: const [
          SharedFile(path: '/tmp/vacation-plan.jpg', mimeType: 'image/jpeg'),
        ]),
      );
      expect(task.title, 'vacation-plan');
    });

    test('a generated file name falls back to a generic title', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(files: const [
          SharedFile(path: '/tmp/IMG_20260101_120000.jpg', mimeType: 'image/jpeg'),
        ]),
      );
      expect(task.title, 'Shared photo');
    });

    test('multiple files note how many more in the title', () {
      final task = ShareIntentService.buildDraftTask(
        SharedPayload(files: const [
          SharedFile(path: '/tmp/report.pdf', mimeType: 'application/pdf'),
          SharedFile(path: '/tmp/appendix.pdf', mimeType: 'application/pdf'),
        ]),
      );
      expect(task.title, 'report (+1 more)');
    });
  });

  group('dedup', () {
    test('an identical payload delivered again within the window is dropped',
        () {
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      expect(received, hasLength(1));
    });

    test('a different payload is not treated as a duplicate', () {
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy eggs'));
      expect(received, hasLength(2));
    });

    test('the same content is accepted again once the window has passed',
        () async {
      ShareIntentService.dedupWindow = const Duration(milliseconds: 1);
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      expect(received, hasLength(2));
    });
  });

  group('payload callback routing', () {
    test('the callback receives payloads directly once attached', () {
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'buy milk'));
      expect(received.map((p) => p.text), ['buy milk']);
    });

    test('payloads queued before the callback attaches are drained on attach',
        () {
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'first'));
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'second'));
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      expect(received.map((p) => p.text), ['first', 'second']);
      // Draining is one-shot: re-attaching hands over nothing again.
      final again = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(again.add);
      expect(again, isEmpty);
    });

    test('an empty payload (no text, no files) is ignored', () {
      final received = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(received.add);
      ShareIntentService.instance.handleSharedPayload(SharedPayload(text: '   \n '));
      expect(received, isEmpty);
    });

    test('detaching the callback queues later payloads again', () {
      final received = <SharedPayload>[];
      void callback(SharedPayload p) => received.add(p);
      ShareIntentService.instance.setOnSharedPayload(callback);
      ShareIntentService.instance.setOnSharedPayload(null);
      ShareIntentService.instance
          .handleSharedPayload(SharedPayload(text: 'queued'));
      expect(received, isEmpty);
      final lateReceived = <SharedPayload>[];
      ShareIntentService.instance.setOnSharedPayload(lateReceived.add);
      expect(lateReceived.map((p) => p.text), ['queued']);
    });
  });

  group('saveTask', () {
    test('a registered consumer claims the task', () async {
      final received = <Task>[];
      ShareIntentService.instance.registerConsumer(received.add);
      final task = Task(title: 'buy milk');
      await ShareIntentService.instance.saveTask(task);
      expect(received, [task]);
    });

    test('without a consumer, the task is persisted directly', () async {
      final task = Task(title: 'buy milk', dueDate: DateTime(2026, 8, 8));
      await ShareIntentService.instance.saveTask(task);

      final storage = StorageService();
      final saved = (await storage.loadTaskList())
          .where((t) => t.title == 'buy milk')
          .toList();
      expect(saved, hasLength(1));
      // The direct-to-storage path normalizes the deadline time like the
      // home page does on save.
      expect(saved.single.dueDate!.hour, 18);
    });

    test('unregister detaches the consumer, later tasks persist directly',
        () async {
      final received = <Task>[];
      void consumer(Task t) => received.add(t);
      ShareIntentService.instance.registerConsumer(consumer);
      ShareIntentService.instance.unregisterConsumer(consumer);
      final task = Task(title: 'buy milk');
      await ShareIntentService.instance.saveTask(task);
      expect(received, isEmpty);

      final storage = StorageService();
      final saved = (await storage.loadTaskList())
          .where((t) => t.title == 'buy milk')
          .toList();
      expect(saved, hasLength(1));
    });
  });

  group('importAttachments', () {
    test('copies image/pdf files into permanent storage and clears the cache '
        'copy', () async {
      final cacheDir = await Directory.systemTemp.createTemp();
      final imageFile = File('${cacheDir.path}/photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final pdfFile = File('${cacheDir.path}/doc.pdf')
        ..writeAsBytesSync([4, 5, 6]);

      final attachments = await ShareIntentService.importAttachments(
        'task-uid',
        [
          SharedFile(path: imageFile.path, mimeType: 'image/jpeg'),
          SharedFile(path: pdfFile.path, mimeType: 'application/pdf'),
        ],
      );

      expect(attachments, hasLength(2));
      expect(attachments[0].type, Attachment.typeImage);
      expect(attachments[1].type, Attachment.typePdf);
      expect(await imageFile.exists(), false);
      expect(await pdfFile.exists(), false);
    });

    test('a file type with no attachment viewer is skipped', () async {
      final cacheDir = await Directory.systemTemp.createTemp();
      final textFile = File('${cacheDir.path}/notes.txt')
        ..writeAsBytesSync([1]);

      final attachments = await ShareIntentService.importAttachments(
        'task-uid',
        [SharedFile(path: textFile.path, mimeType: 'text/plain')],
      );

      expect(attachments, isEmpty);
      expect(await textFile.exists(), true);
    });
  });

  test('init pulls content queued on the platform side', () async {
    final pulls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      pulls.add(call.method);
      if (call.method == 'takeSharedContent') {
        return <Object?>[
          {
            'text': 'from cold start',
            'files': <Object?>[],
          }
        ];
      }
      return null;
    });
    final received = <SharedPayload>[];
    ShareIntentService.instance.setOnSharedPayload(received.add);
    await ShareIntentService.instance.init();
    expect(pulls, ['takeSharedContent']);
    expect(received.map((p) => p.text), ['from cold start']);
    // init is once-only; a second call must not pull (and duplicate) again.
    await ShareIntentService.instance.init();
    expect(pulls, ['takeSharedContent']);
  });

  test('returnToPreviousApp invokes the platform channel and swallows errors',
      () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await ShareIntentService.instance.returnToPreviousApp();
    expect(calls, ['returnToPreviousApp']);
  });
}
