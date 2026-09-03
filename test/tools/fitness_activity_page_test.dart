import 'package:besttodo/ui/fitness_activity_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The `health` plugin has no platform implementation under flutter_test,
  // so FitnessActivityService.read() throws (MissingPluginException) and the
  // page falls back to its "denied" state. That state used to summarize into
  // an *empty* list while the chart/insights code unconditionally indexed 7
  // days, throwing during build and rendering Flutter's gray error widget
  // instead of the page. Guard against that regression.
  testWidgets('renders the connect-health-data state instead of a blank/error screen',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FitnessActivityPage()));
    final marker = find.text('Connect your health data');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Connect your health data'), findsOneWidget);
    expect(find.text('Fitness Activity'), findsOneWidget);
    // No RangeError/StateError-driven error widget in place of the page.
    expect(find.byType(ErrorWidget), findsNothing);

    // Scroll to reveal the chart and insights, built further down the
    // ListView (a sliver only realizes children near the viewport, so a
    // fixed single drag is brittle whenever content above the chart grows —
    // drag repeatedly instead of guessing a large-enough one-shot offset).
    await tester.dragUntilVisible(
      find.byType(BarChart),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BarChart), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('What the data says'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('What the data says'), findsOneWidget);
  });
}
