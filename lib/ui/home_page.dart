import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/task_utils.dart';
import 'about_page.dart';
import 'app_logs_page.dart';
import 'calendar_view_page.dart' show ScheduleView;
import 'changelog_page.dart';
import 'chronize_page.dart';
import 'countdown_timer_page.dart';
import 'home_scaffold_key.dart';
import 'startup_times_page.dart';
import 'deleted_items_page.dart';
import 'settings_page.dart';
import 'task_tile.dart';
import 'your_stats_page.dart';

class HomePage extends StatefulWidget {
  final int initialTabIndex;

  const HomePage({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  /// Current virtual date for the app. In dev mode this can be changed
  /// using the arrows in the app bar.
  DateTime _currentDate = DateTime.now();

  /// All tasks in the app. Tasks are assigned a dueDate when created and
  /// filtered into the appropriate lists based on [_currentDate].
  final List<Task> _tasks = [];
  final List<Task> _deletedTasks = [];
  final Map<String, DailyTaskStats> _dailyStatsByDay = {};
  final StorageService _storageService = StorageService();

  final String appGroupId = 'group.homeScreenApp';
  final String iOSWidgetName = 'SimpleWidgetProvider';
  final String androidWidgetName = 'SimpleWidgetProvider';
  final String dataKey = 'text_from_flutter_app';
  final String progressVisibleKey = 'widget_progress_visible';
  final String progressPercentKey = 'widget_progress_percent';
  final String progressColorKey = 'widget_progress_color';

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();
  Timer? _midnightTimer;

  /// When true, the body renders one long schedule list with day-grouped
  /// sections; tab taps scroll that list instead of switching panes.
  bool _scheduleView = Config.startInScheduleView;
  final ScrollController _scheduleScrollController = ScrollController();
  final Map<int, GlobalKey> _scheduleTabAnchors = {
    for (var i = 0; i < 6; i++) i: GlobalKey(),
  };
  int _lastTabIndex = 0;

  static const int _futureTabIndex = 5;
  static final DateTime _futureDueDate = DateTime(2300, 1, 1);

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
      final deletedAt = now.subtract(Duration(days: dayOffsets[i], minutes: i * 11));
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
    final loaded = await _storageService.loadTaskList();
    final loadedDeleted = await _storageService.loadDeletedTaskList();
    final loadedDailyStats = await _storageService.loadDailyTaskStats();
    if (loaded.isEmpty) {
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
    _refreshAllRecurringTasks();
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
    if (loadedDailyStats.isNotEmpty) {
      _dailyStatsByDay.addAll(loadedDailyStats);
    } else if (Config.isDev) {
      _dailyStatsByDay.addAll(_buildDevDailyStatsSeed(_currentDate));
      _saveDailyStats();
    }
    _initializeStatsForCurrentDay();
    LogService.add('HomePage._loadTasks',
        '*** Tasks loaded into widget (${_tasks.length}) ***');
    if (mounted) {
      setState(() {});
    }
    _saveTasks();
  }

  void _saveDeletedTasks() {
    _storageService.saveDeletedTaskList(_deletedTasks);
  }

  void _saveDailyStats() {
    _storageService.saveDailyTaskStats(_dailyStatsByDay);
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
    HomeWidget.setAppGroupId(appGroupId).catchError((_) {});
    _loadTasks();
    _scheduleMidnightUpdate();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    _scheduleScrollController.dispose();
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Map a task to the tab index that would own it in list mode. Used by
  /// the schedule view so each tile's "move to" menu hides the task's
  /// current bucket.
  int _tabIndexForTask(Task task) {
    final due = task.dueDate;
    if (due == null) return _futureTabIndex;
    if (_isFutureBucketDate(due)) return _futureTabIndex;
    final diff = dateDiffInDays(due, _currentDate);
    if (diff <= 0) return 0;
    if (diff == 1) return 1;
    if (diff == 2) return 2;
    if (diff < 30) return 3;
    return 4;
  }

  /// Reorder within one day section of the schedule view. Other tasks in
  /// the same tab keep their relative position; only the slice belonging
  /// to this section is shuffled.
  void _reorderTaskInSection(
    List<Task> sectionTasks,
    int oldIndex,
    int newIndex,
  ) {
    if (sectionTasks.isEmpty) return;
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
    final key = _scheduleTabAnchors[tabIndex];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
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

  void _addTask(String title) {
    if (title.trim().isEmpty) return;
    final tabIndex = _tabController.index;
    final task = Task(
      title: title,
      createdAt: DateTime.now(),
      dueDate: _dueDateForTab(tabIndex),
      listRanking: _listRankingForNewTask(
        tabIndex,
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
      task.dueDate = _currentDate;
      _tasks.add(task);
      _refreshRecurringForTask(task);
    });
    _saveTasks();
    _saveDeletedTasks();
    LogService.add('HomePage._restoreTask', 'Restored "${task.title}"');
  }

  void _deleteTaskPermanently(Task task) {
    final originalIndex = _deletedTasks.indexOf(task);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _deletedTasks.removeAt(originalIndex);
    });
    _saveDeletedTasks();
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
                final insertAt = originalIndex <= _deletedTasks.length
                    ? originalIndex
                    : _deletedTasks.length;
                _deletedTasks.insert(insertAt, task);
              });
              _saveDeletedTasks();
              LogService.add('HomePage._deleteTaskPermanently',
                  'Restored from undo "${task.title}"');
            },
          ),
        ),
      );
  }

  void _updateSettings() {
    setState(() {});
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

  Future<void> _updateHomeWidget() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayTasks = _tasks.where((t) {
      if (t.dueDate == null) return false;
      final due = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !due.isAfter(today);
    }).toList()
      ..sort((a, b) =>
          (a.listRanking ?? 1 << 31).compareTo(b.listRanking ?? 1 << 31));

    final openTasks = todayTasks.where((t) => !t.isDone).toList();
    final totalCount = todayTasks.length;
    final completedCount = totalCount - openTasks.length;
    final remainingCount = openTasks.length;
    final percent = totalCount == 0
        ? 0
        : ((completedCount / totalCount) * 100).round().clamp(0, 100);

    String progressColor = 'green';
    if (completedCount == totalCount && totalCount > 0) {
      progressColor = 'green';
    } else if (remainingCount >= 5) {
      progressColor = 'red';
    } else if (remainingCount == 4) {
      progressColor = 'orange';
    }

    final data = openTasks.isEmpty
        ? 'Well done!\nNo more tasks for today!'
        : openTasks.map((t) => '- ${t.title}').join('\n');

    try {
      await HomeWidget.saveWidgetData(dataKey, data);
      await HomeWidget.saveWidgetData(
          progressVisibleKey, Config.showWidgetProgressLine);
      await HomeWidget.saveWidgetData(progressPercentKey, percent);
      await HomeWidget.saveWidgetData(progressColorKey, progressColor);
      await HomeWidget.updateWidget(
          iOSName: iOSWidgetName, androidName: androidWidgetName);
    } catch (_) {}
  }

  void _saveTasks() {
    for (var i = 0; i < Config.tabs.length; i++) {
      final listTasks = _tasksForTab(i);
      for (var j = 0; j < listTasks.length; j++) {
        listTasks[j].listRanking = j + 1;
      }
    }
    // Default every deadline time to 18:00, bumping to 18:01, 18:02, ... when
    // multiple tasks land on the same day so no two share a time.
    applyDefaultDeadlineTimes(_tasks);
    _storageService.saveTaskList(_tasks);
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
      'countdown_timers':
          (timers ?? []).map((t) => t.toJson()).toList(),
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
      final settings = settingsRaw is Map
          ? Map<String, dynamic>.from(settingsRaw as Map)
          : decoded;
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
        Config.applyMap(Map<String, dynamic>.from(settingsRaw as Map));
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
          Config.applyMap(Map<String, dynamic>.from(settingsRaw as Map));
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
  List<Task> _tasksForTab(int pageIndex) {
    final list = _tasks.where((task) {
      if (task.dueDate == null) return false;
      // Compare dates without considering the time of day so that tasks due
      // tomorrow don't appear in today's list simply because they are less
      // than 24 hours away.
      final diff = dateDiffInDays(task.dueDate!, _currentDate);
      final isFutureTask = _isFutureBucketDate(task.dueDate!);
      if (pageIndex == 0) return diff <= 0;
      if (pageIndex == 1) return diff == 1;
      if (pageIndex == 2) return diff == 2;
      if (pageIndex == 3) return diff >= 3 && diff < 30;
      if (pageIndex == 4) return diff >= 30 && !isFutureTask;
      return isFutureTask;
    }).toList();
    sortTasks(list);
    return list;
  }

  Widget _buildAddTaskRow() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Add task'),
              onSubmitted: _addTask,
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
      onToggle: () {
        final wasDone = task.isDone;
        setState(() {
          task.toggleDone();
          task.completedAt = task.isDone ? DateTime.now() : null;
        });
        _trackTaskDoneState(task, wasDone);
        _saveTasks();
      },
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
      onMove: (dest) => _moveTask(pageIndex, indexInTab, dest),
      onMoveToWeekday: (weekday) =>
          _moveTaskToWeekday(pageIndex, indexInTab, weekday),
      onMoveNext: () => _moveTaskToNextPage(pageIndex, indexInTab),
      onDelete: () => _deleteTask(pageIndex, indexInTab),
      pageIndex: pageIndex,
      showSwipeButton: !isAndroid,
      swipeLeftDelete: Config.swipeLeftDelete,
    );
    if (usesCustomSwipe) return tile;
    return Dismissible(
      key: ValueKey(task.uid),
      background: Container(color: Colors.greenAccent.withOpacity(0.5)),
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
              ? const Center(child: Text('No tasks for today'))
              : ReorderableListView.builder(
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
    return ScheduleView(
      tasks: _tasks,
      currentDate: _currentDate,
      scrollController: _scheduleScrollController,
      tabAnchorKeys: _scheduleTabAnchors,
      addTaskRow: _buildAddTaskRow(),
      buildTile: (task) {
        final pageIndex = _tabIndexForTask(task);
        final tabTasks = _tasksForTab(pageIndex);
        final indexInTab = tabTasks.indexOf(task);
        return _buildTaskTile(task, pageIndex, indexInTab);
      },
      onReorderSection: _reorderTaskInSection,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: homeScaffoldKey,
      drawer: Drawer(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(16), // adjust as you like
              color: Theme.of(context).colorScheme.primary,
              child: Text(
                'BestToDo v${Config.version}',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      onSettingsChanged: _updateSettings,
                      onExportTasksRequested: _exportTasks,
                      onExportSettingsRequested: _exportSettingsOnly,
                      onExportEverythingRequested: _exportEverything,
                      onImportRequested: _importAutoDetect,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Deleted Items'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DeletedItemsPage(
                      items: _deletedTasks,
                      onRestore: _restoreTask,
                      onDeletePermanently: _deleteTaskPermanently,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: const Text('Your Stats'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => YourStatsPage(
                      tasks: _tasks,
                      deletedItems: _deletedTasks,
                      dailyStatsByDay: _dailyStatsByDay,
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
              leading: const Icon(Icons.history),
              title: const Text('Changelog'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangelogPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('App Logs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppLogsPage()),
                );
              },
            ),
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
            ExpansionTile(
              leading: const Icon(Icons.build),
              title: const Text('Tools'),
              childrenPadding: const EdgeInsets.only(left: 16),
              children: [
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('Countdown'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CountdownTimerPage(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('Chronize'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChronizePage(tasks: _tasks),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'search soon available',
            border: InputBorder.none,
            suffixIcon: Icon(Icons.search),
          ),
        ),
        actions: [
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
      body: _scheduleView
          ? _buildScheduleBody()
          : TabBarView(
              controller: _tabController,
              children: List.generate(Config.tabs.length, _buildTaskList),
            ),
    );
  }
}
