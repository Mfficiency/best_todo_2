import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/startup_time_service.dart';
import 'subpage_app_bar.dart';

/// Displays a graph of recent application startup durations.
class StartupTimesPage extends StatefulWidget {
  const StartupTimesPage({Key? key}) : super(key: key);

  @override
  State<StartupTimesPage> createState() => _StartupTimesPageState();
}

class _StartupTimesPageState extends State<StartupTimesPage> {
  List<int> _times = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final times = await StartupTimeService.getStartupTimes();
    setState(() => _times = times);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Startup Times'),
      body: _times.isEmpty
          ? const Center(child: Text('No startup records yet'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 1.5,
                    rangeAnnotations: RangeAnnotations(
                      horizontalRangeAnnotations: [
                        HorizontalRangeAnnotation(
                          y1: 1,
                          y2: 1.5,
                          color: Colors.red.withOpacity(0.2),
                        ),
                      ],
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) => Text('${value.toInt()}s'),
                        ),
                      ),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < _times.length; i++)
                            FlSpot(i.toDouble(), _times[i] / 1000.0),
                        ],
                        isCurved: false,
                        dotData: FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

