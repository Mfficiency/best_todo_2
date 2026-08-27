import 'package:besttodo/models/label.dart';
import 'package:besttodo/services/label_service.dart';
import 'package:besttodo/ui/label_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Deliberately no PathProviderPlatform override: the field
  // registers/loads LabelService in the background on a fire-and-forget
  // chain (see LabelService), and real dart:io calls kicked off from
  // initState never complete inside a testWidgets fake-async zone (they
  // just hang the test — see CLAUDE.md). Leaving path_provider
  // unimplemented makes that chain fail fast (caught internally) instead,
  // which is fine here since these tests only assert on in-memory state.
  setUp(() {
    LabelService.instance.resetForTest();
  });

  Future<void> pumpField(
    WidgetTester tester, {
    required String value,
    required ValueChanged<String> onChanged,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LabelPickerField(value: value, onChanged: onChanged),
      ),
    ));
  }

  testWidgets('shows current labels as chips', (tester) async {
    await pumpField(tester, value: 'urgent, gift', onChanged: (_) {});
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('gift'), findsOneWidget);
    expect(find.text('Add label'), findsOneWidget);
  });

  testWidgets('deleting a chip removes just that label', (tester) async {
    String? changedTo;
    await pumpField(
      tester,
      value: 'urgent, gift',
      onChanged: (v) => changedTo = v,
    );

    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, 'urgent'),
      matching: find.byTooltip('Delete'),
    ));
    await tester.pump();

    expect(changedTo, 'gift');
    expect(find.text('urgent'), findsNothing);
    expect(find.text('gift'), findsOneWidget);
  });

  testWidgets('picking an existing label from the list adds it',
      (tester) async {
    String? changedTo;
    await pumpField(
      tester,
      value: 'urgent',
      onChanged: (v) => changedTo = v,
    );
    LabelService.instance.labels.value = [
      Label(name: 'someday', kind: Label.kindTag),
    ];
    await tester.pump();

    await tester.tap(find.text('Add label'));
    await tester.pumpAndSettle();

    expect(find.text('someday'), findsOneWidget);
    await tester.tap(find.text('someday'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(changedTo, 'urgent, someday');
  });

  testWidgets('typing a new name offers "Add" and creates a custom label',
      (tester) async {
    String? changedTo;
    await pumpField(tester, value: '', onChanged: (v) => changedTo = v);

    await tester.tap(find.text('Add label'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'homework');
    await tester.pump();

    expect(find.text('Add "homework"'), findsOneWidget);
    await tester.tap(find.text('Add "homework"'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(changedTo, 'homework');
  });

  testWidgets(
      'a reserved state tag (e.g. "Wish") renders as a protected chip, a '
      'plain tag does not', (tester) async {
    await pumpField(tester, value: 'Wish, urgent', onChanged: (_) {});

    final protectedChip =
        tester.widget<InputChip>(find.widgetWithText(InputChip, 'Wish'));
    final plainChip =
        tester.widget<InputChip>(find.widgetWithText(InputChip, 'urgent'));

    expect(protectedChip.tooltip, isNotNull);
    expect(plainChip.tooltip, isNull);
    expect(protectedChip.backgroundColor, isNotNull);
    expect(plainChip.backgroundColor, isNull);
  });

  testWidgets('matching a reserved tag by lowercase still renders protected',
      (tester) async {
    await pumpField(tester, value: 'archived', onChanged: (_) {});
    final chip =
        tester.widget<InputChip>(find.widgetWithText(InputChip, 'archived'));
    expect(chip.tooltip, isNotNull);
  });

  testWidgets('cancel leaves the labels unchanged', (tester) async {
    var called = false;
    await pumpField(
      tester,
      value: 'urgent',
      onChanged: (_) => called = true,
    );

    await tester.tap(find.text('Add label'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ignored');
    await tester.pump();
    await tester.tap(find.text('Add "ignored"'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('ignored'), findsNothing);
  });
}
