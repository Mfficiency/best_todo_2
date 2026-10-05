import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/install_info_service.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('formatInstalledAt shows the time and how long ago', () {
    final at = DateTime(2026, 10, 4, 8, 5);
    expect(formatInstalledAt(at, now: at), '2026-10-04 08:05 (just now)');
    expect(formatInstalledAt(at, now: at.add(const Duration(minutes: 12))),
        '2026-10-04 08:05 (12 min ago)');
    expect(formatInstalledAt(at, now: at.add(const Duration(hours: 1))),
        '2026-10-04 08:05 (1 hour ago)');
    expect(formatInstalledAt(at, now: at.add(const Duration(days: 3))),
        '2026-10-04 08:05 (3 days ago)');
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
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (find.byKey(const Key('changelog-installed-since')).evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.byKey(const Key('changelog-installed-since')), findsOneWidget);
    expect(find.textContaining('Installed v9.9.9+99 · 2026-10-04 18:40'),
        findsOneWidget);
  });
}
