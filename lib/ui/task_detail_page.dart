import 'package:flutter/material.dart';
import '../models/alarm.dart';
import '../models/item_event.dart';
import '../models/label.dart';
import '../models/task.dart';
import '../services/alarm_service.dart';
import '../services/item_event_journal.dart';
import '../services/label_service.dart';
import '../services/reminder_sync_service.dart';
import '../utils/label_utils.dart';
import 'subpage_app_bar.dart';

class TaskDetailPage extends StatelessWidget {
  final Task task;
  const TaskDetailPage({Key? key, required this.task}) : super(key: key);

  static String _clockLabel(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Task Details'),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            task.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.description),
          ],
          if (task.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note: ${task.note}'),
          ],
          if (task.label.isNotEmpty) ...[
            const SizedBox(height: 8),
            TaskLabelLine(label: task.label),
          ],
          if (task.dueDate != null) ...[
            const SizedBox(height: 8),
            Text('Due: ${task.dueDate!.toLocal().toString().split(' ')[0]}'),
          ],
          // A real interval (start != end) shows its range and length;
          // deadline-style tasks (start == end) keep just the Due line.
          if (task.duration != null && task.duration! > Duration.zero) ...[
            const SizedBox(height: 8),
            Text('Start: ${_clockLabel(task.startAt!)}'),
            Text('End: ${_clockLabel(task.endAt!)}'),
            Text('Duration: ${_durationLabel(task.duration!)}'),
          ],
          const SizedBox(height: 8),
          Text('Completed: ${task.isDone ? 'Yes' : 'No'}'),
          TaskReminderSection(task: task),
          TaskHistorySection(taskUid: task.uid),
        ],
      ),
    );
  }
}

/// One-tap reminder attached to this task. Creating uses the default "15
/// minutes before due"; the reminder then follows the task automatically
/// (reschedules move it, completing disables it, deleting removes it — see
/// `ReminderSyncService`), so this one tap is the entire interaction.
class TaskReminderSection extends StatelessWidget {
  final Task task;
  const TaskReminderSection({Key? key, required this.task}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Nothing to anchor a reminder to without a scheduled time.
    if (task.endAt == null) return const SizedBox.shrink();
    return ValueListenableBuilder<List<Alarm>>(
      valueListenable: AlarmService.instance.alarms,
      builder: (context, alarms, _) {
        Alarm? linked;
        for (final alarm in alarms) {
          if (alarm.itemUid == task.uid) {
            linked = alarm;
            break;
          }
        }
        if (linked == null) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.alarm_add),
              label: const Text('Remind me 15 min before due'),
              onPressed: () {
                final reminder = ReminderSyncService.buildReminder(task);
                if (reminder != null) {
                  // The in-memory list updates immediately; persistence /
                  // OS scheduling may be unavailable (web) — swallowed like
                  // all storage in this app.
                  AlarmService.instance.upsert(reminder).catchError((_) {});
                }
              },
            ),
          );
        }
        final reminder = linked;
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              const Icon(Icons.alarm_on),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Reminder ${reminder.scheduleLabel} ${reminder.timeLabel}'),
              ),
              IconButton(
                tooltip: 'Remove reminder',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => AlarmService.instance
                    .delete(reminder.uid)
                    .catchError((_) {}),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The task's label tokens annotated with their registry kind, e.g.
/// "Label: urgent (tag) · priority-high (priority)". Ensures the tokens are
/// registered (idempotent, background) and live-updates with the registry;
/// until it answers, the kind falls back to the same pure classification the
/// registry itself uses.
class TaskLabelLine extends StatelessWidget {
  final String label;
  const TaskLabelLine({Key? key, required this.label}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = splitLabelTokens(label);
    LabelService.instance.registerTokens(tokens);
    return ValueListenableBuilder<List<Label>>(
      valueListenable: LabelService.instance.labels,
      builder: (context, _, __) {
        final parts = tokens.map((token) {
          final kind =
              LabelService.instance.byName(token)?.kind ?? labelKindFor(token);
          return '$token ($kind)';
        }).join(' · ');
        return Text('Label: $parts');
      },
    );
  }
}

/// The item's journal timeline, loaded lazily when the page opens — the
/// journal file is never touched during app startup or list rendering.
class TaskHistorySection extends StatelessWidget {
  final String taskUid;
  const TaskHistorySection({Key? key, required this.taskUid})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ItemEvent>>(
      future: ItemEventJournal.instance.eventsForItem(taskUid),
      builder: (context, snapshot) {
        final events = snapshot.data;
        if (events == null || events.isEmpty) {
          // Nothing recorded (yet) — stay quiet rather than showing an empty
          // shell while the journal loads.
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('History', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final event in events.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        _timestampLabel(event.at),
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
        );
      },
    );
  }

  static String _timestampLabel(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// One human-readable line per journal event. Kept as a top-level function so
/// tests can cover the wording without pumping widgets.
String describeItemEvent(ItemEvent event) {
  String suffix() => event.seeded ? ' (reconstructed)' : '';
  Object? changeTo(String field) {
    for (final change in event.patch) {
      if (change.field == field) return change.to;
    }
    return null;
  }

  switch (event.type) {
    case ItemEvent.typeCreated:
      return 'Created${suffix()}';
    case ItemEvent.typeDeleted:
      return 'Deleted${suffix()}';
    case ItemEvent.typeRestored:
      return 'Restored${suffix()}';
    case ItemEvent.typeStatusChanged:
      return (changeTo('isDone') == true ? 'Completed' : 'Reopened') +
          suffix();
    case ItemEvent.typeScheduled:
      final due = changeTo('dueDate');
      if (due is String && due.isNotEmpty) {
        final parsed = DateTime.tryParse(due);
        if (parsed != null) {
          return 'Rescheduled to '
              '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-'
              '${parsed.day.toString().padLeft(2, '0')}${suffix()}';
        }
      }
      if (event.patch.any((c) => c.field == 'dueDate' && c.to == null)) {
        return 'Due date removed${suffix()}';
      }
      return 'Schedule changed${suffix()}';
    case ItemEvent.typeProjectChanged:
      return 'Project or stage changed${suffix()}';
    case ItemEvent.typeLabeled:
      final label = changeTo('label');
      return (label is String && label.isNotEmpty
              ? 'Labels changed to "$label"'
              : 'Labels cleared') +
          suffix();
    case ItemEvent.typeWishChanged:
      return (changeTo('isWish') == true
              ? 'Moved to wishlist'
              : 'Removed from wishlist') +
          suffix();
    case ItemEvent.typeRecurrenceChanged:
      return 'Recurrence changed${suffix()}';
    case ItemEvent.typeEdited:
      final fields = event.patch.map((c) => c.field).toList();
      return fields.isEmpty
          ? 'Edited${suffix()}'
          : 'Edited ${fields.join(', ')}${suffix()}';
    default:
      return '${event.type}${suffix()}';
  }
}
