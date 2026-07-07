import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/ui/alarm_edit_page.dart';

void main() {
  Object? result;

  Future<void> openEditor(WidgetTester tester) async {
    result = null;
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
  }

  testWidgets('the editor has a Save action in the top app bar',
      (tester) async {
    await openEditor(tester);

    // The check icon sits inside the AppBar, before the form's own button.
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(find.byTooltip('Save'), findsOneWidget);
  });

  testWidgets('tapping the top Save pops with the edited alarm',
      (tester) async {
    await openEditor(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Morning run');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    // Back on the host page with the alarm carrying the entered name.
    expect(find.text('open editor'), findsOneWidget);
    expect(result, isA<Alarm>());
    expect((result as Alarm).name, 'Morning run');
  });

  testWidgets('the bottom Save button still works too', (tester) async {
    await openEditor(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Evening walk');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(result, isA<Alarm>());
    expect((result as Alarm).name, 'Evening walk');
  });
}
