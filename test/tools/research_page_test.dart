import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/research_page.dart';
import 'package:besttodo/utils/description_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Config.swipeLeftDelete = true;
    // Opt out of the one-time Todo.md import so tests only see their own
    // items.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpResearch(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: ResearchPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'ResearchPage never loaded the tasks');
  }

  /// Like [pumpResearch], but for the empty-list case, which has no task
  /// title to use as a load-finished marker: polls until the loading
  /// spinner is gone instead.
  Future<void> pumpResearchEmpty(WidgetTester tester) async {
    await tester.runAsync(() => StorageService().saveTaskList([]));
    await tester.pumpWidget(const MaterialApp(home: ResearchPage()));
    final spinner = find.byType(CircularProgressIndicator);
    for (var i = 0; i < 300 && spinner.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(spinner, findsNothing,
        reason: 'ResearchPage never finished loading');
  }

  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<List<dynamic>> readJsonList(WidgetTester tester, String name) async {
    return await tester.runAsync(() async {
      final file = File('${tempDir.path}/$name');
      if (!await file.exists()) return <dynamic>[];
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    }) as List<dynamic>;
  }

  testWidgets('shows only research-flagged tasks, hiding plain ones',
      (tester) async {
    await pumpResearch(
      tester,
      tasks: [
        Task(title: 'Compare CRDT libraries', isResearch: true),
        Task(title: 'Plain task', dueDate: DateTime.now()),
      ],
      marker: 'Compare CRDT libraries',
    );

    expect(find.text('Plain task'), findsNothing);
  });

  testWidgets('the empty state shows when there are no research items',
      (tester) async {
    await pumpResearchEmpty(tester);

    expect(find.textContaining('No research items yet'), findsOneWidget);
  });

  testWidgets('adding an item via the FAB saves it as research-flagged',
      (tester) async {
    await pumpResearchEmpty(tester);

    await tester.tap(find.byTooltip('Add research item'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Look into vector DBs');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Look into vector DBs'), findsOneWidget);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['isResearch'], isTrue);
  });

  testWidgets('swiping an item away archives it, with an undo window',
      (tester) async {
    await pumpResearch(
      tester,
      tasks: [Task(title: 'Compare CRDT libraries', isResearch: true)],
      marker: 'Compare CRDT libraries',
    );

    // Same swipe as a home-tab task: swipe left for the delete options,
    // then tap "Delete" to skip its countdown.
    await tester.drag(
        find.text('Compare CRDT libraries'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Compare CRDT libraries'), findsNothing);
    expect(find.text('Deleted "Compare CRDT libraries"'), findsOneWidget);

    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved, isEmpty);
  });

  testWidgets(
      'tapping an item folds it open with every field a normal task has',
      (tester) async {
    await pumpResearch(
      tester,
      tasks: [Task(title: 'Compare CRDT libraries', isResearch: true)],
      marker: 'Compare CRDT libraries',
    );

    await tester.tap(find.text('Compare CRDT libraries'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Note'), findsOneWidget);
    expect(find.text('No due date'), findsOneWidget);
    expect(find.text('Pick due date'), findsOneWidget);
    expect(find.text('Recurring'), findsOneWidget);
    expect(find.byTooltip('Notify'), findsOneWidget);
    expect(find.byTooltip('Send to Claude'), findsOneWidget);
  });

  testWidgets('the checkbox marks a research item done and persists it',
      (tester) async {
    await pumpResearch(
      tester,
      tasks: [Task(title: 'Compare CRDT libraries', isResearch: true)],
      marker: 'Compare CRDT libraries',
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await settleWrites(tester);

    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['isDone'], isTrue);
    expect(saved.single['isResearch'], isTrue);
  });

  testWidgets('a research item with a due date shows it on the tile',
      (tester) async {
    await pumpResearch(
      tester,
      tasks: [
        Task(
          title: 'Compare CRDT libraries',
          isResearch: true,
          dueDate: DateTime(2026, 10, 3),
          description: 'Yjs vs Automerge',
        ),
      ],
      marker: 'Compare CRDT libraries',
    );

    expect(find.text('Due 2026-10-03'), findsOneWidget);
    // The description sits collapsed under the title, like a wish's.
    expect(find.byType(DescriptionDisclosure), findsOneWidget);
  });

  testWidgets('the add dialog also saves a note', (tester) async {
    await pumpResearchEmpty(tester);

    await tester.tap(find.byTooltip('Add research item'));
    await tester.pumpAndSettle();
    expect(find.text('No due date'), findsOneWidget);
    expect(find.text('Pick due date'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Look into vector DBs');
    await tester.enterText(
        find.widgetWithText(TextField, 'Note'), 'Ask Sam about pgvector');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['note'], 'Ask Sam about pgvector');
    expect(saved.single['isResearch'], isTrue);
  });
}
