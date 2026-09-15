import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/streak_flame_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Finder get _addTaskField => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          (w.decoration?.labelText?.startsWith('Add task') ?? false),
    );

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpHome(
    WidgetTester tester,
    Widget home, {
    required String marker,
  }) async {
    await tester.pumpWidget(MaterialApp(home: home));
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

  test('worklist is registered as a feature and a start-tool option', () {
    expect(Config.featureKeys, contains('worklist'));
    expect(Config.startToolOptions, contains('worklist'));
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });

  testWidgets(
      'a tag-filtered home instance shows only tasks tagged mlr, titled by '
      'toolTitle, and tags a task typed directly into it', (tester) async {
    final today = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Tagged worklist item', dueDate: today, label: 'mlr'),
          Task(title: 'Unrelated task', dueDate: today),
        ]));

    await pumpHome(
      tester,
      const HomePage(tagFilter: 'mlr', toolTitle: 'Worklist'),
      marker: 'Tagged worklist item',
    );

    expect(find.text('Tagged worklist item'), findsOneWidget);
    expect(find.text('Unrelated task'), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Worklist')),
      findsOneWidget,
    );

    // Typing directly into this instance's add-task row stamps the mlr tag,
    // so the new task passes the same filter and shows up immediately.
    await tester.enterText(_addTaskField, 'New worklist item');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('New worklist item'), findsOneWidget);
  });

  testWidgets(
      'Worklist stays filtered to mlr in schedule view too', (tester) async {
    final today = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Tagged worklist item', dueDate: today, label: 'mlr'),
          Task(title: 'Unrelated task', dueDate: today),
        ]));

    await pumpHome(
      tester,
      const HomePage(tagFilter: 'mlr', toolTitle: 'Worklist'),
      marker: 'Tagged worklist item',
    );

    // Switching to the schedule view (one long day-grouped list, an
    // alternative to the tab-per-bucket layout) used to read straight from
    // the full task list instead of going through the same tag filter as
    // the tab view, leaking every other task into a supposedly filtered
    // instance.
    await tester.tap(find.byTooltip('Schedule view'));
    await tester.pumpAndSettle();

    expect(find.text('Tagged worklist item'), findsOneWidget);
    expect(find.text('Unrelated task'), findsNothing);
  });

  testWidgets(
      'Worklist hides the streak flame and dice icons and uses an orange '
      'accent', (tester) async {
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(
              title: 'Tagged worklist item',
              dueDate: DateTime.now(),
              label: 'mlr'),
        ]));

    await pumpHome(
      tester,
      const HomePage(tagFilter: 'mlr', toolTitle: 'Worklist'),
      marker: 'Tagged worklist item',
    );

    expect(find.byType(StreakFlameButton), findsNothing);
    expect(find.byIcon(Icons.casino), findsNothing);
    expect(
      find.byWidgetPredicate(
          (w) => w is Theme && w.data.colorScheme.primary == Colors.orange),
      findsOneWidget,
    );
  });

  testWidgets(
      'the regular (unfiltered) home page hides mlr-tagged tasks — they '
      'show only in the Worklist tool', (tester) async {
    final today = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Tagged worklist item', dueDate: today, label: 'mlr'),
          Task(title: 'Unrelated task', dueDate: today),
        ]));

    await pumpHome(tester, const HomePage(), marker: 'Unrelated task');

    expect(find.text('Unrelated task'), findsOneWidget);
    expect(find.text('Tagged worklist item'), findsNothing);
  });

  testWidgets('Worklist is listed under Tools in the drawer', (tester) async {
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]));

    await pumpHome(tester, const HomePage(), marker: 'Alpha');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    final drawerScrollable = find.descendant(
        of: find.byType(Drawer), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Tools'), 200,
        scrollable: drawerScrollable.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Worklist'), 50,
        scrollable: drawerScrollable.first);
    await tester.pumpAndSettle();
    expect(find.text('Worklist'), findsOneWidget);
  });
}
