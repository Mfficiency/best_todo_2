import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/research_page.dart';
import 'package:besttodo/ui/task_detail_page.dart';
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

    await tester.drag(
        find.text('Compare CRDT libraries'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Compare CRDT libraries'), findsNothing);

    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved, isEmpty);
  });

  testWidgets('tapping an item opens the Task Details page', (tester) async {
    await pumpResearch(
      tester,
      tasks: [Task(title: 'Compare CRDT libraries', isResearch: true)],
      marker: 'Compare CRDT libraries',
    );

    await tester.tap(find.text('Compare CRDT libraries'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailPage), findsOneWidget);
  });
}
