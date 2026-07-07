import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/ui/alarm_edit_page.dart';

void main() {
  Future<Object?> Function() pushEditor(WidgetTester tester, {Alarm? alarm}) {
    Object? result;
    var popped = false;
    return () async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => AlarmEditPage(alarm: alarm)),
                  );
                  popped = true;
                },
                child: const Text('open editor'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();
      return popped ? result : null;
    };
  }

  testWidgets('the editor has a Save action in the top app bar',
      (tester) async {
    await pushEditor(tester)();

    // The check icon sits inside the AppBar, before the form's own button.
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(find.byTooltip('Save'), findsOneWidget);
  });

  testWidgets('tapping the top Save returns the edited alarm', (tester) async {
    final open = pushEditor(tester);
    await open();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Morning run');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    // The editor popped back to the host page.
    expect(find.text('open editor'), findsOneWidget);
  });

  testWidgets('top Save pops with the alarm carrying the entered name',
      (tester) async {
    Object? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AlarmEditPage()),
                );
              },
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Morning run');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(result, isA<Alarm>());
    expect((result as Alarm).name, 'Morning run');
  });
}
