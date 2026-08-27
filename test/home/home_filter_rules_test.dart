import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/settings_page.dart';
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
    ProjectService.instance.resetForTest();
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  tearDown(() {
    Config.viewFilterRules = {};
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(markerFinder, findsOneWidget,
        reason: 'HomePage never loaded the tasks');
  }

  testWidgets(
      'a Home exclude-tag rule hides matching tasks from the Today tab',
      (tester) async {
    final today = DateTime.now();
    Config.viewFilterRules[ViewFilterRules.home] =
        ViewFilterRules(excludeTags: ['Waiting_for_approval']);

    await pumpHome(
      tester,
      tasks: [
        Task(title: 'Visible task', dueDate: today),
        Task(
          title: 'Blocked task',
          dueDate: today,
          label: 'Waiting_for_approval',
        ),
      ],
      marker: 'Visible task',
    );

    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Blocked task'), findsNothing);
  });

  testWidgets('clearing the rule brings the task back', (tester) async {
    final today = DateTime.now();
    await pumpHome(
      tester,
      tasks: [
        Task(title: 'Visible task', dueDate: today),
        Task(title: 'Also visible', dueDate: today, label: 'later'),
      ],
      marker: 'Visible task',
    );

    expect(find.text('Also visible'), findsOneWidget);
  });

  testWidgets(
      'Settings → Filtering rules: adding a tag updates Config and shows a chip',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    // initState kicks off the SMS config file load; walk real-event-loop
    // slices so the dart:io future completes inside testWidgets (see
    // test/README.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    // Sections start collapsed, and this one is last, so its chip sits off
    // the horizontally-scrolled chip row too — scroll it into view before
    // tapping the chip row's jump-to-section (which then scrolls the lazy
    // sliver into view and expands it).
    final filteringChip = find.widgetWithText(ChoiceChip, 'Filtering rules');
    await tester.ensureVisible(filteringChip);
    await tester.pumpAndSettle();
    await tester.tap(filteringChip);
    await tester.pumpAndSettle();

    final homeExcludeField = find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byWidgetPredicate((w) =>
          w is TextField &&
          w.decoration?.hintText == 'Tag name'),
    );
    expect(homeExcludeField, findsWidgets);

    await tester.enterText(homeExcludeField.first, 'Waiting_for_approval');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
      contains('Waiting_for_approval'),
    );
    expect(find.text('Waiting_for_approval'), findsOneWidget);

    // Removing the chip clears it again (invoke onDeleted directly rather
    // than hit-testing the small delete glyph, which sits inside the chip's
    // own gesture handling).
    final chip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'Waiting_for_approval'),
    );
    chip.onDeleted!();
    await tester.pumpAndSettle();
    expect(
      Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
      isEmpty,
    );
  });

  testWidgets(
      'Settings → Filtering rules: the Waiting for Approval view is listed '
      'with its built-in rule', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final filteringChip = find.widgetWithText(ChoiceChip, 'Filtering rules');
    await tester.ensureVisible(filteringChip);
    await tester.pumpAndSettle();
    await tester.tap(filteringChip);
    await tester.pumpAndSettle();

    expect(find.text('Waiting for Approval'), findsOneWidget);
    expect(
      find.textContaining('Always excludes Waiting for Approval, Archived, '
          'and Deleted'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Always shows only items still tagged Waiting '
          'for Approval'),
      findsOneWidget,
    );
  });

  testWidgets(
      'Settings → Filtering rules: Food Diary, Alarms and Countdown are '
      'listed as views', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final filteringChip = find.widgetWithText(ChoiceChip, 'Filtering rules');
    await tester.ensureVisible(filteringChip);
    await tester.pumpAndSettle();
    await tester.tap(filteringChip);
    await tester.pumpAndSettle();

    expect(find.text('Food Diary'), findsOneWidget);
    expect(find.text('Alarms'), findsOneWidget);
    expect(find.text('Countdown'), findsOneWidget);
  });
}
