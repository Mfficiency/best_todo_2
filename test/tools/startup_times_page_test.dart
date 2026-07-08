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

void main() {
  // Real file I/O awaited inside a testWidgets body hangs under the
  // fake-async zone (see CLAUDE.md), so the temp dir comes from setUp and all
  // other I/O goes through tester.runAsync.
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
  });

  Future<void> pumpPage(WidgetTester tester, {required String waitFor}) async {
    await tester.pumpWidget(const MaterialApp(home: StartupTimesPage()));
    // initState loads the history files (real I/O in the fake zone); pump
    // real-event-loop slices until the page renders its loaded state.
    final marker = find.textContaining(waitFor);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shows summary, chart and explanation for timestamped history',
      (tester) async {
    final history = [
      for (var i = 0; i < 10; i++)
        {
          'at': DateTime(2026, 7, 1 + i, 9, 30).toIso8601String(),
          'ms': 400 + i * 10,
        },
      // One slow outlier well over the 1 s threshold.
      {'at': DateTime(2026, 7, 11, 8, 0).toIso8601String(), 'ms': 2200},
    ];
    await tester.runAsync(() => File('${docsDir.path}/startup_history.json')
        .writeAsString(jsonEncode(history)));

    await pumpPage(tester, waitFor: 'Last 11 launches');

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
    await tester.runAsync(() => File('${docsDir.path}/startup_times.json')
        .writeAsString(jsonEncode([500, 600, 700])));

    await pumpPage(tester, waitFor: 'Last 3 launches');

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Last 3 launches'), findsOneWidget);
    expect(find.textContaining('Oldest on the left'), findsOneWidget);
    expect(find.text('What this means'), findsOneWidget);
  });

  testWidgets('shows empty state when nothing recorded', (tester) async {
    await pumpPage(tester, waitFor: 'No startup records yet');

    expect(find.text('No startup records yet'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });
}
