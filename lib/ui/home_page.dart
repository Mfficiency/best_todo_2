import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/item_event.dart';
import '../models/streak_kind.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/alarm_service.dart';
import '../services/auto_backup_service.dart';
import '../services/auto_tag_service.dart';
import '../services/item_event_journal.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
import '../services/project_service.dart';
import '../services/reminder_sync_service.dart';
import '../services/share_intent_service.dart';
import '../services/storage_service.dart';
import '../services/streak_service.dart';
import '../services/sync_service.dart';
import '../services/todoist_sync_service.dart';
import '../services/task_widget_service.dart';
import '../services/test_report_service.dart';
import '../services/wishlist_migration.dart';
import '../services/wishlist_shipped.dart';
import '../utils/date_utils.dart';
import '../utils/task_utils.dart';
import 'about_page.dart';
import 'alarms_page.dart';
import 'app_logs_page.dart';
import 'archived_items_page.dart';
import 'calendar_view_page.dart' show ScheduleView, ScheduleViewState;
import 'changelog_page.dart';
import 'chronize_page.dart';
import 'countdown_timer_page.dart';
import 'deleted_bin_page.dart';
import 'dice_timer_page.dart';
import 'home_scaffold_key.dart';
import 'startup_times_page.dart';
import 'projects_page.dart';
import 'settings_page.dart';
import 'streak_celebration.dart';
import 'streak_flame_button.dart';
import 'task_tile.dart';
import 'test_results_page.dart';
import 'usage_data_page.dart';
import 'waiting_approval_page.dart';
import 'wishlist_page.dart';
import 'your_stats_page.dart';

/// One entry of the drawer's Tools section: its feature/tool key, the label
/// shown in the drawer and the icon in front of it.
class _ToolEntry {
  final String key;
  final String label;
  final IconData icon;

  const _ToolEntry(this.key, this.label, this.icon);
}

class HomePage extends StatefulWidget {
  final int initialTabIndex;

  const HomePage({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Current virtual date for the app. In dev mode this can be changed
  /// using the arrows in the app bar.
  DateTime _currentDate = DateTime.now();

  /// All tasks in the app. Tasks are assigned a dueDate when created and
  /// filtered into the appropriate lists based on [_currentDate].
  final List<Task> _tasks = [];
  /// Archived items ("Archived Items" page) — soft-deleted, capped by count,
  /// never purged by age.
  final List<Task> _deletedTasks = [];
  /// The real Deleted bin ("Deleted Items" page) — denials from Waiting for
  /// Approval, or archived items sent on manually. Purged after
  /// [Config.deletedItemsRetentionDays] days (see `StorageService.loadBinTaskList`).
  final List<Task> _binTasks = [];

  final Map<String, DailyTaskStats> _dailyStatsByDay = {};
  // Item store goes through the repository seam; _storageService remains for
  // backup/export tooling, which is about files rather than the item store.
  final ItemRepository _repository = ItemRepository.instance;
  final StorageService _storageService = StorageService();

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _homeKeyboardFocusNode =
      FocusNode(debugLabel: 'Home keyboard shortcuts');
  final FocusNode _addTaskFocusNode = FocusNode(debugLabel: 'Add task');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'Task search');
  final Map<String, TaskTileController> _taskTileControllers = {};
  String? _focusedTaskUid;

  /// Picks which of today's tasks the dice timer lands on.
  final Random _diceRandom = Random();

  /// Current search query; when non-empty every tab (and the schedule view)
  /// only shows tasks matching it.
  String _searchQuery = '';
  Timer? _midnightTimer;

  /// When true, the body renders one long schedule list with day-grouped
  /// sections; tab taps scroll that list instead of switching panes.
  bool _scheduleView =
      Config.startInScheduleView && Config.isFeatureEnabled('schedule_view');

  /// Day section currently scrolled to the top of the schedule view (the
  /// highlighted one). New tasks added while the schedule view is open are
  /// due on this day.
  DateTime? _scheduleActiveDate;
  final ScrollController _scheduleScrollController = ScrollController();
  final Map<int, GlobalKey> _scheduleTabAnchors = {
    for (var i = 0; i < 6; i++) i: GlobalKey(),
  };
  final GlobalKey<ScheduleViewState> _scheduleViewKey =
      GlobalKey<ScheduleViewState>();
  int _lastTabIndex = 0;

  static const int _futureTabIndex = 5;
  static final DateTime _futureDueDate = Task.futureBucketMarker;

  /// Day offsets for each non-future tab.
  static const List<int> _offsetDays = [0, 1, 2, 7, 30];

  /// Asset paths for tab icons used when a tab is not selected.
  static const List<String> _tabIconPaths = [
    'assets/icons/today.png',
    'assets/icons/tomorrow.png',
    'assets/icons/the_day_after.png',
    'assets/icons/next_week.png',
    'assets/icons/next_month.png',
    'assets/icons/next_year.png',
  ];

  List<Task> _buildDevDeletedSeed(DateTime referenceDate) {
    final now = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
      12,
    );
    const titles = <String>[
      'Lorem ipsum dolor sit amet',
      'Consectetur adipiscing elit',
      'Sed do eiusmod tempor',
      'Incididunt ut labore et dolore',
      'Magna aliqua ut enim ad',
      'Minim veniam quis nostrud',
      'Exercitation ullamco laboris nisi',
      'Ut aliquip ex ea commodo',
      'Duis aute irure dolor',
      'In reprehenderit in voluptate',
      'Velit esse cillum dolore',
      'Eu fugiat nulla pariatur',
      'Excepteur sint occaecat cupidatat',
      'Non proident sunt in culpa',
      'Qui officia deserunt mollit',
      'Anim id est laborum',
      'Curabitur pretium tincidunt lacus',
      'Nulla gravida orci a odio',
      'Nullam varius turpis et commodo',
      'Suspendisse potenti in faucibus',
    ];

    // 20 total deleted tasks across the last 2 weeks.
    // Includes examples of 1, 2, 3, 4, and 6 tasks completed in one day.
    const dayBuckets = <MapEntry<int, int>>[
      MapEntry(1, 6),
      MapEntry(2, 4),
      MapEntry(3, 3),
      MapEntry(5, 2),
      MapEntry(6, 1),
      MapEntry(8, 1),
      MapEntry(10, 1),
      MapEntry(12, 1),
      MapEntry(13, 1),
    ];

    final seeded = <Task>[];
    var titleIndex = 0;
    for (final bucket in dayBuckets) {
      final dayOffset = bucket.key;
      final count = bucket.value;
      for (var i = 0; i < count; i++) {
        final deletedAt =
            now.subtract(Duration(days: dayOffset, minutes: i * 7));
        // Alternate auto-deleted (done tasks swept at day rollover) and
        // manually-deleted seeds so dev can exercise both restore paths.
        final isAuto = (titleIndex % 2) == 0;
        seeded.add(
          Task(
            title: titles[titleIndex % titles.length],
            description: isAuto
                ? 'Seeded dev auto-deleted task'
                : 'Seeded dev manually-deleted task',
            createdAt: deletedAt.subtract(const Duration(days: 3)),
            completedAt:
                isAuto ? deletedAt.subtract(const Duration(hours: 1)) : null,
            movedAt: deletedAt.subtract(const Duration(days: 2)),
            rescheduledAt: deletedAt.subtract(const Duration(days: 2)),
            dueDate: deletedAt.subtract(const Duration(days: 1)),
            deletedAt: deletedAt,
            autoDeleted: isAuto,
            isDone: isAuto,
          ),
        );
        titleIndex++;
      }
    }
    seeded.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return seeded;
  }

  /// Auto-deleted-only seed used in dev mode to backfill existing dev users
  /// whose persisted deleted list pre-dates the `autoDeleted` flag.
  List<Task> _buildDevAutoDeletedBackfill(DateTime referenceDate) {
    final now = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
      12,
    );
    const titles = <String>[
      'Auto-swept morning routine',
      'Auto-swept inbox triage',
      'Auto-swept stand-up notes',
      'Auto-swept gym session',
      'Auto-swept code review',
      'Auto-swept journal entry',
    ];
    // Spread across different days so the date column varies in the UI.
    const dayOffsets = <int>[1, 2, 4, 7, 9, 11];
    final seeded = <Task>[];
    for (var i = 0; i < titles.length; i++) {
      final deletedAt =
          now.subtract(Duration(days: dayOffsets[i], minutes: i * 11));
      seeded.add(
        Task(
          title: titles[i],
          description: 'Seeded dev auto-deleted backfill',
          createdAt: deletedAt.subtract(const Duration(days: 3)),
          completedAt: deletedAt.subtract(const Duration(hours: 1)),
          movedAt: deletedAt.subtract(const Duration(days: 2)),
          rescheduledAt: deletedAt.subtract(const Duration(days: 2)),
          dueDate: deletedAt.subtract(const Duration(days: 1)),
          deletedAt: deletedAt,
          autoDeleted: true,
          isDone: true,
        ),
      );
    }
    return seeded;
  }

  /// Marker used to identify (and avoid duplicating) the dev-seeded future
  /// tasks across loads.
  static const String _devFutureTaskMarker = 'Seeded dev future task';

  /// Twenty seeded tasks with deadlines spread from tomorrow through about
  /// two months out, so dev builds always have data to drive the schedule
  /// view and the next-week / next-month tabs.
  List<Task> _buildDevFutureTasksSeed(DateTime referenceDate) {
    final base = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
      9,
    );
    final now = DateTime.now();
    const entries = <MapEntry<int, String>>[
      MapEntry(1, 'Review PR for auth refactor'),
      MapEntry(1, 'Call dentist to reschedule'),
      MapEntry(2, 'Pay credit card bill'),
      MapEntry(2, 'Submit weekly timesheet'),
      MapEntry(3, 'Coffee with Alex'),
      MapEntry(4, 'Renew gym membership'),
      MapEntry(6, 'Prep slides for team demo'),
      MapEntry(7, 'Annual physical at the doctor'),
      MapEntry(9, 'Book hotel for the conference trip'),
      MapEntry(12, 'File quarterly compliance report'),
      MapEntry(14, "Birthday — buy gift for Sam"),
      MapEntry(18, 'Renew passport'),
      MapEntry(22, 'Schedule annual roof inspection'),
      MapEntry(28, 'Draft tax return for accountant'),
      MapEntry(32, 'Take car in for 60k service'),
      MapEntry(38, 'Quarterly OKR review with manager'),
      MapEntry(44, 'Plan vacation itinerary'),
      MapEntry(50, 'Submit talk proposal for conference'),
      MapEntry(55, 'Renew domain registrations'),
      MapEntry(60, 'Start packing for apartment move'),
    ];
    final seeded = <Task>[];
    for (var i = 0; i < entries.length; i++) {
      final offset = entries[i].key;
      final title = entries[i].value;
      seeded.add(
        Task(
          title: title,
          description: _devFutureTaskMarker,
          createdAt: now,
          dueDate: base.add(Duration(days: offset)),
          listRanking: i + 1,
        ),
      );
    }
    return seeded;
  }

  /// Dev-only wishlist seed. The real backlog import
  /// ([StorageService] via `wishlist_migration`) is a one-time, flag-guarded
  /// event, so dev machines that already spent the flag come up with an empty
  /// wishlist. This rebuilds the [legacyTodoWishlistItems] backlog as wish
  /// tasks. Callers only invoke it when the list holds no wishes, so it never
  /// duplicates existing ones.
  List<Task> _buildDevWishlistSeed() {
    final now = DateTime.now();
    return [
      for (final legacy in legacyTodoWishlistItems)
        Task(
          uid: legacy.uid,
          title: legacy.title,
          description: legacy.description,
          label: legacyTodoImportLabel,
          createdAt: now,
          isWish: true,
        ),
    ];
  }

  /// Spreads the dev-seeded future tasks across the seed projects (one task
  /// per Kanban column in each project) so dev builds — including desktop
  /// and web, where the Projects tool is exercised with a mouse — open with
  /// populated project cards and boards. Only runs while none of the seeded
  /// tasks carries a project yet, so manual (re)assignments survive reloads.
  /// Dev-only: one task with a real time range (the schema-v2 interval) on
  /// today's tab and the first project's board, so start/end/duration can be
  /// inspected on its detail page without hand-editing JSON.
  void _seedDevRangeTask() {
    final day = _currentDate;
    _tasks.add(Task(
      title: 'Deep work block',
      description: 'Dev seed: a task with a real time range',
      createdAt: DateTime.now(),
      startAt: DateTime(day.year, day.month, day.day, 9),
      endAt: DateTime(day.year, day.month, day.day, 10, 30),
      hasExplicitTime: true,
      projectId: ProjectService.instance.list.isNotEmpty
          ? ProjectService.instance.list.first.id
          : null,
    ));
  }

  /// Dev-only: one wishlist item, so the Wishlist tool and the wish rows on
  /// the Future tab have data on platforms where the one-time Todo.md import
  /// cannot run (the browser has no files to import from).
  void _seedDevWishItem() {
    _tasks.add(Task(
      title: 'Learn to sail',
      description: 'Dev seed: a wishlist item',
      label: 'priority-medium',
      createdAt: DateTime.now(),
      isWish: true,
    ));
  }

  /// Dev-only: attaches a reminder to the seeded range task ("Deep work
  /// block", 15 min before its end) so the item-linked reminder row on the
  /// task-detail page and the linked alarm in the Alarms tool are testable
  /// right away. In-memory only — a real save persists it like any alarm.
  void _seedDevLinkedReminder() {
    Task? found;
    for (final task in _tasks) {
      if (task.deletedAt == null &&
          task.duration != null &&
          task.duration! > Duration.zero) {
        found = task;
        break;
      }
    }
    final target = found;
    if (target == null) return;
    final service = AlarmService.instance;
    if (service.list.any((a) => a.itemUid == target.uid)) return;
    final reminder = ReminderSyncService.buildReminder(target);
    if (reminder == null) return;
    service.alarms.value = [...service.list, reminder];
  }

  /// Dev-only: writes a small ready-made history for the first project-board
  /// task so the History timeline on the task-detail page has data on a
  /// fresh install — including in Chrome, where the journal lives in memory
  /// for the session. Uses the journal's normal append path.
  void _seedDevItemHistory() {
    Task? sample;
    Task? second;
    for (final task in _tasks) {
      if (task.projectId != null && task.deletedAt == null) {
        if (sample == null) {
          sample = task;
        } else {
          second = task;
          break;
        }
      }
    }
    if (sample == null) return;
    // Give the sample board tasks one label of every kind, so the structured
    // label registry fills itself on the first save and the kinds are
    // inspectable on the task-detail page (and as tags on the home tiles).
    if (sample.label.isEmpty) sample.label = 'urgent, priority-high';
    if (second != null && second.label.isEmpty) second.label = 'gift, old';
    final now = DateTime.now();
    // The second board task gets pre-journal, seeded events so the
    // "(reconstructed)" rendering of the history backfill is visible in dev
    // without waiting for the real once-per-install seeder.
    if (second != null) {
      ItemEventJournal.instance.recordEvents([
        ItemEvent(
          itemId: second.uid,
          seq: 0,
          at: now.subtract(const Duration(days: 30)),
          type: ItemEvent.typeCreated,
          patch: [FieldChange('title', null, second.title)],
          seeded: true,
        ),
        ItemEvent(
          itemId: second.uid,
          seq: 0,
          at: now.subtract(const Duration(days: 14)),
          type: ItemEvent.typeScheduled,
          seeded: true,
        ),
      ]);
    }
    ItemEventJournal.instance.recordEvents([
      ItemEvent(
        itemId: sample.uid,
        seq: 0,
        at: now.subtract(const Duration(days: 2)),
        type: ItemEvent.typeCreated,
        patch: [FieldChange('title', null, sample.title)],
      ),
      ItemEvent(
        itemId: sample.uid,
        seq: 0,
        at: now.subtract(const Duration(days: 1)),
        type: ItemEvent.typeScheduled,
        patch: [
          FieldChange('dueDate', null, sample.dueDate?.toIso8601String()),
        ],
      ),
      ItemEvent(
        itemId: sample.uid,
        seq: 0,
        at: now.subtract(const Duration(hours: 3)),
        type: ItemEvent.typeEdited,
        patch: [FieldChange('description', null, sample.description)],
      ),
    ]);
  }

  void _applyDevProjectSeed() {
    assignDevProjectSeed(
      _tasks
          .where((t) =>
              t.deletedAt == null && t.description == _devFutureTaskMarker)
          .toList(),
      ProjectService.instance.list,
    );
  }

  Map<String, DailyTaskStats> _buildDevDailyStatsSeed(DateTime referenceDate) {
    final seeds = <String, DailyTaskStats>{};
    final dayStart = DateTime(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    const pattern = <Map<String, int>>[
      {
        'opening': 7,
        'moved': 1,
        'doneOpening': 3,
        'created': 2,
        'doneCreated': 1
      },
      {
        'opening': 6,
        'moved': 2,
        'doneOpening': 2,
        'created': 1,
        'doneCreated': 0
      },
      {
        'opening': 5,
        'moved': 0,
        'doneOpening': 3,
        'created': 3,
        'doneCreated': 2
      },
      {
        'opening': 8,
        'moved': 1,
        'doneOpening': 4,
        'created': 0,
        'doneCreated': 0
      },
      {
        'opening': 4,
        'moved': 1,
        'doneOpening': 1,
        'created': 2,
        'doneCreated': 1
      },
      {
        'opening': 9,
        'moved': 2,
        'doneOpening': 5,
        'created': 1,
        'doneCreated': 1
      },
      {
        'opening': 3,
        'moved': 0,
        'doneOpening': 1,
        'created': 4,
        'doneCreated': 2
      },
    ];

    for (var offset = 13; offset >= 0; offset--) {
      final date = dayStart.subtract(Duration(days: offset));
      final key = _dayKey(date);
      final row = pattern[offset % pattern.length];
      final opening = row['opening'] ?? 0;
      final moved = row['moved'] ?? 0;
      final doneOpening = row['doneOpening'] ?? 0;
      final created = row['created'] ?? 0;
      final doneCreated = row['doneCreated'] ?? 0;

      final stats = DailyTaskStats(dayKey: key);

      for (var i = 0; i < opening; i++) {
        final id = 'dev_open_${key}_$i';
        stats.openingTaskIds.add(id);
        if (i < moved) {
          stats.movedFromOpeningTaskIds.add(id);
        } else if (i < moved + doneOpening) {
          stats.completedFromOpeningTaskIds.add(id);
        }
      }

      for (var i = 0; i < created; i++) {
        final id = 'dev_new_${key}_$i';
        stats.createdDuringDayTaskIds.add(id);
        if (i < doneCreated) {
          stats.completedFromCreatedTaskIds.add(id);
        }
      }

      seeds[key] = stats;
    }

    return seeds;
  }

  Future<void> _loadTasks() async {
    // loadTaskList also merges legacy wishlist.json items (and the one-time
    // Todo.md import) into the task list as isWish tasks.
    final loaded = await _repository.loadItems();
    final loadedDeleted = await _repository.loadDeletedItems();
    final loadedBin = await _repository.loadBinItems();
    final loadedDailyStats = await _repository.loadDailyStats();
    // A share-sheet task created while this load was reading the file can be
    // in memory (via ShareIntentService's consumer) *and* in the read result
    // (via its own save); keep the in-memory one only.
    if (_tasks.isNotEmpty) {
      final known = _tasks.map((t) => t.uid).toSet();
      loaded.removeWhere((t) => known.contains(t.uid));
    }
    // A fresh install does not come back empty: the merge above turns the
    // one-time Todo.md import into wish tasks. Only real (non-wish) tasks
    // decide whether the starter list still has to be seeded — otherwise a
    // first launch would silently skip it.
    final isFirstLaunch = !loaded.any((t) => !t.isWish);
    if (isFirstLaunch) {
      _tasks.addAll(
        Config.initialTasks.map((t) => Task(
              title: t,
              dueDate: _currentDate,
              createdAt: DateTime.now(),
            )),
      );
      _tasks.addAll(
        Config.initialFutureTasks.map(
          (t) => Task(
            title: t,
            createdAt: DateTime.now(),
            dueDate: _futureDueDate,
          ),
        ),
      );
      // The imported wishes follow the starter tasks, so the Today list opens
      // on them instead of on the old backlog.
      _tasks.addAll(loaded);
      if (Config.isDev) {
        _tasks.addAll(_buildDevFutureTasksSeed(_currentDate));
      }
    } else {
      _tasks.addAll(loaded);
      // Backfill the spread-out dev seed for existing dev installs so the
      // schedule view and the next-week / next-month tabs always have data.
      if (Config.isDev &&
          !_tasks.any((t) => t.description == _devFutureTaskMarker)) {
        _tasks.addAll(_buildDevFutureTasksSeed(_currentDate));
      }
    }
    // Backfill the wishlist for dev installs whose one-time backlog import
    // flag is already spent (so nothing else repopulates it). Runs only when
    // no wishes exist, keeping it idempotent across loads.
    if (Config.isDev && !_tasks.any((t) => t.isWish)) {
      final seeded = _buildDevWishlistSeed();
      // The seed lands after loadTaskList already ran its shipped-wish pass,
      // so apply it here too — otherwise a dev install shows the backlog
      // untagged until the next launch.
      applyShippedWishes(seeded);
      _tasks.addAll(seeded);
    }
    // Prepopulate the Projects tool in dev builds so the cards/boards have
    // data to drag around right away.
    if (Config.isDev) {
      _applyDevProjectSeed();
      // Fresh dev installs (and every web run, where nothing persists) also
      // get a visible item history, so the task-detail History timeline can
      // be tested immediately: Tools → Projects → open a board → tap a card.
      if (isFirstLaunch) {
        _seedDevRangeTask();
        _seedDevWishItem();
        _seedDevItemHistory();
        _seedDevLinkedReminder();
      }
    }
    if (loadedDeleted.isNotEmpty) {
      _deletedTasks.addAll(loadedDeleted);
      // Backfill auto-deleted seed items for dev users whose persisted
      // deleted list pre-dates the autoDeleted flag, so the new restore
      // path is visible without clearing storage.
      if (Config.isDev && !_deletedTasks.any((t) => t.autoDeleted)) {
        _deletedTasks.insertAll(0, _buildDevAutoDeletedBackfill(_currentDate));
        _deletedTasks.sort((a, b) {
          final ad = a.deletedAt;
          final bd = b.deletedAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });
        if (_deletedTasks.length > 100) {
          _deletedTasks.removeRange(100, _deletedTasks.length);
        }
        _saveDeletedTasks();
      }
    } else if (Config.isDev) {
      _deletedTasks.addAll(_buildDevDeletedSeed(_currentDate));
      _saveDeletedTasks();
    }
    _binTasks.addAll(loadedBin);
    // Recurring-series regeneration below has to see the archive and the bin
    // so a manually archived/binned instance's date stays skipped instead of
    // being silently recreated — see _refreshRecurringForTask.
    _refreshAllRecurringTasks();
    if (loadedDailyStats.isNotEmpty) {
      _dailyStatsByDay.addAll(loadedDailyStats);
    } else if (Config.isDev) {
      _dailyStatsByDay.addAll(_buildDevDailyStatsSeed(_currentDate));
      _saveDailyStats();
    }
    _initializeStatsForCurrentDay();
    await StreakService.instance.load();
    if (StreakService.instance.needsSeed) {
      // First run with the streak feature: backfill from the completion
      // history that already exists so the flame starts warm.
      StreakService.instance.seedFromHistory(
        tasks: [..._tasks, ..._deletedTasks],
        dailyStats: _dailyStatsByDay,
      );
      // Dev/demo builds (Chrome above all, where nothing persists between
      // runs) get a longer streak than the 14 days of seeded stats, so the
      // flame and the streak page have something to show off.
      if (Config.isDev) {
        StreakService.instance.seedDevStreak(now: _currentDate);
      }
    }
    LogService.add('HomePage._loadTasks',
        '*** Tasks loaded into widget (${_tasks.length}) ***');
    if (mounted) {
      setState(() {});
    }
    _saveTasks();
  }

  void _saveDeletedTasks() {
    _repository.saveDeletedItems(_deletedTasks);
  }

  void _saveBinTasks() {
    _repository.saveBinItems(_binTasks);
  }

  void _saveDailyStats() {
    _repository.saveDailyStats(_dailyStatsByDay);
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);

  bool _isFutureBucketDate(DateTime date) => _isSameDay(date, _futureDueDate);

  DateTime _dueDateForTab(int tabIndex) {
    if (tabIndex == _futureTabIndex) return _futureDueDate;
    return _currentDate.add(Duration(days: _offsetDays[tabIndex]));
  }

  String _dayKey(DateTime date) {
    final d = _dateOnly(date);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  void _refreshRecurringForTask(Task task) {
    if (task.recurrenceParentUid != null) return;
    final parentUid = task.uid;

    if (!task.isRecurring ||
        task.dueDate == null ||
        task.recurrenceEndDate == null) {
      _tasks.removeWhere((t) => t.recurrenceParentUid == parentUid);
      return;
    }

    final intervalDays =
        task.recurrenceIntervalDays < 1 ? 1 : task.recurrenceIntervalDays;
    task.recurrenceIntervalDays = intervalDays;
    final baseDate = _dateOnly(task.dueDate!);
    final endDate = _dateOnly(task.recurrenceEndDate!);

    final existingByKey = <String, Task>{};
    _tasks.removeWhere((t) {
      if (t.recurrenceParentUid != parentUid) return false;
      final dueDate = t.dueDate;
      if (dueDate == null) return true;
      final d = _dateOnly(dueDate);
      final diff = d.difference(baseDate).inDays;
      final valid = diff > 0 && diff % intervalDays == 0 && !d.isAfter(endDate);
      if (!valid) return true;
      existingByKey[_dayKey(d)] = t;
      return false;
    });

    // A date already accounted for in the archive or the bin was manually
    // archived — skip it here too, so it stays gone instead of being
    // silently recreated on the next refresh (see the class doc on
    // _deletedTasks/_binTasks).
    for (final t in _deletedTasks.followedBy(_binTasks)) {
      if (t.recurrenceParentUid != parentUid) continue;
      final dueDate = t.dueDate;
      if (dueDate == null) continue;
      existingByKey.putIfAbsent(_dayKey(_dateOnly(dueDate)), () => t);
    }

    for (var date = baseDate.add(Duration(days: intervalDays));
        !date.isAfter(endDate);
        date = date.add(Duration(days: intervalDays))) {
      final key = _dayKey(date);
      if (existingByKey.containsKey(key)) continue;
      _tasks.add(
        Task(
          title: task.title,
          description: task.description,
          note: task.note,
          label: task.label,
          createdAt: task.createdAt,
          completedAt: task.completedAt,
          movedAt: task.movedAt,
          rescheduledAt: task.rescheduledAt,
          dueDate: date,
          recurrenceParentUid: parentUid,
          recurrenceInstanceKey: key,
        ),
      );
    }
  }

  void _refreshAllRecurringTasks() {
    final parents = _tasks.where((t) => t.recurrenceParentUid == null).toList();
    for (final task in parents) {
      _refreshRecurringForTask(task);
    }
  }

  List<Task> _tasksDueOn(DateTime date) {
    return _tasks.where((task) {
      final dueDate = task.dueDate;
      if (dueDate == null) return false;
      return _isSameDay(dueDate, date);
    }).toList();
  }

  DailyTaskStats _getOrCreateDailyStats(DateTime date) {
    final key = _dayKey(date);
    return _dailyStatsByDay.putIfAbsent(
      key,
      () => DailyTaskStats(dayKey: key),
    );
  }

  void _initializeStatsForCurrentDay() {
    final key = _dayKey(_currentDate);
    if (_dailyStatsByDay.containsKey(key)) return;
    final stats = DailyTaskStats(dayKey: key);
    stats.openingTaskIds
        .addAll(_tasksDueOn(_currentDate).map((task) => task.uid));
    _dailyStatsByDay[key] = stats;
    _saveDailyStats();
  }

  void _trackTaskCreated(Task task) {
    final dueDate = task.dueDate;
    if (dueDate == null || !_isSameDay(dueDate, _currentDate)) return;
    final stats = _getOrCreateDailyStats(_currentDate);
    if (stats.openingTaskIds.contains(task.uid)) return;
    stats.createdDuringDayTaskIds.add(task.uid);
    if (task.isDone) {
      stats.completedFromCreatedTaskIds.add(task.uid);
    }
    _saveDailyStats();
  }

  void _trackTaskMove(Task task, DateTime? oldDueDate, DateTime? newDueDate) {
    if (oldDueDate == null && newDueDate == null) return;
    final currentDay = _dateOnly(_currentDate);
    final wasToday = oldDueDate != null && _isSameDay(oldDueDate, currentDay);
    final isToday = newDueDate != null && _isSameDay(newDueDate, currentDay);
    if (!wasToday && !isToday) return;

    final stats = _getOrCreateDailyStats(currentDay);
    if (wasToday && !isToday && stats.openingTaskIds.contains(task.uid)) {
      stats.movedFromOpeningTaskIds.add(task.uid);
      stats.completedFromOpeningTaskIds.remove(task.uid);
      _saveDailyStats();
      return;
    }
    if (!wasToday && isToday && !stats.openingTaskIds.contains(task.uid)) {
      stats.createdDuringDayTaskIds.add(task.uid);
      if (task.isDone) {
        stats.completedFromCreatedTaskIds.add(task.uid);
      }
      _saveDailyStats();
    }
  }

  void _trackTaskDoneState(Task task, bool wasDone) {
    if (task.isDone == wasDone) return;
    final dueDate = task.dueDate;
    if (dueDate == null || !_isSameDay(dueDate, _currentDate)) return;
    final stats = _getOrCreateDailyStats(_currentDate);
    final isDoneNow = task.isDone;
    if (stats.openingTaskIds.contains(task.uid)) {
      if (isDoneNow) {
        stats.completedFromOpeningTaskIds.add(task.uid);
      } else {
        stats.completedFromOpeningTaskIds.remove(task.uid);
      }
      _saveDailyStats();
      return;
    }
    stats.createdDuringDayTaskIds.add(task.uid);
    if (isDoneNow) {
      stats.completedFromCreatedTaskIds.add(task.uid);
    } else {
      stats.completedFromCreatedTaskIds.remove(task.uid);
    }
    _saveDailyStats();
  }

  /// Feeds a done-state change into the streak. On the first completion of
  /// the day (the moment the streak is kept) it plays the celebration when
  /// that setting is on. Uses [_currentDate] so the dev date arrows work.
  void _recordStreakToggle(Task task, bool wasDone) {
    if (task.isWish || task.isDone == wasDone) return;
    if (!Config.isFeatureEnabled('streak')) return;
    if (task.isDone) {
      final firstOfDay =
          StreakService.instance.recordCompletion(_currentDate);
      _recordGoalCompletion(task);
      if (firstOfDay &&
          Config.showStreak &&
          Config.streakCompletionAnimation &&
          mounted) {
        showStreakCelebration(
            context, StreakService.instance.currentStreak(now: _currentDate));
      }
    } else {
      StreakService.instance.recordUncompletion(_currentDate);
      _recordGoalUncompletion(task);
    }
  }

  /// Feeds a task completion into the user-configured goals of the
  /// customizable flames (green = [StreakKind.create], blue =
  /// [StreakKind.plan] — see [StreakGoal]). A flame with no goal configured
  /// simply has nothing to match against and stays cold.
  void _recordGoalCompletion(Task task) {
    for (final kind in const [StreakKind.create, StreakKind.plan]) {
      final goal = Config.streakGoals[kind.id];
      if (goal != null && goal.matches(task)) {
        StreakService.instance.recordGoal(kind, _currentDate);
      }
    }
  }

  /// Reverts a task's contribution to a configured goal when it is
  /// un-toggled, mirroring [StreakService.recordUncompletion] for the
  /// `complete` flame.
  void _recordGoalUncompletion(Task task) {
    for (final kind in const [StreakKind.create, StreakKind.plan]) {
      final goal = Config.streakGoals[kind.id];
      if (goal != null && goal.matches(task)) {
        StreakService.instance.recordUncompletion(_currentDate, kind: kind);
      }
    }
  }

  void _addToDeletedTasks(Task task, {bool autoDeleted = false}) {
    task.deletedAt = DateTime.now();
    task.autoDeleted = autoDeleted;
    _deletedTasks.insert(0, task);
    if (_deletedTasks.length > 100) {
      _deletedTasks.removeLast();
    }
  }

  int _listRankingForNewTask(int tabIndex, {required bool addToTop}) {
    final pendingTasks =
        _tasksForTab(tabIndex).where((task) => !task.isDone).toList();
    if (pendingTasks.isEmpty) return 1;

    if (addToTop) {
      final minRanking = pendingTasks
          .map((task) => task.listRanking ?? (1 << 31))
          .reduce((a, b) => a < b ? a : b);
      return minRanking - 1;
    }

    final maxRanking = pendingTasks
        .map((task) => task.listRanking ?? 0)
        .reduce((a, b) => a > b ? a : b);
    return maxRanking + 1;
  }

  @override
  void initState() {
    super.initState();
    final safeInitialTab =
        widget.initialTabIndex.clamp(0, Config.tabs.length - 1);
    _tabController = TabController(
      length: Config.tabs.length,
      vsync: this,
      initialIndex: safeInitialTab,
    );
    _lastTabIndex = _tabController.index;
    _tabController.addListener(() {
      setState(() {});
      final idx = _tabController.index;
      if (idx != _lastTabIndex) {
        _lastTabIndex = idx;
        if (_scheduleView) _scrollToScheduleAnchor(idx);
      }
    });
    Config.ensureVersionLoaded().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
    HomeWidget.setAppGroupId(TaskWidgetService.appGroupId)
        .catchError((_) => false);
    // Tasks ticked off on the home-screen widget are written to storage by the
    // widget's own isolate; on the way back into the app they are merged in.
    WidgetsBinding.instance.addObserver(this);
    // Text shared into the app from other apps becomes a task on Today.
    // Registering before _loadTasks means every share from here on goes
    // through this page's in-memory list — never a second tasks.json writer.
    ShareIntentService.instance.registerConsumer(_addSharedTask);
    // Lets the app shell reopen a live dice timer after its full-screen alarm
    // is stopped (see main.dart), with the task's actions ready.
    openRunningDiceTimer = _reopenRunningDiceTimer;
    // CI embeds its test results as a bundled asset; builds whose test run
    // had unacknowledged failures get a red dot on the Test Results drawer
    // entry — and on the hamburger icon itself when the "Red dot on menu"
    // setting is on. Opening the Test Results page clears the dots.
    TestReportService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
    // A sync failure from a previous run keeps its red dot on the App Logs
    // drawer entry until acknowledged; lazy load, nothing blocks startup.
    SyncService.instance.ensureLoaded();
    TodoistSyncService.instance.ensureLoaded();
    // Project names are shown as tags on task tiles, so load them here and
    // not only when the Projects tool is opened.
    ProjectService.instance.load();
    // Auto-tag rules are needed synchronously the moment a task is created,
    // so load them eagerly too rather than on first use.
    AutoTagService.instance.load();
    // Some tools (Chronize, Productivity Stats, ...) render the task data, so
    // the configured start tool is only opened once loading finished.
    _loadTasks().then((_) {
      _maybeOpenStartTool();
      // A due automatic backup runs after startup, off the critical path.
      unawaited(AutoBackupService.maybeRun());
    });
    _scheduleMidnightUpdate();
  }

  /// The page for a tool key from [Config.startToolOptions]; null for
  /// 'tasks' (the home page itself) and unknown keys.
  Widget? _buildToolPage(String tool) {
    // Simple mode and the per-feature switches hide a tool's entry points;
    // this guard also covers stale deep links and start-page settings.
    if (!Config.isFeatureEnabled(tool)) return null;
    switch (tool) {
      case 'alarms':
        return const AlarmsPage();
      case 'countdown':
        return const CountdownTimerPage();
      case 'wishlist':
        return const WishlistPage();
      case 'projects':
        return ProjectsPage(tasks: _tasks, onChanged: _saveTasks);
      case 'chronize':
        return ChronizePage(
          tasks: _tasks,
          onCreateTask: _addTaskFromChronize,
          onTaskChanged: _onChronizeTaskChanged,
          onDeleteTask: _deleteTaskFromChronize,
        );
      case 'usage_data':
        return UsageDataPage(
          tasks: _tasks,
          deletedTasks: _deletedTasks,
          dailyStatsByDay: _dailyStatsByDay,
        );
      case 'test_results':
        return const TestResultsPage();
      case 'productivity_stats':
        return YourStatsPage(
          tasks: _tasks,
          deletedItems: _deletedTasks,
          dailyStatsByDay: _dailyStatsByDay,
        );
    }
    return null;
  }

  /// Pushes the given tool's page. Used by the Tools drawer section and by
  /// the "Default start page" setting on launch.
  void _openTool(String tool) {
    final page = _buildToolPage(tool);
    if (page == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page))
        .then((_) {
      // Tools like Projects mutate tasks in place; refresh the lists when
      // coming back.
      if (mounted) setState(() {});
      // The Wishlist tool loads and saves the task list on its own, so this
      // page's in-memory copy is refreshed from disk when coming back.
      if (tool == 'wishlist') _reloadTasksFromStorage();
    });
  }

  Future<void> _reloadTasksFromStorage() async {
    // On the web nothing can have been persisted by the tool we're returning
    // from (no documents dir), so reloading would only wipe the in-memory
    // dev seeds. Keep the current list there.
    if (kIsWeb) return;
    final loaded = await _repository.loadItems();
    if (!mounted) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(loaded);
      _refreshAllRecurringTasks();
    });
    // The list the widget mirrors just changed under it (a Todoist pull, an
    // approval denied, a wishlist edit), and none of those went through
    // _saveTasks here — so push the fresh payload.
    _updateHomeWidget();
  }

  /// Pull-to-refresh on the task list: runs a two-way Todoist sync (a no-op
  /// if Todoist sync isn't enabled/configured) and reloads from storage so
  /// anything it pulled down shows up immediately.
  Future<void> _pullToRefreshSync() async {
    final entry = await TodoistSyncService.instance.syncNow(
      trigger: 'pull_to_refresh',
    );
    await _reloadTasksFromStorage();
    if (!mounted || entry == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(entry.success
            ? 'Synced ${entry.itemCount} change(s) with Todoist'
            : 'Todoist sync failed: ${entry.message}'),
      ));
  }

  /// Opens the tool configured as the default start page (if any) on top of
  /// the task list, so backing out of it lands on the tasks as usual.
  void _maybeOpenStartTool() {
    if (Config.startTool == 'tasks') return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openTool(Config.startTool);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
      // An app kept open across midnight still gets its scheduled backup.
      unawaited(AutoBackupService.maybeRun());
    }
  }

  /// Backgrounding the app (pause/hidden/detached) is also what triggers the
  /// Todoist quit-sync (see `TodoistSyncService.onLifecycleChanged`) — if it
  /// finished before the app came back, its pulls already sit in storage but
  /// this page's in-memory `_tasks` doesn't know yet. Reload first so
  /// `_mergeWidgetCompletions` (which can itself re-save `_tasks`) compares
  /// against that fresh copy instead of overwriting a pulled task it never
  /// saw.
  Future<void> _onResumed() async {
    await _reloadTasksFromStorage();
    await _mergeWidgetCompletions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareIntentService.instance.unregisterConsumer(_addSharedTask);
    if (openRunningDiceTimer == _reopenRunningDiceTimer) {
      openRunningDiceTimer = null;
    }
    _homeKeyboardFocusNode.dispose();
    _addTaskFocusNode.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _controller.dispose();
    _searchController.dispose();
    _scheduleScrollController.dispose();
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Reopens the dice timer page for a timer that is still live — used after
  /// its full-screen alarm was stopped. Never rolls a new task: with no live
  /// timer (e.g. the app was killed and relaunched by the alarm) it does
  /// nothing at all.
  void _reopenRunningDiceTimer() {
    if (!mounted) return;
    final controller = DiceTimerController.instance;
    if (!controller.isActive || controller.task == null) return;
    // The timer page can already be behind the alarm screen (the app was open
    // on it when zero came) — reopening would stack a second copy.
    if (controller.isPageVisible) return;
    _rollRandomTaskTimer();
  }

  /// Map a due date to the tab index that would own it in list mode.
  int _tabIndexForDueDate(DateTime? due) {
    if (due == null || _isFutureBucketDate(due)) return _futureTabIndex;
    final diff = dateDiffInDays(due, _currentDate);
    if (diff <= 0) return 0;
    if (diff == 1) return 1;
    if (diff == 2) return 2;
    if (diff < 30) return 3;
    return 4;
  }

  /// Map a task to the tab index that would own it in list mode. Used by
  /// the schedule view so each tile's "move to" menu hides the task's
  /// current bucket.
  int _tabIndexForTask(Task task) => _tabIndexForDueDate(task.dueDate);

  /// Reorder within one day section of the schedule view. Other tasks in
  /// the same tab keep their relative position; only the slice belonging
  /// to this section is shuffled.
  void _reorderTaskInSection(
    List<Task> sectionTasks,
    int oldIndex,
    int newIndex,
  ) {
    if (sectionTasks.isEmpty) return;
    // See _reorderTask: reordering is disabled while searching or while a
    // Home filter rule is hiding tasks.
    if (_searchQuery.trim().isNotEmpty || _homeFilterRulesActive) return;
    final pageIndex = _tabIndexForTask(sectionTasks.first);
    final fullList = _tasksForTab(pageIndex);

    final sectionSet = Set<Task>.identity()..addAll(sectionTasks);
    final sectionPositions = <int>[];
    for (var i = 0; i < fullList.length; i++) {
      if (sectionSet.contains(fullList[i])) sectionPositions.add(i);
    }
    if (sectionPositions.length != sectionTasks.length) return;
    if (oldIndex < 0 || oldIndex >= sectionTasks.length) return;
    if (newIndex < 0 || newIndex > sectionTasks.length) return;

    final reordered = List<Task>.from(sectionTasks);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    for (var k = 0; k < sectionPositions.length; k++) {
      fullList[sectionPositions[k]] = reordered[k];
    }

    setState(() {
      for (var i = 0; i < fullList.length; i++) {
        fullList[i].listRanking = i + 1;
      }
    });
    _saveTasks();
    LogService.add(
      'HomePage._reorderTaskInSection',
      'Reordered "${moved.title}" within day section of tab $pageIndex',
    );
  }

  void _scrollToScheduleAnchor(int tabIndex) {
    _scheduleViewKey.currentState?.scrollToSection(tabIndex);
  }

  void _scheduleMidnightUpdate() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final duration = tomorrow.difference(now);
    _midnightTimer = Timer(duration, () {
      _updateHomeWidget();
      _scheduleMidnightUpdate();
    });
  }

  /// Tab a task typed into the add-task row belongs to: the bucket pinned in
  /// Settings ("New tasks go to"), or the tab currently open when that is left
  /// at "Current tab".
  int _addTargetTabIndex() {
    final pinned = Config.defaultAddTabIndex;
    if (pinned < 0 || pinned >= Config.tabs.length) return _tabController.index;
    return pinned;
  }

  void _addTask(String title) {
    if (title.trim().isEmpty) return;
    // In schedule view new tasks land on the highlighted (active) day; in
    // list mode they go to the default bucket (the current tab unless one is
    // pinned in Settings).
    final dueDate = _scheduleView && _scheduleActiveDate != null
        ? _scheduleActiveDate!
        : _dueDateForTab(_addTargetTabIndex());
    final rankingTabIndex = _tabIndexForDueDate(dueDate);
    final task = Task(
      title: title,
      label: AutoTagService.instance.withAutoTags(title, ''),
      createdAt: DateTime.now(),
      dueDate: dueDate,
      listRanking: _listRankingForNewTask(
        rankingTabIndex,
        addToTop: Config.addNewTasksToTop,
      ),
    );
    setState(() {
      _tasks.add(task);
    });
    _trackTaskCreated(task);
    _controller.clear();
    _saveTasks();
    LogService.add('HomePage._addTask', 'Added task: $title');
  }

  bool _isDesktopShortcutsEnabled(BuildContext context) {
    final platform = defaultTargetPlatform;
    final desktopPlatform = kIsWeb ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    return desktopPlatform && MediaQuery.of(context).size.width >= 700;
  }

  bool get _primaryFocusIsTextInput {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null && context.widget is EditableText;
  }

  TaskTileController _controllerForTask(Task task) {
    return _taskTileControllers.putIfAbsent(
      task.uid,
      TaskTileController.new,
    );
  }

  List<Task> _keyboardTasks() => _tasksForTab(_tabController.index);

  int _focusedTaskIndex(List<Task> tasks) {
    final uid = _focusedTaskUid;
    if (uid == null) return -1;
    return tasks.indexWhere((task) => task.uid == uid);
  }

  Task? _focusedTask() {
    final tasks = _keyboardTasks();
    final index = _focusedTaskIndex(tasks);
    if (index < 0) return null;
    return tasks[index];
  }

  Task? _ensureFocusedTask() {
    final tasks = _keyboardTasks();
    if (tasks.isEmpty) {
      if (_focusedTaskUid != null) setState(() => _focusedTaskUid = null);
      return null;
    }
    final currentIndex = _focusedTaskIndex(tasks);
    if (currentIndex >= 0) return tasks[currentIndex];
    setState(() => _focusedTaskUid = tasks.first.uid);
    return tasks.first;
  }

  void _moveFocusedTask(int delta) {
    final tasks = _keyboardTasks();
    if (tasks.isEmpty) {
      setState(() => _focusedTaskUid = null);
      return;
    }
    final currentIndex = _focusedTaskIndex(tasks);
    final nextIndex = currentIndex < 0
        ? (delta > 0 ? 0 : tasks.length - 1)
        : (currentIndex + delta).clamp(0, tasks.length - 1);
    setState(() => _focusedTaskUid = tasks[nextIndex].uid);
    _homeKeyboardFocusNode.requestFocus();
  }

  void _focusAfterKeyboardAction(int pageIndex, int originalIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tasks = _tasksForTab(pageIndex);
      setState(() {
        if (tasks.isEmpty) {
          _focusedTaskUid = null;
        } else {
          final nextIndex = originalIndex.clamp(0, tasks.length - 1);
          _focusedTaskUid = tasks[nextIndex].uid;
        }
      });
      _homeKeyboardFocusNode.requestFocus();
    });
  }

  void _toggleTask(Task task) {
    final wasDone = task.isDone;
    setState(() {
      task.toggleDone();
      task.completedAt = task.isDone ? DateTime.now() : null;
    });
    _trackTaskDoneState(task, wasDone);
    _recordStreakToggle(task, wasDone);
    _saveTasks();
  }

  Future<void> _openSettingsPage() {
    return Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          onSettingsChanged: _updateSettings,
          onExportTasksRequested: _exportTasks,
          onExportSettingsRequested: _exportSettingsOnly,
          onExportEverythingRequested: _exportEverything,
          onImportRequested: _importAutoDetect,
        ),
      ),
    )
        .then((_) {
      // Settings is where Todoist "Sync now" lives — a pull there (a new
      // task, a label/edit picked up from Todoist) writes straight to
      // storage but never touches this page's in-memory _tasks. Without
      // this, a pulled task stays invisible until the app is fully
      // restarted, even though the sync itself succeeded.
      if (mounted) _reloadTasksFromStorage();
    });
  }

  void _focusSearch() {
    if (!Config.isFeatureEnabled('search')) return;
    _searchFocusNode.requestFocus();
  }

  void _focusAddTask() {
    _addTaskFocusNode.requestFocus();
  }

  void _openFocusedTask() {
    final task = _ensureFocusedTask();
    if (task == null) return;
    _controllerForTask(task).open();
    _homeKeyboardFocusNode.requestFocus();
  }

  void _handleSideArrow(LogicalKeyboardKey key) {
    final task = _ensureFocusedTask();
    if (task == null) return;
    final controller = _controllerForTask(task);
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final directionIsMove =
        isRight ? Config.swipeLeftDelete : !Config.swipeLeftDelete;
    final sameOpenMenu = (directionIsMove && controller.hasMoveOptions) ||
        (!directionIsMove && controller.hasDeleteOptions);
    if (controller.hasOptions) {
      if (sameOpenMenu) {
        controller.stepOptions();
      } else {
        controller.closeOptions();
      }
      return;
    }
    if (directionIsMove) {
      controller.startMoveOptions();
    } else {
      controller.startDeleteOptions();
    }
  }

  KeyEventResult _handleAddTaskKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final enterPressed = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (Config.enterSavesNewTask &&
        enterPressed &&
        !ctrlPressed &&
        !shiftPressed) {
      _addTask(_controller.text);
      return KeyEventResult.handled;
    }
    if (!Config.enterSavesNewTask && ctrlPressed && enterPressed) {
      _addTask(_controller.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleHomeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_isDesktopShortcutsEnabled(context)) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (ctrlPressed && key == LogicalKeyboardKey.comma) {
      _openSettingsPage();
      return KeyEventResult.handled;
    }
    if (ctrlPressed && key == LogicalKeyboardKey.keyF) {
      _focusSearch();
      return KeyEventResult.handled;
    }
    if (ctrlPressed && key == LogicalKeyboardKey.keyN) {
      _focusAddTask();
      return KeyEventResult.handled;
    }

    if (_primaryFocusIsTextInput) {
      if (key == LogicalKeyboardKey.escape) {
        FocusManager.instance.primaryFocus?.unfocus();
        _homeKeyboardFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _moveFocusedTask(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveFocusedTask(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowLeft:
        _handleSideArrow(key);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        final task = _focusedTask();
        final controller = task == null ? null : _controllerForTask(task);
        if (controller?.hasOptions ?? false) {
          controller!.confirmOptions();
        } else {
          _openFocusedTask();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        final task = _ensureFocusedTask();
        if (task != null) _toggleTask(task);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        final tasks = _keyboardTasks();
        final index = _focusedTaskIndex(tasks);
        if (index >= 0) _deleteTask(_tabController.index, index);
        _focusAfterKeyboardAction(_tabController.index, index);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        final task = _focusedTask();
        _taskTileControllers[task?.uid]?.closeOptions();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Creates a task from text shared into the app (Android share sheet) —
  /// always due today, whatever tab or view is open.
  void _addSharedTask(String text) {
    final task = ShareIntentService.buildTask(text);
    task.listRanking = _listRankingForNewTask(
      0,
      addToTop: Config.addNewTasksToTop,
    );
    setState(() {
      _tasks.add(task);
    });
    _trackTaskCreated(task);
    _saveTasks();
    LogService.add(
        'HomePage._addSharedTask', 'Added shared task: ${task.title}');
  }

  /// Creates a task from the Chronize timeline at an explicit deadline
  /// (date + time), preserving the chosen time of day.
  void _addTaskFromChronize(String title, DateTime dueDate) {
    if (title.trim().isEmpty) return;
    final trimmedTitle = title.trim();
    final task = Task(
      title: trimmedTitle,
      label: AutoTagService.instance.withAutoTags(trimmedTitle, ''),
      createdAt: DateTime.now(),
      dueDate: dueDate,
      hasExplicitTime: true,
      listRanking: 1 << 30,
    );
    setState(() {
      _tasks.add(task);
    });
    _trackTaskCreated(task);
    _saveTasks();
    LogService.add('HomePage._addTaskFromChronize',
        'Added "$title" due ${dueDate.toIso8601String()}');
  }

  /// Persists in-place edits made to a task from the Chronize timeline.
  void _onChronizeTaskChanged() {
    setState(() {});
    _saveTasks();
  }

  /// Deletes a task chosen on the Chronize timeline, moving it to the deleted
  /// list (consistent with the rest of the app).
  void _deleteTaskFromChronize(Task task) {
    final index = _tasks.indexOf(task);
    if (index < 0) return;
    setState(() {
      _tasks.removeAt(index);
      _tasks.removeWhere((t) => t.recurrenceParentUid == task.uid);
    });
    _addToDeletedTasks(task);
    _saveTasks();
    _saveDeletedTasks();
    LogService.add(
        'HomePage._deleteTaskFromChronize', 'Deleted "${task.title}"');
  }

  void _moveTaskToNextPage(int pageIndex, int index) {
    final tasks = _tasksForTab(pageIndex);
    int destination = pageIndex + 1;
    if (destination >= Config.tabs.length) {
      destination = 0;
    }
    if (index >= tasks.length) return;
    final task = tasks[index];
    if (task.recurrenceParentUid != null) {
      task.recurrenceParentUid = null;
      task.recurrenceInstanceKey = null;
    }
    final oldDueDate = task.dueDate;
    final newDueDate = _dueDateForTab(destination);
    setState(() {
      task.dueDate = newDueDate;
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
      _refreshRecurringForTask(task);
    });
    _trackTaskMove(task, oldDueDate, newDueDate);
    _saveTasks();
    LogService.add('HomePage._moveTaskToNextPage',
        'Moved "${task.title}" to page $destination');
  }

  void _moveTask(int pageIndex, int index, int destination) {
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    if (task.recurrenceParentUid != null) {
      task.recurrenceParentUid = null;
      task.recurrenceInstanceKey = null;
    }
    final oldDueDate = task.dueDate;
    final newDueDate = _dueDateForTab(destination);
    setState(() {
      task.dueDate = newDueDate;
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
      _refreshRecurringForTask(task);
    });
    _trackTaskMove(task, oldDueDate, newDueDate);
    _saveTasks();
    LogService.add(
        'HomePage._moveTask', 'Moved "${task.title}" to page $destination');
  }

  DateTime _nextWeekdayDate(int weekday) {
    final start = _dateOnly(_currentDate);
    var daysUntil = (weekday - start.weekday) % 7;
    if (daysUntil == 0) daysUntil = 7;
    return start.add(Duration(days: daysUntil));
  }

  void _moveTaskToWeekday(int pageIndex, int index, int weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) return;
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    if (task.recurrenceParentUid != null) {
      task.recurrenceParentUid = null;
      task.recurrenceInstanceKey = null;
    }
    final oldDueDate = task.dueDate;
    final newDueDate = _nextWeekdayDate(weekday);
    setState(() {
      task.dueDate = newDueDate;
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
      _refreshRecurringForTask(task);
    });
    _trackTaskMove(task, oldDueDate, newDueDate);
    _saveTasks();
    LogService.add(
      'HomePage._moveTaskToWeekday',
      'Moved "${task.title}" to ${newDueDate.toIso8601String()}',
    );
  }

  void _reorderTask(int pageIndex, int oldIndex, int newIndex) {
    // Reordering a search- or filter-rule-narrowed list would renumber only
    // the visible subset and scramble the hidden tasks' order, so it is
    // disabled while either is active.
    if (_searchQuery.trim().isNotEmpty || _homeFilterRulesActive) return;
    final tasks = _tasksForTab(pageIndex);
    if (oldIndex >= tasks.length || newIndex > tasks.length) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final task = tasks.removeAt(oldIndex);
      tasks.insert(newIndex, task);
      for (var i = 0; i < tasks.length; i++) {
        tasks[i].listRanking = i + 1;
      }
    });
    _saveTasks();
    LogService.add('HomePage._reorderTask',
        'Reordered task to position ${newIndex + 1} on page $pageIndex');
  }

  void _deleteTask(int pageIndex, int index) {
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    final originalIndex = _tasks.indexOf(task);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _tasks.removeAt(originalIndex);
      _tasks.removeWhere((t) => t.recurrenceParentUid == task.uid);
    });
    _saveTasks();
    LogService.add('HomePage._deleteTask', 'Deleted "${task.title}"');

    late Timer timer;
    timer = Timer(Config.delayDuration, () {
      if (!mounted) return;
      setState(() {
        _addToDeletedTasks(task);
      });
      _saveDeletedTasks();
      // Explicitly close the snackbar when its undo window expires.
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${task.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                _tasks.insert(originalIndex, task);
                _refreshRecurringForTask(task);
              });
              _saveTasks();
              LogService.add(
                  'HomePage._deleteTask', 'Restored from undo "${task.title}"');
            },
          ),
        ),
      );
  }

  void _restoreTask(Task task) {
    setState(() {
      _deletedTasks.remove(task);
      task.deletedAt = null;
      task.autoDeleted = false;
      // Wishlist items stay undated so they return to the wishlist/Future
      // bucket instead of today's list.
      if (!task.isWish) task.dueDate = _currentDate;
      _tasks.add(task);
      _refreshRecurringForTask(task);
    });
    _saveTasks();
    _saveDeletedTasks();
    LogService.add('HomePage._restoreTask', 'Restored "${task.title}"');
  }

  /// Sends an archived item on to the real Deleted bin, where it starts
  /// aging toward permanent purge (see [Config.deletedItemsRetentionDays]).
  void _moveArchivedToBin(Task task) {
    final index = _deletedTasks.indexOf(task);
    if (index < 0) return;
    setState(() {
      _deletedTasks.removeAt(index);
      // Re-stamp the timestamp: retention is measured from bin entry, not
      // from the original archive time.
      task.deletedAt = DateTime.now();
      _binTasks.insert(0, task);
    });
    _saveDeletedTasks();
    _saveBinTasks();
    LogService.add(
        'HomePage._moveArchivedToBin', 'Moved "${task.title}" to the bin');
  }

  /// Restores a task straight out of the real Deleted bin back into the
  /// active list, mirroring [_restoreTask].
  void _restoreFromBin(Task task) {
    setState(() {
      _binTasks.remove(task);
      task.deletedAt = null;
      task.autoDeleted = false;
      if (!task.isWish) task.dueDate = _currentDate;
      _tasks.add(task);
      _refreshRecurringForTask(task);
    });
    _saveTasks();
    _saveBinTasks();
    LogService.add(
        'HomePage._restoreFromBin', 'Restored "${task.title}" from the bin');
  }

  /// Erases a bin item for good. Only reachable from the real Deleted bin —
  /// archived items are sent to the bin first (see [_moveArchivedToBin]).
  void _deleteTaskPermanently(Task task) {
    final originalIndex = _binTasks.indexOf(task);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _binTasks.removeAt(originalIndex);
    });
    _saveBinTasks();
    LogService.add('HomePage._deleteTaskPermanently',
        'Queued permanent delete "${task.title}"');

    late Timer timer;
    timer = Timer(Config.delayDuration, () {
      if (!mounted) return;
      // Explicitly close the snackbar when its undo window expires.
      messenger.hideCurrentSnackBar();
      LogService.add('HomePage._deleteTaskPermanently',
          'Permanent delete finalized "${task.title}"');
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Permanently deleted "${task.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                final insertAt = originalIndex <= _binTasks.length
                    ? originalIndex
                    : _binTasks.length;
                _binTasks.insert(insertAt, task);
              });
              _saveBinTasks();
              LogService.add('HomePage._deleteTaskPermanently',
                  'Restored from undo "${task.title}"');
            },
          ),
        ),
      );
  }

  /// Rolls the dice: picks a random open task from today's tab and opens the
  /// rotary egg-timer page for it. If a timer is already running, returns to it
  /// instead of rolling a new one.
  void _rollRandomTaskTimer() {
    final controller = DiceTimerController.instance;
    final Task task;
    if (controller.isActive && controller.task != null) {
      task = controller.task!;
      LogService.add('HomePage._rollRandomTaskTimer',
          'Returned to running timer for "${task.title}"');
    } else {
      final candidates =
          _tasksForTab(0, applySearch: false).where((t) => !t.isDone).toList();
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('No open tasks for today')),
          );
        return;
      }
      task = candidates[_diceRandom.nextInt(candidates.length)];
      LogService.add(
          'HomePage._rollRandomTaskTimer', 'Dice picked "${task.title}"');
    }
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => DiceTimerPage(
          task: task,
          onTaskDone: () => _completeTaskFromDice(task),
          onTaskPostponed: () => _postponeTaskFromDice(task),
        ),
      ),
    )
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Double-tap → "Start timer": opens the same egg-timer page the dice
  /// uses, but for [task] specifically, with the countdown already running at
  /// the default duration — grabbing the dial still pauses and rewinds it
  /// like any dice timer. Double-tapping the task whose timer is already
  /// live just returns to it; picking a different task replaces the old
  /// timer, since the double tap is an explicit choice for this one.
  void _startTaskTimer(Task task) {
    final controller = DiceTimerController.instance;
    if (controller.isActive && identical(controller.task, task)) {
      LogService.add('HomePage._startTaskTimer',
          'Returned to running timer for "${task.title}"');
    } else {
      controller.configure(task);
      controller.releaseDial();
      LogService.add(
          'HomePage._startTaskTimer', 'Started timer for "${task.title}"');
    }
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => DiceTimerPage(
          task: task,
          caption: 'Timer for',
          captionIcon: Icons.timer_outlined,
          onTaskDone: () => _completeTaskFromDice(task),
          onTaskPostponed: () => _postponeTaskFromDice(task),
        ),
      ),
    )
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  /// The dice timer rang and the user confirmed the task is done.
  void _completeTaskFromDice(Task task) {
    if (task.isDone) return;
    setState(() {
      task.isDone = true;
      task.completedAt = DateTime.now();
    });
    _trackTaskDoneState(task, false);
    _recordStreakToggle(task, false);
    _saveTasks();
    LogService.add(
        'HomePage._completeTaskFromDice', 'Completed "${task.title}"');
  }

  /// The dice timer rang and the user postponed the task to tomorrow.
  void _postponeTaskFromDice(Task task) {
    if (task.recurrenceParentUid != null) {
      task.recurrenceParentUid = null;
      task.recurrenceInstanceKey = null;
    }
    final oldDueDate = task.dueDate;
    final newDueDate = _dueDateForTab(1);
    setState(() {
      task.dueDate = newDueDate;
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
      _refreshRecurringForTask(task);
    });
    _trackTaskMove(task, oldDueDate, newDueDate);
    _saveTasks();
    LogService.add('HomePage._postponeTaskFromDice',
        'Postponed "${task.title}" to tomorrow');
  }

  /// The drawer's Home entry: back to the start screen. Any tool or subpage
  /// stacked on top of the home page is popped, an active search is dropped
  /// and the list returns to the tab (and view) the app opens on, so "Home"
  /// always lands on the same familiar screen.
  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      if (_searchQuery.isNotEmpty) {
        _searchController.clear();
        _searchQuery = '';
      }
      _scheduleView = Config.isFeatureEnabled('schedule_view') &&
          Config.startInScheduleView;
    });
    final startTab = Config.startTabIndex.clamp(0, Config.tabs.length - 1);
    if (_tabController.index != startTab) {
      _tabController.animateTo(startTab);
    }
    LogService.add('HomePage._goHome', 'Returned to the home screen');
  }

  void _updateSettings() {
    setState(() {
      // Switching to simple mode (or turning a feature off) while its view is
      // active would leave the home page in a state with no way back, so both
      // are reset here.
      if (!Config.isFeatureEnabled('schedule_view')) _scheduleView = false;
      if (!Config.isFeatureEnabled('search') && _searchQuery.isNotEmpty) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
    _updateHomeWidget();
    LogService.add('HomePage._updateSettings', 'Settings updated');
  }

  /// Change the current virtual date by the given number of days.
  /// When moving forward, overdue tasks remain visible in the Today tab.
  void _changeDate(int delta) {
    setState(() {
      _currentDate = _currentDate.add(Duration(days: delta));
      // Move completed tasks to the deleted list when progressing to the next
      // day so that finished items no longer clutter the lists.
      if (delta > 0) {
        final doneTasks = _tasks.where((t) => t.isDone).toList();
        for (final task in doneTasks) {
          _tasks.remove(task);
          _addToDeletedTasks(task, autoDeleted: true);
        }
      }
    });
    _initializeStatsForCurrentDay();
    _saveTasks();
    _saveDeletedTasks();
    LogService.add(
        'HomePage._changeDate', 'Changed date by $delta to $_currentDate');
  }

  Future<void> _updateHomeWidget() => TaskWidgetService.sync(_tasks);

  /// Picks up completions made on the home-screen widget while the app was in
  /// the background ([Config.widgetCheckboxes]). The widget writes straight to
  /// `tasks.json` from its own isolate, so without this the in-memory list
  /// would overwrite the change on the next save. Only the done state is
  /// merged — everything else in memory is newer than the file.
  Future<void> _mergeWidgetCompletions() async {
    if (!Config.widgetCheckboxes) return;
    // Deliberately the raw read: loadTaskList's day-rollover sweep would fight
    // the in-memory list on a resume that crosses midnight.
    final stored = await _storageService.readTaskListRaw();
    if (!mounted || stored.isEmpty) return;
    final doneByUid = {for (final t in stored) t.uid: t};
    final changed = <Task>[];
    for (final task in _tasks) {
      final other = doneByUid[task.uid];
      if (other == null || other.isDone == task.isDone) continue;
      changed.add(task);
    }
    if (changed.isEmpty) return;
    setState(() {
      for (final task in changed) {
        final other = doneByUid[task.uid]!;
        task.isDone = other.isDone;
        task.completedAt = other.completedAt;
      }
    });
    for (final task in changed) {
      // The streak was already recorded by the widget's isolate; the daily
      // stats live only here, so they catch up now.
      _trackTaskDoneState(task, !task.isDone);
    }
    _saveTasks();
    LogService.add('HomePage._mergeWidgetCompletions',
        'Merged ${changed.length} widget completion(s)');
  }

  void _saveTasks() {
    for (var i = 0; i < Config.tabs.length; i++) {
      final listTasks = _tasksForTab(i, applySearch: false);
      for (var j = 0; j < listTasks.length; j++) {
        listTasks[j].listRanking = j + 1;
      }
    }
    // Default every deadline time to 18:00, bumping to 18:01, 18:02, ... when
    // multiple tasks land on the same day so no two share a time.
    applyDefaultDeadlineTimes(_tasks);
    _repository.saveItems(_tasks);
    _updateHomeWidget();
  }

  String _timestampForFilename() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<String?> _pickDirectory() async {
    final downloadsDir = await getDownloadsDirectory();
    return getDirectoryPath(initialDirectory: downloadsDir?.path);
  }

  Future<void> _exportSettingsOnly() async {
    final directory = await _pickDirectory();
    if (directory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    final sep = Platform.pathSeparator;
    final path =
        '$directory${directory.endsWith(sep) ? '' : sep}settings_${_timestampForFilename()}.json';
    final file = File(path);
    final payload = <String, dynamic>{
      'export_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': Config.toMap(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
  }

  Future<void> _exportTasks() async {
    final ts = _timestampForFilename();
    final directory = await _pickDirectory();
    if (directory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    final sep = Platform.pathSeparator;
    final path =
        '$directory${directory.endsWith(sep) ? '' : sep}tasks_$ts.json';
    final file = await _storageService.exportTaskData(
      tasks: _tasks,
      deletedTasks: _deletedTasks,
      dailyStatsByDay: _dailyStatsByDay,
      path: path,
    );
    if (!mounted) return;
    final message =
        file != null ? 'Exported to ${file.path}' : 'Failed to export tasks';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportEverything() async {
    final directory = await _pickDirectory();
    if (directory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    final sep = Platform.pathSeparator;
    final path =
        '$directory${directory.endsWith(sep) ? '' : sep}besttodo_export_${_timestampForFilename()}.json';
    final timers = await _storageService.loadCountdownTimers();
    final payload = <String, dynamic>{
      'export_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': Config.toMap(),
      'tasks_bundle': _storageService.buildTaskExportPayload(
        tasks: _tasks,
        deletedTasks: _deletedTasks,
        dailyStatsByDay: _dailyStatsByDay,
      ),
      'countdown_timers': (timers ?? []).map((t) => t.toJson()).toList(),
    };
    final file = File(path);
    await file.writeAsString(jsonEncode(payload), flush: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
  }

  Future<void> _importSettingsOnly() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    try {
      final decoded = jsonDecode(await File(picked.path).readAsString())
          as Map<String, dynamic>;
      final settingsRaw = decoded['settings'];
      final settings =
          settingsRaw is Map ? Map<String, dynamic>.from(settingsRaw) : decoded;
      Config.applyMap(settings);
      await Config.save();
      _updateSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings imported')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to import settings')));
    }
  }

  Future<void> _importTasks() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final imported = await _storageService.importTaskData(file.path);
    if (imported.tasks.isEmpty && imported.deletedTasks.isEmpty) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(imported.tasks);
      _deletedTasks
        ..clear()
        ..addAll(imported.deletedTasks);
      _dailyStatsByDay
        ..clear()
        ..addAll(imported.dailyStatsByDay);
      _refreshAllRecurringTasks();
    });
    _initializeStatsForCurrentDay();
    _saveTasks();
    _saveDeletedTasks();
    _saveDailyStats();
    if (mounted) {
      final warningSuffix = imported.warnings.isEmpty
          ? ''
          : ' (${imported.warnings.join(' | ')})';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tasks imported$warningSuffix')));
    }
  }

  Future<void> _importEverything() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    try {
      final decoded = jsonDecode(await File(picked.path).readAsString())
          as Map<String, dynamic>;
      final settingsRaw = decoded['settings'];
      if (settingsRaw is Map) {
        Config.applyMap(Map<String, dynamic>.from(settingsRaw));
        await Config.save();
      }

      final tasksBundleRaw = decoded['tasks_bundle'];
      if (tasksBundleRaw != null) {
        final imported =
            _storageService.importTaskDataFromDecoded(tasksBundleRaw);
        if (imported.tasks.isNotEmpty || imported.deletedTasks.isNotEmpty) {
          setState(() {
            _tasks
              ..clear()
              ..addAll(imported.tasks);
            _deletedTasks
              ..clear()
              ..addAll(imported.deletedTasks);
            _dailyStatsByDay
              ..clear()
              ..addAll(imported.dailyStatsByDay);
            _refreshAllRecurringTasks();
          });
          _initializeStatsForCurrentDay();
          _saveTasks();
          _saveDeletedTasks();
          _saveDailyStats();
        }
      }

      final timersRaw = decoded['countdown_timers'];
      if (timersRaw != null) {
        await _storageService.importCountdownTimersFromDecoded(timersRaw);
      }
      _updateSettings();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Everything imported')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to import full backup')));
    }
  }

  Future<void> _importAutoDetect() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;

    try {
      final decoded = jsonDecode(await File(picked.path).readAsString());
      if (decoded is List) {
        final imported = _storageService.importTaskDataFromDecoded(decoded);
        if (imported.tasks.isNotEmpty || imported.deletedTasks.isNotEmpty) {
          setState(() {
            _tasks
              ..clear()
              ..addAll(imported.tasks);
            _deletedTasks
              ..clear()
              ..addAll(imported.deletedTasks);
            _dailyStatsByDay
              ..clear()
              ..addAll(imported.dailyStatsByDay);
            _refreshAllRecurringTasks();
          });
          _initializeStatsForCurrentDay();
          _saveTasks();
          _saveDeletedTasks();
          _saveDailyStats();
          if (!mounted) return;
          final warningSuffix = imported.warnings.isEmpty
              ? ''
              : ' (${imported.warnings.join(' | ')})';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tasks imported$warningSuffix')),
          );
        }
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unsupported import file')),
        );
        return;
      }

      final hasSettings = decoded['settings'] is Map;
      final hasEverythingBundle = decoded['tasks_bundle'] != null;
      final hasTasksPayload = decoded.containsKey('tasks') ||
          decoded.containsKey('deleted_tasks') ||
          decoded.containsKey('daily_stats') ||
          decoded.containsKey('task_events') ||
          decoded.containsKey('export_version');

      if (hasEverythingBundle) {
        final settingsRaw = decoded['settings'];
        if (settingsRaw is Map) {
          Config.applyMap(Map<String, dynamic>.from(settingsRaw));
          await Config.save();
        }
        final imported =
            _storageService.importTaskDataFromDecoded(decoded['tasks_bundle']);
        if (imported.tasks.isNotEmpty || imported.deletedTasks.isNotEmpty) {
          setState(() {
            _tasks
              ..clear()
              ..addAll(imported.tasks);
            _deletedTasks
              ..clear()
              ..addAll(imported.deletedTasks);
            _dailyStatsByDay
              ..clear()
              ..addAll(imported.dailyStatsByDay);
            _refreshAllRecurringTasks();
          });
          _initializeStatsForCurrentDay();
          _saveTasks();
          _saveDeletedTasks();
          _saveDailyStats();
        }
        final timersRaw = decoded['countdown_timers'];
        if (timersRaw != null) {
          await _storageService.importCountdownTimersFromDecoded(timersRaw);
        }
        _updateSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Everything imported')));
        return;
      }

      if (hasSettings && !hasTasksPayload) {
        Config.applyMap(Map<String, dynamic>.from(decoded['settings'] as Map));
        await Config.save();
        _updateSettings();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings imported')));
        return;
      }

      final imported = _storageService.importTaskDataFromDecoded(decoded);
      if (imported.tasks.isNotEmpty || imported.deletedTasks.isNotEmpty) {
        setState(() {
          _tasks
            ..clear()
            ..addAll(imported.tasks);
          _deletedTasks
            ..clear()
            ..addAll(imported.deletedTasks);
          _dailyStatsByDay
            ..clear()
            ..addAll(imported.dailyStatsByDay);
          _refreshAllRecurringTasks();
        });
        _initializeStatsForCurrentDay();
        _saveTasks();
        _saveDeletedTasks();
        _saveDailyStats();
      }
      if (!mounted) return;
      final warningSuffix = imported.warnings.isEmpty
          ? ''
          : ' (${imported.warnings.join(' | ')})';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tasks imported$warningSuffix')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to import file')));
    }
  }

  /// Returns the list of tasks that should appear on the given tab index.
  /// True when [task] matches the search [query] (case-insensitive substring
  /// over title, description, note, label and project name).
  bool _matchesSearch(Task task, String query) {
    bool has(String s) => s.toLowerCase().contains(query);
    return has(task.title) ||
        has(task.description) ||
        has(task.note) ||
        has(task.label) ||
        (task.projectId != null &&
            has(ProjectService.instance.nameOf(task.projectId)));
  }

  /// Whether the Home view's configured filter rules (Settings → Filtering
  /// rules) currently hide anything.
  bool get _homeFilterRulesActive =>
      !(Config.viewFilterRules[ViewFilterRules.home]?.isEmpty ?? true);

  /// Tasks shown on [pageIndex]. While a search query is active the list is
  /// narrowed to matching tasks, and the configured Home filter rules (if
  /// any) are always applied on top; pass [applySearch] false for logic that
  /// must see the full tab regardless of either (e.g. renumbering
  /// [Task.listRanking] on save).
  List<Task> _tasksForTab(int pageIndex, {bool applySearch = true}) {
    // Tab membership is a query over the one list (ItemViews); only the
    // search predicate is home-page state.
    final query = applySearch ? _searchQuery.trim().toLowerCase() : '';
    return ItemViews.homeBucket(
      _tasks,
      pageIndex,
      _currentDate,
      where: query.isEmpty ? null : (task) => _matchesSearch(task, query),
      rules: applySearch ? Config.viewFilterRules[ViewFilterRules.home] : null,
    );
  }

  /// Short label for the schedule view's active day shown in the add-task
  /// field, e.g. "Today", "Tomorrow", "Aug 1" or "Someday".
  String _scheduleDayLabel(DateTime date) {
    if (_isFutureBucketDate(date)) return 'Someday';
    final diff = dateDiffInDays(date, _currentDate);
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  Widget _buildAddTaskRow() {
    final desktopShortcuts = _isDesktopShortcutsEnabled(context);
    final activeDate = _scheduleView ? _scheduleActiveDate : null;
    // The label names the target whenever it is not simply "the list you are
    // looking at": the schedule view's active day, or the bucket pinned in
    // Settings — otherwise a task typed in Today would silently appear in
    // another tab.
    final pinnedTab = activeDate == null &&
            Config.defaultAddTabIndex != Config.addToCurrentTab
        ? _addTargetTabIndex()
        : null;
    final label = activeDate != null
        ? 'Add task · ${_scheduleDayLabel(activeDate)}'
        : pinnedTab != null
            ? 'Add task · ${Config.tabs[pinnedTab].replaceAll('\n', ' ').trim()}'
            : 'Add task';
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: _handleAddTaskKeyEvent,
              child: TextField(
                controller: _controller,
                focusNode: _addTaskFocusNode,
                decoration: InputDecoration(labelText: label),
                keyboardType: desktopShortcuts
                    ? TextInputType.multiline
                    : TextInputType.text,
                minLines: 1,
                maxLines: desktopShortcuts ? null : 1,
                textInputAction: desktopShortcuts
                    ? TextInputAction.newline
                    : TextInputAction.done,
                onSubmitted: desktopShortcuts ? null : _addTask,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addTask(_controller.text),
          )
        ],
      ),
    );
  }

  Widget _buildTaskTile(Task task, int pageIndex, int indexInTab) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final usesCustomSwipe = isAndroid || kIsWeb;
    final tile = TaskTile(
      key: usesCustomSwipe ? ValueKey(task.uid) : null,
      task: task,
      onChanged: _saveTasks,
      onToggle: () => _toggleTask(task),
      onDueDateChanged: (oldDueDate, newDueDate) {
        setState(() {
          if (task.recurrenceParentUid != null) {
            task.recurrenceParentUid = null;
            task.recurrenceInstanceKey = null;
          }
          final now = DateTime.now();
          task.movedAt = now;
          task.rescheduledAt = now;
          _trackTaskMove(task, oldDueDate, newDueDate);
          _refreshRecurringForTask(task);
        });
        _saveTasks();
      },
      onRecurringChanged: () {
        setState(() {
          _refreshRecurringForTask(task);
        });
        _saveTasks();
      },
      onStartTimer: () => _startTaskTimer(task),
      onMove: (dest) => _moveTask(pageIndex, indexInTab, dest),
      onMoveToWeekday: (weekday) =>
          _moveTaskToWeekday(pageIndex, indexInTab, weekday),
      onMoveNext: () => _moveTaskToNextPage(pageIndex, indexInTab),
      onDelete: () => _deleteTask(pageIndex, indexInTab),
      pageIndex: pageIndex,
      showSwipeButton: !isAndroid,
      swipeLeftDelete: Config.swipeLeftDelete,
      controller: _controllerForTask(task),
      keyboardFocused: _focusedTaskUid == task.uid,
      onFocusRequested: () {
        setState(() => _focusedTaskUid = task.uid);
        _homeKeyboardFocusNode.requestFocus();
      },
      onKeyboardActionCommitted: () =>
          _focusAfterKeyboardAction(pageIndex, indexInTab),
    );
    if (usesCustomSwipe) return tile;
    return Dismissible(
      key: ValueKey(task.uid),
      background: Container(
        color: Config.minimalistMode
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)
            : Colors.greenAccent.withOpacity(0.5),
      ),
      onDismissed: (_) => _moveTaskToNextPage(pageIndex, indexInTab),
      child: tile,
    );
  }

  Widget _buildTaskList(int pageIndex) {
    final tasks = _tasksForTab(pageIndex);
    return Column(
      children: [
        _buildAddTaskRow(),
        Expanded(
          child: tasks.isEmpty && pageIndex == 0
              ? LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: const Center(child: Text('No tasks for today')),
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderTask(pageIndex, oldIndex, newIndex),
                  buildDefaultDragHandles: true,
                  itemBuilder: (context, index) =>
                      _buildTaskTile(tasks[index], pageIndex, index),
                ),
        )
      ],
    );
  }

  Widget _buildScheduleBody() {
    final query = _searchQuery.trim().toLowerCase();
    final visibleTasks = _tasks
        .where((t) =>
            ItemViews.isApproved(t) &&
            (query.isEmpty || _matchesSearch(t, query)))
        .toList();
    return ScheduleView(
      key: _scheduleViewKey,
      tasks: visibleTasks,
      currentDate: _currentDate,
      scrollController: _scheduleScrollController,
      tabAnchorKeys: _scheduleTabAnchors,
      addTaskRow: _buildAddTaskRow(),
      onActiveDateChanged: (date) {
        if (_scheduleActiveDate == date) return;
        setState(() => _scheduleActiveDate = date);
      },
      buildTile: (task) {
        final pageIndex = _tabIndexForTask(task);
        final tabTasks = _tasksForTab(pageIndex);
        final indexInTab = tabTasks.indexOf(task);
        return _buildTaskTile(task, pageIndex, indexInTab);
      },
      onReorderSection: _reorderTaskInSection,
    );
  }

  /// Tools listed under the drawer's Tools section, in display order. Each
  /// key doubles as its feature key ([Config.featureKeys]) and its
  /// [Config.startToolOptions] key, so a tool switched off in Settings
  /// disappears here and can no longer be the start page.
  static const List<_ToolEntry> _toolEntries = [
    _ToolEntry('alarms', 'Alarms', Icons.alarm),
    _ToolEntry('countdown', 'Countdown', Icons.timer),
    _ToolEntry('wishlist', 'Wishlist', Icons.favorite_border),
    _ToolEntry('projects', 'Projects', Icons.dashboard),
    _ToolEntry('chronize', 'Chronize', Icons.access_time),
    _ToolEntry('productivity_stats', 'Productivity Stats', Icons.insights),
    _ToolEntry('usage_data', 'Usage Data', Icons.query_stats),
    _ToolEntry('test_results', 'Test Results', Icons.fact_check),
  ];

  /// An icon overlaid with a small red dot, used on the Test Results entry —
  /// and, when [Config.showFailureDotOnMenu] is on, the drawer/hamburger
  /// icon — while the newest test run has unacknowledged failures, and (with
  /// its own [dotKey]) on the App Logs entry after a failed sync. Every dot
  /// clears itself once its page is opened.
  Widget _iconWithFailureDot(IconData icon,
      {Key dotKey = const Key('test-failure-dot')}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            key: dotKey,
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keeps configured flame goals (see StreakGoal) able to tell a deleted
    // target task apart from one that just has not fired yet today.
    StreakService.instance.syncKnownTasks(_tasks);
    final enabledTools =
        _toolEntries.where((t) => Config.isFeatureEnabled(t.key)).toList();
    final pendingApprovalCount = ItemViews.waitingApproval(_tasks).length;
    final scaffold = Scaffold(
      key: homeScaffoldKey,
      drawer: Drawer(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(16), // adjust as you like
              color: Theme.of(context).colorScheme.primary,
              child: Text(
                'BestToDo v${Config.version}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 18,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                _goHome();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _openSettingsPage();
              },
            ),
            if (Config.isFeatureEnabled('deleted_items'))
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Archived Items'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ArchivedItemsPage(
                        items: ItemViews.applyFilterRules(
                          _deletedTasks,
                          Config.viewFilterRules[ViewFilterRules.archived],
                        ),
                        onRestore: _restoreTask,
                        onMoveToBin: _moveArchivedToBin,
                        onOpenBin: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DeletedBinPage(
                                items: ItemViews.applyFilterRules(
                                  _binTasks,
                                  Config.viewFilterRules[ViewFilterRules.bin],
                                ),
                                onRestore: _restoreFromBin,
                                onDeletePermanently: _deleteTaskPermanently,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.pending_actions),
              title: const Text('Waiting for Approval'),
              trailing: pendingApprovalCount > 0
                  ? CircleAvatar(
                      radius: 10,
                      backgroundColor: Theme.of(context).colorScheme.error,
                      child: Text(
                        '$pendingApprovalCount',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                          builder: (_) => const WaitingApprovalPage()),
                    )
                    .then((_) => _reloadTasksFromStorage());
              },
            ),
            if (Config.isFeatureEnabled('changelog'))
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Changelog'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChangelogPage()),
                  );
                },
              ),
            if (Config.isFeatureEnabled('app_logs'))
              ValueListenableBuilder<bool>(
                valueListenable: SyncService.instance.hasUnseenError,
                builder: (context, syncError, _) =>
                    ValueListenableBuilder<bool>(
                  valueListenable: TodoistSyncService.instance.hasUnseenError,
                  builder: (context, todoistError, __) {
                    final hasError = syncError || todoistError;
                    return ListTile(
                      leading: hasError
                          ? _iconWithFailureDot(Icons.list_alt,
                              dotKey: const Key('sync-error-dot'))
                          : const Icon(Icons.list_alt),
                      title: const Text('App Logs'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AppLogsPage()),
                        );
                      },
                    );
                  },
                ),
              ),
            if (Config.isFeatureEnabled('startup_times'))
              ListTile(
                leading: const Icon(Icons.show_chart),
                title: const Text('Startup Times'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StartupTimesPage()),
                  );
                },
              ),
            if (enabledTools.isNotEmpty)
              ExpansionTile(
                leading: const Icon(Icons.build),
                title: const Text('Tools'),
                childrenPadding: const EdgeInsets.only(left: 16),
                children: [
                  for (final tool in enabledTools)
                    ListTile(
                      leading: tool.key == 'test_results' &&
                              TestReportService.instance.hasUnseenFailures
                          ? _iconWithFailureDot(tool.icon)
                          : Icon(tool.icon),
                      title: Text(tool.label),
                      onTap: () {
                        Navigator.pop(context);
                        _openTool(tool.key);
                      },
                    ),
                ],
              ),
          ],
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            icon: Config.showFailureDotOnMenu &&
                    TestReportService.instance.hasUnseenFailures
                ? _iconWithFailureDot(Icons.menu)
                : const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Config.isFeatureEnabled('search')
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search tasks',
                  border: InputBorder.none,
                  suffixIcon: _searchQuery.isEmpty
                      ? const Icon(Icons.search)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : const Text('BestToDo'),
        actions: [
          StreakFlameButton(
            now: _currentDate,
            onSettingsChanged: () {
              if (mounted) setState(() {});
            },
          ),
          ListenableBuilder(
            listenable: DiceTimerController.instance,
            builder: (context, _) {
              if (!Config.isFeatureEnabled('dice_timer')) {
                return const SizedBox.shrink();
              }
              final active = DiceTimerController.instance.isActive;
              return IconButton(
                icon: active
                    ? const Badge(
                        smallSize: 9,
                        child: Icon(Icons.casino),
                      )
                    : const Icon(Icons.casino),
                tooltip: active
                    ? 'Return to the running task timer'
                    : 'Roll a random task timer',
                onPressed: _rollRandomTaskTimer,
              );
            },
          ),
          if (Config.isFeatureEnabled('schedule_view'))
            IconButton(
              icon: Icon(_scheduleView
                  ? Icons.format_list_bulleted
                  : Icons.calendar_month),
              tooltip: _scheduleView ? 'List view' : 'Schedule view',
              onPressed: () {
                setState(() {
                  _scheduleView = !_scheduleView;
                });
                if (_scheduleView) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToScheduleAnchor(_tabController.index);
                  });
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Config.isDev ? 72 : 48),
          child: Column(
            children: [
              if (Config.isDev)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeDate(-1),
                    ),
                    Text(
                      _currentDate.toLocal().toString().split(' ')[0],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeDate(1),
                    ),
                  ],
                ),
              TabBar(
                controller: _tabController,
                labelPadding: const EdgeInsets.symmetric(horizontal: 1),
                tabs: Config.useIconTabs
                    ? List.generate(Config.tabs.length, (index) {
                        final selected = _tabController.index == index;
                        if (selected) {
                          return Tab(
                            child: Text(
                              Config.tabs[index],
                              textAlign:
                                  TextAlign.center, // ✅ center multiline titles
                            ),
                          );
                        }
                        return Tab(
                          icon: index == _futureTabIndex
                              ? const Text('✨', style: TextStyle(fontSize: 20))
                              : Image.asset(
                                  _tabIconPaths[index],
                                  height: 24,
                                ),
                        );
                      })
                    : Config.tabs.map((t) => Tab(text: t)).toList(),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Shown only while the first-launch Todoist import is still
          // pulling in everything past today (see IntroPage's import
          // chooser) — `syncing` otherwise only flips on for the brief
          // duration of a manual/quit-time sync, which has its own spinner
          // in Settings and is never visible here in practice.
          ValueListenableBuilder<bool>(
            valueListenable: TodoistSyncService.instance.syncing,
            builder: (context, syncing, _) {
              if (!syncing) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Importing the rest of your tasks from Todoist…',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _pullToRefreshSync,
              child: _scheduleView
                  ? _buildScheduleBody()
                  : TabBarView(
                      controller: _tabController,
                      children:
                          List.generate(Config.tabs.length, _buildTaskList),
                    ),
            ),
          ),
        ],
      ),
    );
    return Focus(
      focusNode: _homeKeyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleHomeKeyEvent,
      child: scaffold,
    );
  }
}
