import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/task.dart';
import '../services/project_service.dart';
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
  late Project _project = widget.project;

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

  Future<void> _editProject() async {
    final updated = await showDialog<Project>(
      context: context,
      builder: (_) => _ProjectEditDialog(project: _project),
    );
    if (updated != null) {
      await ProjectService.instance.upsert(updated);
      if (mounted) setState(() => _project = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: _project.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit project',
            onPressed: _editProject,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_project.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _project.description,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final column in _columns)
                    Expanded(child: _buildColumn(column)),
                ],
              ),
            ),
          ),
        ],
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

/// Name + description editor for a [Project]. Owns its text controllers (so
/// they outlive the dialog's exit animation) and pops with the edited copy on
/// Save, or null on Cancel. An emptied name keeps the previous one.
class _ProjectEditDialog extends StatefulWidget {
  final Project project;

  const _ProjectEditDialog({required this.project});

  @override
  State<_ProjectEditDialog> createState() => _ProjectEditDialogState();
}

class _ProjectEditDialogState extends State<_ProjectEditDialog> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.project.name);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.project.description);

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    Navigator.of(context).pop(widget.project.copyWith(
      name: name.isEmpty ? widget.project.name : name,
      description: _descriptionController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _descriptionController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description'),
            keyboardType: TextInputType.multiline,
            maxLines: null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
