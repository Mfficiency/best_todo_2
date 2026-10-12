import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseLegacyVersion', () {
    expect(parseLegacyVersion('0.2.106+414'), (version: '0.2.106', build: 414));
    expect(
        parseLegacyVersion('v0.2.106-414'), (version: '0.2.106', build: 414));
    expect(parseLegacyVersion('0.1.19 (build 123) · dev'),
        (version: '0.1.19', build: 123));
    expect(parseLegacyVersion('1.0.0'), (version: '1.0.0', build: null));
    expect(parseLegacyVersion('nothing'), isNull);
  });

  test(
      'moves the old records once, never over the package\'s, and removes '
      'the old keys and files', () async {
    final apk =
        File('${(await Directory.systemTemp.createTemp('old')).path}/old.apk')
          ..writeAsStringSync('x');
    SharedPreferences.setMockInitialValues({
      'update_last_checked': DateTime(2026, 10, 1, 8).millisecondsSinceEpoch,
      'update_last_download': jsonEncode({
        'version': '0.2.106+414',
        'at': DateTime(2026, 10, 2, 9).millisecondsSinceEpoch,
      }),
      'update_apk': apk.path,
      // Already the package's: kept.
      UpdateController.installedAtKey: '2026-10-05T10:00:00.000',
      'install_first_seen': '2026-09-01T00:00:00.000',
    });
    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'update_last_checked',
      'update_last_download',
      'update_apk',
      'install_first_seen',
    ];
    LegacyUpdateRecords read(SharedPreferences p) {
      final d = jsonDecode(p.getString('update_last_download')!) as Map;
      final v = parseLegacyVersion('${d['version']}')!;
      return LegacyUpdateRecords(
        lastCheck: DateTime.fromMillisecondsSinceEpoch(
            p.getInt('update_last_checked')!),
        installedBuild: 414,
        installedAt: DateTime.parse(p.getString('install_first_seen')!),
        downloaded: (
          version: v.version,
          build: v.build,
          at: DateTime.fromMillisecondsSinceEpoch(d['at'] as int),
        ),
        files: [p.getString('update_apk')!],
      );
    }

    expect(
      await migrateLegacyUpdateState(prefs, legacyKeys: keys, read: read),
      isTrue,
    );
    expect(prefs.getString(UpdateController.lastCheckKey),
        '2026-10-01T08:00:00.000');
    expect(jsonDecode(prefs.getString(UpdateController.downloadedKey)!), {
      'key': '0.2.106+414',
      'label': '0.2.106 (414)',
      'at': '2026-10-02T09:00:00.000',
    });
    expect(prefs.getString(UpdateController.installedAtKey),
        '2026-10-05T10:00:00.000');
    expect(prefs.getInt(UpdateController.installedBuildKey), isNull);
    for (final k in keys) {
      expect(prefs.containsKey(k), isFalse, reason: k);
    }
    expect(apk.existsSync(), isFalse);

    // Once: nothing left to move.
    expect(
      await migrateLegacyUpdateState(prefs, legacyKeys: keys, read: read),
      isFalse,
    );

    // The controller reads what was moved.
    final c = UpdateController(
      config: const UpdateConfig(appName: 'A', version: '0.2.106', build: 414),
      store: SharedPreferencesUpdateStore(prefs),
      platform: UpdatePlatform(supported: false),
    );
    addTearDown(c.dispose);
    await c.init();
    expect(c.downloaded.value?.label, '0.2.106 (414)');
    expect(c.lastCheck, DateTime(2026, 10, 1, 8));
  });

  test('unreadable old state: the keys still go', () async {
    SharedPreferences.setMockInitialValues({'old.update': 'garbage'});
    final prefs = await SharedPreferences.getInstance();
    expect(
      await migrateLegacyUpdateState(
        prefs,
        legacyKeys: const ['old.update'],
        read: (p) => throw const FormatException(),
        deleteExternalUpdatesFolder: true,
      ),
      isTrue,
    );
    expect(prefs.getKeys(), isEmpty);
  });
}
