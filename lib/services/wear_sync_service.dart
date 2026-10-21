import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/alarm.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import 'task_widget_service.dart';

/// One command the watch sent (`/todo/command/complete`), as queued by the
/// phone's native `WearCommandService` until the app applies it.
@immutable
class WearCommand {
  const WearCommand({required this.action, required this.id, this.at});

  /// `complete` is the only action of v1.
  final String action;

  /// The task's uid.
  final String id;

  /// When the phone received it (the completion time), null if unknown.
  final DateTime? at;

  static const String complete = 'complete';
}

/// The Wear OS companion (`wear/`, see wear/README.md): the phone publishes
/// today's/tomorrow's tasks and the alarms as Wearable Data Layer items, the
/// watch sends "complete this task" back.
///
/// * Publishing rides on the two home-screen widget syncs
///   ([TaskWidgetService.sync], `AlarmWidgetService.sync`), so the watch sees
///   exactly the widget's list (same gates: deleted, waiting for approval,
///   Food Diary/Research, the Worklist-only `mlr` tag, the Home filter rules)
///   whenever the widget is redrawn. The Kotlin side (`WearSync.kt`) puts the
///   JSON into a DataItem; nothing is sent when it didn't change.
/// * Commands are never applied in Kotlin: `WearCommandService.kt` only
///   queues them (native SharedPreferences `best_todo_wear`) and pokes the
///   running app (`wearCommandsPending`); the home page drains the queue with
///   [takeCommands] on start, on resume and on that poke, and completes the
///   tasks through its own in-memory list and save path (stats, streak,
///   history, Todoist), then the widget sync republishes. With the app not
///   running at all the service also fires the widget's own background path
///   (`besttodotask://complete?id=`), so the task is done even before the app
///   is opened; the queued copy then finds it done and does nothing.
///
/// Every call is Android only and swallows every error: the web, desktop and
/// tests have no such channel.
class WearSyncService {
  WearSyncService._();

  static const MethodChannel channel = MethodChannel('besttodo/wear');

  static const String todayPath = '/todo/today';
  static const String alarmsPath = '/todo/alarms';

  /// Most rows per list the watch gets (it shows them all, scrolling).
  static const int maxRows = 40;

  /// Payload format version (`v` in every JSON).
  static const int payloadVersion = 1;

  /// Last JSON handed to the platform per path, so an unchanged list is not
  /// re-sent on every save.
  static final Map<String, String> _lastPublished = {};

  @visibleForTesting
  static bool? debugIsAndroid;

  static bool get _isAndroid =>
      debugIsAndroid ?? (!kIsWeb && Platform.isAndroid);

  @visibleForTesting
  static void resetForTest() {
    _lastPublished.clear();
    debugIsAndroid = null;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Map<String, Object?> _row(Task t) => {
        'id': t.uid,
        'title': t.title.trim().isEmpty ? '(no title)' : t.title.trim(),
        'done': t.isDone,
      };

  /// The `/todo/today` JSON: today's list exactly as the task widget shows it
  /// ([TaskWidgetService.todayTasks]: today + overdue, open first) and
  /// tomorrow's ([TaskWidgetService.tomorrowTasks]), at most [maxRows] each
  /// (`todayMore`/`tomorrowMore` count the rest).
  static String tasksPayload(
    List<Task> tasks, {
    DateTime? now,
    ViewFilterRules? rules,
  }) {
    final at = now ?? DateTime.now();
    final today = TaskWidgetService.todayTasks(tasks, now: at, rules: rules);
    final tomorrow =
        TaskWidgetService.tomorrowTasks(tasks, now: at, rules: rules);
    return jsonEncode({
      'v': payloadVersion,
      'day': _day(at),
      'today': today.take(maxRows).map(_row).toList(),
      'todayMore': today.length > maxRows ? today.length - maxRows : 0,
      'tomorrow': tomorrow.take(maxRows).map(_row).toList(),
      'tomorrowMore':
          tomorrow.length > maxRows ? tomorrow.length - maxRows : 0,
    });
  }

  /// The `/todo/alarms` JSON: the alarms the alarm widget shows, the ones
  /// that will ring first (soonest next time), then those switched off.
  /// `next` is the next ring time in epoch millis (null when off or past).
  static String alarmsPayload(List<Alarm> alarms, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final rows = alarms.map((a) {
      final next = a.enabled ? a.nextOccurrence(at) : null;
      return (alarm: a, next: next);
    }).toList()
      ..sort((x, y) {
        if (x.next != null && y.next != null) return x.next!.compareTo(y.next!);
        if (x.next != null) return -1;
        if (y.next != null) return 1;
        final xm = x.alarm.hour * 60 + x.alarm.minute;
        final ym = y.alarm.hour * 60 + y.alarm.minute;
        return xm.compareTo(ym);
      });
    return jsonEncode({
      'v': payloadVersion,
      'alarms': rows
          .take(maxRows)
          .map((r) => {
                'id': r.alarm.uid,
                'time': r.alarm.timeLabel,
                'name': r.alarm.name.isEmpty ? 'Alarm' : r.alarm.name,
                'sub': r.alarm.scheduleLabel,
                'on': r.alarm.enabled,
                'next': r.next?.millisecondsSinceEpoch,
              })
          .toList(),
    });
  }

  /// Publishes today's/tomorrow's tasks. Fire and forget.
  static void publishTasks(List<Task> tasks, {DateTime? now}) {
    if (!_isAndroid) return;
    try {
      _publish(todayPath, tasksPayload(tasks, now: now));
    } catch (_) {}
  }

  /// Publishes the alarm list. Fire and forget.
  static void publishAlarms(List<Alarm> alarms, {DateTime? now}) {
    if (!_isAndroid) return;
    try {
      _publish(alarmsPath, alarmsPayload(alarms, now: now));
    } catch (_) {}
  }

  static void _publish(String path, String json) {
    if (_lastPublished[path] == json) return;
    _lastPublished[path] = json;
    unawaited(channel
        .invokeMethod<void>('publish', {'path': path, 'json': json})
        .catchError((Object _) {
      // No channel here (the widget's background isolate) or no Play
      // services: forget it, so the next sync tries again.
      if (_lastPublished[path] == json) _lastPublished.remove(path);
    }));
  }

  /// Parses the queue handed over by `takeCommands` (a list of JSON strings
  /// `{"action":"complete","id":"…","at":millis}`); malformed entries are
  /// skipped.
  static List<WearCommand> parseCommands(Object? raw) {
    if (raw is! List) return const [];
    final out = <WearCommand>[];
    for (final entry in raw) {
      try {
        final decoded = entry is String ? jsonDecode(entry) : entry;
        if (decoded is! Map) continue;
        final action = decoded['action'];
        final id = decoded['id'];
        if (action is! String || id is! String || id.trim().isEmpty) continue;
        final at = decoded['at'];
        out.add(WearCommand(
          action: action,
          id: id.trim(),
          at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
        ));
      } catch (_) {}
    }
    return out;
  }

  /// The tasks of [tasks] the `complete` commands in [commands] should
  /// complete: each existing, not deleted and still open task once, in
  /// command order, with the time the command arrived. Already done (the
  /// widget's background path or the phone got there first), unknown or
  /// other actions are ignored, so applying a queue twice is harmless.
  static List<({Task task, DateTime? at})> completionsFor(
      List<Task> tasks, List<WearCommand> commands) {
    final byUid = {for (final t in tasks) t.uid: t};
    final seen = <String>{};
    final out = <({Task task, DateTime? at})>[];
    for (final c in commands) {
      if (c.action != WearCommand.complete || !seen.add(c.id)) continue;
      final task = byUid[c.id];
      if (task == null || task.isDone || task.deletedAt != null) continue;
      out.add((task: task, at: c.at));
    }
    return out;
  }

  /// Takes (and clears) the queued watch commands. Empty off Android or
  /// when the channel isn't there.
  static Future<List<WearCommand>> takeCommands() async {
    if (!_isAndroid) return const [];
    try {
      final raw = await channel.invokeMethod<List<Object?>>('takeCommands');
      return parseCommands(raw);
    } catch (_) {
      return const [];
    }
  }

  /// Registers what to do when the native side says commands are waiting
  /// (the app is running). Null removes it.
  static void setPendingHandler(Future<void> Function()? onPending) {
    if (!_isAndroid) return;
    try {
      channel.setMethodCallHandler(onPending == null
          ? null
          : (call) async {
              if (call.method == 'wearCommandsPending') await onPending();
              return null;
            });
    } catch (_) {}
  }
}
