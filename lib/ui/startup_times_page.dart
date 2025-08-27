import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/startup_time_service.dart';

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
      appBar: AppBar(title: const Text('Startup Times')),
      body: _times.isEmpty
          ? const Center(child: Text('No startup records yet'))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: LineChart(
                LineChartData(
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < _times.length; i++)
                          FlSpot(i.toDouble(), _times[i].toDouble()),
                      ],
                      isCurved: false,
                      dotData: FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

