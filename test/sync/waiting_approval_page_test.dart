import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/waiting_approval_page.dart';
import 'package:besttodo/utils/label_utils.dart';
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

  Future<void> pumpPending(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    // Pre-saving and the page's initState load are real file I/O, which must
    // run on the real event loop (runAsync), not the fake-async test zone.
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: WaitingApprovalPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'WaitingApprovalPage never loaded the tasks');
  }

  /// The save started by a tap/swipe handler is awaited before setState in
  /// some paths; a fixed number of runAsync rounds lets the write finish.
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

  testWidgets('shows only pending tasks, hiding already-approved ones',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [
        Task(title: 'From Todoist', label: waitingApprovalToken),
        Task(title: 'Already approved', dueDate: DateTime.now()),
      ],
      marker: 'From Todoist',
    );

    expect(find.text('Already approved'), findsNothing);
  });

  testWidgets(
      'approve swipe shows day shortcuts; picking one approves and '
      'schedules it', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(300, 0));
    await tester.pump();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Future'), findsOneWidget);

    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await settleWrites(tester);

    // Approved out of the pending view, due tomorrow.
    expect(find.text('From Todoist'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    final due = DateTime.parse(saved.single['dueDate'] as String);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(due.year, tomorrow.year);
    expect(due.month, tomorrow.month);
    expect(due.day, tomorrow.day);
  });

  testWidgets('approve swipe countdown approves the item onto today',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(300, 0));
    await tester.pump();
    // Letting the countdown run out applies the default: due today.
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    expect(find.text('From Todoist'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    final due = DateTime.parse(saved.single['dueDate'] as String);
    final today = DateTime.now();
    expect(due.year, today.year);
    expect(due.month, today.month);
    expect(due.day, today.day);
  });

  testWidgets('deny swipe shows Deny plus weekday shortcuts', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(-300, 0));
    await tester.pump();
    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Fri'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('deny-side weekday shortcut approves the item onto that day',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Fri'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('From Todoist'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    final due = DateTime.parse(saved.single['dueDate'] as String);
    expect(due.weekday, DateTime.friday);
  });

  testWidgets(
      'deny swipe moves the item to the bin with an undo window',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [
        Task(title: 'From Todoist', label: waitingApprovalToken),
        Task(title: 'Already approved', dueDate: DateTime.now()),
      ],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();

    // Removed from the list right away, with an undo window like the home
    // page; the move to the bin is persisted when it expires.
    expect(find.text('From Todoist'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    var tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.map((t) => t['title']), ['Already approved']);

    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.map((t) => t['title']), ['Already approved']);
    final binned = await readJsonList(tester, 'deleted_bin.json');
    expect(binned.single['title'], 'From Todoist');
    expect(binned.single['deletedAt'], isNotNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('undo restores a denied item', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.drag(find.text('From Todoist'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    // Let the snackbar finish animating in so the Undo action is tappable.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('From Todoist'), findsOneWidget);
    final tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.single['title'], 'From Todoist');
    expect(tasks.single['label'], contains('approval'));
    final binned = await readJsonList(tester, 'deleted_bin.json');
    expect(binned, isEmpty);
    await tester.pump(Config.delayDuration + const Duration(seconds: 1));
  });

  testWidgets('the plain Approve button approves without touching the date',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.tap(find.byTooltip('Approve'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('From Todoist'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    expect(saved.single['dueDate'], isNull);
  });

  testWidgets('the plain Deny button sends the item straight to the bin',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.tap(find.byTooltip('Deny'));
    await tester.pump();
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    expect(find.text('From Todoist'), findsNothing);
    final binned = await readJsonList(tester, 'deleted_bin.json');
    expect(binned.single['title'], 'From Todoist');
    await tester.pump(const Duration(seconds: 1));
  });
}
