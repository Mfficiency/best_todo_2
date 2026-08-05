import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:besttodo/services/task_widget_service.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // Opt out of the one-time Todo.md → wishlist import, which would otherwise
    // append its backlog to every list loaded here.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('test');
    StorageService.resetJournalBaselineForTest();
    StreakService.instance.resetForTest();
    Config.widgetCheckboxes = false;
  });

  tearDown(() {
    Config.widgetCheckboxes = false;
  });

  Task taskDue(String title, DateTime due,
          {bool done = false, int? ranking}) =>
      Task(
        title: title,
        dueDate: due,
        isDone: done,
        listRanking: ranking,
        createdAt: DateTime(2026, 1, 1),
      );

  test('the widget setting is off by default and round-trips', () {
    expect(Config.widgetCheckboxes, isFalse);

    Config.widgetCheckboxes = true;
    final map = Config.toMap();
    expect(map['widgetCheckboxes'], isTrue);

    Config.widgetCheckboxes = false;
    Config.applyMap(map);
    expect(Config.widgetCheckboxes, isTrue);
  });

  test('todayTasks keeps today + overdue, open ones first', () {
    final now = DateTime(2026, 8, 5, 10);
    final today = DateTime(2026, 8, 5);
    final tasks = [
      taskDue('done today', today, done: true, ranking: 1),
      taskDue('open today', today, ranking: 2),
      taskDue('overdue', today.subtract(const Duration(days: 2)), ranking: 3),
      taskDue('tomorrow', today.add(const Duration(days: 1)), ranking: 4),
      Task(title: 'no due date', createdAt: now),
    ];

    final rows = TaskWidgetService.todayTasks(tasks, now: now);

    expect(rows.map((t) => t.title).toList(),
        ['open today', 'overdue', 'done today']);
  });

  test('toggleInStorage completes a task in storage and back again', () async {
    final storage = StorageService();
    final task = taskDue('Water the plants', DateTime(2026, 8, 5), ranking: 1);
    await storage.saveTaskList([task]);

    final at = DateTime(2026, 8, 5, 9, 30);
    await TaskWidgetService.toggleInStorage(task.uid, now: at);

    var stored = await storage.loadTaskList();
    expect(stored.single.isDone, isTrue);
    expect(stored.single.completedAt, at);

    await TaskWidgetService.toggleInStorage(task.uid, now: at);
    stored = await storage.loadTaskList();
    expect(stored.single.isDone, isFalse);
    expect(stored.single.completedAt, isNull);
  });

  test('a completion from the widget counts toward the streak', () async {
    final storage = StorageService();
    final task = taskDue('Ship it', DateTime(2026, 8, 5), ranking: 1);
    await storage.saveTaskList([task]);

    final at = DateTime(2026, 8, 5, 9, 30);
    await TaskWidgetService.toggleInStorage(task.uid, now: at);

    expect(StreakService.instance.completionsOn(at), 1);

    // Un-checking it again takes the day back off the flame.
    await TaskWidgetService.toggleInStorage(task.uid, now: at);
    expect(StreakService.instance.completionsOn(at), 0);
  });

  testWidgets('the setting is searchable and switches Config', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    // initState kicks off the SMS config file load; walk real-event-loop
    // slices so the dart:io future completes inside testWidgets.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'checkbox');
    await tester.pump();
    expect(find.text('Check off tasks on the widget'), findsOneWidget);

    // Jumping there from the result opens the Widget section on the switch.
    await tester.tap(find.text('Check off tasks on the widget'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(
        SwitchListTile, 'Check off tasks on the widget'));
    // The handler awaits Config.save() before the rebuild lands.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(Config.widgetCheckboxes, isTrue);
  });

  test('every non-checkbox tap on the widget opens the task list', () {
    // The Kotlin side writes the URI as a literal, so the two halves of the
    // contract can only be checked against each other. `besttodotask://open`
    // is what makes `main.dart` pop back to the home page instead of resuming
    // on whatever page the app was left on.
    final provider = File('android/app/src/main/kotlin/com/example/'
        'best_todo_2/SimpleWidgetProvider.kt');
    if (!provider.existsSync()) return; // not checked out (e.g. pub package)
    final source = provider.readAsStringSync();

    final openUri = '${TaskWidgetService.scheme}://${TaskWidgetService.hostOpen}';
    expect(source, contains('Uri.parse("$openUri")'));

    // The progress line, the task rows and the summary text all use it.
    for (final id in const [
      'R.id.widget_container',
      'R.id.widget_text',
      'R.id.widget_progress_green',
      'R.id.widget_progress_orange',
      'R.id.widget_progress_red',
      'rowContainers[i]',
      'titleViews[i]',
    ]) {
      expect(source, contains('setOnClickPendingIntent($id, pendingIntent)'),
          reason: '$id should open the app');
    }

    // ...while the checkbox still toggles in the background.
    expect(source,
        contains('setOnClickPendingIntent(checkViews[i], toggleIntent)'));
  });

  test('an unknown id leaves storage untouched', () async {
    final storage = StorageService();
    final task = taskDue('Keep me', DateTime(2026, 8, 5), ranking: 1);
    await storage.saveTaskList([task]);

    await TaskWidgetService.toggleInStorage('no-such-uid');

    final stored = await storage.loadTaskList();
    expect(stored.single.isDone, isFalse);
  });
}
