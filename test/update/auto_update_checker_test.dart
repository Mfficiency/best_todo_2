import 'dart:convert';

import 'package:besttodo/services/auto_update_checker.dart';
import 'package:besttodo/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The background poll's pure logic (dedup + dismissal), driven directly via
/// [AutoUpdateChecker.checkOnce] rather than the real [Timer.periodic] — the
/// periodic wiring itself only ever runs on-device (see `main.dart`, gated on
/// `Platform.isAndroid`, which is false under `flutter test`). Network is
/// faked through [UpdateService.fetchOverride], same seam as
/// `update_service_test.dart` / `about_page_update_test.dart`.
void main() {
  setUp(() {
    UpdateService.resetForTest();
    AutoUpdateChecker.resetForTest();
  });

  tearDown(() {
    UpdateService.resetForTest();
    AutoUpdateChecker.resetForTest();
  });

  String releaseJson(String tag, {bool withApk = true}) => jsonEncode({
        'tag_name': tag,
        'name': 'BestToDo release',
        'html_url': 'https://example.com/release',
        'assets': [
          if (withApk)
            {
              'name': 'BestToDo.apk',
              'browser_download_url': 'https://example.com/BestToDo.apk',
              'size': 52428800,
            },
        ],
      });

  test('reports an installable newer build', () async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');

    UpdateInfo? found;
    await AutoUpdateChecker.instance.checkOnce((info) => found = info);

    expect(found?.version, '9.9.9+999');
  });

  test('stays quiet when already up to date', () async {
    // The running version in tests is 'unknown', which compares as 0.0.0 —
    // so a v0.0.0-0 release is not newer.
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v0.0.0-0');

    UpdateInfo? found;
    await AutoUpdateChecker.instance.checkOnce((info) => found = info);

    expect(found, isNull);
  });

  test('skips a release with no APK asset — nothing to auto-install',
      () async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999', withApk: false);

    UpdateInfo? found;
    await AutoUpdateChecker.instance.checkOnce((info) => found = info);

    expect(found, isNull);
  });

  test('a dismissed version is not reported again', () async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');

    var calls = 0;
    await AutoUpdateChecker.instance.checkOnce((info) => calls++);
    expect(calls, 1);

    AutoUpdateChecker.instance.dismiss('9.9.9+999');
    await AutoUpdateChecker.instance.checkOnce((info) => calls++);
    expect(calls, 1);
  });

  test('a newer build is reported again after an older one was dismissed',
      () async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');
    UpdateInfo? found;
    await AutoUpdateChecker.instance.checkOnce((info) => found = info);
    AutoUpdateChecker.instance.dismiss('9.9.9+999');

    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-1000');
    await AutoUpdateChecker.instance.checkOnce((info) => found = info);

    expect(found?.version, '9.9.9+1000');
  });

  test('a failed check is swallowed and does not call back', () async {
    UpdateService.instance.fetchOverride =
        (url) async => throw Exception('offline');

    var calls = 0;
    await AutoUpdateChecker.instance.checkOnce((info) => calls++);

    expect(calls, 0);
  });

  test('start() checks immediately instead of waiting for the first tick',
      () async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');

    UpdateInfo? found;
    // A long testInterval proves any result came from the immediate check
    // start() fires, not from the periodic timer ticking.
    AutoUpdateChecker.instance
        .start((info) => found = info, testInterval: const Duration(minutes: 5));
    addTearDown(AutoUpdateChecker.instance.stop);

    // Let the fire-and-forget immediate check's microtasks/awaits flush.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(found?.version, '9.9.9+999');
  });
}
