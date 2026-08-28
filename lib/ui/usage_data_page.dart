import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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
import '../services/digital_wellbeing_service.dart';
import 'subpage_app_bar.dart';

/// Returns an x-axis label for each six-hour boundary in the wellbeing chart.
String wellbeingHourLabel(double value) {
  final hour = value.toInt();
  if (value != hour || hour < 0 || hour > 23 || hour % 6 != 0) return '';
  return '$hour:00';
}

/// Returns a y-axis label (in minutes, or hours once past 60) for the
/// wellbeing chart's screen-time values.
String wellbeingMinuteLabel(double value) {
  final minutes = value.round();
  if (minutes <= 0) return '0';
  if (minutes % 60 == 0) return '${minutes ~/ 60}h';
  return '${minutes}m';
}

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

class _UsageDataPageState extends State<UsageDataPage>
    with WidgetsBindingObserver {
  List<UsageCsvDataset>? _datasets;
  final Set<String> _excluded = <String>{};
  bool _exporting = false;
  bool _usagePermission = false;
  bool _loadingPhone = true;
  String _period = 'Week';
  int _weekOffset = 0;
  DateTimeRange? _customRange;
  List<PhoneUsageSession> _phoneSessions = const [];
  List<UsageEvent> _events = const [];
  WellbeingGoals _goals = const WellbeingGoals();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPhoneUsage();
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
    final events = <UsageEvent>[
      ...UsageDataService.taskEvents(widget.tasks, widget.deletedTasks),
      ...UsageDataService.alarmLogEvents(alarmLogText),
      ...UsageDataService.appOpenEvents(startupHistory),
      ...UsageDataService.timerEvents(timers),
    ];
    final goals = await DigitalWellbeingService.loadGoals();
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
      _events = events;
      _goals = goals;
    });
    await _loadPhoneUsage();
  }

  DateTime get _periodStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case 'Today': return today;
      case 'Month': return DateTime(now.year, now.month, 1);
      case 'Year': return DateTime(now.year, 1, 1);
      case 'Custom': return _customRange?.start ?? today;
      default: return today
          .subtract(Duration(days: today.weekday - 1))
          .add(Duration(days: _weekOffset * 7));
    }
  }

  Future<void> _loadPhoneUsage() async {
    final permitted = await _tryLoad(DigitalWellbeingService.hasPermission, false);
    final sessions = permitted
        ? await _tryLoad(() => DigitalWellbeingService.sessions(
            _period == 'Week' ? _periodStart.subtract(const Duration(days: 7)) : _periodStart,
            _period == 'Week' ? _periodStart.add(const Duration(days: 7)) : (_period == 'Custom' ? (_customRange?.end ?? DateTime.now()) : DateTime.now())), <PhoneUsageSession>[])
        : <PhoneUsageSession>[];
    if (!mounted) return;
    setState(() {
      _usagePermission = permitted;
      _phoneSessions = sessions;
      _loadingPhone = false;
    });
  }

  String _duration(Duration duration) {
    final minutes = duration.inMinutes;
    return minutes >= 60 ? '${minutes ~/ 60}h ${minutes % 60}m' : '${minutes}m';
  }

  Widget _metric(String value, String label, IconData icon, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color), const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ));

  Widget _buildDashboard() {
    final start = _periodStart;
    final end = _period == 'Week' ? start.add(const Duration(days: 7)) : (_period == 'Custom' ? (_customRange?.end ?? DateTime.now()) : DateTime.now());
    final events = _events.where((e) => !e.at.isBefore(start) && !e.at.isAfter(end)).toList();
    final currentSessions = _phoneSessions.where((s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end)).toList();
    final previousStart = start.subtract(end.difference(start));
    final previousSessions = _phoneSessions.where((s) => !s.startedAt.isBefore(previousStart) && s.startedAt.isBefore(start)).toList();
    final total = currentSessions.fold(Duration.zero, (v, s) => v + s.duration);
    final previousTotal = previousSessions.fold(Duration.zero, (v, s) => v + s.duration);
    final completed = events.where((e) => e.source == 'task' && e.type == 'completed').length;
    final created = events.where((e) => e.source == 'task' && e.type == 'created').length;
    final pickups = currentSessions.length;
    final previousPickups = previousSessions.length;
    final byHour = List<int>.filled(24, 0);
    for (final s in currentSessions) { byHour[s.startedAt.hour] += s.duration.inMinutes; }
    final byApp = <String, Duration>{};
    final previousByApp = <String, Duration>{};
    for (final s in currentSessions) { byApp[s.appName] = (byApp[s.appName] ?? Duration.zero) + s.duration; }
    for (final s in previousSessions) { previousByApp[s.appName] = (previousByApp[s.appName] ?? Duration.zero) + s.duration; }
    final apps = byApp.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lateMinutes = currentSessions.where((s) => s.startedAt.hour >= _goals.noPhoneStartHour || s.startedAt.hour < 6)
        .fold(0, (v, s) => v + s.duration.inMinutes);
    final daily = List<int>.filled(7, 0);
    for (final s in currentSessions) { final i = DateTime(s.startedAt.year,s.startedAt.month,s.startedAt.day).difference(start).inDays; if (i >= 0 && i < 7) daily[i] += s.duration.inMinutes; }
    String comparison(int now, int before) => before == 0 ? (now == 0 ? 'No data' : 'First measured period') : '${((now-before) * 100 / before).abs().round()}% ${now <= before ? 'lower · improving' : 'higher'} than previous week';
    return GestureDetector(onHorizontalDragEnd: _period == 'Week' ? (details) { if ((details.primaryVelocity ?? 0) > 150) { setState(() => _weekOffset--); _loadPhoneUsage(); } else if ((details.primaryVelocity ?? 0) < -150 && _weekOffset < 0) { setState(() => _weekOffset++); _loadPhoneUsage(); } } : null,
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Digital wellbeing', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const Text('Your phone and BestTodo, together. Private on this device.'),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<String>(
        segments: const ['Today', 'Week', 'Month', 'Year', 'Custom'].map((p) => ButtonSegment(value: p, label: Text(p))).toList(),
        selected: {_period}, onSelectionChanged: (v) async {
          if (v.first == 'Custom') {
            final now = DateTime.now();
            final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: now, initialDateRange: _customRange);
            if (picked == null || !mounted) return;
            _customRange = DateTimeRange(start: picked.start, end: picked.end.add(const Duration(days: 1)));
          }
          setState(() { _period = v.first; _weekOffset = 0; _loadingPhone = true; }); _loadPhoneUsage();
        },
      )),
      if (_period == 'Week') Row(children: [
        IconButton(tooltip: 'Previous week', onPressed: () { setState(() => _weekOffset--); _loadPhoneUsage(); }, icon: const Icon(Icons.chevron_left)),
        Expanded(child: Text('${UsageDataService.dayKey(start)} → ${UsageDataService.dayKey(end.subtract(const Duration(days: 1)))}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium)),
        IconButton(tooltip: 'Next week', onPressed: _weekOffset < 0 ? () { setState(() => _weekOffset++); _loadPhoneUsage(); } : null, icon: const Icon(Icons.chevron_right)),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        _metric(_duration(total), 'Screen time', Icons.phone_android, Colors.deepPurple), const SizedBox(width: 8),
        _metric('$pickups', 'Sessions', Icons.touch_app, Colors.orange),
      ]), const SizedBox(height: 8),
      Row(children: [
        _metric('$completed', 'Tasks completed', Icons.task_alt, Colors.green), const SizedBox(width: 8),
        _metric(created == 0 ? '—' : '${(completed * 100 / created).round()}%', 'Completion / created', Icons.trending_up, Colors.blue),
      ]),
      if (_period == 'Week') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Screen time: ${comparison(total.inMinutes, previousTotal.inMinutes)} · Sessions: ${comparison(pickups, previousPickups)}. Daily average: ${_duration(Duration(minutes: total.inMinutes ~/ 7))}.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      if (!_usagePermission) Card(margin: const EdgeInsets.only(top: 16), color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(
        leading: const Icon(Icons.insights), title: const Text('See your whole-phone picture'),
        subtitle: const Text('Optionally allow Android Usage Access. BestTodo reads totals locally and never blocks apps.'),
        trailing: FilledButton(onPressed: () async {
          final opened = await DigitalWellbeingService.openPermissionSettings();
          if (!opened && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Couldn\'t open Usage Access settings automatically. '
                  'Open Settings → Apps → Special access → Usage access → BestTodo.'),
              duration: Duration(seconds: 6),
            ));
          }
        }, child: const Text('Allow')),
      )),
      if (_loadingPhone) const LinearProgressIndicator(),
      const SizedBox(height: 20),
      if (_period == 'Week') ...[
        Text('Screen time by day', style: Theme.of(context).textTheme.titleLarge),
        const Text('Vertical axis: minutes · horizontal axis: day of week'),
        SizedBox(height: 170, child: BarChart(BarChartData(
          maxY: daily.reduce((a,b) => a > b ? a : b).clamp(60, 1440).toDouble(),
          gridData: const FlGridData(show: true, drawVerticalLine: false), borderData: FlBorderData(show: true, border: const Border(left: BorderSide(), bottom: BorderSide())),
          titlesData: FlTitlesData(topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), leftTitles: const AxisTitles(axisNameWidget: Text('minutes'), sideTitles: SideTitles(showTitles: true, reservedSize: 36)), bottomTitles: AxisTitles(axisNameWidget: const Text('day'), sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v,_) => Text(const ['M','T','W','T','F','S','S'][v.toInt().clamp(0,6)])))),
          barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: daily[i].toDouble(), width: 17)])),
        ))), const SizedBox(height: 20),
      ],
      Text('When you use your phone', style: Theme.of(context).textTheme.titleLarge),
      const Text('Vertical axis: minutes · horizontal axis: time of day'),
      const SizedBox(height: 8), SizedBox(height: 150, child: BarChart(BarChartData(
        maxY: (byHour.reduce((a, b) => a > b ? a : b).clamp(10, 600)).toDouble(),
        barTouchData: BarTouchData(enabled: true), gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text(wellbeingMinuteLabel(v), style: const TextStyle(fontSize: 10)))),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(wellbeingHourLabel(v), style: const TextStyle(fontSize: 10)))),
        ),
        barGroups: List.generate(24, (h) => BarChartGroupData(x: h, barRods: [BarChartRodData(toY: byHour[h].toDouble(), width: 7, color: h >= 22 || h < 6 ? Colors.orange : Colors.deepPurple, borderRadius: BorderRadius.circular(3))])),
      ))),
      const SizedBox(height: 20), Text('Most used', style: Theme.of(context).textTheme.titleLarge),
      if (apps.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Usage appears here after Android access is enabled.')),
      ...apps.take(8).map((a) { final old = previousByApp[a.key] ?? Duration.zero; return ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(child: Text(a.key.characters.first.toUpperCase())), title: Text(a.key), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: total.inSeconds == 0 ? 0 : a.value.inSeconds / total.inSeconds), if (_period == 'Week') Text(comparison(a.value.inMinutes, old.inMinutes))]), trailing: Text(_duration(a.value))); }),
      const SizedBox(height: 12), Text('Supportive insights', style: Theme.of(context).textTheme.titleLarge),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.bedtime_outlined, color: Colors.indigo), title: Text(lateMinutes > 0 ? '${_duration(Duration(minutes: lateMinutes))} after your wind-down time' : 'Your late-night use looks calm'), subtitle: Text(lateMinutes > 30 ? 'Try placing your most-used app off the home screen after ${_goals.noPhoneStartHour}:00.' : 'No action needed — keep the routine that works for you.')),
        ListTile(leading: const Icon(Icons.bolt, color: Colors.amber), title: Text(pickups > 20 ? '$pickups short opportunities to refocus' : 'Few distracting checks'), subtitle: const Text('A realistic challenge: aim for 20% fewer sessions next period.')),
      ])),
      Card(child: SwitchListTile(value: _goals.enabled, onChanged: (v) async { final next = _goals.copyWith(enabled: v); await DigitalWellbeingService.saveGoals(next); setState(() => _goals = next); }, title: const Text('Gentle goals & challenges'), subtitle: Text('Daily target ${_goals.dailyMinutes ~/ 60}h ${_goals.dailyMinutes % 60}m · ${_goals.pickupLimit} pickups · wind down ${_goals.noPhoneStartHour}:00'))),
      const SizedBox(height: 12), ExpansionTile(title: const Text('Export & inspect raw usage data'), subtitle: const Text('Choose detailed CSV datasets'), children: datasetsTiles()),
    ])));
  }

  List<Widget> datasetsTiles() => [
    if (_datasets != null) _buildSummaryCard(_datasets!),
    ...?_datasets?.map(_buildDatasetTile),
    const SizedBox(height: 80),
  ];

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
      appBar: buildSubpageAppBar(context, title: 'Usage & Wellbeing'),
      body: datasets == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [_buildDashboard()],
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
