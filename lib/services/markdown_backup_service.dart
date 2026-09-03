import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../models/alarm.dart';
import '../models/attachment.dart';
import '../models/countdown_timer.dart';
import '../models/item_event.dart';
import '../models/project.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../models/view_filter_rules.dart';
import '../models/view_presentation.dart';
import '../utils/label_utils.dart';

/// Writes the Markdown companion of a full backup: one small vault, next to
/// the JSON file, with one human-readable note per item plus a description
/// of the views and settings in effect at backup time.
///
/// Every note — whatever the item type — follows the same section order, so
/// the same Obsidian template/Dataview query works across the whole vault:
/// title, description, notes, then a Properties block (YAML frontmatter,
/// which Obsidian collapses by default — the note's "hidden" fields) holding
/// the raw description again, the tag list, the created time, reminders,
/// notification settings and every other field the JSON backup carries.
/// Visible tags are rendered as `[[wikilinks]]` in a Links section so
/// Obsidian's graph view picks them up like any other note reference.
///
/// This is purely an export format: nothing here is read back in. The JSON
/// backup written alongside it remains the one thing Import restores from.
class MarkdownBackupService {
  MarkdownBackupService._();

  /// Writes the whole vault under [root] (created if missing), from the same
  /// data [AutoBackupService] just wrote into the JSON backup. [tasks] is
  /// the active list; [archivedTasks] is Archived Items; [binTasks] is the
  /// real Deleted bin — all three land in the same `Tasks/` folder, tagged
  /// with their `status` frontmatter field, since they're the same kind of
  /// item and differ only in which list currently holds them.
  static Future<void> writeVault({
    required Directory root,
    required List<Task> tasks,
    required List<Task> archivedTasks,
    required List<Task> binTasks,
    required List<Project> projects,
    required List<Alarm> alarms,
    required List<CountdownTimerItem> timers,
    required List<ItemEvent> itemEvents,
  }) async {
    final eventsByItem = <String, List<ItemEvent>>{};
    for (final event in itemEvents) {
      eventsByItem.putIfAbsent(event.itemId, () => []).add(event);
    }
    final remindersByTask = <String, List<Alarm>>{};
    final standaloneAlarms = <Alarm>[];
    for (final alarm in alarms) {
      final itemUid = alarm.itemUid;
      if (itemUid != null) {
        remindersByTask.putIfAbsent(itemUid, () => []).add(alarm);
      } else {
        standaloneAlarms.add(alarm);
      }
    }
    final projectNames = {for (final project in projects) project.id: project.name};
    final taskTitles = {
      for (final task in [...tasks, ...archivedTasks, ...binTasks])
        task.uid: task.title,
    };

    final taskFiles = <String, String>{};
    void addTasks(List<Task> list, String status) {
      for (final task in list) {
        taskFiles[_fileName(task.title, task.uid)] = _taskNote(
          task,
          status,
          remindersByTask[task.uid] ?? const [],
          eventsByItem[task.uid] ?? const [],
          projectNames,
        );
      }
    }

    addTasks(tasks, 'active');
    addTasks(archivedTasks, 'archived');
    addTasks(binTasks, 'binned');
    await _writeFolder(root, 'Tasks', taskFiles);

    await _writeFolder(root, 'Projects', {
      for (final project in projects)
        _fileName(project.name, project.id): _projectNote(project),
    });
    await _writeFolder(root, 'Alarms', {
      for (final alarm in standaloneAlarms)
        _fileName(alarm.name, alarm.uid): _alarmNote(alarm),
    });
    await _writeFolder(root, 'Countdown Timers', {
      for (final timer in timers)
        _fileName(timer.label, timer.uid): _timerNote(timer, taskTitles),
    });
    await _writeFolder(root, 'Views', _viewNotes());
    await _writeFolder(root, 'Settings', {'Settings.md': _settingsNote()});
  }

  static Future<void> _writeFolder(
    Directory root,
    String name,
    Map<String, String> files,
  ) async {
    final sep = Platform.pathSeparator;
    final dir = Directory('${root.path}$sep$name');
    await dir.create(recursive: true);
    for (final entry in files.entries) {
      final file = File('${dir.path}$sep${entry.key}');
      await file.writeAsString(entry.value, flush: true);
    }
  }

  /// A filesystem-safe, human-readable filename: the title, sanitized and
  /// capped, plus an 8-char uid suffix so same-titled items never collide.
  static String _fileName(String title, String uid) {
    var slug = title.trim();
    if (slug.isEmpty) slug = 'Untitled';
    slug = slug.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    slug = slug.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (slug.length > 60) slug = slug.substring(0, 60).trim();
    final suffix = uid.length >= 8 ? uid.substring(0, 8) : uid;
    return '$slug ($suffix).md';
  }

  // ---------------------------------------------------------------------
  // Per-item notes
  // ---------------------------------------------------------------------

  static String _taskNote(
    Task task,
    String status,
    List<Alarm> reminders,
    List<ItemEvent> events,
    Map<String, String> projectNames,
  ) {
    final other = <String, Object?>{
      'status': status,
      'due': task.dueDate?.toIso8601String(),
      'allDay': task.allDay,
      'isDone': task.isDone,
      'completedAt': task.completedAt?.toIso8601String(),
      'deletedAt': task.deletedAt?.toIso8601String(),
      'project': task.projectId != null
          ? (projectNames[task.projectId] ?? task.projectId)
          : null,
      'kanbanStatus': task.projectId != null ? task.kanbanStatus : null,
      'isWish': task.isWish,
      'isFoodDiaryEntry': task.isEatingHabit,
      'isRecurring': task.isRecurring,
      if (task.isRecurring) 'recurrenceFrequency': task.recurrenceFrequency,
      if (task.isRecurring) 'recurrenceInterval': task.recurrenceInterval,
      if (task.isRecurring && task.recurrenceWeekdays.isNotEmpty)
        'recurrenceWeekdays':
            task.recurrenceWeekdays.map((d) => d.toString()).toList(),
      if (task.isRecurring) 'recurrenceEndType': task.recurrenceEndType,
      if (task.isRecurring && task.recurrenceOccurrenceCount != null)
        'recurrenceOccurrenceCount': task.recurrenceOccurrenceCount,
      if (task.isRecurring)
        'recurrenceEndDate': task.recurrenceEndDate?.toIso8601String(),
      if (task.recurrenceExceptionDates.isNotEmpty)
        'recurrenceExceptionDates': task.recurrenceExceptionDates,
      if (task.recurrenceOverride) 'recurrenceOverride': task.recurrenceOverride,
      if (task.recurrenceParentUid != null)
        'recurrenceParentUid': task.recurrenceParentUid,
      if (task.recurrenceInstanceKey != null)
        'recurrenceInstanceKey': task.recurrenceInstanceKey,
      'autoDeleted': task.autoDeleted,
      if (task.attachments.isNotEmpty)
        'attachments': [
          for (final attachment in task.attachments) _attachmentSummary(attachment),
        ],
    }..removeWhere((key, value) => value == null);

    return _buildNote(
      type: 'task',
      uid: task.uid,
      title: task.title,
      description: task.description,
      notes: task.note,
      tags: splitLabelTokens(task.label),
      created: task.createdAt,
      reminders: [for (final alarm in reminders) _reminderSummary(alarm)],
      historyLines: _historyLines(events),
      otherFields: other,
    );
  }

  static String _attachmentSummary(Attachment attachment) {
    final kind = switch (attachment.type) {
      Attachment.typeImage => 'image',
      Attachment.typePdf => 'pdf',
      _ => 'text',
    };
    if (attachment.type == Attachment.typeText) {
      final flat = attachment.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      final preview = flat.length > 60 ? '${flat.substring(0, 60)}…' : flat;
      return '$kind: $preview';
    }
    final name = attachment.fileName.isNotEmpty
        ? attachment.fileName
        : (attachment.relativePath ?? attachment.uid);
    return '$kind: $name';
  }

  static String _projectNote(Project project) => _buildNote(
        type: 'project',
        uid: project.id,
        title: project.name,
        description: project.description,
        notes: '',
        tags: const [],
        created: null,
        reminders: const [],
        historyLines: const [],
        otherFields: const {},
      );

  static String _alarmNote(Alarm alarm) {
    final other = <String, Object?>{
      'time': alarm.timeLabel,
      'schedule': alarm.scheduleLabel,
      'enabled': alarm.enabled,
      'melody': alarm.melody,
      'volume': alarm.volume,
      'vibrate': alarm.vibrate,
      'overrideDnd': alarm.overrideDnd,
      'snoozeEnabled': alarm.snoozeEnabled,
      if (alarm.snoozeEnabled) 'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
      if (alarm.snoozeEnabled) 'snoozeMaxCount': alarm.snoozeMaxCount,
    };
    return _buildNote(
      type: 'alarm',
      uid: alarm.uid,
      title: alarm.name,
      description: alarm.description,
      notes: '',
      tags: splitLabelTokens(alarm.tags),
      created: null,
      reminders: ['${alarm.scheduleLabel} at ${alarm.timeLabel}'],
      historyLines: const [],
      otherFields: other,
    );
  }

  static String _timerNote(
    CountdownTimerItem timer,
    Map<String, String> taskTitles,
  ) {
    final other = <String, Object?>{
      'target': timer.target.toIso8601String(),
      'notifyOnZero': timer.notifyOnZero,
      'notifyRoundNumbers': timer.notifyRoundNumbers,
      if (timer.itemUid != null)
        'linkedTask': taskTitles[timer.itemUid] ?? timer.itemUid,
    };
    return _buildNote(
      type: 'countdownTimer',
      uid: timer.uid,
      title: timer.label,
      description: '',
      notes: '',
      tags: splitLabelTokens(timer.tags),
      created: timer.createdAt,
      reminders: timer.notifyRoundNumbers
          ? [
              for (final milestone in timer.sortedMilestones)
                '${milestone.label} (${milestone.directionLabel})',
            ]
          : const [],
      historyLines: ['${_dateTime(timer.editedAt)} — Last edited'],
      otherFields: other,
    );
  }

  /// Assembles one note: a YAML frontmatter block (Obsidian's Properties
  /// panel — collapsed by default, hence the "hidden" fields) followed by
  /// the visible body. Every item type funnels through here so the section
  /// order never drifts between Tasks/Projects/Alarms/Countdown Timers.
  static String _buildNote({
    required String type,
    required String uid,
    required String title,
    required String description,
    required String notes,
    required List<String> tags,
    required DateTime? created,
    required List<String> reminders,
    required List<String> historyLines,
    required Map<String, Object?> otherFields,
  }) {
    final frontmatter = <String, Object?>{
      'uid': uid,
      'type': type,
      'created': created?.toIso8601String(),
      'description': description,
      'tags': tags,
      'reminders': reminders,
      ...otherFields,
    };
    final displayTitle = title.trim().isEmpty ? '(untitled)' : title.trim();
    final buffer = StringBuffer()
      ..writeln('---')
      ..write(_yaml(frontmatter))
      ..writeln('---')
      ..writeln()
      ..writeln('# $displayTitle')
      ..writeln()
      ..writeln(description.trim().isEmpty ? '_No description._' : description.trim())
      ..writeln()
      ..writeln('## Notes')
      ..writeln()
      ..writeln(notes.trim().isEmpty ? '_No notes._' : notes.trim())
      ..writeln()
      ..writeln('## Links')
      ..writeln()
      ..writeln(tags.isEmpty ? '_No tags._' : tags.map((t) => '[[$t]]').join(' '))
      ..writeln()
      ..writeln('## Edit History')
      ..writeln();
    if (historyLines.isEmpty) {
      buffer.writeln('_No recorded history._');
    } else {
      for (final line in historyLines) {
        buffer.writeln('- $line');
      }
    }
    return buffer.toString();
  }

  static String _reminderSummary(Alarm alarm) {
    final anchor = alarm.triggerAnchor == Alarm.anchorStart ? 'start' : 'end';
    final offset = alarm.triggerOffsetMinutes;
    final when = offset == 0
        ? 'at $anchor'
        : '${offset.abs()}m ${offset < 0 ? 'before' : 'after'} $anchor';
    final bits = <String>[
      when,
      alarm.melody,
      'volume ${(alarm.volume * 100).round()}%',
    ];
    if (alarm.vibrate) bits.add('vibrate');
    if (alarm.overrideDnd) bits.add('overrides Do Not Disturb');
    if (!alarm.enabled) bits.add('disabled');
    return bits.join(' · ');
  }

  static List<String> _historyLines(List<ItemEvent> events) {
    final sorted = [...events]..sort((a, b) => a.seq.compareTo(b.seq));
    return [for (final event in sorted) _historyLine(event)];
  }

  static String _historyLine(ItemEvent event) {
    final ts = _dateTime(event.at);
    final label = switch (event.type) {
      ItemEvent.typeCreated => 'Created',
      ItemEvent.typeDeleted => 'Deleted',
      ItemEvent.typeRestored => 'Restored',
      ItemEvent.typeStatusChanged => 'Status changed',
      ItemEvent.typeScheduled => 'Rescheduled',
      ItemEvent.typeLabeled => 'Tags changed',
      ItemEvent.typeProjectChanged => 'Project changed',
      ItemEvent.typeWishChanged => 'Wishlist flag changed',
      ItemEvent.typeRecurrenceChanged => 'Recurrence changed',
      _ => 'Edited',
    };
    final source = event.source == TaskChangeSource.user
        ? ''
        : ' [${TaskChangeSource.label(event.source)}]';
    return '$ts — $label$source${_patchSuffix(event)}';
  }

  static String _patchSuffix(ItemEvent event) {
    if (event.patch.isEmpty) return '';
    final changes = event.patch
        .map((c) => '${c.field}: ${c.from ?? '—'} → ${c.to ?? '—'}')
        .join(', ');
    return ' ($changes)';
  }

  // ---------------------------------------------------------------------
  // Views + Settings
  // ---------------------------------------------------------------------

  /// One note per view (Home, Wishlist, Waiting for Approval, Projects,
  /// Food Diary, Alarms, Countdown, Archived items, Deleted bin): its
  /// built-in structural rule, the Settings → Filtering rules tags currently
  /// configured for it, and its presentation settings. Sourced live from
  /// [ViewFilterRules]/[Config.viewFilterRules]/[ViewPresentation] so this
  /// always matches what the app is actually doing, not a hand-written
  /// snapshot that drifts as views are added or reconfigured.
  static Map<String, String> _viewNotes() {
    final notes = <String, String>{};
    for (final id in ViewFilterRules.viewIds) {
      final label = ViewFilterRules.viewLabels[id] ?? id;
      final description = ViewFilterRules.viewDescriptions[id] ?? '';
      final builtIn = ViewFilterRules.builtInRules[id] ?? '';
      final rules = Config.viewFilterRules[id] ?? ViewFilterRules.defaultsFor(id);
      final presentation = ViewPresentation.forView(id);
      final buffer = StringBuffer()
        ..writeln('# $label')
        ..writeln()
        ..writeln(description.isEmpty ? '_No description._' : description)
        ..writeln();
      if (builtIn.isNotEmpty) {
        buffer
          ..writeln('## Built-in rule')
          ..writeln()
          ..writeln(builtIn)
          ..writeln();
      }
      buffer
        ..writeln('## Configured filtering rules')
        ..writeln();
      if (rules == null || rules.isEmpty) {
        buffer.writeln('_No extra tag filter configured (Settings → '
            'Filtering rules)._');
      } else {
        if (rules.includeTags.isNotEmpty) {
          buffer.writeln('- Show only items tagged: ${rules.includeTags.join(', ')}');
        }
        if (rules.excludeTags.isNotEmpty) {
          buffer.writeln('- Hide items tagged: ${rules.excludeTags.join(', ')}');
        }
      }
      buffer
        ..writeln()
        ..writeln('## Cosmetic settings')
        ..writeln()
        ..writeln('- Reminder section shown on Task Details: '
            '${presentation.showReminderSection}')
        ..writeln('- Countdown section shown on Task Details: '
            '${presentation.showCountdownSection}');
      if (id == ViewFilterRules.home) {
        final startTab = Config.startTabIndex >= 0 &&
                Config.startTabIndex < Config.tabs.length
            ? Config.tabs[Config.startTabIndex].replaceAll(RegExp(r'\s+'), ' ').trim()
            : 'Today';
        buffer
          ..writeln()
          ..writeln('## Home tab buckets')
          ..writeln()
          ..writeln('Six tabs bucket every visible task by its due date, '
              'relative to today:')
          ..writeln()
          ..writeln('| Tab | Filter |')
          ..writeln('| --- | --- |')
          ..writeln('| Today | overdue, or due today |')
          ..writeln('| Tomorrow | due date exactly 1 day away |')
          ..writeln('| Day after tomorrow | due date exactly 2 days away |')
          ..writeln('| Next week | 3–29 days away |')
          ..writeln('| Next month | 30+ days away |')
          ..writeln('| Future | no due date, or parked with the Future marker |')
          ..writeln()
          ..writeln('Within a tab, open tasks are listed before done ones, '
              'then by manual ranking.')
          ..writeln()
          ..writeln('- Start tab: $startTab')
          ..writeln('- Icon tabs: ${Config.useIconTabs}')
          ..writeln('- Minimalist mode: ${Config.minimalistMode}')
          ..writeln('- 24-hour time: ${Config.use24HourFormat}')
          ..writeln('- Date format: ${Config.dateFormat}');
      } else if (id == ViewFilterRules.projects) {
        buffer
          ..writeln()
          ..writeln('## Kanban board')
          ..writeln()
          ..writeln('Every project board has the same three fixed columns:')
          ..writeln()
          ..writeln('| Column | Filter |')
          ..writeln('| --- | --- |')
          ..writeln('| To-Do | `kanbanStatus = todo` |')
          ..writeln('| Ongoing | `kanbanStatus = ongoing` |')
          ..writeln('| Closed | `kanbanStatus = closed` |');
      }
      notes['$label.md'] = buffer.toString();
    }
    return notes;
  }

  static String _settingsNote() {
    final map = Config.toMap();
    final token = map['todoistApiToken'] as String? ?? '';
    map['todoistApiToken'] = token.isEmpty
        ? ''
        : '(hidden — restore the JSON backup to recover it)';
    final calendarUrl = map['googleCalendarUrl'] as String? ?? '';
    map['googleCalendarUrl'] = calendarUrl.isEmpty
        ? ''
        : '(hidden — restore the JSON backup to recover it)';
    const encoder = JsonEncoder.withIndent('  ');
    return '''
# Settings

Snapshot of every app setting at backup time. The Todoist API token and the
Google Calendar feed URL are redacted here — both grant access to an outside
account — and are preserved in the JSON backup for a full restore.

```json
${encoder.convert(map)}
```
''';
  }

  // ---------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dateTime(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  /// Minimal YAML encoder for the flat frontmatter maps built above: null,
  /// bool, num, String and `List<String>` values only — everything this
  /// service ever puts in a frontmatter block.
  static String _yaml(Map<String, Object?> map) {
    final buffer = StringBuffer();
    map.forEach((key, value) {
      if (value == null) {
        buffer.writeln('$key:');
      } else if (value is List) {
        if (value.isEmpty) {
          buffer.writeln('$key: []');
        } else {
          buffer.writeln('$key:');
          for (final item in value) {
            buffer.writeln('  - ${_yamlScalar(item)}');
          }
        }
      } else {
        buffer.writeln('$key: ${_yamlScalar(value)}');
      }
    });
    return buffer.toString();
  }

  static String _yamlScalar(Object? value) {
    if (value is bool || value is num) return value.toString();
    final s = value.toString();
    // A plain YAML scalar is safe with commas and lone colons; it only needs
    // quoting when it could be mistaken for a mapping ("key: value"), a flow
    // collection, a comment, another type, or when it carries leading/
    // trailing whitespace or a literal newline/quote.
    final needsQuoting = s.isEmpty ||
        s.trim() != s ||
        s.contains(': ') ||
        s.endsWith(':') ||
        s.contains('#') ||
        s.contains('"') ||
        s.contains('\n') ||
        RegExp(r'^[-?:,\[\]{}&*!|>%@`]').hasMatch(s) ||
        RegExp(r'^(true|false|null|~|-?\d+(\.\d+)?)$', caseSensitive: false)
            .hasMatch(s);
    if (!needsQuoting) return s;
    final escaped =
        s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n');
    return '"$escaped"';
  }
}
