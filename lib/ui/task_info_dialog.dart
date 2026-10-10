import 'package:flutter/material.dart';

import '../models/item_event.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../services/item_repository.dart';
import '../services/todoist_sync_service.dart';
import '../utils/label_utils.dart';
import 'task_detail_page.dart' show describeItemEvent;

/// Where a task came from, as shown in the task info dialog. [inferred] is
/// true when the task carries no explicit [Task.origin] stamp and the answer
/// was reconstructed from other traces (the history journal, approval
/// metadata) — or, failing those, assumed.
class TaskOriginInfo {
  /// One of [TaskChangeSource]'s constants, or null when nothing at all
  /// points at an origin.
  final String? source;
  final bool inferred;

  const TaskOriginInfo(this.source, {this.inferred = false});
}

/// Resolves [task]'s origin: the explicit [Task.origin] stamp when present
/// (0.2.88+), else traces only a Todoist pull leaves (approval metadata, the
/// waiting-for-approval tag), else the journal's live `created` event, else
/// a generated recurring occurrence. Null source when none of these apply.
TaskOriginInfo resolveTaskOrigin(Task task, List<ItemEvent> history) {
  final stamped = task.origin;
  if (stamped != null && stamped.isNotEmpty) return TaskOriginInfo(stamped);
  if (task.pendingSourceTitle != null ||
      task.approvedAt != null ||
      hasWaitingApprovalToken(task.label)) {
    return const TaskOriginInfo(TaskChangeSource.sync, inferred: true);
  }
  for (final event in history) {
    if (event.type == ItemEvent.typeCreated && !event.seeded) {
      return TaskOriginInfo(event.source, inferred: true);
    }
  }
  if (task.recurrenceParentUid != null) {
    return const TaskOriginInfo(TaskChangeSource.automation, inferred: true);
  }
  return const TaskOriginInfo(null, inferred: true);
}

/// Human-readable origin line, e.g. "Automatically via Todoist (approval
/// path)". Top-level so tests can cover the wording without widgets.
String describeTaskOrigin(TaskOriginInfo origin) {
  String text;
  switch (origin.source) {
    case TaskChangeSource.user:
    case TaskChangeSource.undo:
    case TaskChangeSource.redo:
      text = 'Manually in the app';
      break;
    case TaskChangeSource.sync:
      text = 'Automatically via Todoist (approval path)';
      break;
    case TaskChangeSource.share:
      text = 'Shared into the app (Android share sheet)';
      break;
    case TaskChangeSource.automation:
      text = 'Automatically by the app (recurring task)';
      break;
    default:
      return 'Unknown — created before origin tracking';
  }
  return origin.inferred ? '$text (inferred)' : text;
}

String _dateTimeLabel(DateTime at) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Opens the task info dialog: creation time, origin (in-app vs. Todoist /
/// approval path vs. share), approval and Todoist sync details, and the
/// task's full history timeline from the item journal.
Future<void> showTaskInfoDialog(BuildContext context, Task task) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Task info'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: TaskInfoView(task: task)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// The body of [showTaskInfoDialog]. Loads the task's history once (lazily,
/// like [TaskHistorySection]) since the origin inference also needs it.
class TaskInfoView extends StatefulWidget {
  final Task task;

  /// False on [TaskDetailPage], which already renders its own
  /// [TaskHistorySection] below.
  final bool showHistory;

  const TaskInfoView({Key? key, required this.task, this.showHistory = true})
      : super(key: key);

  @override
  State<TaskInfoView> createState() => _TaskInfoViewState();
}

class _TaskInfoViewState extends State<TaskInfoView> {
  late final Future<List<ItemEvent>> _history =
      ItemRepository.instance.historyOf(widget.task.uid).catchError(
            (_) => <ItemEvent>[],
          );

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final syncEntry = TodoistSyncService.instance.entryForLocalUid(task.uid);
    return FutureBuilder<List<ItemEvent>>(
      future: _history,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final events = snapshot.data ?? const <ItemEvent>[];
        final origin = resolveTaskOrigin(task, events);
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ])),
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(
              'Created',
              task.createdAt == null
                  ? 'Unknown'
                  : _dateTimeLabel(task.createdAt!),
            ),
            // Explicit stamps and approval traces don't need the journal, so
            // only an origin still unresolved waits for history to load.
            row(
              'Origin',
              loading && origin.source == null
                  ? '…'
                  : describeTaskOrigin(origin),
            ),
            if (task.pendingSourceTitle != null &&
                task.pendingSourceTitle!.trim().isNotEmpty)
              row('Todoist source', task.pendingSourceTitle!.trim()),
            if (hasWaitingApprovalToken(task.label))
              row('Approval', 'Waiting for approval')
            else if (task.approvedAt != null)
              row('Approved', _dateTimeLabel(task.approvedAt!)),
            if (task.completedAt != null)
              row('Completed', _dateTimeLabel(task.completedAt!)),
            if (task.deletedAt != null)
              row('Deleted', _dateTimeLabel(task.deletedAt!)),
            if (syncEntry != null) ...[
              row('Todoist ID', syncEntry.todoistId),
              row('Last synced', _dateTimeLabel(syncEntry.syncedAt)),
            ],
            if (widget.showHistory) ...[
              const SizedBox(height: 16),
              Text('History', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              // Plain text rather than a spinner: an indefinite animation
              // would keep pumpAndSettle from ever settling in widget tests.
              if (loading)
                Text('Loading…', style: theme.textTheme.bodySmall)
              else if (events.isEmpty)
                Text(
                  'No history recorded for this task.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                )
              else
                for (final event in events.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(
                            _dateTimeLabel(event.at),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.hintColor),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            describeItemEvent(event),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}
