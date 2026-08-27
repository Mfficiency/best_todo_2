import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/utils/date_time_format.dart';

void main() {
  testWidgets('pickTimeOfDay offers manual Save on the minute step',
      (tester) async {
    TimeOfDay? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await pickTimeOfDay(
                  context,
                  const TimeOfDay(hour: 8, minute: 45),
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    await tester.tap(find.text('Minutes'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 8, minute: 45));
  });

  testWidgets('pickDateInstantly supports dates back to 1900', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                picked =
                    await pickDateInstantly(context, DateTime(1985, 6, 15));
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    // Before the range was widened to 1900, an initial date before 2000 was
    // clamped up to 2000; the calendar must open on the requested month.
    expect(find.textContaining('1985'), findsWidgets);

    // Tapping a day closes the instant picker and returns the past date.
    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(1985, 6, 20));
  });
}
