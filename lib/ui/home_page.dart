import 'package:flutter/material.dart';
import '../models/task.dart';
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

  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      if (_tabController.index == 0) {
        _todayTasks.add(Task(title: title));
      } else {
        _tomorrowTasks.add(Task(title: title));
      }
    });
    _controller.clear();
  }

  void _moveTaskToNextPage(int index) {
    setState(() {
      if (_tabController.index == 0 && index < _todayTasks.length) {
        final task = _todayTasks.removeAt(index);
        _tomorrowTasks.add(task);
      } else if (_tabController.index == 1 && index < _tomorrowTasks.length) {
        _tomorrowTasks.removeAt(index);
      }
    });
  }

  Widget _buildTaskList(List<Task> tasks) {
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
                key: ValueKey('${task.title}-$index-${_tabController.index}'),
                background: Container(
                  color: Colors.greenAccent.withOpacity(0.5),
                ),
                onDismissed: (_) => _moveTaskToNextPage(index),
                child: TaskTile(
                  task: task,
                  onChanged: () => setState(task.toggleDone),
                  onSwiped: () => _moveTaskToNextPage(index),
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
      appBar: AppBar(
        title: const Text('Best Todo 2'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Today'), Tab(text: 'Tomorrow')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTaskList(_todayTasks),
          _buildTaskList(_tomorrowTasks),
        ],
      ),
    );
  }
}
