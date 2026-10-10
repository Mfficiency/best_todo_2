import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/startup_time_service.dart';
import 'subpage_app_bar.dart';

/// One launch shown on this page: duration plus (when known) when it happened.
class _Launch {
  final DateTime? at;
  final int ms;

  const _Launch({required this.at, required this.ms});
}

/// Displays recent application startup durations with a chart, summary
/// statistics and an auto-generated interpretation of the numbers.
class StartupTimesPage extends StatefulWidget {
  const StartupTimesPage({Key? key}) : super(key: key);

  @override
  State<StartupTimesPage> createState() => _StartupTimesPageState();
}

class _StartupTimesPageState extends State<StartupTimesPage> {
  static const int _chartMaxPoints = 30;
  static const int _slowThresholdMs = 1000;

  List<_Launch>? _launches;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // The timestamped history was introduced later than the plain duration
    // list, so fall back to the legacy list when no history exists yet.
    var launches = <_Launch>[];
    try {
      final history = await StartupTimeService.getStartupHistory();
      launches = [
        for (final r in history) _Launch(at: r.at, ms: r.ms),
      ];
    } catch (_) {}
    if (launches.isEmpty) {
      try {
        final times = await StartupTimeService.getStartupTimes();
        launches = [for (final ms in times) _Launch(at: null, ms: ms)];
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _launches = launches);
  }

  // ---------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------

  String _fmtMs(int ms) =>
      ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(2)} s';

  String _shortMonthName(int month) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month];
  }

  String _fmtDay(DateTime d) => '${d.day} ${_shortMonthName(d.month)}';

  String _fmtDayTime(DateTime d) =>
      '${_fmtDay(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtAxisSeconds(double v) {
    if (v == v.roundToDouble()) return '${v.toInt()}s';
    var s = v.toStringAsFixed(2);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return '${s}s';
  }

  // ---------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------

  int _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : ((sorted[mid - 1] + sorted[mid]) / 2).round();
  }

  String _dayKeyOf(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month}-${local.day}';
  }

  /// The conclusion plus any observations that the data supports.
  List<String> _observations(List<_Launch> launches) {
    final result = <String>[];
    final times = [for (final l in launches) l.ms];
    final median = _median(times);

    // Conclusion: how does the typical startup feel?
    final String verdict;
    if (median < 400) {
      verdict = 'that feels effectively instant';
    } else if (median <= _slowThresholdMs) {
      verdict = 'quick enough that the wait is barely noticeable';
    } else if (median <= 2500) {
      verdict = 'a noticeable wait — worth keeping an eye on';
    } else {
      verdict = 'slow enough to be annoying on every launch';
    }
    result.add('Typical startup is ${_fmtMs(median)} — $verdict.');

    // Trend: older half vs. newer half.
    if (times.length >= 6) {
      final half = times.length ~/ 2;
      final olderMedian = _median(times.sublist(0, half));
      final recentMedian = _median(times.sublist(half));
      if (olderMedian > 0) {
        final change = (recentMedian - olderMedian) / olderMedian;
        if (change.abs() < 0.10) {
          result.add(
              'Startup time has stayed stable: recent launches (median ${_fmtMs(recentMedian)}) are about as fast as earlier ones (${_fmtMs(olderMedian)}).');
        } else if (change < 0) {
          result.add(
              'Startup has been getting faster: recent launches (median ${_fmtMs(recentMedian)}) are ${(change.abs() * 100).round()}% quicker than earlier ones (${_fmtMs(olderMedian)}).');
        } else {
          result.add(
              'Startup has been getting slower: recent launches (median ${_fmtMs(recentMedian)}) take ${(change * 100).round()}% longer than earlier ones (${_fmtMs(olderMedian)}). App updates, more stored data or a busy device can all contribute.');
        }
      }
    }

    // How often is startup actually slow?
    final slowCount = times.where((t) => t > _slowThresholdMs).length;
    if (slowCount == 0) {
      result.add(
          'None of the ${times.length} recorded launches took longer than 1 second.');
    } else {
      final pct = (slowCount / times.length * 100).round();
      result.add(
          '$slowCount of ${times.length} launches ($pct%) took longer than 1 second.');
    }

    // Outlier: is the slowest launch far outside the typical range?
    final slowest = launches.reduce((a, b) => a.ms >= b.ms ? a : b);
    if (median > 0 && slowest.ms > 3 * median && slowest.ms > _slowThresholdMs) {
      final when = slowest.at == null ? '' : ' (${_fmtDayTime(slowest.at!)})';
      result.add(
          'The slowest launch$when took ${_fmtMs(slowest.ms)} — over ${(slowest.ms / median).round()}× the typical time. Isolated spikes like this usually mean the device was busy or the app had to cold-start after a reboot or an update.');
    }

    // Cold-start pattern: is the first launch of a day slower than later ones?
    final byDay = <String, List<_Launch>>{};
    for (final l in launches) {
      if (l.at == null) continue;
      byDay.putIfAbsent(_dayKeyOf(l.at!), () => []).add(l);
    }
    final firstOfDay = <int>[];
    final laterInDay = <int>[];
    for (final day in byDay.values) {
      if (day.length < 2) continue;
      day.sort((a, b) => a.at!.compareTo(b.at!));
      firstOfDay.add(day.first.ms);
      laterInDay.addAll([for (final l in day.skip(1)) l.ms]);
    }
    if (firstOfDay.length >= 3 && laterInDay.length >= 3) {
      final firstMedian = _median(firstOfDay);
      final laterMedian = _median(laterInDay);
      if (laterMedian > 0 && firstMedian > laterMedian * 1.2) {
        result.add(
            'The first launch of the day is typically slower (${_fmtMs(firstMedian)} vs ${_fmtMs(laterMedian)} later on) — overnight the system evicts the app from memory, so the morning launch is a cold start.');
      } else if (laterMedian > 0) {
        result.add(
            'First launches of the day (median ${_fmtMs(firstMedian)}) are about as fast as later ones (${_fmtMs(laterMedian)}), so cold starts are not a problem on this device.');
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------

  Widget _statTile(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSummaryCard(List<_Launch> launches) {
    final theme = Theme.of(context);
    final times = [for (final l in launches) l.ms];
    final median = _median(times);
    final fastest = times.reduce(math.min);
    final slowest = times.reduce(math.max);
    final latest = launches.last.ms;
    final firstDate = launches.map((l) => l.at).whereType<DateTime>().isEmpty
        ? null
        : launches.map((l) => l.at).whereType<DateTime>().reduce(
            (a, b) => a.isBefore(b) ? a : b);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Typical startup',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(_fmtMs(median),
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _statTile('Last launch', _fmtMs(latest)),
                _statTile('Fastest', _fmtMs(fastest)),
                _statTile('Slowest', _fmtMs(slowest)),
                _statTile('Launches recorded', '${launches.length}'),
              ],
            ),
            if (firstDate != null) ...[
              const SizedBox(height: 12),
              Text('Recording since ${_fmtDay(firstDate)} ${firstDate.year}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(List<_Launch> launches) {
    final theme = Theme.of(context);
    final chartLaunches = launches.length <= _chartMaxPoints
        ? launches
        : launches.sublist(launches.length - _chartMaxPoints);
    final hasDates = chartLaunches.any((l) => l.at != null);

    // A y-axis that fits the data instead of clipping slow launches.
    final maxSec =
        chartLaunches.map((l) => l.ms).reduce(math.max) / 1000.0;
    final target = math.max(maxSec * 1.15, 0.5);
    const candidates = [0.1, 0.2, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0];
    final interval = candidates.firstWhere(
      (c) => target / c <= 5,
      orElse: () => candidates.last,
    );
    final maxY = (target / interval).ceil() * interval;
    final showSlowBand = maxY > _slowThresholdMs / 1000.0;

    // Date labels on the first, middle and last point (when dates exist).
    final labelIndexes = <int>{
      0,
      chartLaunches.length ~/ 2,
      chartLaunches.length - 1,
    };

    final primary = theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last ${chartLaunches.length} launches',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  rangeAnnotations: RangeAnnotations(
                    horizontalRangeAnnotations: [
                      if (showSlowBand)
                        HorizontalRangeAnnotation(
                          y1: _slowThresholdMs / 1000.0,
                          y2: maxY,
                          color: theme.colorScheme.error.withOpacity(0.10),
                        ),
                    ],
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.dividerColor.withOpacity(0.35),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: interval,
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _fmtAxisSeconds(value),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: hasDates,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (value != i.toDouble() ||
                              !labelIndexes.contains(i)) {
                            return const SizedBox.shrink();
                          }
                          final at = chartLaunches[i].at;
                          if (at == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_fmtDay(at),
                                style: theme.textTheme.bodySmall),
                          );
                        },
                      ),
                    ),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: theme.colorScheme.inverseSurface,
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            () {
                              final launch = chartLaunches[spot.x.toInt()];
                              final when = launch.at == null
                                  ? ''
                                  : '\n${_fmtDayTime(launch.at!)}';
                              return '${_fmtMs(launch.ms)}$when';
                            }(),
                            TextStyle(
                              color: theme.colorScheme.onInverseSurface,
                            ),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < chartLaunches.length; i++)
                          FlSpot(i.toDouble(), chartLaunches[i].ms / 1000.0),
                      ],
                      isCurved: false,
                      barWidth: 2,
                      color: primary,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 2.5,
                          color: primary,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: primary.withOpacity(0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (!hasDates) 'Oldest on the left, newest on the right.',
                if (showSlowBand) 'The shaded band marks starts over 1 s.',
                'Tap a point for details.',
              ].join(' '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationCard(List<_Launch> launches) {
    final theme = Theme.of(context);
    final observations = _observations(launches);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What this means', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Startup time is measured from the moment the app process starts '
              'running until the first frame of the interface is on screen. '
              'Under about half a second feels instant; beyond one second the '
              'wait becomes noticeable.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final obs in observations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Text(obs, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No startup records yet',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Every time the app starts, the time until the interface is '
              'ready is recorded. Close and reopen the app a few times, then '
              'come back here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final launches = _launches;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Startup Times'),
      body: launches == null
          ? const Center(child: CircularProgressIndicator())
          : launches.isEmpty
              ? _buildEmptyState()
              : ListView(
                  children: [
                    _buildSummaryCard(launches),
                    _buildChartCard(launches),
                    _buildExplanationCard(launches),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}
