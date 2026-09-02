import 'dart:io';

import 'package:besttodo/services/health_tracking_service.dart';
import 'package:besttodo/ui/fitness_activity_page.dart';
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
    HealthTrackingService.instance.resetForTest();
  });

  // Real file I/O (the page's Health Connect probe + HealthTrackingService's
  // load/save) hangs inside testWidgets' fake-async zone, so every step that
  // triggers it is followed by a bounded runAsync+pump polling loop — same
  // pattern as food_diary_page_test.dart.
  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> pumpAndReachSection(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FitnessActivityPage()));
    final marker = find.text('Connect your health data');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Weight & personal bests'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('logging a weight entry shows it and persists', (tester) async {
    await pumpAndReachSection(tester);

    await tester.tap(find.byTooltip('Log weight'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Weight (kg)'), '72.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('72.5 kg'), findsOneWidget);
    expect(await File('${tempDir.path}/weight_log.json').exists(), isTrue);
  });

  testWidgets('adding a personal best shows it and persists', (tester) async {
    await pumpAndReachSection(tester);

    await tester.tap(find.byTooltip('Add personal best'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Name (e.g. Bench press, 5K run)'),
        'Bench press');
    await tester.enterText(find.widgetWithText(TextField, 'Value'), '80');
    await tester.enterText(
        find.widgetWithText(TextField, 'Unit (e.g. kg, min)'), 'kg');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Bench press'), findsOneWidget);
    expect(find.textContaining('80 kg'), findsOneWidget);
    expect(await File('${tempDir.path}/personal_bests.json').exists(), isTrue);
  });

  testWidgets('deleting a weight entry removes it from the list',
      (tester) async {
    await pumpAndReachSection(tester);

    await tester.tap(find.byTooltip('Log weight'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Weight (kg)'), '70');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);
    expect(find.text('70 kg'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('70 kg'), findsNothing);
    expect(find.text('Weight entry deleted'), findsOneWidget);
  });

  testWidgets('tapping a weight entry opens the edit dialog prefilled',
      (tester) async {
    await pumpAndReachSection(tester);

    await tester.tap(find.byTooltip('Log weight'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Weight (kg)'), '68');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    await tester.tap(find.text('68 kg'));
    await tester.pumpAndSettle();

    expect(find.text('Edit weight'), findsOneWidget);
    final field = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Weight (kg)'));
    expect(field.controller?.text, '68');
  });
}
