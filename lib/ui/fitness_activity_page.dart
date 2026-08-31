import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/health_metrics.dart';
import '../services/fitness_activity_service.dart';
import '../services/health_tracking_service.dart';
import '../utils/date_time_format.dart';
import 'subpage_app_bar.dart';

/// Trims a whole-number value down to no decimals, e.g. 72.0 -> "72" but
/// 71.5 -> "71.5". Shared by the weight and personal-best displays/dialogs.
String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

class FitnessActivityPage extends StatefulWidget {
  const FitnessActivityPage({super.key});

  @override
  State<FitnessActivityPage> createState() => _FitnessActivityPageState();
}

class _FitnessActivityPageState extends State<FitnessActivityPage>
    with WidgetsBindingObserver {
  late DateTime _weekStart;
  List<FitnessDay>? _days;
  List<FitnessDay>? _previous;
  bool _denied = false;
  bool _notInstalled = false;

  List<AutoPersonalBest> _autoBests = [];
  bool _autoBestsLoading = false;
  bool _autoBestsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _weekStart = _monday(DateTime.now());
    _load();
    _loadAutoBests();
    HealthTrackingService.instance.loadWeightEntries();
    HealthTrackingService.instance.loadPersonalBests();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user comes back from the Play Store (installing
    // Health Connect) or the OS permissions screen, same idea as the Usage
    // & Wellbeing page.
    if (state == AppLifecycleState.resumed && (_notInstalled || _denied)) {
      _load();
    }
  }

  DateTime _monday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  Future<void> _load() async {
    setState(() { _days = null; _denied = false; _notInstalled = false; });
    try {
      final available = await FitnessActivityService.isAvailable();
      if (!available) {
        if (!mounted) return;
        setState(() {
          _notInstalled = true;
          _days = FitnessActivityService.summarize(_weekStart, const []);
          _previous = FitnessActivityService.summarize(
              _weekStart.subtract(const Duration(days: 7)), const []);
        });
        return;
      }
      final from = _weekStart.subtract(const Duration(days: 7));
      final samples = await FitnessActivityService.read(
          from, _weekStart.add(const Duration(days: 7)));
      if (!mounted) return;
      setState(() {
        _denied = samples == null;
        _previous = FitnessActivityService.summarize(from, samples ?? const []);
        _days = FitnessActivityService.summarize(_weekStart, samples ?? const []);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _denied = true;
        _days = FitnessActivityService.summarize(_weekStart, const []);
        _previous = FitnessActivityService.summarize(_weekStart.subtract(const Duration(days: 7)), const []);
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read Health Connect data: $e')));
    }
  }

  /// Fetches roughly a year of Health Connect history and derives personal
  /// bests from it (see [FitnessActivityService.computeAutoBests]), so the
  /// "Personal bests" section fills itself in instead of requiring manual
  /// entry. Runs once per page lifetime unless [force]d, e.g. by pull-to-refresh.
  Future<void> _loadAutoBests({bool force = false}) async {
    if (_autoBestsLoaded && !force) return;
    if (!mounted) return;
    setState(() => _autoBestsLoading = true);
    try {
      final available = await FitnessActivityService.isAvailable();
      if (!available) {
        if (!mounted) return;
        setState(() {
          _autoBests = [];
          _autoBestsLoading = false;
          _autoBestsLoaded = true;
        });
        return;
      }
      final to = DateTime.now();
      final from = to.subtract(const Duration(days: 365));
      final samples = await FitnessActivityService.read(from, to);
      if (!mounted) return;
      setState(() {
        _autoBests = FitnessActivityService.computeAutoBests(samples ?? const []);
        _autoBestsLoading = false;
        _autoBestsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _autoBestsLoading = false;
        _autoBestsLoaded = true;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadAutoBests(force: true)]);
  }

  Future<void> _connect() async {
    if (_notInstalled) {
      await FitnessActivityService.promptInstall();
      return;
    }
    await _load();
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekStart,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Choose any week in your health history',
    );
    if (picked == null) return;
    setState(() => _weekStart = _monday(picked));
    await _load();
  }

  Future<void> _openSources() async {
    try {
      final opened = await FitnessActivityService.openDataSources();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Health data settings are not available on this device.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open health data settings.')));
      }
    }
  }

  String _range(DateTime start) {
    final end = start.add(const Duration(days: 6));
    return '${start.day}/${start.month} – ${end.day}/${end.month}/${end.year}';
  }

  double _sum(List<FitnessDay> days, double Function(FitnessDay) value) =>
      days.fold(0, (sum, day) => sum + value(day));

  String _change(double current, double previous, {bool lowerIsBetter = false}) {
    if (previous == 0) return current == 0 ? 'No data yet' : 'First recorded week';
    final percent = ((current - previous) / previous * 100).round();
    final improving = lowerIsBetter ? percent < 0 : percent > 0;
    return '${percent >= 0 ? '+' : ''}$percent% vs previous week${percent == 0 ? '' : improving ? ' · improving' : ' · down'}';
  }

  Future<void> _editWeightEntry([WeightEntry? entry]) async {
    final result = await showDialog<_WeightEntryResult>(
      context: context,
      builder: (context) => _WeightEntryDialog(entry: entry),
    );
    if (result == null) return;
    final saved = entry == null
        ? WeightEntry(
            date: result.date, weightKg: result.weightKg, note: result.note)
        : entry.copyWith(
            date: result.date, weightKg: result.weightKg, note: result.note);
    await HealthTrackingService.instance.saveWeightEntry(saved);
  }

  void _deleteWeightEntry(WeightEntry entry) {
    HealthTrackingService.instance.deleteWeightEntry(entry.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Weight entry deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => HealthTrackingService.instance.saveWeightEntry(entry),
        ),
      ));
  }

  Future<void> _editPersonalBest([PersonalBest? best]) async {
    final result = await showDialog<_PersonalBestResult>(
      context: context,
      builder: (context) => _PersonalBestDialog(best: best),
    );
    if (result == null) return;
    final saved = best == null
        ? PersonalBest(
            name: result.name,
            value: result.value,
            unit: result.unit,
            date: result.date,
            note: result.note)
        : best.copyWith(
            name: result.name,
            value: result.value,
            unit: result.unit,
            date: result.date,
            note: result.note);
    await HealthTrackingService.instance.savePersonalBest(saved);
  }

  void _deletePersonalBest(PersonalBest best) {
    HealthTrackingService.instance.deletePersonalBest(best.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Personal best deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => HealthTrackingService.instance.savePersonalBest(best),
        ),
      ));
  }

  Widget _buildWeightSection() {
    return ValueListenableBuilder<List<WeightEntry>>(
      valueListenable: HealthTrackingService.instance.weightEntries,
      builder: (context, entries, _) {
        final latest = entries.isEmpty ? null : entries.first;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text('Weight',
                          style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    tooltip: 'Log weight',
                    onPressed: () => _editWeightEntry(),
                    icon: const Icon(Icons.add),
                  ),
                ]),
                if (latest == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No weight logged yet. Add your first entry.'),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_formatNumber(latest.weightKg)} kg',
                        style: Theme.of(context).textTheme.headlineSmall),
                    subtitle: Text('Logged ${formatTimerDate(latest.date)}'
                        '${latest.note.isNotEmpty ? ' · ${latest.note}' : ''}'),
                    onTap: () => _editWeightEntry(latest),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteWeightEntry(latest),
                    ),
                  ),
                if (entries.length > 1) ...[
                  const Divider(height: 1),
                  for (final entry in entries.skip(1).take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${_formatNumber(entry.weightKg)} kg'),
                      subtitle: Text('${formatTimerDate(entry.date)}'
                          '${entry.note.isNotEmpty ? ' · ${entry.note}' : ''}'),
                      onTap: () => _editWeightEntry(entry),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteWeightEntry(entry),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static const Map<AutoBestMetric, (IconData, Color)> _autoBestStyle = {
    AutoBestMetric.steps: (Icons.directions_walk, Colors.blue),
    AutoBestMetric.distance: (Icons.route, Colors.orange),
    AutoBestMetric.calories: (Icons.local_fire_department, Colors.deepOrange),
    AutoBestMetric.workout: (Icons.fitness_center, Colors.teal),
    AutoBestMetric.sleep: (Icons.bedtime, Colors.indigo),
    AutoBestMetric.heartRate: (Icons.favorite, Colors.pink),
    AutoBestMetric.restingHeartRate: (Icons.favorite_border, Colors.purple),
  };

  Widget _iconBadge(IconData icon, Color color, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: size * 0.5),
      );

  Widget _autoBestTile(AutoPersonalBest best) {
    final (icon, color) = _autoBestStyle[best.metric]!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _iconBadge(icon, color),
      title: Text(best.label),
      subtitle: Text(formatTimerDate(best.date)),
      trailing: Text(
        '${_formatNumber(best.value)} ${best.unit}',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildAutoBestsSection() {
    if (_autoBestsLoading && _autoBests.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Scanning your history for personal bests…'),
          ]),
        ),
      );
    }
    if (_autoBests.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text('Auto-detected records',
                      style: Theme.of(context).textTheme.titleMedium)),
              Tooltip(
                message: 'Refresh from Health Connect history',
                child: IconButton(
                  onPressed: () => _loadAutoBests(force: true),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ]),
            const Text('Calculated automatically from your last 12 months of Health Connect data.'),
            const SizedBox(height: 4),
            for (final best in _autoBests)
              _autoBestTile(best),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalBestsSection() {
    return ValueListenableBuilder<List<PersonalBest>>(
      valueListenable: HealthTrackingService.instance.personalBests,
      builder: (context, bests, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text('Your personal bests',
                          style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                    tooltip: 'Add personal best',
                    onPressed: () => _editPersonalBest(),
                    icon: const Icon(Icons.add),
                  ),
                ]),
                const Text('Manually logged — e.g. a gym lift or race time.'),
                if (bests.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No personal bests recorded yet.'),
                  )
                else
                  for (final best in bests)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _iconBadge(Icons.emoji_events, Colors.amber),
                      title: Text(best.name),
                      subtitle: Text(
                          '${_formatNumber(best.value)} ${best.unit} · ${formatTimerDate(best.date)}'
                          '${best.note.isNotEmpty ? ' · ${best.note}' : ''}'),
                      onTap: () => _editPersonalBest(best),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deletePersonalBest(best),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metric(String title, String value, String comparison, IconData icon, Color color) =>
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            _iconBadge(icon, color, size: 34),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            Text(comparison, style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
      );

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final previous = _previous ?? [];
    final steps = days == null ? 0.0 : _sum(days, (d) => d.steps.toDouble());
    final oldSteps = _sum(previous, (d) => d.steps.toDouble());
    final distance = days == null ? 0.0 : _sum(days, (d) => d.distanceKm);
    final calories = days == null ? 0.0 : _sum(days, (d) => d.activeCalories);
    final workouts = days == null ? 0.0 : _sum(days, (d) => d.workoutMinutes.toDouble());
    final sleepDays = days?.where((d) => d.sleepHours > 0).toList() ?? [];
    final sleep = sleepDays.isEmpty ? 0.0 : _sum(sleepDays, (d) => d.sleepHours) / sleepDays.length;
    final oldSleepDays = previous.where((d) => d.sleepHours > 0).toList();
    final oldSleep = oldSleepDays.isEmpty ? 0.0 : _sum(oldSleepDays, (d) => d.sleepHours) / oldSleepDays.length;
    final maxSteps = days == null || days.isEmpty ? 10000.0 : days.map((d) => d.steps).reduce((a,b) => a > b ? a : b).clamp(10000, 100000).toDouble();
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Fitness Activity'),
      body: days == null ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          // Samsung Health-style hero card: rounded, tinted, big total number
          // with a round accent icon, the week picker, and the bar chart all
          // bundled into one surface instead of separate flat rows.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.secondaryContainer,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(tooltip: 'Previous week', onPressed: () { _weekStart = _weekStart.subtract(const Duration(days: 7)); _load(); }, icon: const Icon(Icons.chevron_left)),
                Expanded(child: InkWell(
                  onTap: _pickWeek,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [
                    const Text('WEEK', style: TextStyle(fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                    Text(_range(_weekStart), style: Theme.of(context).textTheme.titleSmall),
                  ])),
                )),
                IconButton(tooltip: 'Next week', onPressed: _weekStart.isBefore(_monday(DateTime.now())) ? () { _weekStart = _weekStart.add(const Duration(days: 7)); _load(); } : null, icon: const Icon(Icons.chevron_right)),
                _iconBadge(Icons.directions_run, Theme.of(context).colorScheme.primary, size: 44),
              ]),
              const SizedBox(height: 4),
              Text(steps.round().toString(),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
              Text('steps this week', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                '${distance.toStringAsFixed(1)} km  ·  ${calories.round()} kcal  ·  ${workouts.round()} min active',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(height: 190, child: BarChart(BarChartData(
                minY: 0, maxY: maxSteps, gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v == 0 ? '0' : '${(v/1000).round()}k', style: const TextStyle(fontSize: 10)))),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(const ['M','T','W','T','F','S','S'][v.toInt().clamp(0,6)])))),
                barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: days[i].steps.toDouble(),
                    width: 18,
                    borderRadius: BorderRadius.circular(6),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ])),
              ))),
              const Text('steps · day of week', style: TextStyle(fontSize: 11)),
              const SizedBox(height: 4),
            ]),
          ),
          const SizedBox(height: 12),
          Card(child: ListTile(
            leading: const Icon(Icons.watch_outlined),
            title: const Text('Smart watch & health data sources'),
            subtitle: const Text('Open Health Connect to allow Samsung Health to share Galaxy Watch data and manage connected sources.'),
            trailing: const Icon(Icons.open_in_new),
            onTap: _openSources,
          )),
          if (_notInstalled) Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(
            leading: const Icon(Icons.health_and_safety), title: const Text('Install Health Connect'),
            subtitle: const Text('Steps, distance, calories, workouts, heart rate, sleep and weight come from the Health Connect app, which isn\'t installed on this device yet.'),
            trailing: FilledButton(onPressed: _connect, child: const Text('Install')),
          )) else if (_denied) Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(
            leading: const Icon(Icons.health_and_safety), title: const Text('Connect your health data'),
            subtitle: const Text('Grant read-only Health Connect access to show steps, distance, calories, workouts, heart rate, sleep and weight. Data stays on your device.'),
            trailing: FilledButton(onPressed: _connect, child: const Text('Connect')),
          )),
          const SizedBox(height: 4),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.15, mainAxisSpacing: 8, crossAxisSpacing: 8, children: [
            _metric('Steps', steps.round().toString(), _change(steps, oldSteps), Icons.directions_walk, Colors.blue),
            _metric('Daily average', _denied || _notInstalled ? '—' : '${(steps / 7).round()}', 'Across all 7 calendar days', Icons.calendar_today, Colors.purple),
            _metric('Distance', '${distance.toStringAsFixed(1)} km', 'Recorded walking + running distance', Icons.route, Colors.orange),
            _metric('Active energy', '${calories.round()} kcal', 'Movement energy, not total burn', Icons.local_fire_department, Colors.deepOrange),
            _metric('Workouts', '${workouts.round()} min', _change(workouts, _sum(previous, (d) => d.workoutMinutes.toDouble())), Icons.fitness_center, Colors.teal),
            _metric('Sleep average', sleep == 0 ? '—' : '${sleep.toStringAsFixed(1)} h', _change(sleep, oldSleep), Icons.bedtime, Colors.indigo),
          ]),
          const SizedBox(height: 16), Text('What the data says', style: Theme.of(context).textTheme.titleLarge),
          Card(child: Column(children: [
            ListTile(leading: Icon(steps >= oldSteps ? Icons.trending_up : Icons.trending_down), title: Text(_change(steps, oldSteps)), subtitle: Text(steps == 0 ? 'No step records were available for this week.' : 'Your strongest day was ${const ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'][days.indexWhere((d) => d.steps == days.map((x) => x.steps).reduce((a,b) => a > b ? a : b))]} with ${days.map((d) => d.steps).reduce((a,b) => a > b ? a : b)} steps.')),
            ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(steps / 7 >= 7500 ? 'Activity is consistently strong' : 'A small daily walk would move the weekly total'), subtitle: Text(steps / 7 >= 7500 ? 'Keep protecting the routine behind your ${(steps/7).round()}-step daily average.' : 'Adding 1,000 steps a day would add 7,000 steps to this week.')),
          ])),
          if (days.any((d) => d.averageHeartRate != null || d.restingHeartRate != null || d.weightKg != null)) ...[
            Text('Latest body measurements', style: Theme.of(context).textTheme.titleLarge),
            ...days.reversed.where((d) => d.averageHeartRate != null || d.restingHeartRate != null || d.weightKg != null).take(1).map((d) => ListTile(
              title: Text([if (d.averageHeartRate != null) 'Avg heart ${d.averageHeartRate!.round()} bpm', if (d.restingHeartRate != null) 'resting ${d.restingHeartRate!.round()} bpm', if (d.weightKg != null) 'weight ${d.weightKg!.toStringAsFixed(1)} kg'].join(' · ')),
              subtitle: const Text('Measurements are displayed, not medically interpreted.'),
            )),
          ],
          const SizedBox(height: 16),
          Text('Weight & personal bests', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildWeightSection(),
          const SizedBox(height: 12),
          _buildAutoBestsSection(),
          const SizedBox(height: 12),
          _buildPersonalBestsSection(),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

class _WeightEntryResult {
  final DateTime date;
  final double weightKg;
  final String note;

  const _WeightEntryResult(this.date, this.weightKg, this.note);
}

/// Add/edit dialog owning its text controllers, so the dialog's exit
/// animation never touches a disposed one (see food_diary's rule).
class _WeightEntryDialog extends StatefulWidget {
  final WeightEntry? entry;

  const _WeightEntryDialog({this.entry});

  @override
  State<_WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends State<_WeightEntryDialog> {
  late final TextEditingController _weightController;
  late final TextEditingController _noteController;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
        text: widget.entry == null ? '' : _formatNumber(widget.entry!.weightKg));
    _noteController = TextEditingController(text: widget.entry?.note ?? '');
    _date = widget.entry?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await pickDateInstantly(context, _date);
    if (date == null || !mounted) return;
    setState(() => _date =
        DateTime(date.year, date.month, date.day, _date.hour, _date.minute));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? 'Log weight' : 'Edit weight'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _weightController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(formatTimerDate(_date)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final weight = double.tryParse(
                _weightController.text.trim().replaceAll(',', '.'));
            if (weight == null || weight <= 0) return;
            Navigator.of(context).pop(_WeightEntryResult(
                _date, weight, _noteController.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PersonalBestResult {
  final String name;
  final double value;
  final String unit;
  final DateTime date;
  final String note;

  const _PersonalBestResult(
      this.name, this.value, this.unit, this.date, this.note);
}

/// Add/edit dialog owning its text controllers, so the dialog's exit
/// animation never touches a disposed one (see food_diary's rule).
class _PersonalBestDialog extends StatefulWidget {
  final PersonalBest? best;

  const _PersonalBestDialog({this.best});

  @override
  State<_PersonalBestDialog> createState() => _PersonalBestDialogState();
}

class _PersonalBestDialogState extends State<_PersonalBestDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late final TextEditingController _unitController;
  late final TextEditingController _noteController;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.best?.name ?? '');
    _valueController = TextEditingController(
        text: widget.best == null ? '' : _formatNumber(widget.best!.value));
    _unitController = TextEditingController(text: widget.best?.unit ?? '');
    _noteController = TextEditingController(text: widget.best?.note ?? '');
    _date = widget.best?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _unitController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await pickDateInstantly(context, _date);
    if (date == null || !mounted) return;
    setState(() => _date =
        DateTime(date.year, date.month, date.day, _date.hour, _date.minute));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.best == null ? 'Add personal best' : 'Edit personal best'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Name (e.g. Bench press, 5K run)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valueController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Value'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _unitController,
                    decoration:
                        const InputDecoration(labelText: 'Unit (e.g. kg, min)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(formatTimerDate(_date)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final value = double.tryParse(
                _valueController.text.trim().replaceAll(',', '.'));
            if (name.isEmpty || value == null) return;
            Navigator.of(context).pop(_PersonalBestResult(name, value,
                _unitController.text.trim(), _date, _noteController.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
