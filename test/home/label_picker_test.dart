import 'dart:io';

import 'package:besttodo/models/label.dart';
import 'package:besttodo/services/label_service.dart';
import 'package:besttodo/ui/label_picker.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    LabelService.instance.resetForTest();
  });

  // The field registers/loads in the background on a fire-and-forget chain
  // (see LabelService); drain it here — outside the widget test's fake-async
  // zone, where real file I/O actually completes — so nothing from one test
  // leaks a late write into the next.
  tearDown(() async {
    await LabelService.instance.pendingWrites;
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
    await tester.tap(find.text('Add "ignored"'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('ignored'), findsNothing);
  });
}
