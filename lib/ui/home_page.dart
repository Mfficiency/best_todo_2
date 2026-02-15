import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/task.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';
import '../utils/task_utils.dart';
import 'about_page.dart';
import 'app_logs_page.dart';
import 'changelog_page.dart';
import 'startup_times_page.dart';
import 'deleted_items_page.dart';
import 'settings_page.dart';
import 'task_tile.dart';
import 'your_stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

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
  final StorageService _storageService = StorageService();

  final String appGroupId = 'group.homeScreenApp';
  final String iOSWidgetName = 'SimpleWidgetProvider';
  final String androidWidgetName = 'SimpleWidgetProvider';
  final String dataKey = 'text_from_flutter_app';

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();
  Timer? _midnightTimer;

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
    final loadedDeleted = await _storageService.loadDeletedTaskList();
    if (loaded.isEmpty) {
      _tasks.addAll(
        Config.initialTasks.map((t) => Task(title: t, dueDate: _currentDate)),
      );
    } else {
      _tasks.addAll(loaded);
    }
    _deletedTasks.addAll(loadedDeleted);
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

  void _addToDeletedTasks(Task task) {
    task.deletedAt = DateTime.now();
    _deletedTasks.insert(0, task);
    if (_deletedTasks.length > 100) {
      _deletedTasks.removeLast();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: Config.tabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() {});
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
    _midnightTimer?.cancel();
    super.dispose();
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
      task.dueDate = _currentDate.add(Duration(days: _offsetDays[destination]));
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
      task.dueDate = _currentDate.add(Duration(days: _offsetDays[destination]));
    });
    _saveTasks();
    LogService.add(
        'HomePage._moveTask', 'Moved "${task.title}" to page $destination');
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
      task.dueDate = _currentDate;
      _tasks.add(task);
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
    LogService.add(
        'HomePage._deleteTaskPermanently', 'Queued permanent delete "${task.title}"');

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
          _addToDeletedTasks(task);
        }
      }
    });
    _saveTasks();
    _saveDeletedTasks();
    LogService.add(
        'HomePage._changeDate', 'Changed date by $delta to $_currentDate');
  }

  Future<void> _updateHomeWidget() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tasks = _tasks
        .where((t) {
          if (t.dueDate == null) return false;
          final due =
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return !t.isDone && !due.isAfter(today);
        })
        .toList()
      ..sort((a, b) => (a.listRanking ?? 1 << 31)
          .compareTo(b.listRanking ?? 1 << 31));

    final data = tasks.isEmpty
        ? 'No tasks for today'
        : tasks.map((t) => '• ${t.title}').join('\n');

    try {
      await HomeWidget.saveWidgetData(dataKey, data);
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
    _storageService.saveTaskList(_tasks);
    _updateHomeWidget();
  }

  Future<void> _exportTasks() async {
    final downloadsDir = await getDownloadsDirectory();
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final directory = await getDirectoryPath(
      initialDirectory: downloadsDir?.path,
    );
    if (directory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    final sep = Platform.pathSeparator;
    final path = '$directory${directory.endsWith(sep) ? '' : sep}tasks_$ts.json';
    final file = await _storageService.exportTaskList(_tasks, path);
    if (!mounted) return;
    final message =
        file != null ? 'Exported to ${file.path}' : 'Failed to export tasks';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importTasks() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final imported = await _storageService.importTaskList(file.path);
    if (imported.isEmpty) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(imported);
    });
    _saveTasks();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tasks imported')));
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
      if (pageIndex == 0) return diff <= 0;
      if (pageIndex == 1) return diff == 1;
      if (pageIndex == 2) return diff == 2;
      if (pageIndex == 3) return diff >= 3 && diff < 30;
      return diff >= 30;
    }).toList();
    sortTasks(list);
    return list;
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
          child: tasks.isEmpty && pageIndex == 0
              ? const Center(child: Text('No tasks for today'))
              : ReorderableListView.builder(
                  itemCount: tasks.length,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderTask(pageIndex, oldIndex, newIndex),
                  buildDefaultDragHandles: true,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    final isAndroid =
                        Theme.of(context).platform == TargetPlatform.android;
                    final tile = TaskTile(
                      key: isAndroid ? ValueKey(task.uid) : null,
                      task: task,
                      onChanged: _saveTasks,
                      onToggle: () {
                        setState(task.toggleDone);
                        _saveTasks();
                      },
                      onMove: (dest) => _moveTask(pageIndex, index, dest),
                      onMoveNext: () => _moveTaskToNextPage(pageIndex, index),
                      onDelete: () => _deleteTask(pageIndex, index),
                      pageIndex: pageIndex,
                      showSwipeButton: !isAndroid,
                      swipeLeftDelete: Config.swipeLeftDelete,
                    );
                    if (isAndroid) {
                      return tile;
                    }
                    return Dismissible(
                      key: ValueKey(task.uid),
                      background: Container(
                        color: Colors.greenAccent.withOpacity(0.5),
                      ),
                      onDismissed: (_) =>
                          _moveTaskToNextPage(pageIndex, index),
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
                    builder: (_) => YourStatsPage(deletedItems: _deletedTasks),
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
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('Export Tasks'),
              onTap: () {
                Navigator.pop(context);
                _exportTasks();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('Import Tasks'),
              onTap: () {
                Navigator.pop(context);
                _importTasks();
              },
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
                              textAlign: TextAlign.center, // ✅ center multiline titles
                            ),
                          );
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
