import 'package:flutter/material.dart';

import '../models/project.dart';
import '../models/task.dart';
import 'project_board_page.dart';
import 'subpage_app_bar.dart';

/// Projects tool. The top pane lists all existing tasks and the bottom pane
/// lists the available projects. Drag a task from the top pane onto a project
/// in the bottom pane to assign it. Tapping a project opens its Kanban board.
class ProjectsPage extends StatefulWidget {
  final List<Task> tasks;
  final VoidCallback onChanged;

  const ProjectsPage({
    Key? key,
    required this.tasks,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  final List<Project> _projects = Project.placeholders;

  List<Task> get _activeTasks =>
      widget.tasks.where((t) => t.deletedAt == null).toList();

  int _taskCountForProject(Project project) =>
      widget.tasks.where((t) => t.deletedAt == null && t.projectId == project.id).length;

  Project? _projectById(String? id) {
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  void _assignTaskToProject(Task task, Project project) {
    setState(() {
      task.projectId = project.id;
      task.kanbanStatus = Task.kanbanTodo;
    });
    widget.onChanged();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Added "${task.title}" to ${project.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _openProject(Project project) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ProjectBoardPage(
              project: project,
              tasks: widget.tasks,
              onChanged: widget.onChanged,
            ),
          ),
        )
        .then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Projects'),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildTasksPane()),
          const Divider(height: 1, thickness: 1),
          Expanded(flex: 2, child: _buildProjectsPane()),
        ],
      ),
    );
  }

  Widget _buildTasksPane() {
    final tasks = _activeTasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'All Tasks',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Long-press a task and drag it onto a project below.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? const Center(child: Text('No tasks yet'))
              : ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _buildTaskTile(tasks[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildTaskTile(Task task) {
    final project = _projectById(task.projectId);
    final tile = Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.drag_indicator),
        title: Text(task.title),
        trailing: project == null
            ? null
            : Chip(
                label: Text(
                  project.name,
                  style: const TextStyle(fontSize: 11),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
      ),
    );

    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(12),
          child: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _buildProjectsPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Projects',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final project in _projects)
                  Expanded(child: _buildProjectCard(project)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildProjectCard(Project project) {
    final count = _taskCountForProject(project);
    return DragTarget<Task>(
      onWillAccept: (task) => task != null,
      onAccept: (task) => _assignTaskToProject(task, project),
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.all(4),
          child: InkWell(
            onTap: () => _openProject(project),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: highlighted
                    ? scheme.primary.withOpacity(0.25)
                    : scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: highlighted
                      ? scheme.primary
                      : scheme.primary.withOpacity(0.4),
                  width: highlighted ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder, color: scheme.primary),
                  const SizedBox(height: 8),
                  Text(
                    project.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count task${count == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
