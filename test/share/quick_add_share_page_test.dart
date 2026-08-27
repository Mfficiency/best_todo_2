import 'dart:io';

import 'package:besttodo/models/shared_payload.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/share_intent_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/quick_add_share_page.dart';
import 'package:flutter/material.dart';
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
  const shareChannel = MethodChannel('besttodo/share');

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ShareIntentService.instance.resetForTest();
  });

  tearDown(() {
    ShareIntentService.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
  });

  Future<void> pumpPage(WidgetTester tester, SharedPayload payload) async {
    await tester.pumpWidget(MaterialApp(
      home: QuickAddSharePage(payload: payload),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills title and description from the shared text',
      (tester) async {
    await pumpPage(
      tester,
      SharedPayload(text: 'Great article\nhttps://example.com/article'),
    );

    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    final titleField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Title'));
    expect(titleField.controller!.text, 'Great article');
    final descriptionField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Description'));
    expect(descriptionField.controller!.text,
        'Great article\nhttps://example.com/article');
  });

  testWidgets('shows both Today and Inbox save options', (tester) async {
    await pumpPage(tester, SharedPayload(text: 'buy milk'));
    expect(find.text('Save to Today'), findsOneWidget);
    expect(find.text('Save to Inbox'), findsOneWidget);
  });

  testWidgets(
      'Save to Today persists the task due today and returns to the '
      'previous app', (tester) async {
    final channelCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      channelCalls.add(call.method);
      return null;
    });

    await pumpPage(tester, SharedPayload(text: 'buy milk'));
    await tester.tap(find.text('Save to Today'));
    // The tap handler awaits real file I/O (StorageService via saveTask)
    // before its setState/pop; pumpAndSettle would hang waiting on a
    // dart:io completion the fake-async zone never services. Poll rounds of
    // a real-event-loop slice + pump until the save shows up (see
    // CLAUDE.md's I/O-inside-testWidgets guidance).
    final storage = StorageService();
    var saved = <Task>[];
    for (var i = 0; i < 300 && saved.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      saved = (await tester.runAsync(() => storage.loadTaskList()))!
          .where((t) => t.title == 'buy milk')
          .toList();
    }
    expect(saved, hasLength(1));
    final now = DateTime.now();
    expect(saved.single.dueDate!.year, now.year);
    expect(saved.single.dueDate!.month, now.month);
    expect(saved.single.dueDate!.day, now.day);
    expect(channelCalls, contains('returnToPreviousApp'));
  });

  testWidgets('Save to Inbox leaves the task undated (Future bucket)',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async => null);

    await pumpPage(tester, SharedPayload(text: 'someday maybe'));
    await tester.tap(find.text('Save to Inbox'));
    final storage = StorageService();
    var saved = <Task>[];
    for (var i = 0; i < 300 && saved.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      saved = (await tester.runAsync(() => storage.loadTaskList()))!
          .where((t) => t.title == 'someday maybe')
          .toList();
    }
    expect(saved, hasLength(1));
    // Every save normalizes the deadline time (see applyDefaultDeadlineTimes)
    // even for the Future-bucket marker date, so only the date carries the
    // "undated" meaning here.
    final due = saved.single.dueDate!;
    expect(due.year, Task.futureBucketMarker.year);
    expect(due.month, Task.futureBucketMarker.month);
    expect(due.day, Task.futureBucketMarker.day);
  });

  testWidgets('Discard returns to the previous app without saving a task',
      (tester) async {
    final channelCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      channelCalls.add(call.method);
      return null;
    });

    final received = <Task>[];
    ShareIntentService.instance.registerConsumer(received.add);

    await pumpPage(tester, SharedPayload(text: 'buy milk'));
    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();

    expect(received, isEmpty);
    expect(channelCalls, contains('returnToPreviousApp'));
  });
}
