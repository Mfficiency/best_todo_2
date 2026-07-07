import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/ui/alarm_ring_page.dart';

Map<String, dynamic> _payload({bool snoozeEnabled = true}) => {
      'uid': 'test-uid',
      'name': 'Wake up',
      'body': 'Morning run',
      'vibrate': true,
      'snoozeEnabled': snoozeEnabled,
      'snoozeMinutes': 9,
      'snoozeId': 123,
      'color': 0xFFE53935,
    };

void main() {
  testWidgets('ring page shows alarm name, body, clock and actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AlarmRingPage(
        payload: _payload(),
        onDismiss: (_) async {},
        onSnooze: (_) async {},
      ),
    ));

    expect(find.text('Wake up'), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.textContaining('Snooze'), findsOneWidget);
    expect(find.textContaining('9 min'), findsOneWidget);
    // Live clock renders an HH:mm time.
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
  });

  testWidgets('snooze button is hidden when the alarm cannot be snoozed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AlarmRingPage(
        payload: _payload(snoozeEnabled: false),
        onDismiss: (_) async {},
        onSnooze: (_) async {},
      ),
    ));

    expect(find.text('Stop'), findsOneWidget);
    expect(find.textContaining('Snooze'), findsNothing);
  });

  testWidgets('empty name falls back to "Alarm"', (tester) async {
    final payload = _payload()..['name'] = '';
    await tester.pumpWidget(MaterialApp(
      home: AlarmRingPage(
        payload: payload,
        onDismiss: (_) async {},
        onSnooze: (_) async {},
      ),
    ));

    expect(find.text('Alarm'), findsOneWidget);
  });

  testWidgets('Stop invokes the dismiss handler and closes the page',
      (tester) async {
    Map<String, dynamic>? dismissed;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlarmRingPage(
                  payload: _payload(),
                  onDismiss: (p) async => dismissed = p,
                  onSnooze: (_) async {},
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(dismissed?['uid'], 'test-uid');
    expect(find.text('Stop'), findsNothing);
  });

  testWidgets('Snooze invokes the snooze handler and closes the page',
      (tester) async {
    Map<String, dynamic>? snoozed;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AlarmRingPage(
                  payload: _payload(),
                  onDismiss: (_) async {},
                  onSnooze: (p) async => snoozed = p,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.textContaining('Snooze'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(snoozed?['snoozeMinutes'], 9);
    expect(find.text('Stop'), findsNothing);
  });
}
