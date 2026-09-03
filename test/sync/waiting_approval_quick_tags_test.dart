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

  testWidgets(
      'a single tap expands the item and shows the default Wishlist/'
      'Research quick-tag buttons', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    expect(find.text('Wishlist'), findsNothing);

    await tester.tap(find.text('From Todoist'));
    await tester.pump();

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
  });

  testWidgets(
      'tapping the Research quick-tag button approves the item and flags '
      'it as research, out of the pending list', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'Look into RSS readers', label: waitingApprovalToken)],
      marker: 'Look into RSS readers',
    );

    await tester.tap(find.text('Look into RSS readers'));
    await tester.pump();
    await tester.tap(find.text('Research'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('Look into RSS readers'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    expect(saved.single['isResearch'], isTrue);
    expect(saved.single['isWish'], isNot(true));
  });

  testWidgets(
      'tapping the Wishlist quick-tag button approves the item and flags '
      'it as a wish', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'Someday: learn pottery', label: waitingApprovalToken)],
      marker: 'Someday: learn pottery',
    );

    await tester.tap(find.text('Someday: learn pottery'));
    await tester.pump();
    await tester.tap(find.text('Wishlist'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('Someday: learn pottery'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], isNot(contains('approval')));
    expect(saved.single['isWish'], isTrue);
  });

  testWidgets('collapsing the panel again touches nothing', (tester) async {
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.tap(find.text('From Todoist'));
    await tester.pump();
    expect(find.text('Wishlist'), findsOneWidget);

    await tester.tap(find.text('From Todoist'));
    await tester.pump();

    expect(find.text('Wishlist'), findsNothing);
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

    await tester.tap(find.text('From Todoist'));
    await tester.pump();
    expect(find.text('Wishlist'), findsNothing);
    expect(find.text('Rabbit hole'), findsOneWidget);

    await tester.tap(find.text('Rabbit hole'));
    await tester.pump();
    await settleWrites(tester);

    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['isResearch'], isTrue);
  });

  testWidgets('no quick tags configured means no button row, just the rest '
      'of the panel', (tester) async {
    await tester.runAsync(() => ApprovalQuickTagService.instance.save([]));
    await pumpPending(
      tester,
      tasks: [Task(title: 'From Todoist', label: waitingApprovalToken)],
      marker: 'From Todoist',
    );

    await tester.tap(find.text('From Todoist'));
    await tester.pump();

    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.textContaining('From:'), findsOneWidget);
  });
}
