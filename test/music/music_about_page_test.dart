import 'package:besttodo/config.dart';
import 'package:besttodo/ui/music_about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Best Music's About page (SPEC.md §10.6f): same [UpdateSection] widget as
/// BestToDo's own About page, wired to [MusicAboutPage.updateService] (an
/// [UpdateService.forApp] instance) instead of the default
/// [UpdateService.instance] — see about_page_update_test.dart for the shared
/// widget's own check/download/rollback coverage.
void main() {
  setUp(() {
    Config.resetVersionForTest();
  });

  tearDown(() {
    MusicAboutPage.updateService.fetchOverride = null;
  });

  testWidgets('shows Best Music branding and a Check for updates button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicAboutPage()));
    await tester.pump();

    expect(find.textContaining('Best Music v'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets(
      'Check for updates goes through MusicAboutPage.updateService, not '
      "BestToDo's own instance", (tester) async {
    MusicAboutPage.updateService.fetchOverride = (url) async => '[]';

    await tester.pumpWidget(const MaterialApp(home: MusicAboutPage()));
    await tester.pump();
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    // Awaits PackageInfo (a platform-channel call) before the fetchOverride
    // result comes back — give the real event loop a few slices, same as
    // about_page_update_test.dart's tapCheck helper.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.textContaining('You are on the latest version'),
        findsOneWidget);
  });
}
