import 'package:besttodo/ui/estimated_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  double barValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('estimatedProgressBar')))
      .value!;

  testWidgets('without a real value it keeps filling toward ~95%',
      (tester) async {
    await tester.pumpWidget(host(const EstimatedProgressBar(
        active: true, expected: Duration(seconds: 4))));
    await tester.pump(const Duration(milliseconds: 500));
    final early = barValue(tester);
    await tester.pump(const Duration(seconds: 4));
    final later = barValue(tester);
    expect(early, greaterThan(0));
    expect(later, greaterThan(early));
    expect(later, lessThan(0.96));
  });

  testWidgets('shows a real value when given one', (tester) async {
    await tester
        .pumpWidget(host(const EstimatedProgressBar(active: true, value: 0.4)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(barValue(tester), 0.4);
  });

  testWidgets('fills up when loading ends, then disappears', (tester) async {
    await tester.pumpWidget(host(const EstimatedProgressBar(active: true)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(host(const EstimatedProgressBar(active: false)));
    await tester.pump();
    expect(barValue(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('estimatedProgressBar')), findsNothing);
  });

  testWidgets('nothing loading: no bar', (tester) async {
    await tester.pumpWidget(host(const EstimatedProgressBar(active: false)));
    expect(find.byKey(const ValueKey('estimatedProgressBar')), findsNothing);
  });
}
