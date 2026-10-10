import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end navigation test: launches the whole app and walks through every
/// menu destination, confirming each opens and backs out cleanly. Run it on a
/// device or desktop:
///
///   flutter test integration_test/app_flow_test.dart -d windows
///
/// (Add platform folders first with `flutter create --platforms=windows .` if
/// the template has none yet.)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('0.1.0', '1');
  });

  testWidgets('every menu destination opens and returns', (tester) async {
    await tester.pumpWidget(const TemplateApp(showIntro: false));
    await tester.pumpAndSettle();

    // Menu shows the app name and the version banner.
    expect(find.text(AppConfig.appName), findsWidgets);
    expect(find.textContaining('v0.1.0+1'), findsOneWidget);

    Future<void> visit(String label, String appBarTitle) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, appBarTitle), findsOneWidget,
          reason: '$label did not open');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(AppConfig.appName), findsWidgets,
          reason: 'did not return to the menu from $label');
    }

    await visit('Settings', 'Settings');
    await visit('About', 'About');
    await visit('Changelog', 'Changelog');
    await visit('App Logs', 'App Logs');
    await visit('Startup Times', 'Startup Times');
    await visit('Test Results', 'Test Results');
  });

  testWidgets('a theme change persists across navigation', (tester) async {
    await tester.pumpWidget(const TemplateApp(showIntro: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dark'));
    await tester.pumpAndSettle();

    expect(AppSettings.instance.themeMode, AppThemeMode.dark);
    // The MaterialApp is now in dark mode.
    final ctx = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });
}
