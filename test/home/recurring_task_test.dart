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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

Finder _addTaskField(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

void main() {
  late String tempPath;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    tempPath = tempDir.path;
    PathProviderPlatform.instance = _FakePathProvider(tempPath);
    ProjectService.instance.resetForTest();
  });

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
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

  /// Pumps a brand new HomePage against whatever is already on disk —
  /// simulating an app restart — without reseeding storage.
  Future<void> pumpFreshHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('the Repeat picker creates a series that spans future days',
      (tester) async {
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();

    await tester.enterText(_addTaskField('Add task'), 'Take vitamins');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final series = saved!.where((t) => t.title == 'Take vitamins').toList();
    // A master plus at least a handful of generated future occurrences.
    expect(series.length, greaterThan(5));
    final master = series.firstWhere((t) => t.recurrenceParentUid == null);
    expect(master.isRecurring, isTrue);
    expect(master.recurrenceFrequency, 'daily');
    expect(master.recurrenceEndType, 'never');
    for (final child in series.where((t) => t.uid != master.uid)) {
      expect(child.recurrenceParentUid, master.uid);
    }
  });

  testWidgets(
      'deleting "this event" on a series survives a reload instead of '
      'silently coming back', (tester) async {
    final today = DateTime.now();
    final master = Task(
      title: 'Daily standup',
      dueDate: today,
      isRecurring: true,
      recurrenceFrequency: 'daily',
      recurrenceEndType: 'date',
      recurrenceEndDate: today.add(const Duration(days: 3)),
    );
    await pumpHome(tester, [master]);

    // Swipe left to bring up the delete confirmation (the default
    // swipeLeftDelete direction), then tap "Delete" to skip its countdown.
    await tester.drag(find.text('Daily standup').first, const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // The Calendar-style scope dialog appears; pick "this event" only.
    expect(find.text('This is a repeating task'), findsOneWidget);
    await tester.tap(find.text('Delete this event'));
    await tester.pumpAndSettle();

    // Today's occurrence is gone; the series continues from tomorrow (the
    // master promotes) so this exact title no longer appears on Today.
    expect(find.text('Daily standup'), findsNothing);

    // Let the pending move-to-trash timer fire so the test doesn't leave a
    // dangling Timer behind.
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));

    // Simulate an app restart: a fresh HomePage reloads from the same disk
    // state and re-runs the exact same regeneration pass load always does.
    // Before this fix, that regeneration only ever looked at the live task
    // list (never the deletion), so the deleted occurrence would silently
    // reappear here.
    await pumpFreshHome(tester);

    final reloaded =
        await tester.runAsync(() => StorageService().loadTaskList());
    final series = reloaded!.where((t) => t.title == 'Daily standup').toList();
    expect(
        series.any((t) => _dateOnly(t.dueDate!) == _dateOnly(today)), isFalse,
        reason: "today's deleted occurrence must not come back");
    final newMaster = series.firstWhere((t) => t.recurrenceParentUid == null);
    expect(newMaster.isRecurring, isTrue);
    expect(_dateOnly(newMaster.dueDate!),
        _dateOnly(today.add(const Duration(days: 1))));
  });
}
