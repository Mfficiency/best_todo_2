import 'package:flutter/material.dart';

import '../models/f1_reminder.dart';
import '../services/f1_reminder_service.dart';
import '../services/sms_report_scheduler.dart';
import 'subpage_app_bar.dart';

/// Tools → F1 Reminder: texts a phone number 4 hours before every upcoming
/// race (SPEC.md §10.6l).
class F1ReminderPage extends StatefulWidget {
  /// Fixed clock for tests; defaults to [DateTime.now].
  final DateTime? now;

  const F1ReminderPage({super.key, this.now});

  @override
  State<F1ReminderPage> createState() => _F1ReminderPageState();
}

class _F1ReminderPageState extends State<F1ReminderPage> {
  F1ReminderConfig? _config;
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sendingWelcome = false;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await F1ReminderService.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _phoneController.text = config.phoneNumber;
      _messageController.text = config.template;
    });
  }

  /// Copies the text fields into the config, persists it and re-arms the
  /// alarm for the next race.
  Future<void> _save({bool announce = false}) async {
    final config = _config;
    if (config == null) return;
    config.phoneNumber = _phoneController.text.trim();
    final template = _messageController.text;
    config.template = template.trim().isEmpty ? kDefaultF1Template : template;
    await F1ReminderService.save(config);
    await F1ReminderService.applyFromConfig(config);
    if (!mounted) return;
    setState(() {});
    if (announce) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('F1 reminder saved')));
    }
  }

  Future<void> _toggle(bool value) async {
    final config = _config;
    if (config == null) return;
    setState(() => config.enabled = value);
    // Grant SMS, exact-alarm and battery exemptions here in the foreground:
    // the background isolate can't show permission dialogs.
    if (value) await SmsReportScheduler.ensureBackgroundPermissions();
    await _save();
  }

  Future<void> _sendWelcome() async {
    final config = _config;
    if (config == null) return;
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a phone number first')));
      return;
    }
    setState(() => _sendingWelcome = true);
    await _save();
    final error = await F1ReminderService.sendWelcome(config, now: _now);
    if (!mounted) return;
    setState(() => _sendingWelcome = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(error == null
            ? 'Welcome message sent'
            : 'Welcome message failed: $error'),
      ));
  }

  Future<void> _resetMessage() async {
    setState(() => _messageController.text = kDefaultF1Template);
  }

  String _relative(DateTime at) {
    final d = at.difference(_now);
    if (d.isNegative) return 'as soon as possible';
    if (d.inDays >= 1) {
      final h = d.inHours % 24;
      return 'in ${d.inDays} day${d.inDays == 1 ? '' : 's'}'
          '${h > 0 ? ' ${h}h' : ''}';
    }
    if (d.inHours >= 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'in ${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'F1 Reminder',
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Save',
            onPressed: _config == null ? null : () => _save(announce: true),
          ),
        ],
      ),
      body: _config == null
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, _config!),
    );
  }

  Widget _buildBody(BuildContext context, F1ReminderConfig config) {
    final theme = Theme.of(context);
    final pending = F1ReminderService.nextPending(config, now: _now);
    return ListView(
      key: const Key('f1-reminder-list'),
      padding: const EdgeInsets.all(16),
      children: [
        _buildNextCard(theme, config, pending),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send race reminders'),
          subtitle: const Text('A text 4 hours before every race'),
          value: config.enabled,
          onChanged: _toggle,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('f1-phone'),
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+31 6 12345678',
            prefixIcon: Icon(Icons.phone),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('f1-message'),
          controller: _messageController,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: 'Message',
            helperText: 'Fills in {race}, {time}, {date} and {countdown}',
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset message',
              onPressed: _resetMessage,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (pending != null) ...[
          const SizedBox(height: 12),
          Text('Preview', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              F1ReminderService.render(
                _messageController.text.trim().isEmpty
                    ? kDefaultF1Template
                    : _messageController.text,
                pending.race,
              ),
              key: const Key('f1-preview'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _sendingWelcome ? null : _sendWelcome,
          icon: _sendingWelcome
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.waving_hand),
          label: const Text('Send welcome message'),
        ),
        const SizedBox(height: 24),
        Text('Races', style: theme.textTheme.titleMedium),
        Text('Tap a race to change its date or start time',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        for (final race in config.races) _buildRaceTile(theme, config, race, pending),
        if (config.history.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Recent texts', style: theme.textTheme.titleMedium),
          for (final record in config.history.reversed.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                record.success ? Icons.check_circle : Icons.error,
                color: record.success
                    ? Colors.green
                    : theme.colorScheme.error,
              ),
              title: Text(record.message,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                F1ReminderService.formatDateTime(record.at),
                if (record.error != null) record.error!,
              ].join(' • ')),
            ),
        ],
      ],
    );
  }

  Widget _buildNextCard(
      ThemeData theme, F1ReminderConfig config, F1PendingReminder? pending) {
    final String headline;
    final String? detail;
    if (!config.enabled) {
      headline = 'Reminders are off';
      detail = 'Switch them on below to get a text before every race.';
    } else if (_phoneController.text.trim().isEmpty) {
      headline = 'Add a phone number';
      detail = 'Reminders are on, but there\'s nobody to text yet.';
    } else if (pending == null) {
      headline = 'No more races this season';
      detail = null;
    } else {
      headline = 'Next text: ${F1ReminderService.formatDateTime(pending.sendAt)}';
      detail = '${pending.race.name} • ${_relative(pending.sendAt)}';
    }
    return Card(
      key: const Key('f1-next-card'),
      color: config.enabled
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.sports_score,
                size: 36,
                color: config.enabled
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline, style: theme.textTheme.titleMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(detail, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tap on a race: pick a new date, then a new start time. Saving re-arms
  /// the alarm; an already-sent reminder goes out again for the new time.
  Future<void> _editRaceTime(F1ReminderConfig config, F1Race race) async {
    final date = await showDatePicker(
      context: context,
      initialDate: race.start,
      firstDate: DateTime(race.start.year - 1),
      lastDate: DateTime(race.start.year + 2),
      helpText: '${race.name} — race day',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(race.start),
      helpText: '${race.name} — lights out',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    final start =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (start == race.start) return;
    await _setRaceStart(config, race, start);
  }

  Future<void> _setRaceStart(
      F1ReminderConfig config, F1Race race, DateTime start) async {
    setState(() => config.setStart(race, start));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            '${race.name}: ${F1ReminderService.formatDateTime(start)}'),
      ));
  }

  Widget _buildRaceTile(ThemeData theme, F1ReminderConfig config, F1Race race,
      F1PendingReminder? pending) {
    final handled = config.handledRaces.contains(race.key);
    final isNext = pending?.race.key == race.key;
    final over = !race.start.isAfter(_now);
    final edited = config.startOverrides.containsKey(race.key);
    final String status;
    final IconData icon;
    Color? color;
    if (handled) {
      status = 'Text sent';
      icon = Icons.mark_chat_read;
      color = Colors.green;
    } else if (over) {
      status = 'Finished';
      icon = Icons.flag;
      color = theme.disabledColor;
    } else {
      final at =
          F1ReminderService.formatTime(F1ReminderService.sendTimeFor(race));
      status = isNext ? 'Next text at $at' : 'Text at $at';
      icon = isNext ? Icons.schedule_send : Icons.sports_motorsports;
      if (isNext) color = theme.colorScheme.primary;
    }
    final original = kF1Races.firstWhere((r) => r.key == race.key,
        orElse: () => race);
    return ListTile(
      key: Key('f1-race-${race.key}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(race.name,
          style: over && !handled
              ? TextStyle(color: theme.disabledColor)
              : (isNext ? const TextStyle(fontWeight: FontWeight.bold) : null)),
      subtitle: Text(
        '${F1ReminderService.formatDateTime(race.start)}'
        '${edited ? ' (edited)' : ''}\n$status',
      ),
      isThreeLine: true,
      onTap: () => _editRaceTime(config, race),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (edited)
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Reset time',
              onPressed: () => _setRaceStart(config, race, original.start),
            ),
          IconButton(
            icon: const Icon(Icons.edit_calendar),
            tooltip: 'Edit time',
            onPressed: () => _editRaceTime(config, race),
          ),
        ],
      ),
    );
  }
}
