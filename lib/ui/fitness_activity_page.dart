import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/fitness_activity_service.dart';
import 'subpage_app_bar.dart';

class FitnessActivityPage extends StatefulWidget {
  const FitnessActivityPage({super.key});

  @override
  State<FitnessActivityPage> createState() => _FitnessActivityPageState();
}

class _FitnessActivityPageState extends State<FitnessActivityPage> {
  late DateTime _weekStart;
  List<FitnessDay>? _days;
  List<FitnessDay>? _previous;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _weekStart = _monday(DateTime.now());
    _load();
  }

  DateTime _monday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  Future<void> _load() async {
    setState(() { _days = null; _denied = false; });
    try {
      final from = _weekStart.subtract(const Duration(days: 7));
      final samples = await FitnessActivityService.read(
          from, _weekStart.add(const Duration(days: 7)));
      if (!mounted) return;
      setState(() {
        _denied = samples == null;
        _previous = FitnessActivityService.summarize(from, samples ?? const []);
        _days = FitnessActivityService.summarize(_weekStart, samples ?? const []);
      });
    } catch (_) {
      if (mounted) setState(() {
        _denied = true;
        _days = FitnessActivityService.summarize(_weekStart, const []);
        _previous = FitnessActivityService.summarize(_weekStart.subtract(const Duration(days: 7)), const []);
      });
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

  Widget _metric(String title, String value, String comparison, IconData icon) =>
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 19), const SizedBox(width: 6), Expanded(child: Text(title))]),
          const SizedBox(height: 7), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text(comparison, style: Theme.of(context).textTheme.bodySmall),
        ],
      )));

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
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            IconButton(tooltip: 'Previous week', onPressed: () { _weekStart = _weekStart.subtract(const Duration(days: 7)); _load(); }, icon: const Icon(Icons.chevron_left)),
            Expanded(child: Column(children: [const Text('WEEK', style: TextStyle(fontSize: 11, letterSpacing: 1.5)), Text(_range(_weekStart), style: Theme.of(context).textTheme.titleMedium)])),
            IconButton(tooltip: 'Next week', onPressed: _weekStart.isBefore(_monday(DateTime.now())) ? () { _weekStart = _weekStart.add(const Duration(days: 7)); _load(); } : null, icon: const Icon(Icons.chevron_right)),
          ]),
          if (_denied) Card(color: Theme.of(context).colorScheme.primaryContainer, child: ListTile(
            leading: const Icon(Icons.health_and_safety), title: const Text('Connect your health data'),
            subtitle: const Text('Grant read-only Health Connect access to show steps, distance, calories, workouts, heart rate, sleep and weight. Data stays on your device.'),
            trailing: FilledButton(onPressed: _load, child: const Text('Connect')),
          )),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.35, children: [
            _metric('Steps', steps.round().toString(), _change(steps, oldSteps), Icons.directions_walk),
            _metric('Daily average', _denied ? '—' : '${(steps / 7).round()}', 'Across all 7 calendar days', Icons.calendar_today),
            _metric('Distance', '${distance.toStringAsFixed(1)} km', 'Recorded walking + running distance', Icons.route),
            _metric('Active energy', '${calories.round()} kcal', 'Movement energy, not total burn', Icons.local_fire_department),
            _metric('Workouts', '${workouts.round()} min', _change(workouts, _sum(previous, (d) => d.workoutMinutes.toDouble())), Icons.fitness_center),
            _metric('Sleep average', sleep == 0 ? '—' : '${sleep.toStringAsFixed(1)} h', _change(sleep, oldSleep), Icons.bedtime),
          ]),
          const SizedBox(height: 12), Text('Steps by day', style: Theme.of(context).textTheme.titleLarge),
          const Text('Vertical axis: steps · horizontal axis: day of week'),
          SizedBox(height: 210, child: BarChart(BarChartData(
            minY: 0, maxY: maxSteps, gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: true, border: const Border(left: BorderSide(), bottom: BorderSide())),
            titlesData: FlTitlesData(topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(axisNameWidget: const Text('steps'), sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, _) => Text(v == 0 ? '0' : '${(v/1000).round()}k', style: const TextStyle(fontSize: 10)))),
              bottomTitles: AxisTitles(axisNameWidget: const Text('day'), sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(const ['M','T','W','T','F','S','S'][v.toInt().clamp(0,6)])))),
            barGroups: List.generate(7, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: days[i].steps.toDouble(), width: 18, borderRadius: BorderRadius.circular(3))])),
          ))),
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
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
