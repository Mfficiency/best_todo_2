import 'package:flutter/material.dart';
import 'dart:async';
import '../models/task.dart';
import '../config.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import 'package:home_widget/home_widget.dart';
import 'task_tile.dart';
import 'about_page.dart';
import 'settings_page.dart';
import 'deleted_items_page.dart';
import 'changelog_page.dart';
import 'app_logs_page.dart';
import '../utils/date_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

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
  final List<Task> _deletedTasks = [];
  final StorageService _storageService = StorageService();

  final String appGroupId = 'group.homeScreenApp';
  final String iOSWidgetName = 'SimpleWidgetProvider';
  final String androidWidgetName = 'SimpleWidgetProvider';
  final String dataKey = 'text_from_flutter_app';

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();

  /// Day offsets for each tab. The last two entries represent
  /// "next week" and "next month" respectively.
  static const List<int> _offsetDays = [0, 1, 2, 7, 30];

  /// Asset paths for tab icons used when a tab is not selected.
  static const List<String> _tabIconPaths = [
    'assets/icons/today.png',
    'assets/icons/tomorrow.png',
    'assets/icons/the_day_after.png',
    'assets/icons/next_week.png',
    'assets/icons/next_month.png',
  ];

  Future<void> _loadTasks() async {
    final loaded = await _storageService.loadTaskList();
    if (loaded.isEmpty) {
      _tasks.addAll(
        Config.initialTasks
            .map((t) => Task(title: t, dueDate: _currentDate)),
      );
    } else {
      _tasks.addAll(loaded);
    }
    LogService.add('HomePage._loadTasks',
        '*** Tasks loaded into widget (${_tasks.length}) ***');
    if (mounted) {
      setState(() {});
    }
    _updateHomeWidget();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController =
        TabController(length: Config.tabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    HomeWidget.setAppGroupId(appGroupId).catchError((_) {});
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final current = DateTime(
          _currentDate.year, _currentDate.month, _currentDate.day);
      final diff = today.difference(current).inDays;
      if (diff > 0) {
        _changeDate(diff);
      } else {
        _updateHomeWidget();
      }
    }
  }

  void _addTask(String title) {
    if (title.trim().isEmpty) return;
    final offset = _offsetDays[_tabController.index];
    final task = Task(
      title: title,
      dueDate: _currentDate.add(Duration(days: offset)),
    );
    setState(() {
      _tasks.add(task);
    });
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
    setState(() {
      task.dueDate =
          _currentDate.add(Duration(days: _offsetDays[destination]));
    });
    _saveTasks();
    LogService.add('HomePage._moveTaskToNextPage',
        'Moved "${task.title}" to page $destination');
  }

  void _moveTask(int pageIndex, int index, int destination) {
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    setState(() {
      task.dueDate =
          _currentDate.add(Duration(days: _offsetDays[destination]));
    });
    _saveTasks();
    LogService.add(
        'HomePage._moveTask', 'Moved "${task.title}" to page $destination');
  }

  void _deleteTask(int pageIndex, int index) {
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    final originalIndex = _tasks.indexOf(task);

    setState(() {
      _tasks.removeAt(originalIndex);
    });
    _saveTasks();
    LogService.add('HomePage._deleteTask', 'Deleted "${task.title}"');

    late Timer timer;
    timer = Timer(Config.delayDuration, () {
      setState(() {
        _deletedTasks.insert(0, task);
        if (_deletedTasks.length > 100) {
          _deletedTasks.removeLast();
        }
      });
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${task.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Cancel',
            onPressed: () {
              timer.cancel();
              setState(() {
                _tasks.insert(originalIndex, task);
              });
              _saveTasks();
              LogService.add('HomePage._deleteTask',
                  'Restored from undo "${task.title}"');
            },
          ),
        ),
      );
  }

  void _restoreTask(Task task) {
    setState(() {
      _deletedTasks.remove(task);
      task.dueDate = _currentDate;
      _tasks.add(task);
    });
    _saveTasks();
    LogService.add('HomePage._restoreTask', 'Restored "${task.title}"');
  }

  void _updateSettings() {
    setState(() {});
    LogService.add('HomePage._updateSettings', 'Settings updated');
  }

  /// Change the current virtual date by the given number of days.
  /// When moving forward, overdue tasks remain visible in the Today tab.
  void _changeDate(int delta) {
    setState(() {
      _currentDate = _currentDate.add(Duration(days: delta));
      // Remove completed tasks when progressing to the next day so that
      // finished items no longer clutter the lists.
      if (delta > 0) {
        _tasks.removeWhere((t) => t.isDone);
      }
    });
    _saveTasks();
    LogService.add('HomePage._changeDate',
        'Changed date by $delta to $_currentDate');
  }

  Future<void> _updateHomeWidget() async {
    if (!Config.enableWidgetUpdates) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final data = _tasks
        .where((t) {
          if (t.dueDate == null) return false;
          final due = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return !t.isDone && !due.isAfter(today);
        }) // keep only pending tasks due today or earlier
        .map((t) => '• ${t.title}')
        .join('\n');

    try {
      await HomeWidget.saveWidgetData(dataKey, data);
      await HomeWidget.updateWidget(
          iOSName: iOSWidgetName, androidName: androidWidgetName);
    } catch (_) {}
  }

  void _saveTasks() {
    _storageService.saveTaskList(_tasks);
    _updateHomeWidget();
  }

  /// Returns the list of tasks that should appear on the given tab index.
  List<Task> _tasksForTab(int pageIndex) {
    return _tasks.where((task) {
      if (task.dueDate == null) return false;
      // Compare dates without considering the time of day so that tasks due
      // tomorrow don't appear in today's list simply because they are less
      // than 24 hours away.
      final diff = dateDiffInDays(task.dueDate!, _currentDate);
      if (pageIndex == 0) return diff <= 0;
      if (pageIndex == 1) return diff == 1;
      if (pageIndex == 2) return diff == 2;
      if (pageIndex == 3) return diff >= 3 && diff < 30;
      return diff >= 30;
    }).toList();
  }

  Widget _buildTaskList(int pageIndex) {
    final tasks = _tasksForTab(pageIndex);
    // LogService.add('HomePage._buildTaskList',
    //     'Building tab $pageIndex with ${tasks.length} tasks');
    return Column(
      children: [
        Padding(
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
        ),
        Expanded(
          child: ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              final isAndroid = Theme.of(context).platform == TargetPlatform.android;
              final tile = TaskTile(
                task: task,
                onChanged: () {
                  setState(() {
                    task.toggleDone();
                    if (task.isDone) {
                      _tasks
                        ..remove(task)
                        ..add(task);
                    }
                  });
                  _saveTasks();
                },
                onMove: (dest) => _moveTask(pageIndex, index, dest),
                onMoveNext: () => _moveTaskToNextPage(pageIndex, index),
                onDelete: () => _deleteTask(pageIndex, index),
                pageIndex: pageIndex,
                showSwipeButton: !isAndroid,
                swipeLeftDelete: Config.swipeLeftDelete,
              );
              return isAndroid
                  ? tile
                  : Dismissible(
                      key: ValueKey('${task.title}-$index-$pageIndex'),
                      background: Container(
                        color: Colors.greenAccent.withOpacity(0.5),
                      ),
                      onDismissed: (_) => _moveTaskToNextPage(pageIndex, index),
                      child: tile,
                    );
            },
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Menu', style: TextStyle(color: Colors.white)),
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
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      onSettingsChanged: _updateSettings,
                    ),
                  ),
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
              leading: const Icon(Icons.delete),
              title: const Text('Deleted Items'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => DeletedItemsPage(
                      items: _deletedTasks,
                      onRestore: _restoreTask,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text('Best Todo 2 v${Config.version}'),
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
                          return Tab(text: Config.tabs[index]);
                        }
                        return Tab(
                          icon: Image.asset(
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(0),
          _buildTaskList(1),
          _buildTaskList(2),
          _buildTaskList(3),
          _buildTaskList(4),
        ],
      ),
    );
  }
}
