import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/startup_time_service.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';
import 'widgets/spacing.dart';

/// Shows recent, *real* application startup durations: a line chart, summary
/// statistics and a plain-language interpretation. Data comes from
/// [StartupTimeService] — nothing here is synthesised.
class StartupTimesPage extends StatefulWidget {
  const StartupTimesPage({super.key});

  @override
  State<StartupTimesPage> createState() => _StartupTimesPageState();
}

class _StartupTimesPageState extends State<StartupTimesPage> {
  static const int _chartMaxPoints = 30;
  static const int _slowThresholdMs = 1000;

  List<StartupRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var records = <StartupRecord>[];
    try {
      records = await StartupTimeService.getStartupHistory();
      if (records.isEmpty) {
        // Fall back to the legacy plain-duration list (no timestamps).
        final times = await StartupTimeService.getStartupTimes();
        records = [
          for (final ms in times) StartupRecord(at: DateTime.now(), ms: ms),
        ];
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _records = records);
  }

  String _fmtMs(int ms) =>
      ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Startup Times'),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(child: Text('No startup data recorded yet'))
              : _buildContent(context, records),
    );
  }

  Widget _buildContent(BuildContext context, List<StartupRecord> records) {
    final values = records.map((r) => r.ms).toList();
    final recent = values.length > _chartMaxPoints
        ? values.sublist(values.length - _chartMaxPoints)
        : values;
    final avg = values.reduce((a, b) => a + b) / values.length;
    final best = values.reduce(math.min);
    final worst = values.reduce(math.max);
    final last = values.last;
    final slowCount = values.where((v) => v > _slowThresholdMs).length;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SizedBox(height: 220, child: _Chart(values: recent)),
        const SizedBox(height: AppSpacing.xl),
        _statRow('Last launch', _fmtMs(last)),
        _statRow('Average', _fmtMs(avg.round())),
        _statRow('Fastest', _fmtMs(best)),
        _statRow('Slowest', _fmtMs(worst)),
        _statRow('Launches recorded', '${values.length}'),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _interpretation(avg, slowCount, values.length),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Last recorded: ${formatDateTime(records.last.at)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _statRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  String _interpretation(double avg, int slowCount, int total) {
    final buffer = StringBuffer();
    if (avg < 500) {
      buffer.write('Startup is snappy — averaging under half a second. ');
    } else if (avg < _slowThresholdMs) {
      buffer.write('Startup is healthy, under one second on average. ');
    } else {
      buffer.write('Startup is on the slow side, over a second on average. ');
    }
    if (slowCount > 0) {
      buffer.write('$slowCount of $total launches took longer than '
          '${_slowThresholdMs ~/ 1000}s.');
    } else {
      buffer.write('No launch exceeded ${_slowThresholdMs ~/ 1000}s.');
    }
    return buffer.toString();
  }
}

class _Chart extends StatelessWidget {
  final List<int> values;
  const _Chart({required this.values});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = (values.reduce(math.max) * 1.2).clamp(100, double.infinity);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY.toDouble(),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i].toDouble()),
            ],
            isCurved: true,
            color: scheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
