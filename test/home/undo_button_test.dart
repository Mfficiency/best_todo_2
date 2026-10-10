import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/task_mutation_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    TaskMutationService.instance.resetForTest();
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

  Future<void> settleIo(WidgetTester tester, [int rounds = 60]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  // A completed task sorts to the bottom of its tab, so a positional
  // Checkbox index shifts after each tap — find the checkbox by the task's
  // own title instead.
  Finder checkboxFor(String title) => find.descendant(
        of: find.ancestor(
            of: find.text(title), matching: find.byType(ListTile)),
        matching: find.byType(Checkbox),
      );

  // HomePage's own load seeds dev-only extras (see CLAUDE.md) after
  // TaskMutationService.noteBaseline, pushing an unrelated entry onto the
  // undo stack before a test's own actions run. Re-baseline against
  // whatever's on disk once that settles, so each test's undo history
  // starts clean.
  Future<void> resetUndoBaseline(WidgetTester tester) async {
    final storage = StorageService();
    final active = await tester.runAsync(() => storage.loadTaskList());
    final deleted = await tester.runAsync(() => storage.loadDeletedTaskList());
    final bin = await tester.runAsync(() => storage.loadBinTaskList());
    TaskMutationService.instance.resetForTest();
    TaskMutationService.instance
        .noteBaseline(active: active!, deleted: deleted!, bin: bin!);
  }

  testWidgets(
      'tapping Undo after completing one task reverts only that task, in '
      'one step (no unrelated "Edited" tasks bundled in)', (tester) async {
    final today = DateTime.now();
    await pumpHome(tester, [
      Task(title: 'Feed the zebra', dueDate: today),
      Task(title: 'Water plants', dueDate: today),
    ]);
    // HomePage's own load can seed dev-only extras (see CLAUDE.md) after
    // noteBaseline, in a chain of real I/O that keeps running past the
    // point pumpHome's marker check stops waiting — give it time to finish
    // and land on disk before re-baselining, or this test's own actions get
    // bundled into the same undo entry as that unrelated seeding.
    await settleIo(tester);
    await resetUndoBaseline(tester);

    await tester.tap(checkboxFor('Feed the zebra'));
    await settleIo(tester);

    final undoButton = find.byIcon(Icons.undo);
    expect(undoButton, findsOneWidget);
    expect(
      find.byTooltip(
          'Undo: Completed "Feed the zebra"\n(long-press for history)'),
      findsOneWidget,
      reason: 'a single checkbox tap should describe as one plain action, '
          'not bundle in unrelated tasks',
    );

    await tester.tap(undoButton);
    await settleIo(tester);

    final checkbox = tester.widget<Checkbox>(checkboxFor('Feed the zebra'));
    expect(checkbox.value, isFalse);
    expect(find.byTooltip('Nothing to undo'), findsOneWidget);
  });

  testWidgets(
      'long-pressing Undo lists every past action and jumping to an older '
      'one undoes everything back to and including it', (tester) async {
    final today = DateTime.now();
    await pumpHome(tester, [
      Task(title: 'Feed the zebra', dueDate: today),
      Task(title: 'Water plants', dueDate: today),
    ]);
    // HomePage's own load can seed dev-only extras (see CLAUDE.md) after
    // noteBaseline, in a chain of real I/O that keeps running past the
    // point pumpHome's marker check stops waiting — give it time to finish
    // and land on disk before re-baselining, or this test's own actions get
    // bundled into the same undo entry as that unrelated seeding.
    await settleIo(tester);
    await resetUndoBaseline(tester);

    await tester.tap(checkboxFor('Feed the zebra'));
    await settleIo(tester);
    await tester.tap(checkboxFor('Water plants'));
    await settleIo(tester);

    await tester.longPress(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();

    expect(find.text('Previous actions'), findsOneWidget);
    expect(find.text('Completed "Water plants"'), findsOneWidget);
    expect(find.text('Completed "Feed the zebra"'), findsOneWidget);

    // Jump to the older entry ("Feed the zebra") — both completions should
    // undo in this one tap.
    await tester.tap(find.text('Completed "Feed the zebra"'));
    await tester.pump();
    await settleIo(tester);

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.every((c) => c.value == false), isTrue);
    expect(find.byTooltip('Nothing to undo'), findsOneWidget);
  });
}
