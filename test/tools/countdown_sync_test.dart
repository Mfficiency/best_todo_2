import 'dart:io';

import 'package:besttodo/models/countdown_timer.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/countdown_sync_service.dart';
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
  group('buildLinkedTimer', () {
    test('targets the task due date', () {
      final task = Task(title: 'launch', dueDate: DateTime(2026, 8, 1, 18));
      final timer = CountdownSyncService.buildLinkedTimer(task)!;
      expect(timer.itemUid, task.uid);
      expect(timer.target, DateTime(2026, 8, 1, 18));
      expect(timer.label, 'launch');
    });

    test('an undated task gets no timer', () {
      expect(CountdownSyncService.buildLinkedTimer(Task(title: 'someday')),
          isNull);
    });
  });

  group('applyTaskToTimer', () {
    test('follows the task due date', () {
      final task = Task(title: 'launch', dueDate: DateTime(2026, 8, 1, 18));
      final timer = CountdownSyncService.buildLinkedTimer(task)!;

      task.dueDate = DateTime(2026, 8, 3, 9);
      expect(CountdownSyncService.applyTaskToTimer(task, timer), isTrue);
      expect(timer.target, DateTime(2026, 8, 3, 9));
      // Unchanged state reports no change.
      expect(CountdownSyncService.applyTaskToTimer(task, timer), isFalse);
    });

    test('an undated task leaves an existing target untouched', () {
      final task = Task(title: 'launch', dueDate: DateTime(2026, 8, 1, 18));
      final timer = CountdownSyncService.buildLinkedTimer(task)!;
      final original = timer.target;
      task.dueDate = null;
      expect(CountdownSyncService.applyTaskToTimer(task, timer), isFalse);
      expect(timer.target, original);
    });
  });

  group('resolveAgainstTasks', () {
    test('a timer whose task is gone is unlinked, not removed', () {
      final timer = CountdownTimerItem(
        label: 'orphan',
        target: DateTime(2026, 8, 1),
        itemUid: 'gone-uid',
      );
      final changed = CountdownSyncService.resolveAgainstTasks([timer], []);
      expect(changed, isTrue);
      expect(timer.itemUid, isNull);
      // The countdown itself survives with its last-known target.
      expect(timer.target, DateTime(2026, 8, 1));
    });

    test('an unlinked timer is left alone', () {
      final timer =
          CountdownTimerItem(label: 'solo', target: DateTime(2026, 1, 1));
      expect(CountdownSyncService.resolveAgainstTasks([timer], []), isFalse);
    });

    test('a linked timer follows its task through the batch resolve', () {
      final task = Task(title: 'launch', dueDate: DateTime(2026, 8, 1, 18));
      final timer = CountdownSyncService.buildLinkedTimer(task)!;
      task.dueDate = DateTime(2026, 9, 1, 12);
      final changed =
          CountdownSyncService.resolveAgainstTasks([timer], [task]);
      expect(changed, isTrue);
      expect(timer.target, DateTime(2026, 9, 1, 12));
      expect(timer.itemUid, task.uid);
    });
  });

  group('TaskCountdownSection', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    // The section loads countdown_timers.json in initState (real file I/O,
    // which the fake-async testWidgets zone never services — see CLAUDE.md)
    // so every pump waits it out with a runAsync delay loop until [marker]
    // appears.
    Future<void> pumpDetail(
      WidgetTester tester,
      Task task, {
      required String marker,
    }) async {
      await tester.pumpWidget(MaterialApp(home: TaskDetailPage(task: task)));
      final markerFinder = find.text(marker);
      for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pump();
      expect(markerFinder, findsOneWidget,
          reason: 'TaskCountdownSection never finished loading');
    }

    testWidgets('undated tasks offer no countdown', (tester) async {
      await pumpDetail(tester, Task(title: 'someday'), marker: 'someday');
      expect(find.text('Add countdown to due date'), findsNothing);
    });

    testWidgets('dated tasks offer to attach a countdown', (tester) async {
      await pumpDetail(
        tester,
        Task(title: 'due', dueDate: DateTime(2026, 8, 1, 18)),
        marker: 'Add countdown to due date',
      );
      expect(find.text('Add countdown to due date'), findsOneWidget);
    });

    testWidgets('attaching shows the linked state with a remove action',
        (tester) async {
      final task = Task(title: 'due', dueDate: DateTime(2026, 8, 1, 18));
      await pumpDetail(tester, task, marker: 'Add countdown to due date');

      await tester.tap(find.text('Add countdown to due date'));
      // The tap's handler awaits a write before setState; poll a fixed
      // number of rounds rather than for a marker (in-memory state already
      // updated, so a marker-based loop would exit before the write lands).
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }

      expect(find.text('Add countdown to due date'), findsNothing);
      expect(find.byTooltip('Remove countdown link'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove countdown link'));
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(find.text('Add countdown to due date'), findsOneWidget);
    });
  });
}
