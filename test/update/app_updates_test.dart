import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/services/pre_update_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_fakes.dart';

/// BestToDo's side of the updates package
/// (`lib/services/app_updates.dart`): which releases it takes, the
/// "Automatically update" switch, the state stored before the package, the
/// full backup before Android's installer opens and the held-back
/// prompt. Everything else is the package's default behaviour (resume
/// check, the switch turned on/off while running, GitHub's rate limit,
/// User-Agent, channel order, APK-less releases), tested in the package
/// (`packages/mfficiency_updates/test`); here only that the app keeps
/// those defaults. The flow as the app shows it: update_flow_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeGithub github;
  late FakeDownloader downloader;
  late FakeInstaller installer;

  setUp(() {
    github = FakeGithub();
    downloader = FakeDownloader();
    installer = FakeInstaller();
    Config.autoUpdateCheckEnabled = true;
  });
  tearDown(() {
    installer.dispose();
    AppUpdates.controller?.dispose();
    AppUpdates.controller = null;
    AppUpdates.promptAllowed.value = true;
    Config.autoUpdateCheckEnabled = true;
  });

  /// Lets the background download and the install call finish.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('config', () {
    test('one public repo, tag prefix v, every 15 minutes', () {
      final c =
          AppUpdates.config(UpdatesApp.todo, version: '0.2.106', build: 9);
      expect(c.githubRepo, 'Mfficiency/best_todo_2');
      expect(c.privateRepo, isFalse, reason: 'no token: the repo is public');
      expect(c.pollInterval, const Duration(minutes: 15));
      expect(c.checkInterval, const Duration(minutes: 15));
      expect(c.includePrereleases(), isTrue,
          reason: 'dev/staging builds are prereleases of the same app');
      expect(c.tagPrefix, 'v');
      expect(c.appName, 'BestToDo');
    });

    test('automatic checks follow the "Automatically update" switch', () {
      final todo = AppUpdates.config(UpdatesApp.todo, version: '1', build: 1);
      expect(todo.autoCheck(), isTrue);
      Config.autoUpdateCheckEnabled = false;
      expect(todo.autoCheck(), isFalse);
    });

    test("the package's behaviour is left at its defaults", () {
      for (final app in UpdatesApp.values) {
        final c = AppUpdates.config(app, version: '0.2.106', build: 9);
        expect(c.checkOnResume, isTrue,
            reason: 'back in the app after 15 minutes: a check');
        expect(c.dueAfter, AppUpdates.interval);
        expect(c.requireApk, isTrue,
            reason: 'a release whose APK is still uploading is not offered');
        expect(c.strictTags, isFalse);
        expect(c.tagPattern, isNull);
        expect(c.buildPrefix, '');
        expect(c.rateLimitPause, const Duration(minutes: 30));
        expect(c.userAgent, isNull);
        expect(c.autoCheckChanges, isNull,
            reason: 'Settings calls the controller\'s autoCheckChanged()');
      }
      expect(
          AppUpdates.config(UpdatesApp.todo, version: '1', build: 1)
              .httpUserAgent,
          'BestToDo-update-check');
    });

    test('the install prompt is held back while the intro is open', () {
      final todo = fakeController(github: github, downloader: downloader);
      expect(todo.promptAllowed, same(AppUpdates.promptAllowed));
    });

    test('the running channel is only shown next to the version', () {
      final c = AppUpdates.config(UpdatesApp.todo,
          version: '0.2.106', build: 3566146, channel: 'dev');
      expect(c.versionLabel, '0.2.106 (3566146) · dev');
    });
  });

  group('releases of all channels, own tags only', () {
    test('BestToDo takes the highest build of any channel, never music-v',
        () async {
      github.releases = [
        release('music-v9.0.0-9999999'),
        release('v0.2.107-3600010-dev', prerelease: true),
        release('v0.2.107-3600030-staging', prerelease: true),
        release('v0.2.106-3600020'),
        release('v0.2.108-3600099-dev', draft: true),
      ];
      final c = fakeController(github: github, downloader: downloader);
      final r = await c.check();
      expect(r.status, UpdateStatus.available);
      expect(r.key, '0.2.107+3600030');
      expect(r.channel, 'staging');
      expect(github.requests.single.toString(),
          'https://api.github.com/repos/Mfficiency/best_todo_2/releases?per_page=30');
    });

    test('the build number decides, not x.y.z', () async {
      github.releases = [
        release('v9.9.9-999'),
        release('v0.0.1-1001-dev', prerelease: true),
      ];
      final c = fakeController(github: github, downloader: downloader);
      expect((await c.check()).key, '0.0.1+1001');

      github.releases = [release('v9.9.9-999')];
      expect((await c.check()).status, UpdateStatus.upToDate,
          reason: 'a higher x.y.z with a lower build is not an update');
    });

    test('no release of this app: up to date', () async {
      github.releases = [release('music-v0.3.27-9999999')];
      final c = fakeController(github: github, downloader: downloader);
      expect((await c.check()).status, UpdateStatus.upToDate);
    });

    test("GitHub's anonymous rate limit (403) pauses the automatic checks",
        () async {
      github.failStatus = 403;
      final c = fakeController(github: github, downloader: downloader);
      expect((await c.check()).status, UpdateStatus.rateLimited);
      expect(c.rateLimited, isTrue);
      expect(const UpdateStrings().rateLimited,
          'GitHub is limiting update checks right now — try again later.');
    });
  });

  group('state stored before the package (0.2.106 and older)', () {
    test('last check, last download and first start move to its keys',
        () async {
      final checked = DateTime(2026, 10, 11, 9, 30);
      final downloaded = DateTime(2026, 10, 10, 8, 15);
      final firstSeen = DateTime(2026, 10, 10, 8, 20);
      SharedPreferences.setMockInitialValues({
        'update_last_checked': checked.millisecondsSinceEpoch,
        'update_last_download': jsonEncode({
          'version': '0.2.106+414',
          'at': downloaded.millisecondsSinceEpoch,
        }),
        'install_info_first_seen': jsonEncode({
          'version': '0.2.106+414',
          'at': firstSeen.millisecondsSinceEpoch,
        }),
        'update_pending_download': '{"downloadId":3,"version":"0.2.107+500"}',
        'update_downloaded_version': '0.2.107+500',
        'update_downloaded_apk': '{"version":"0.2.107+500","path":"/x.apk"}',
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs, version: '0.2.106', build: 414);

      final store = SharedPreferencesUpdateStore(prefs);
      final c = UpdateController(
        config: AppUpdates.config(UpdatesApp.todo,
            version: '0.2.106', build: 414),
        store: store,
        http: github.http,
        downloader: downloader,
        platform: UpdatePlatform(supported: false),
      );
      addTearDown(c.dispose);
      await c.init();
      expect(c.lastCheck, checked);
      expect(c.downloaded.value?.key, '0.2.106+414');
      expect(c.downloaded.value?.label, '0.2.106 (414)');
      expect(c.downloaded.value?.at, downloaded);
      expect(c.isRunning(c.downloaded.value!.key), isTrue,
          reason: 'the card shows "Downloaded …" for the running build');
      expect(c.installedAt.value, firstSeen);
      for (final key in AppUpdates.legacyKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    });

    test("another build's first start isn't this one's install time",
        () async {
      SharedPreferences.setMockInitialValues({
        'install_info_first_seen': jsonEncode({
          'version': '0.2.105+400',
          'at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs, version: '0.2.106', build: 414);
      expect(prefs.getString(UpdateController.installedAtKey), isNull);
      expect(prefs.containsKey('install_info_first_seen'), isFalse);
    });

    test("the package's own records are never overwritten", () async {
      SharedPreferences.setMockInitialValues({
        'update_last_checked': DateTime(2020).millisecondsSinceEpoch,
        UpdateController.lastCheckKey: '2026-10-12T10:00:00.000',
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs, version: '1.0.0', build: 1);
      expect(prefs.getString(UpdateController.lastCheckKey),
          '2026-10-12T10:00:00.000');
    });

    test('garbage in the old keys is dropped, not fatal', () async {
      SharedPreferences.setMockInitialValues({
        'update_last_download': 'not json',
        'install_info_first_seen': '[1,2]',
      });
      final prefs = await SharedPreferences.getInstance();
      await AppUpdates.migrateLegacyState(prefs, version: '1.0.0', build: 1);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  test('create() builds the running app from its version and prefs',
      () async {
    PackageInfo.setMockInitialValues(
      appName: 'BestToDo',
      packageName: 'com.mfficiency.best_todo_2',
      version: '0.2.106',
      buildNumber: '3566146',
      buildSignature: '',
    );
    Config.resetVersionForTest();
    SharedPreferences.setMockInitialValues({
      'update_last_checked': DateTime(2026, 10, 11).millisecondsSinceEpoch,
    });
    final c = await AppUpdates.create(UpdatesApp.todo,
        http: github.http, downloader: downloader);
    expect(AppUpdates.controller, same(c));
    expect(c.config.version, '0.2.106');
    expect(c.config.build, 3566146);
    expect(c.config.tagPrefix, 'v');
    expect(c.lastCheck, DateTime(2026, 10, 11));
    Config.resetVersionForTest();
  });

  test(
      'everything is backed up to Download/BestToDo/Backups before '
      "Android's installer opens", () async {
    final dir = await Directory.systemTemp.createTemp('full_backup');
    addTearDown(() => dir.delete(recursive: true));
    final docs = Directory('${dir.path}/docs')..createSync();
    File('${docs.path}/tasks.json').writeAsStringSync('[{"title":"keep"}]');
    File('${docs.path}/attachments/a1/photo.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('jpeg bytes');
    File('${docs.path}/${PreUpdateBackup.backupDirName}/tasks.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('old copy');
    SharedPreferences.setMockInitialValues({'intro_shown': true});
    var scratches = 0;
    final backup = await AppUpdates.createBackup(
      prefs: await SharedPreferences.getInstance(),
      platform: UpdatePlatform(supported: true),
      roots: () async => {'documents': docs.path},
      scratch: (name) async =>
          (Directory('${dir.path}/scratch${scratches++}')..createSync()).path,
    );
    addTearDown(() => AppUpdates.backup = null);
    expect(AppUpdates.backup, same(backup));
    expect(backup.folder, 'Download/BestToDo/Backups');
    expect(backup.looksFresh, isFalse);

    github.releases = [release('v0.2.107-2000')];
    final c = fakeController(
        github: github, downloader: downloader, build: 1, backup: backup);
    await c.init();
    await c.check();
    await settle();
    for (var i = 0; i < 100 && installer.installs.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(installer.installs, ['/cache/updates/BestToDo-0.2.107-2000.apk']);
    // The backup was handed to Downloads before the installer was called.
    final methods = installer.calls.map((c) => c.method).toList();
    expect(methods.indexOf('saveToDownloads'),
        lessThan(methods.indexOf('installApk')));
    expect(installer.downloads.keys.single,
        startsWith('Download/BestToDo/Backups/BestToDo-'));
    final tar = utf8.decode(gzip.decode(installer.downloads.values.single),
        allowMalformed: true);
    expect(tar, contains('[{"title":"keep"}]'));
    expect(tar, contains('jpeg bytes'));
    expect(tar, contains('intro_shown'));
    expect(tar, isNot(contains('old copy')));
    expect(backup.last.value?.reason, 'before-update');
  });

  test("Android's dialog waits while BestToDo's intro is open", () async {
    AppUpdates.promptAllowed.value = false;
    github.releases = [release('v0.2.107-2000')];
    final c = fakeController(github: github, downloader: downloader, build: 1);
    await c.init();
    await c.check();
    await settle();
    expect(c.ready.value, '0.2.107+2000');
    expect(installer.installs, isEmpty);

    AppUpdates.promptAllowed.value = true;
    for (var i = 0; i < 50 && installer.installs.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(installer.installs, ['/cache/updates/BestToDo-0.2.107-2000.apk']);
  });
}
