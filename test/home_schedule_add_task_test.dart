import 'dart:io';

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

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
    // All real file I/O (pre-saving tasks, HomePage's initState loads) must
    // run on the real event loop via runAsync, not the fake-async test zone.
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // HomePage._loadTasks is a long chain of real file operations started in
    // the fake-async zone; each hop needs a real-event-loop slice followed by
    // a pump, so iterate until the first task renders.
    final marker = find.text(tasks.first.title);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  testWidgets('schedule view adds new tasks to the highlighted day',
      (tester) async {
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    await tester.tap(find.byTooltip('Schedule view'));
    await tester.pumpAndSettle();

    // At the top of the schedule the active (highlighted) day is Today.
    expect(_addTaskField('Add task · Today'), findsOneWidget);
    expect(find.byTooltip('Back to top'), findsNothing);

    // Scroll all the way down: Someday becomes the active day and the
    // back-to-top arrow appears.
    await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(_addTaskField('Add task · Someday'), findsOneWidget);
    expect(find.byTooltip('Back to top'), findsOneWidget);

    // Adding a task now targets the highlighted Someday section.
    await tester.enterText(
        _addTaskField('Add task · Someday'), 'Sort the garage');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    // The add handler kicks off a real file write inside the fake-async
    // zone; give it fixed rounds of real-event-loop time (see CLAUDE.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    // The new task renders inside the Someday section (below its header).
    final newTask = find.text('Sort the garage');
    expect(newTask, findsOneWidget);
    expect(
      tester.getTopLeft(newTask).dy,
      greaterThan(tester.getTopLeft(find.text('Someday')).dy),
    );

    // And it was persisted with the future-bucket due date (the time of day
    // comes from the app's default deadline time, so compare the date only).
    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final savedTask = saved!.firstWhere((t) => t.title == 'Sort the garage');
    final due = savedTask.dueDate!;
    expect(DateTime(due.year, due.month, due.day), DateTime(2300, 1, 1));

    // The arrow scrolls back to the top and Today becomes active again.
    await tester.tap(find.byTooltip('Back to top'));
    await tester.pumpAndSettle();
    expect(_addTaskField('Add task · Today'), findsOneWidget);
    expect(find.byTooltip('Back to top'), findsNothing);
  });
}
