import 'dart:convert';
import 'dart:io';

import 'package:besttodo/ui/startup_times_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<Directory> _freshDocsDir() async {
  final tempDir = await Directory.systemTemp.createTemp();
  PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  return tempDir;
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: StartupTimesPage()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows summary, chart and explanation for timestamped history',
      (tester) async {
    final dir = await _freshDocsDir();
    final history = [
      for (var i = 0; i < 10; i++)
        {
          'at': DateTime(2026, 7, 1 + i, 9, 30).toIso8601String(),
          'ms': 400 + i * 10,
        },
      // One slow outlier well over the 1 s threshold.
      {'at': DateTime(2026, 7, 11, 8, 0).toIso8601String(), 'ms': 2200},
    ];
    await File('${dir.path}/startup_history.json')
        .writeAsString(jsonEncode(history));

    await _pumpPage(tester);

    expect(find.text('Typical startup'), findsOneWidget);
    expect(find.text('Last launch'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Slowest'), findsOneWidget);
    expect(find.text('2.20 s'), findsWidgets); // slowest, human readable
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Last 11 launches'), findsOneWidget);
    expect(find.text('What this means'), findsOneWidget);
    // The slow-launch observation is generated from the data.
    expect(find.textContaining('1 of 11 launches'), findsOneWidget);

    // The slow outlier must fit inside the chart instead of being clipped.
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.maxY, greaterThanOrEqualTo(2.2));
  });

  testWidgets('falls back to legacy duration list without timestamps',
      (tester) async {
    final dir = await _freshDocsDir();
    await File('${dir.path}/startup_times.json')
        .writeAsString(jsonEncode([500, 600, 700]));

    await _pumpPage(tester);

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Last 3 launches'), findsOneWidget);
    expect(find.textContaining('Oldest on the left'), findsOneWidget);
    expect(find.text('What this means'), findsOneWidget);
  });

  testWidgets('shows empty state when nothing recorded', (tester) async {
    await _freshDocsDir();

    await _pumpPage(tester);

    expect(find.text('No startup records yet'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });
}
