import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../services/alarm_notification_service.dart';
import '../services/alarm_service.dart';
import '../services/log_service.dart';
import 'alarm_edit_page.dart';
import 'subpage_app_bar.dart';

/// Lists every alarm with a quick on/off toggle and access to the editor.
class AlarmsPage extends StatefulWidget {
  /// Optional alarm uid to open directly in the editor on first build, used
  /// when arriving from a home-screen widget "edit" tap.
  final String? editUid;

  const AlarmsPage({Key? key, this.editUid}) : super(key: key);

  @override
  State<AlarmsPage> createState() => _AlarmsPageState();
}

class _AlarmsPageState extends State<AlarmsPage> {
  final AlarmService _service = AlarmService.instance;

  @override
  void initState() {
    super.initState();
    // Make sure we can post and schedule exact alarms before the user relies
    // on them firing.
    AlarmNotificationService.ensurePermissions();
    _service.load().then((_) {
      if (!mounted) return;
      final uid = widget.editUid;
      if (uid != null) {
        final match = _service.list.where((a) => a.uid == uid);
        if (match.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openEditor(match.first);
          });
        }
      }
    });
  }

  Future<void> _openEditor(Alarm? alarm) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlarmEditPage(alarm: alarm)),
    );
    if (result is Alarm) {
      await _service.upsert(result);
      LogService.add('AlarmsPage', 'Saved alarm "${result.name}"');
    } else if (result == 'delete' && alarm != null) {
      await _service.delete(alarm.uid);
      LogService.add('AlarmsPage', 'Deleted alarm "${alarm.name}"');
    }
  }

  Future<void> _deleteWithUndo(Alarm alarm) async {
    final messenger = ScaffoldMessenger.of(context);
    await _service.delete(alarm.uid);
    LogService.add('AlarmsPage', 'Deleted alarm "${alarm.name}"');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${alarm.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _service.upsert(alarm),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Alarms'),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(null),
        tooltip: 'Add alarm',
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder<List<Alarm>>(
        valueListenable: _service.alarms,
        builder: (context, alarms, _) {
          if (alarms.isEmpty) {
            return const _EmptyState();
          }
          final sorted = [...alarms]..sort((a, b) {
              final am = a.hour * 60 + a.minute;
              final bm = b.hour * 60 + b.minute;
              return am.compareTo(bm);
            });
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final alarm = sorted[index];
              return _AlarmTile(
                alarm: alarm,
                onTap: () => _openEditor(alarm),
                onToggle: (v) => _service.setEnabled(alarm.uid, v),
                onDelete: () => _deleteWithUndo(alarm),
              );
            },
          );
        },
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  final Alarm alarm;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _AlarmTile({
    required this.alarm,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = !alarm.enabled;
    return Dismissible(
      key: ValueKey(alarm.uid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(alarm.color)
                        .withOpacity(faded ? 0.35 : 1.0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.timeLabel,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: faded
                              ? theme.disabledColor
                              : theme.textTheme.headlineMedium?.color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alarm.name.isEmpty ? 'Alarm' : alarm.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: faded ? theme.disabledColor : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            alarm.isRepeating
                                ? Icons.repeat
                                : Icons.event_available,
                            size: 14,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              alarm.scheduleLabel,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                          ),
                          if (alarm.vibrate) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.vibration,
                                size: 14, color: theme.hintColor),
                          ],
                          if (alarm.snoozeEnabled) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.snooze,
                                size: 14, color: theme.hintColor),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alarm.enabled,
                  onChanged: onToggle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_off, size: 64, color: theme.hintColor),
          const SizedBox(height: 12),
          Text('No alarms yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Tap + to add your first alarm',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
