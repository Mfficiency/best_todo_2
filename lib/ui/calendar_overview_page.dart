import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../utils/date_utils.dart';
import '../utils/task_utils.dart';
import 'task_tile.dart';

class CalendarOverviewPage extends StatefulWidget {
  final List<Task> tasks;
  final DateTime currentDate;
  final bool swipeLeftDelete;
  final void Function(String title) onAddTask;
  final void Function(Task task) onTaskChanged;
  final void Function(Task task) onToggleTask;
  final void Function(Task task, DateTime? oldDueDate, DateTime? newDueDate)
      onTaskDueDateChanged;
  final void Function(Task task, int destination) onMoveTask;
  final void Function(Task task) onMoveTaskToNext;
  final void Function(Task task) onDeleteTask;

  const CalendarOverviewPage({
    super.key,
    required this.tasks,
    required this.currentDate,
    required this.swipeLeftDelete,
    required this.onAddTask,
    required this.onTaskChanged,
    required this.onToggleTask,
    required this.onTaskDueDateChanged,
    required this.onMoveTask,
    required this.onMoveTaskToNext,
    required this.onDeleteTask,
  });

  @override
  State<CalendarOverviewPage> createState() => _CalendarOverviewPageState();
}

class _CalendarOverviewPageState extends State<CalendarOverviewPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  int _pageIndexForTask(Task task) {
    final dueDate = task.dueDate;
    if (dueDate == null) return 0;
    final diff = dateDiffInDays(dueDate, widget.currentDate);
    if (diff <= 0) return 0;
    if (diff == 1) return 1;
    if (diff == 2) return 2;
    if (diff < 30) return 3;
    return 4;
  }

  SplayTreeMap<DateTime, List<Task>> _groupedTasks() {
    final groups = SplayTreeMap<DateTime, List<Task>>(
      (a, b) => a.compareTo(b),
    );
    for (final task in widget.tasks) {
      final dueDate = task.dueDate;
      if (dueDate == null) {
        continue;
      }
      final day = _dateOnly(dueDate);
      groups.putIfAbsent(day, () => <Task>[]).add(task);
    }
    for (final entry in groups.entries) {
      sortTasks(entry.value);
    }
    return groups;
  }

  String _formatDate(BuildContext context, DateTime date) {
    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: 'search soon available',
            border: InputBorder.none,
            suffixIcon: Icon(Icons.search),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Calendar List'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration:
                            const InputDecoration(labelText: 'Add task'),
                        onSubmitted: (value) {
                          widget.onAddTask(value);
                          _controller.clear();
                          setState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        widget.onAddTask(_controller.text);
                        _controller.clear();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final groups = _groupedTasks();
                    if (groups.isEmpty) {
                      return const Center(child: Text('No tasks available'));
                    }
                    final entries = groups.entries.toList();
                    final isAndroid =
                        Theme.of(context).platform == TargetPlatform.android;
                    return ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, groupIndex) {
                        final entry = entries[groupIndex];
                        final date = entry.key;
                        final tasks = entry.value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Text(
                                _formatDate(context, date),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: tasks.length,
                              itemBuilder: (context, taskIndex) {
                                final task = tasks[taskIndex];
                                final pageIndex = _pageIndexForTask(task);
                                final tile = TaskTile(
                                  key: isAndroid ? ValueKey(task.uid) : null,
                                  task: task,
                                  onChanged: () {
                                    widget.onTaskChanged(task);
                                  },
                                  onToggle: () {
                                    widget.onToggleTask(task);
                                    setState(() {});
                                  },
                                  onDueDateChanged: (oldDueDate, newDueDate) {
                                    widget.onTaskDueDateChanged(
                                      task,
                                      oldDueDate,
                                      newDueDate,
                                    );
                                    setState(() {});
                                  },
                                  onMove: (dest) {
                                    widget.onMoveTask(task, dest);
                                    setState(() {});
                                  },
                                  onMoveNext: () {
                                    widget.onMoveTaskToNext(task);
                                    setState(() {});
                                  },
                                  onDelete: () {
                                    widget.onDeleteTask(task);
                                    setState(() {});
                                  },
                                  pageIndex: pageIndex,
                                  showSwipeButton: !isAndroid,
                                  swipeLeftDelete: widget.swipeLeftDelete,
                                );
                                if (isAndroid) {
                                  return tile;
                                }
                                return Dismissible(
                                  key: ValueKey(task.uid),
                                  background: Container(
                                    color: Colors.greenAccent.withOpacity(0.5),
                                  ),
                                  onDismissed: (_) {
                                    widget.onMoveTaskToNext(task);
                                    setState(() {});
                                  },
                                  child: tile,
                                );
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
