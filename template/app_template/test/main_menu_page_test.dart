import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('3.4.5', '67');
  });
  tearDown(AppVersion.resetForTest);

  testWidgets('shows app name, dynamic version and the technical pages',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainMenuPage()));
    await tester.pumpAndSettle();

    // Title appears in the app bar and the banner.
    expect(find.text(AppConfig.appName), findsWidgets);
    // Version is rendered dynamically (never hard-coded).
    expect(find.textContaining('v3.4.5+67'), findsOneWidget);

    for (final label in const [
      'Settings',
      'About',
      'Changelog',
      'App Logs',
      'Startup Times',
      'Test Results',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('tapping a menu entry navigates to it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainMenuPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // Settings page app bar title.
    expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
  });
}
