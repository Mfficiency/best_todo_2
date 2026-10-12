import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/install_info_service.dart';
import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockVersion(String version, String build) {
  Config.resetVersionForTest();
  PackageInfo.setMockInitialValues(
    appName: 'BestToDo',
    packageName: 'com.example.besttodo',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
}

class _FakeBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
      Uint8List.fromList(utf8.encode('## [9.9.9] - 2026-10-04\n- x\n')));
}

/// The card's install time comes from prefs/the native side: real async
/// hops, run outside the fake clock until [marker] shows up.
Future<void> _loadCard(WidgetTester tester, String marker) async {
  for (var i = 0; i < 40; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
    if (find.textContaining(marker).evaluate().isNotEmpty) break;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateService.resetForTest();
    InstallInfoService.nativeOverride = null;
    _mockVersion('9.9.9', '99');
  });

  tearDown(() {
    InstallInfoService.nativeOverride = null;
    Config.resetVersionForTest();
  });

  test('prefers Android\'s own lastUpdateTime', () async {
    final installed = DateTime(2026, 10, 4, 18, 40);
    InstallInfoService.nativeOverride = () async => installed;

    final info = await InstallInfoService.load();

    expect(info!.version, '9.9.9+99');
    expect(info.installedAt, installed);
  });

  test('falls back to when this version was first seen running', () async {
    InstallInfoService.nativeOverride = () async => null;
    final first = DateTime(2026, 10, 1, 9);
    await InstallInfoService.recordLaunch(now: first);
    // A later launch of the same version keeps the first time.
    await InstallInfoService.recordLaunch(now: DateTime(2026, 10, 3));

    expect((await InstallInfoService.load())!.installedAt, first);

    // A new version starts a new record.
    _mockVersion('9.9.10', '100');
    final second = DateTime(2026, 10, 4, 12);
    await InstallInfoService.recordLaunch(now: second);
    final info = await InstallInfoService.load();
    expect(info!.version, '9.9.10+100');
    expect(info.installedAt, second);
  });

  testWidgets('the Changelog shows when the running version was installed',
      (tester) async {
    InstallInfoService.nativeOverride =
        () async => DateTime(2026, 10, 4, 18, 40);

    await tester.pumpWidget(MaterialApp(
      home: DefaultAssetBundle(
        bundle: _FakeBundle(),
        child: const ChangelogPage(),
      ),
    ));
    await _loadCard(tester, 'Installed');

    final card = find.byKey(const Key('changelog-update-status'));
    expect(card, findsOneWidget);
    expect(
        find.descendant(
            of: card,
            matching: find.textContaining('Current version 9.9.9 (99)')),
        findsOneWidget);
    expect(
        find.descendant(
            of: card,
            matching: find.textContaining('Installed 04.10.26, 18:40')),
        findsOneWidget);
    // Nothing downloaded or checked yet: no empty parts, no "null".
    expect(
        find.descendant(of: card, matching: find.textContaining('Downloaded')),
        findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('null')),
        findsNothing);
    expect(
        find.descendant(
            of: card,
            matching: find.textContaining(
                'Not checked yet · Pull down to check for updates')),
        findsOneWidget);
    expect(
        find.byKey(const Key('changelog-installed-version')), findsOneWidget);
  });

  testWidgets(
      'the Changelog shows when the running build was downloaded, '
      'installed and last checked', (tester) async {
    SharedPreferences.setMockInitialValues({
      'update_last_download': jsonEncode({
        'version': '9.9.9+99',
        'at': DateTime(2026, 10, 12, 11, 20).millisecondsSinceEpoch,
      }),
      'update_last_checked':
          DateTime(2026, 10, 12, 14, 5).millisecondsSinceEpoch,
    });
    InstallInfoService.nativeOverride =
        () async => DateTime(2026, 10, 12, 11, 25);

    await tester.pumpWidget(MaterialApp(
      home: DefaultAssetBundle(
        bundle: _FakeBundle(),
        child: const ChangelogPage(),
      ),
    ));
    await _loadCard(tester, 'Installed');

    final card = find.byKey(const Key('changelog-update-status'));
    expect(
        find.descendant(
            of: card,
            matching: find.text('Downloaded 12.10.26, 11:20 · '
                'Installed 12.10.26, 11:25\n'
                'Last checked 12.10.26, 14:05 · '
                'Pull down to check for updates')),
        findsOneWidget);
  });
}
