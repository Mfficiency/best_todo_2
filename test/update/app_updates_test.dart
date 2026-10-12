import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/services/pre_update_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_fakes.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// BestToDo's and Best Music's side of the updates package
/// (`lib/services/app_updates.dart`): which releases each app takes, the
/// "Automatically update" switch, the state stored before the package, the
/// pre-update backup before Android's installer opens and the held-back
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
    test('one public repo, a tag prefix per app, every 15 minutes', () {
      final todo =
          AppUpdates.config(UpdatesApp.todo, version: '0.2.106', build: 9);
      final music =
          AppUpdates.config(UpdatesApp.music, version: '0.3.27', build: 9);
      for (final c in [todo, music]) {
        expect(c.githubRepo, 'Mfficiency/best_todo_2');
        expect(c.privateRepo, isFalse, reason: 'no token: the repo is public');
        expect(c.pollInterval, const Duration(minutes: 15));
        expect(c.checkInterval, const Duration(minutes: 15));
        expect(c.includePrereleases(), isTrue,
            reason: 'dev/staging builds are prereleases of the same app');
      }
      expect(todo.tagPrefix, 'v');
      expect(todo.appName, 'BestToDo');
      expect(music.tagPrefix, 'music-v');
      expect(music.appName, 'Best Music');
    });

    test("BestToDo's automatic checks follow its switch; Best Music has none",
        () {
      final todo = AppUpdates.config(UpdatesApp.todo, version: '1', build: 1);
      final music =
          AppUpdates.config(UpdatesApp.music, version: '1', build: 1);
      expect(todo.autoCheck(), isTrue);
      Config.autoUpdateCheckEnabled = false;
      expect(todo.autoCheck(), isFalse);
      expect(music.autoCheck(), isTrue);
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
      expect(
          AppUpdates.config(UpdatesApp.music, version: '1', build: 1)
              .httpUserAgent,
          'BestMusic-update-check');
    });

    test("only BestToDo holds the install prompt back (its intro)", () {
      final todo = fakeController(github: github, downloader: downloader);
      expect(todo.promptAllowed, same(AppUpdates.promptAllowed));
      todo.dispose();
      final music = fakeController(
          app: UpdatesApp.music, github: github, downloader: downloader);
      expect(music.promptAllowed, isNull);
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

    test('Best Music takes only music-v tags, of every channel', () async {
      github.releases = [
        release('v9.9.9-9999999'),
        release('music-v0.3.27-3600050-dev', prerelease: true),
        release('music-v0.3.26-3600040'),
      ];
      final c = fakeController(
          app: UpdatesApp.music, github: github, downloader: downloader);
      expect((await c.check()).key, '0.3.27+3600050');
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
    final c = await AppUpdates.create(UpdatesApp.music,
        http: github.http, downloader: downloader);
    expect(AppUpdates.controller, same(c));
    expect(c.config.version, '0.2.106');
    expect(c.config.build, 3566146);
    expect(c.config.tagPrefix, 'music-v');
    expect(c.lastCheck, DateTime(2026, 10, 11));
    Config.resetVersionForTest();
  });

  test("BestToDo's data files are snapshotted before Android's installer opens",
      () async {
    final dir = await Directory.systemTemp.createTemp('pre_update');
    addTearDown(() => dir.delete(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    PreUpdateBackup.resetForTest();
    await File('${dir.path}/tasks.json').writeAsString('[{"title":"keep"}]');

    github.releases = [release('v0.2.107-2000')];
    final c = fakeController(
        github: github, downloader: downloader, build: 1, backup: true);
    await c.init();
    await c.check();
    await settle();
    for (var i = 0; i < 50 && installer.installs.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(installer.installs, ['/cache/updates/BestToDo-0.2.107-2000.apk']);
    final backup =
        File('${dir.path}/${PreUpdateBackup.backupDirName}/tasks.json');
    expect(await backup.readAsString(), '[{"title":"keep"}]');
    PreUpdateBackup.resetForTest();
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
