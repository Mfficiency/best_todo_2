import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/models/countdown_timer.dart';
import 'package:besttodo/models/item_event.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/markdown_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String readNote(String folder) {
    final files = Directory('${root.path}${Platform.pathSeparator}$folder')
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, hasLength(1));
    return files.single.readAsStringSync();
  }

  test('task note carries title/description/notes/tags/history and hides '
      'the raw description + tags in frontmatter', () async {
    final task = Task(
      title: 'Buy groceries',
      description: 'Milk, eggs, bread',
      note: 'Check the coupon first',
      label: 'errand, urgent',
      createdAt: DateTime(2026, 8, 1, 9),
      dueDate: DateTime(2026, 8, 28),
      projectId: 'project_1',
    );
    final events = [
      ItemEvent(
        itemId: task.uid,
        seq: 1,
        at: DateTime(2026, 8, 1, 9),
        type: ItemEvent.typeCreated,
      ),
      ItemEvent(
        itemId: task.uid,
        seq: 2,
        at: DateTime(2026, 8, 2, 10),
        type: ItemEvent.typeEdited,
        patch: [FieldChange('title', 'Buy stuff', 'Buy groceries')],
      ),
    ];
    final reminder = Alarm(
      name: 'Groceries reminder',
      itemUid: task.uid,
      triggerAnchor: Alarm.anchorEnd,
      triggerOffsetMinutes: -15,
      melody: 'Chimes',
      volume: 0.5,
    );

    await MarkdownBackupService.writeVault(
      root: root,
      tasks: [task],
      archivedTasks: const [],
      binTasks: const [],
      projects: const [Project(id: 'project_1', name: 'Groceries project')],
      alarms: [reminder],
      timers: const [],
      itemEvents: events,
    );

    final content = readNote('Tasks');

    // Frontmatter: the "hidden" fields (Properties panel in Obsidian).
    expect(content, contains('status: active'));
    expect(content, contains('description: Milk, eggs, bread'));
    expect(content, contains('tags:\n  - errand\n  - urgent'));
    expect(content, contains('created: 2026-08-01T09:00:00.000'));
    expect(content, contains('reminders:\n  - 15m before end'));
    expect(content, contains('Chimes'));
    expect(content, contains('project: Groceries project'));

    // Visible body.
    expect(content, contains('# Buy groceries'));
    expect(content, contains('Milk, eggs, bread'));
    expect(content, contains('## Notes\n\nCheck the coupon first'));
    expect(content, contains('## Links\n\n[[errand]] [[urgent]]'));
    expect(content, contains('## Edit History'));
    expect(content, contains('Created'));
    expect(content, contains('title: Buy stuff → Buy groceries'));
  });

  test('placeholder sections appear for empty fields so every note has the '
      'same structure', () async {
    final task = Task(title: 'Bare task');
    await MarkdownBackupService.writeVault(
      root: root,
      tasks: [task],
      archivedTasks: const [],
      binTasks: const [],
      projects: const [],
      alarms: const [],
      timers: const [],
      itemEvents: const [],
    );
    final content = readNote('Tasks');
    expect(content, contains('_No description._'));
    expect(content, contains('_No notes._'));
    expect(content, contains('_No tags._'));
    expect(content, contains('_No recorded history._'));
  });

  test('archived and binned tasks land in the same Tasks folder, tagged '
      'with their status', () async {
    final active = Task(title: 'Active task');
    final archived = Task(title: 'Archived task', deletedAt: DateTime(2026, 1, 1));
    final binned = Task(title: 'Binned task', deletedAt: DateTime(2026, 1, 1));

    await MarkdownBackupService.writeVault(
      root: root,
      tasks: [active],
      archivedTasks: [archived],
      binTasks: [binned],
      projects: const [],
      alarms: const [],
      timers: const [],
      itemEvents: const [],
    );

    final files = Directory('${root.path}${Platform.pathSeparator}Tasks')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .toList();
    expect(files, hasLength(3));
    expect(
      files.firstWhere((c) => c.contains('# Active task')),
      contains('status: active'),
    );
    expect(
      files.firstWhere((c) => c.contains('# Archived task')),
      contains('status: archived'),
    );
    expect(
      files.firstWhere((c) => c.contains('# Binned task')),
      contains('status: binned'),
    );
  });

  test('project/alarm/timer notes follow the same section order', () async {
    final alarm = Alarm(
      name: 'Wake up',
      description: 'Weekday alarm',
      hour: 7,
      minute: 30,
      isRepeating: true,
      repeatDays: [1, 2, 3, 4, 5],
    );
    final linkedTimerTask = Task(uid: 'task_1', title: 'Launch project');
    final timer = CountdownTimerItem(
      label: 'Launch day',
      target: DateTime(2027, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      editedAt: DateTime(2026, 6, 1),
      notifyRoundNumbers: true,
      itemUid: 'task_1',
      tags: 'work',
    );

    await MarkdownBackupService.writeVault(
      root: root,
      tasks: [linkedTimerTask],
      archivedTasks: const [],
      binTasks: const [],
      projects: const [Project(id: 'p1', name: 'Home', description: 'House stuff')],
      alarms: [alarm],
      timers: [timer],
      itemEvents: const [],
    );

    final projectNote = readNote('Projects');
    expect(projectNote, contains('# Home'));
    expect(projectNote, contains('House stuff'));
    expect(projectNote, contains('## Notes\n\n_No notes._'));

    final alarmFiles = Directory('${root.path}${Platform.pathSeparator}Alarms')
        .listSync()
        .whereType<File>()
        .toList();
    expect(alarmFiles, hasLength(1));
    final alarmNote = alarmFiles.single.readAsStringSync();
    expect(alarmNote, contains('# Wake up'));
    expect(alarmNote, contains('Weekday alarm'));
    expect(alarmNote, contains('melody: Classic'));
    // Every alarm carries the reserved "alarm" tag, so Links is never empty.
    expect(alarmNote, contains('## Links\n\n[[alarm]]'));

    final timerFiles =
        Directory('${root.path}${Platform.pathSeparator}Countdown Timers')
            .listSync()
            .whereType<File>()
            .toList();
    expect(timerFiles, hasLength(1));
    final timerNote = timerFiles.single.readAsStringSync();
    expect(timerNote, contains('# Launch day'));
    expect(timerNote, contains('Last edited'));
    expect(timerNote, contains('## Links\n\n[[work]]'));
    expect(timerNote, contains('linkedTask: Launch project'));
  });

  test('Views folder describes every view\'s built-in rule, configured '
      'filtering and cosmetics', () async {
    await MarkdownBackupService.writeVault(
      root: root,
      tasks: const [],
      archivedTasks: const [],
      binTasks: const [],
      projects: const [],
      alarms: const [],
      timers: const [],
      itemEvents: const [],
    );

    final viewsDir = Directory('${root.path}${Platform.pathSeparator}Views');
    final names =
        viewsDir.listSync().whereType<File>().map((f) => f.path.split(Platform.pathSeparator).last).toSet();
    expect(
      names,
      {
        'Home.md',
        'Wishlist.md',
        'Waiting for Approval.md',
        'Projects.md',
        'Food Diary.md',
        'Research.md',
        'Alarms.md',
        'Countdown.md',
        'Archived items.md',
        'Deleted bin.md',
      },
    );

    String read(String name) =>
        File('${viewsDir.path}${Platform.pathSeparator}$name').readAsStringSync();

    final homeView = read('Home.md');
    expect(homeView, contains('Today'));
    expect(homeView, contains('overdue'));

    final wishlistView = read('Wishlist.md');
    expect(wishlistView, contains('Show only items tagged: Wish'));

    final archivedView = read('Archived items.md');
    expect(archivedView, contains('Show only items tagged: Archived'));

    final projectsView = read('Projects.md');
    expect(projectsView, contains('kanbanStatus'));
  });

  test('Settings note redacts the Todoist token and Google Calendar URL',
      () async {
    Config.todoistApiToken = 'super-secret-token';
    Config.googleCalendarUrl = 'https://calendar.google.com/secret-feed.ics';
    addTearDown(() {
      Config.todoistApiToken = '';
      Config.googleCalendarUrl = '';
    });

    await MarkdownBackupService.writeVault(
      root: root,
      tasks: const [],
      archivedTasks: const [],
      binTasks: const [],
      projects: const [],
      alarms: const [],
      timers: const [],
      itemEvents: const [],
    );

    final settings = File(
      '${root.path}${Platform.pathSeparator}Settings${Platform.pathSeparator}Settings.md',
    ).readAsStringSync();
    expect(settings, isNot(contains('super-secret-token')));
    expect(settings, isNot(contains('secret-feed.ics')));
    expect(settings, contains('hidden'));
  });
}
