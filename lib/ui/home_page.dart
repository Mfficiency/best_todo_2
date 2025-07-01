import 'package:flutter/material.dart';
import 'dart:async';
import '../models/task.dart';
import '../config.dart';
import '../services/storage_service.dart';
import 'task_tile.dart';
import 'about_page.dart';
import 'settings_page.dart';
import 'deleted_items_page.dart';
import 'changelog_page.dart';
import '../main.dart' show MyApp;
import '../l10n/app_localizations.dart';

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

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();

  /// Day offsets for each tab. The last entry represents "next week".
  static const List<int> _offsetDays = [0, 1, 2, 7];

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
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: Config.tabs.length, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
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
    _storageService.saveTaskList(_tasks);
  }

  void _moveTaskToNextPage(int pageIndex, int index) {
    final tasks = _tasksForTab(pageIndex);
    int destination = pageIndex + 1;
    if (destination >= Config.tabs.length) {
      destination = 0;
    }
    setState(() {
      if (index >= tasks.length) return;
      final task = tasks[index];
      task.dueDate =
          _currentDate.add(Duration(days: _offsetDays[destination]));
    });
    _storageService.saveTaskList(_tasks);
  }

  void _moveTask(int pageIndex, int index, int destination) {
    setState(() {
      final tasks = _tasksForTab(pageIndex);
      if (index >= tasks.length) return;
      final task = tasks[index];
      task.dueDate =
          _currentDate.add(Duration(days: _offsetDays[destination]));
    });
    _storageService.saveTaskList(_tasks);
  }

  void _deleteTask(int pageIndex, int index) {
    final tasks = _tasksForTab(pageIndex);
    if (index >= tasks.length) return;
    final task = tasks[index];
    final originalIndex = _tasks.indexOf(task);

    setState(() {
      _tasks.removeAt(originalIndex);
    });
    _storageService.saveTaskList(_tasks);

    late Timer timer;
    timer = Timer(const Duration(seconds: Config.defaultDelaySeconds), () {
      setState(() {
        _deletedTasks.insert(0, task);
        if (_deletedTasks.length > 100) {
          _deletedTasks.removeLast();
        }
      });
    });

    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.deleted(task.title)),
          duration: const Duration(seconds: Config.defaultDelaySeconds),
          action: SnackBarAction(
            label: l10n.cancel,
            onPressed: () {
              timer.cancel();
              setState(() {
                _tasks.insert(originalIndex, task);
              });
              _storageService.saveTaskList(_tasks);
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
    _storageService.saveTaskList(_tasks);
  }

  void _updateSettings() {
    setState(() {});
  }

  void _setLocale(Locale locale) {
    final state = MyApp.of(context);
    state?.setLocale(locale);
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
    _storageService.saveTaskList(_tasks);
  }

  /// Returns the list of tasks that should appear on the given tab index.
  List<Task> _tasksForTab(int pageIndex) {
    return _tasks.where((task) {
      if (task.dueDate == null) return false;
      final diff = task.dueDate!.difference(_currentDate).inDays;
      if (pageIndex == 0) return diff <= 0;
      if (pageIndex == 1) return diff == 1;
      if (pageIndex == 2) return diff == 2;
      return diff >= 3;
    }).toList();
  }

  Widget _buildTaskList(int pageIndex) {
    final tasks = _tasksForTab(pageIndex);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).addTask,
                  ),
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
                  setState(task.toggleDone);
                  _storageService.saveTaskList(_tasks);
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
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.blue),
              child: Text(
                AppLocalizations.of(context).menu,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: Text(AppLocalizations.of(context).about),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(AppLocalizations.of(context).settings),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      onSettingsChanged: _updateSettings,
                      onLanguageChanged: _setLocale,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(AppLocalizations.of(context).changelog),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangelogPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(AppLocalizations.of(context).deletedItems),
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
        title: Text(AppLocalizations.of(context).appTitle),
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
                tabs: AppLocalizations.of(context)
                    .tabs
                    .map((t) => Tab(text: t))
                    .toList(),
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
        ],
      ),
    );
  }
}
