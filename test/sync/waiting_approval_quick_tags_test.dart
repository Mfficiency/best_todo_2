import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/approval_quick_tag.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/approval_quick_tag_service.dart';
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
    ApprovalQuickTagService.instance.resetForTest();
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpPending(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
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

  /// Two quick taps on [finder]'s position — close enough together to count
  /// as a double tap. Mirrors `task_double_tap_timer_test.dart`'s helper.
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    final center = tester.getCenter(finder);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'double-tapping a pending item shows the default Wishlist/Research '
      'quick-tag menu', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await doubleTap(tester, find.text('From Todoist'));

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(find.textContaining('Approve into Wishlist'), findsOneWidget);
    expect(find.textContaining('Approve into Research'), findsOneWidget);
  });

  testWidgets(
      'picking the Research quick tag approves the item and flags it as '
      'research, out of the pending list', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'Look into RSS readers', label: waitingApprovalToken)],
      marker: 'Look into RSS readers',
    );

    await doubleTap(tester, find.text('Look into RSS readers'));
    await tester.tap(find.text('Research'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Look into RSS readers'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    expect(saved.single['isResearch'], isTrue);
    expect(saved.single['isWish'], isNot(true));
  });

  testWidgets(
      'picking the Wishlist quick tag approves the item and flags it as a '
      'wish', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'Someday: learn pottery', label: waitingApprovalToken)],
      marker: 'Someday: learn pottery',
    );

    await doubleTap(tester, find.text('Someday: learn pottery'));
    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Someday: learn pottery'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    expect(saved.single['isWish'], isTrue);
  });

  testWidgets('dismissing the quick-tag menu approves nothing',
      (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await doubleTap(tester, find.text('From Todoist'));
    expect(find.text('Wishlist'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('From Todoist'), findsOneWidget);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], contains('approval'));
  });

  testWidgets('a renamed quick tag still routes to the same tool',
      (tester) async {
    await tester.runAsync(() => ApprovalQuickTagService.instance.save([
          ApprovalQuickTag(
              label: 'Rabbit hole', target: ApprovalQuickTag.researchTarget),
        ]));
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await doubleTap(tester, find.text('From Todoist'));
    expect(find.text('Wishlist'), findsNothing);
    expect(find.text('Rabbit hole'), findsOneWidget);

    await tester.tap(find.text('Rabbit hole'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['isResearch'], isTrue);
  });
}
