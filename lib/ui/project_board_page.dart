import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// Kanban-style board for a single [Project]. Tasks assigned to the project
/// are grouped into three columns (To-Do, Ongoing, Closed) and can be dragged
/// between columns to change their status.
class ProjectBoardPage extends StatefulWidget {
  final Project project;
  final List<Task> tasks;
  final VoidCallback onChanged;

  const ProjectBoardPage({
    Key? key,
    required this.project,
    required this.tasks,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<ProjectBoardPage> createState() => _ProjectBoardPageState();
}

class _ProjectBoardPageState extends State<ProjectBoardPage> {
  static const _columns = <_KanbanColumn>[
    _KanbanColumn(
      status: Task.kanbanTodo,
      title: 'To-Do',
      color: Color(0xFF90CAF9),
    ),
    _KanbanColumn(
      status: Task.kanbanOngoing,
      title: 'Ongoing',
      color: Color(0xFFFFCC80),
    ),
    _KanbanColumn(
      status: Task.kanbanClosed,
      title: 'Closed',
      color: Color(0xFFA5D6A7),
    ),
  ];

  List<Task> _tasksForStatus(String status) {
    return widget.tasks
        .where((t) =>
            t.deletedAt == null &&
            t.projectId == widget.project.id &&
            t.kanbanStatus == status)
        .toList();
  }

  void _moveTask(Task task, String status) {
    if (task.kanbanStatus == status) return;
    setState(() {
      task.kanbanStatus = status;
    });
    widget.onChanged();
  }

  void _removeFromProject(Task task) {
    setState(() {
      task.projectId = null;
      task.kanbanStatus = Task.kanbanTodo;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: widget.project.name),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final column in _columns)
              Expanded(child: _buildColumn(column)),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(_KanbanColumn column) {
    final tasks = _tasksForStatus(column.status);
    return DragTarget<Task>(
      onWillAccept: (task) => task != null && task.kanbanStatus != column.status,
      onAccept: (task) => _moveTask(task, column.status),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: column.color.withOpacity(highlighted ? 0.45 : 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: column.color.withOpacity(highlighted ? 1 : 0.5),
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                child: Text(
                  '${column.title} (${tasks.length})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Drop tasks here',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black45),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(4),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) =>
                            _buildCard(tasks[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(Task task) {
    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TaskDetailPage(task: task),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              InkWell(
                onTap: () => _removeFromProject(task),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 16, color: Colors.black45),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(8),
          child: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}

class _KanbanColumn {
  final String status;
  final String title;
  final Color color;

  const _KanbanColumn({
    required this.status,
    required this.title,
    required this.color,
  });
}
