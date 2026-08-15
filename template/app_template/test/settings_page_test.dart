import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('1.0.0', '1');
  });
  tearDown(AppVersion.resetForTest);

  testWidgets('renders section chips and settings controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    // Section chips.
    for (final title in const ['Appearance', 'Startup', 'Notifications', 'Data']) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    // A few representative controls from the first (visible) section.
    expect(find.text('Minimalist mode'), findsOneWidget);
    expect(find.text('24-hour time'), findsOneWidget);
    expect(find.text('Date format'), findsOneWidget);

    // The Notifications section is below the fold; jump to it via its chip and
    // confirm its control lays out.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Enable notifications'), findsOneWidget);
  });

  testWidgets('toggling minimalist updates settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.minimalist, isFalse);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Minimalist mode'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.minimalist, isTrue);
  });

  testWidgets('selecting the dark theme segment updates settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dark'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.themeMode, AppThemeMode.dark);
  });

  testWidgets('search filters settings and lists a match', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'quiet');
    await tester.pumpAndSettle();

    // The result tile for "Quiet hours" appears (under its section subtitle).
    expect(find.text('Quiet hours'), findsOneWidget);
    expect(find.text('Notifications'), findsWidgets);
  });
}
