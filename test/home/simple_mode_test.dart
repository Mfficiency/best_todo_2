import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/mode_select_page.dart';
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
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  tearDown(() {
    // Config is global state; put full mode with every feature back so the
    // next test (and the next suite in this process) starts from the default.
    Config.simpleMode = false;
    Config.modeChosen = false;
    for (final key in Config.featureKeys) {
      Config.featureEnabled[key] = true;
    }
  });

  /// Pumps the home page and waits for its file loads to finish (see
  /// home_search_test.dart for why a single delay is not enough).
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text('Alpha');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  testWidgets('simple mode leaves only the task list on the home page',
      (tester) async {
    Config.simpleMode = true;
    await pumpHome(tester);

    // The task list itself stays, with its tabs and the add-task row.
    expect(find.text('Today'), findsOneWidget);
    expect(find.widgetWithText(TextField, ''), findsWidgets);

    // Every optional surface is gone from the app bar.
    expect(find.byIcon(Icons.casino), findsNothing);
    expect(find.byIcon(Icons.calendar_month), findsNothing);
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsNothing);
    // The search field is replaced by the plain app title.
    expect(find.text('Search tasks'), findsNothing);
    expect(find.text('BestToDo'), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // The drawer keeps the app's own service pages (archived items, about and
    // the diagnostics); only the optional tools are gone.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Archived Items'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Changelog'), findsOneWidget);
    expect(find.text('App Logs'), findsOneWidget);
    expect(find.text('Startup Times'), findsOneWidget);
    expect(find.text('Tools'), findsNothing);
  });

  testWidgets('full mode shows only the tools that are switched on',
      (tester) async {
    Config.simpleMode = false;
    Config.setFeatureEnabled('alarms', false);
    Config.setFeatureEnabled('wishlist', false);
    await pumpHome(tester);

    // Untouched features are still there.
    expect(find.byIcon(Icons.casino), findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    // The drawer has grown past one screen, and the home page body carries
    // its own Scrollables, so scroll the Drawer's own Scrollable specifically
    // to bring Tools into view before it can be tapped.
    await tester.scrollUntilVisible(find.text('Tools'), 200,
        scrollable: find
            .descendant(
                of: find.byType(Drawer), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(find.text('Alarms'), findsNothing);
    expect(find.text('Wishlist'), findsNothing);
    expect(find.text('Countdown'), findsOneWidget);
  });

  testWidgets('a switched-off app-bar feature disappears on its own',
      (tester) async {
    Config.setFeatureEnabled('dice_timer', false);
    Config.setFeatureEnabled('schedule_view', false);
    await pumpHome(tester);

    expect(find.byIcon(Icons.casino), findsNothing);
    expect(find.byIcon(Icons.calendar_month), findsNothing);
    // The search field belongs to another feature and stays.
    expect(find.text('Search tasks'), findsOneWidget);
  });

  testWidgets('mode picker stores the picked mode', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: ModeSelectPage(onModeSelected: () => finished = true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Simple mode'), findsOneWidget);
    expect(find.text('Full mode'), findsOneWidget);

    await tester.tap(find.text('Start simple'));
    // The handler awaits Config.save() before calling back, so walk fixed
    // rounds of the real event loop (see test/README.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    expect(finished, isTrue);
    expect(Config.simpleMode, isTrue);
    expect(Config.modeChosen, isTrue);

    // Persisted, so the picker does not come back on the next launch.
    Config.simpleMode = false;
    Config.modeChosen = false;
    await tester.runAsync(Config.load);
    expect(Config.simpleMode, isTrue);
    expect(Config.modeChosen, isTrue);
  });

  test('features are persisted and simple mode hides them all', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    Config.simpleMode = false;
    Config.setFeatureEnabled('alarms', false);
    Config.setFeatureEnabled('streak', true);
    await Config.save();

    Config.featureEnabled['alarms'] = true;
    await Config.load();
    expect(Config.isFeatureEnabled('alarms'), isFalse);
    expect(Config.isFeatureEnabled('streak'), isTrue);

    // Simple mode overrides the individual switches, except for the service
    // pages in Config.simpleModeFeatures.
    Config.simpleMode = true;
    expect(Config.isFeatureEnabled('streak'), isFalse);
    expect(Config.isFeatureEnabled('projects'), isFalse);
    expect(Config.isFeatureEnabled('deleted_items'), isTrue);
    expect(Config.isFeatureEnabled('changelog'), isTrue);
    expect(Config.isFeatureEnabled('app_logs'), isTrue);
    expect(Config.isFeatureEnabled('startup_times'), isTrue);

    // Unknown keys default to enabled in full mode.
    Config.simpleMode = false;
    expect(Config.isFeatureEnabled('not-a-feature'), isTrue);
  });
}
