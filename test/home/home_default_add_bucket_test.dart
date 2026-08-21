import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Finder _addTaskField(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  tearDown(() {
    // Other suites expect the default ("the tab you are looking at").
    Config.defaultAddTabIndex = Config.addToCurrentTab;
  });

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
    // All real file I/O (pre-saving tasks, HomePage's initState loads) must
    // run on the real event loop via runAsync, not the fake-async test zone.
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text(tasks.first.title);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  /// Types [title] into the add-task row labelled [label] and lets the save
  /// that follows finish (fixed rounds of real-event-loop time, see CLAUDE.md).
  Future<void> addTask(
      WidgetTester tester, String label, String title) async {
    await tester.enterText(_addTaskField(label), title);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('by default a new task lands in the tab that is open',
      (tester) async {
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    // Nothing pinned: the label stays plain and Today owns the new task.
    await addTask(tester, 'Add task', 'Buy stamps');
    expect(find.text('Buy stamps'), findsOneWidget);

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final due = saved!.firstWhere((t) => t.title == 'Buy stamps').dueDate!;
    final today = DateTime.now();
    expect(DateTime(due.year, due.month, due.day),
        DateTime(today.year, today.month, today.day));
  });

  testWidgets('a pinned default bucket files quick-added tasks there',
      (tester) async {
    Config.defaultAddTabIndex = 5; // Future
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    // The add row names the target, so the task does not vanish silently.
    expect(_addTaskField('Add task · Future'), findsOneWidget);

    await addTask(tester, 'Add task · Future', 'Learn to sail');

    // Typed from Today, but filed under Future — so it is not in this list.
    expect(find.text('Learn to sail'), findsNothing);

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final due = saved!.firstWhere((t) => t.title == 'Learn to sail').dueDate!;
    expect(DateTime(due.year, due.month, due.day), DateTime(2300, 1, 1));
  });
}
