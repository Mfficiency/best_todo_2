import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/alarm.dart';
import '../models/countdown_timer.dart';
import '../models/daily_task_stats.dart';
import '../models/sms_report_log_entry.dart';
import '../models/task.dart';
import '../config.dart';
import '../services/alarm_log_service.dart';
import '../services/alarm_storage_service.dart';
import '../services/sms_report_log_service.dart';
import '../services/startup_time_service.dart';
import '../services/storage_service.dart';
import '../services/usage_data_service.dart';
import 'subpage_app_bar.dart';

/// Tools → Usage Data: exports everything the app has ever recorded as
/// detailed CSV files — a Digital-Wellbeing-style data dump covering the full
/// history available on this device.
class UsageDataPage extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> deletedTasks;
  final Map<String, DailyTaskStats> dailyStatsByDay;

  const UsageDataPage({
    Key? key,
    required this.tasks,
    required this.deletedTasks,
    required this.dailyStatsByDay,
  }) : super(key: key);

  @override
  State<UsageDataPage> createState() => _UsageDataPageState();
}

class _UsageDataPageState extends State<UsageDataPage> {
  List<UsageCsvDataset>? _datasets;
  final Set<String> _excluded = <String>{};
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T> _tryLoad<T>(Future<T> Function() loader, T fallback) async {
    try {
      return await loader();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _load() async {
    final alarmLogText = await _tryLoad(AlarmLog.read, '');
    final alarms =
        await _tryLoad(AlarmStorageService().loadAlarms, <Alarm>[]);
    final smsEntries =
        await _tryLoad(SmsReportLogService.load, <SmsReportLogEntry>[]);
    final startupHistory = await _tryLoad(
        StartupTimeService.getStartupHistory, <StartupRecord>[]);
    final startupTimes =
        await _tryLoad(StartupTimeService.getStartupTimes, <int>[]);
    final timers = await _tryLoad(
        () async => await StorageService().loadCountdownTimers() ??
            <CountdownTimerItem>[],
        <CountdownTimerItem>[]);
    if (!mounted) return;
    setState(() {
      _datasets = UsageDataService.buildAllDatasets(
        tasks: widget.tasks,
        deletedTasks: widget.deletedTasks,
        dailyStatsByDay: widget.dailyStatsByDay,
        alarmLogText: alarmLogText,
        alarms: alarms,
        smsEntries: smsEntries,
        startupHistory: startupHistory,
        startupTimes: startupTimes,
        countdownTimers: timers,
      );
    });
  }

  List<UsageCsvDataset> get _selected => (_datasets ?? const [])
      .where((d) => !_excluded.contains(d.id))
      .toList();

  String _formatDay(DateTime? d) =>
      d == null ? '—' : UsageDataService.dayKey(d);

  String _timestampForFilename() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<void> _export() async {
    final datasets = _selected;
    if (datasets.isEmpty || _exporting) return;
    final downloadsDir = await getDownloadsDirectory();
    final directory =
        await getDirectoryPath(initialDirectory: downloadsDir?.path);
    if (directory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final sep = Platform.pathSeparator;
      final folder =
          '$directory${directory.endsWith(sep) ? '' : sep}besttodo_usage_${_timestampForFilename()}';
      final withManifest = [
        ...datasets,
        UsageDataService.exportInfoDataset(
          datasets,
          appVersion: Config.versionWithBuild,
          exportedAt: DateTime.now(),
        ),
      ];
      final files = await UsageDataService.writeDatasets(withManifest, folder);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exported ${files.length} CSV files to $folder'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildSummaryCard(List<UsageCsvDataset> datasets) {
    DateTime? earliest;
    var totalRecords = 0;
    for (final d in datasets) {
      totalRecords += d.recordCount;
      if (d.earliest != null &&
          (earliest == null || d.earliest!.isBefore(earliest))) {
        earliest = d.earliest;
      }
    }
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your complete usage picture',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Exports everything this app has recorded on this device as '
              'detailed CSV files — every task lifecycle event, daily and '
              'hourly activity summaries, alarm history, SMS reports, app '
              'opens and timers. Like Digital Wellbeing, but for your tasks '
              'and with full detail.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Data goes back to: ${_formatDay(earliest)}\n'
              'Total records: $totalRecords',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatasetTile(UsageCsvDataset dataset) {
    final range = dataset.earliest == null
        ? 'no date range'
        : '${_formatDay(dataset.earliest)} → ${_formatDay(dataset.latest ?? dataset.earliest)}';
    return CheckboxListTile(
      value: !_excluded.contains(dataset.id),
      onChanged: (checked) {
        setState(() {
          if (checked ?? false) {
            _excluded.remove(dataset.id);
          } else {
            _excluded.add(dataset.id);
          }
        });
      },
      title: Text(dataset.title),
      subtitle: Text(
        '${dataset.description}\n'
        '${dataset.recordCount} records · $range · ${dataset.fileName}',
      ),
      isThreeLine: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  @override
  Widget build(BuildContext context) {
    final datasets = _datasets;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Usage Data'),
      body: datasets == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSummaryCard(datasets),
                ...datasets.map(_buildDatasetTile),
                const SizedBox(height: 80),
              ],
            ),
      floatingActionButton: datasets == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _selected.isEmpty || _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_exporting
                  ? 'Exporting…'
                  : 'Export ${_selected.length} CSV files'),
            ),
    );
  }
}
