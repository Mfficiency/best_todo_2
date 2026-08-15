@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Headless, automated screenshot process. Opens every important screen and
/// state, renders each to a consistently-named PNG in `build/e2e_screenshots/`,
/// and runs under plain `flutter test` — no device needed:
///
///   flutter test test/screenshots/capture_screens_test.dart
///   dart run tool/screenshot_report.dart   # file + build the gallery
///
/// Screenshot names are stable snake_case (the report tool titlecases them), so
/// a page keeps the same filename across runs and versions. Add a screen by
/// adding a `capture(...)` call; the report tool picks it up automatically.
///
/// For real on-device / OS-chrome screenshots, the same flow can be run from
/// integration_test with `IntegrationTestWidgetsFlutterBinding` and
/// `-d <device>`; this headless variant is the CI default.
void main() {
  // A fixed, phone-like surface so screenshots are consistent run to run.
  const surface = Size(390, 844);

  setUp(() {
    AppSettings.instance.resetForTest();
    AppVersion.setForTest('0.1.0', '1');
    // A fake path provider so pages that read persisted files resolve to their
    // honest empty state instead of hanging on the real plugin in the
    // fake-async zone. It does NOT fabricate any data.
    final dir = Directory.systemTemp.createTempSync('app_template_shots');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  testWidgets('capture every screen', (tester) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    final folder = Directory('build/e2e_screenshots')
      ..createSync(recursive: true);

    Future<void> pump(Widget child) async {
      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: child),
      );
      await tester.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      final context = boundaryKey.currentContext;
      expect(context, isNotNull, reason: 'no boundary for "$name"');
      final boundary = context!.findRenderObject() as RenderRepaintBoundary;
      // Image encode + file write are real dart:io/engine async work; they
      // never complete inside the fake-async test zone, so run them through
      // tester.runAsync (the documented mitigation for I/O in testWidgets).
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        expect(byteData, isNotNull, reason: 'could not encode "$name"');
        await File('${folder.path}/$name.png').writeAsBytes(
          byteData!.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true,
        );
        image.dispose();
      });
    }

    Future<void> openFromMenu(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }

    // --- Main menu (light) ---
    await pump(const TemplateApp(showIntro: false));
    await capture('main_menu');

    // Apply a settings change and repaint. save() notifies listeners
    // synchronously; we deliberately don't await its plugin-backed file write
    // (which never completes in the fake-async zone).
    Future<void> applyAndPump(void Function() mutate) async {
      mutate();
      AppSettings.instance.save();
      await tester.pumpAndSettle();
    }

    // --- Main menu (dark) ---
    await applyAndPump(
        () => AppSettings.instance.themeMode = AppThemeMode.dark);
    await capture('main_menu_dark');
    await applyAndPump(
        () => AppSettings.instance.themeMode = AppThemeMode.system);

    // --- Main menu (minimalist) ---
    await applyAndPump(() => AppSettings.instance.minimalist = true);
    await capture('main_menu_minimalist');
    await applyAndPump(() => AppSettings.instance.minimalist = false);

    // --- Settings ---
    await openFromMenu('Settings');
    await capture('settings');

    // --- Settings: search active ---
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'theme');
    await tester.pumpAndSettle();
    await capture('settings_search');
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    await back();

    // --- About ---
    await openFromMenu('About');
    await capture('about');
    await back();

    // --- Changelog ---
    await openFromMenu('Changelog');
    await capture('changelog');
    await back();

    // --- App Logs ---
    await openFromMenu('App Logs');
    await capture('app_logs');
    await back();

    // --- Startup Times ---
    // This page loads from disk in initState (real dart:io), which only makes
    // progress inside runAsync. Round-pump until it leaves the spinner, then
    // capture its honest (empty) state.
    await tester.tap(find.text('Startup Times'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // finish push anim
    for (var i = 0; i < 40; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await capture('startup_times');
    await back();

    // --- Test Results ---
    await openFromMenu('Test Results');
    await capture('test_results');
    await back();

    // --- Intro carousel (first-run) ---
    await pump(MaterialApp(home: IntroPage(onFinished: () {})));
    await capture('intro');
  });
}

/// Returns a temp dir for every path so file-backed services don't hang on the
/// real (unregistered) plugin. Reads of not-yet-written files return empty —
/// pages then show their genuine empty state.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}
