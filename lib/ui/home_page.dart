import 'package:flutter/material.dart';
import '../models/task.dart';
import '../config.dart';
import 'about_page.dart';
import 'settings_page.dart';
import 'task_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final List<Task> _todayTasks = [
    Task(title: 'Get milk'),
    Task(title: 'Go to the car shop to get my carburator fixed'),
    Task(title: '@myself remember to do sports & drink water'),
  ];
  final List<Task> _tomorrowTasks = [];
  final List<Task> _dayAfterTasks = [];
  final List<Task> _nextWeekTasks = [];

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _addTask(String title) {
    if (title.trim().isEmpty) return;
    setState(() {
      switch (_tabController.index) {
        case 0:
          _todayTasks.add(Task(title: title));
          break;
        case 1:
          _tomorrowTasks.add(Task(title: title));
          break;
        case 2:
          _dayAfterTasks.add(Task(title: title));
          break;
        default:
          _nextWeekTasks.add(Task(title: title));
      }
    });
    _controller.clear();
  }

  void _moveTaskToNextPage(int index) {
    final from = _tabController.index;
    int? destination;
    if (from == 0) destination = 1;
    if (from == 1) destination = 2;
    if (from == 2) destination = 3;
    setState(() {
      if (destination != null) {
        final fromList = _listFor(from);
        if (index < fromList.length) {
          final task = fromList.removeAt(index);
          _listFor(destination).add(task);
        }
      } else if (from == 3) {
        final fromList = _listFor(from);
        if (index < fromList.length) fromList.removeAt(index);
      }
    });
  }

  List<Task> _listFor(int page) {
    switch (page) {
      case 0:
        return _todayTasks;
      case 1:
        return _tomorrowTasks;
      case 2:
        return _dayAfterTasks;
      default:
        return _nextWeekTasks;
    }
  }

  void _moveTask(int pageIndex, int index, int destination) {
    setState(() {
      final fromList = _listFor(pageIndex);
      if (index >= fromList.length) return;
      final task = fromList.removeAt(index);
      _listFor(destination).add(task);
    });
  }

  void _advanceDay() {
    setState(() {
      final temp = List<Task>.from(_todayTasks);
      _todayTasks
        ..clear()
        ..addAll(_tomorrowTasks);
      _tomorrowTasks
        ..clear()
        ..addAll(_dayAfterTasks);
      _dayAfterTasks
        ..clear()
        ..addAll(_nextWeekTasks);
      _nextWeekTasks
        ..clear()
        ..addAll(temp);
    });
  }

  void _rewindDay() {
    setState(() {
      final temp = List<Task>.from(_nextWeekTasks);
      _nextWeekTasks
        ..clear()
        ..addAll(_dayAfterTasks);
      _dayAfterTasks
        ..clear()
        ..addAll(_tomorrowTasks);
      _tomorrowTasks
        ..clear()
        ..addAll(_todayTasks);
      _todayTasks
        ..clear()
        ..addAll(temp);
    });
  }

  Widget _buildTaskList(List<Task> tasks, int pageIndex) {
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
              return Dismissible(
                key: ValueKey('${task.title}-$index-$pageIndex'),
                background: Container(
                  color: Colors.greenAccent.withOpacity(0.5),
                ),
                onDismissed: (_) => _moveTaskToNextPage(index),
                child: TaskTile(
                  task: task,
                  onChanged: () => setState(task.toggleDone),
                  onMove: (dest) => _moveTask(pageIndex, index, dest),
                ),
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
              child: Text('Menu'),
            ),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('Best Todo 2'),
        actions: Config.isDev
            ? [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _rewindDay,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _advanceDay,
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Tomorrow'),
            Tab(text: 'Day After Tomorrow'),
            Tab(text: 'Next Week'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(_todayTasks, 0),
          _buildTaskList(_tomorrowTasks, 1),
          _buildTaskList(_dayAfterTasks, 2),
          _buildTaskList(_nextWeekTasks, 3),
        ],
      ),
    );
  }
}
