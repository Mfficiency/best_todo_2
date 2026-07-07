import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Finder _searchField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search tasks',
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
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  List<Task> todayTasks() {
    final today = DateTime.now();
    return [
      Task(title: 'Feed the zebra', dueDate: today),
      Task(title: 'Water plants', dueDate: today),
      Task(
        title: 'Call plumber',
        description: 'about the zebra-striped sink',
        dueDate: today,
      ),
      Task(title: 'Pay bills', label: 'finances', dueDate: today),
      Task(title: 'Sort receipts', projectId: 'project_2', dueDate: today),
    ];
  }

  testWidgets('search field is enabled and filters by title', (tester) async {
    await pumpHome(tester, todayTasks());

    expect(find.text('Feed the zebra'), findsOneWidget);
    expect(find.text('Water plants'), findsOneWidget);

    await tester.enterText(_searchField(), 'zebra');
    await tester.pumpAndSettle();

    expect(find.text('Feed the zebra'), findsOneWidget);
    // Description matches too ("zebra-striped sink").
    expect(find.text('Call plumber'), findsOneWidget);
    expect(find.text('Water plants'), findsNothing);
    expect(find.text('Pay bills'), findsNothing);
  });

  testWidgets('search is case-insensitive', (tester) async {
    await pumpHome(tester, todayTasks());

    await tester.enterText(_searchField(), 'ZEBRA');
    await tester.pumpAndSettle();

    expect(find.text('Feed the zebra'), findsOneWidget);
    expect(find.text('Water plants'), findsNothing);
  });

  testWidgets('search matches the label field', (tester) async {
    await pumpHome(tester, todayTasks());

    await tester.enterText(_searchField(), 'finances');
    await tester.pumpAndSettle();

    expect(find.text('Pay bills'), findsOneWidget);
    expect(find.text('Feed the zebra'), findsNothing);
  });

  testWidgets('search matches the assigned project name', (tester) async {
    await pumpHome(tester, todayTasks());

    await tester.enterText(_searchField(), 'project 2');
    await tester.pumpAndSettle();

    expect(find.text('Sort receipts'), findsOneWidget);
    expect(find.text('Feed the zebra'), findsNothing);
  });

  testWidgets('the clear button resets the search', (tester) async {
    await pumpHome(tester, todayTasks());

    await tester.enterText(_searchField(), 'zebra');
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('Pay bills'), findsOneWidget);
    // The clear button goes back to the plain search icon.
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('no-match search empties the list', (tester) async {
    await pumpHome(tester, todayTasks());

    await tester.enterText(_searchField(), 'xyzzy-no-such-task');
    await tester.pumpAndSettle();

    expect(find.text('Feed the zebra'), findsNothing);
    expect(find.text('Water plants'), findsNothing);
    expect(find.text('No tasks for today'), findsOneWidget);
  });
}
