import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory docs;
  late Directory support;
  late Directory downloads;
  late List<MethodCall> calls;
  String appId = 'ch.example.app';
  String? picked;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mfb');
    docs = Directory('${tmp.path}/docs')..createSync();
    support = Directory('${tmp.path}/support')..createSync();
    downloads = Directory('${tmp.path}/Download')..createSync();
    calls = [];
    appId = 'ch.example.app';
    picked = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(UpdatePlatform.channelName), (call) async {
      calls.add(call);
      switch (call.method) {
        case 'appId':
          return appId;
        case 'saveToDownloads':
          final args = call.arguments as Map;
          final dir = Directory('${downloads.path}/${args['folder']}')..createSync(recursive: true);
          File(args['path'] as String).copySync('${dir.path}/${args['name']}');
          return 'Download/${args['folder']}/${args['name']}';
        case 'pickFile':
          return picked;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(UpdatePlatform.channelName), null);
    tmp.deleteSync(recursive: true);
  });

  var tick = 0;
  Future<FullBackup> make({
    Set<String> excluded = const {},
    Map<String, FullBackupExtra> extras = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final b = FullBackup(
      config: FullBackupConfig(appName: 'My App', excluded: excluded, extras: extras),
      version: '1.2.3',
      build: 42,
      prefs: prefs,
      platform: UpdatePlatform(supported: true),
      roots: () async => {'documents': docs.path, 'support': support.path},
      scratch: (name) async {
        final d = Directory('${tmp.path}/cache/$name');
        if (d.existsSync()) d.deleteSync(recursive: true);
        return (d..createSync(recursive: true)).path;
      },
      clock: () => DateTime(2026, 10, 23, 18, 0, tick++),
    );
    await b.init();
    return b;
  }

  File backupFile(FullBackupRecord r) => File('${tmp.path}/${r.location}');

  test('backs up every file and preference, restores them exactly', () async {
    SharedPreferences.setMockInitialValues({
      'flag': true,
      'count': 7,
      'ratio': 0.5,
      'name': 'tasks',
      'list': ['a', 'b'],
      'state.updates.lastCheck': 'keep-me',
    });
    File('${docs.path}/tasks.json').writeAsStringSync('{"tasks":[1,2,3]}');
    final deep = 'attachments/${'very_long_folder_name_' * 6}/photo.jpg';
    File('${docs.path}/$deep')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.generate(70000, (i) => i % 251));
    File('${support.path}/settings.json').writeAsStringSync('{"theme":"dark"}');
    File('${docs.path}/pre_update_backup/old.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');

    final b = await make(excluded: {'pre_update_backup'});
    final r = await b.backupNow();
    expect(r.files, 3);
    expect(r.location, startsWith('Download/My App/Backups/My_App-20261023-180000-1.2.3+42'));
    expect(backupFile(r).existsSync(), isTrue);
    expect(b.last.value?.location, r.location);

    // Everything changes afterwards.
    File('${docs.path}/tasks.json').writeAsStringSync('{"tasks":[]}');
    File('${docs.path}/$deep').deleteSync();
    File('${docs.path}/new.json').writeAsStringSync('new');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flag', false);
    await prefs.setString('added', 'x');
    await prefs.setString('state.updates.lastCheck', 'newer');

    picked = backupFile(r).path;
    expect(await b.restoreFromPicker(), FullBackupRestore.restored);

    expect(File('${docs.path}/tasks.json').readAsStringSync(), '{"tasks":[1,2,3]}');
    expect(File('${docs.path}/$deep').readAsBytesSync(), List.generate(70000, (i) => i % 251));
    expect(File('${docs.path}/new.json').existsSync(), isFalse);
    expect(File('${docs.path}/pre_update_backup/old.json').readAsStringSync(), 'old');
    expect(File('${support.path}/settings.json').readAsStringSync(), '{"theme":"dark"}');
    expect(prefs.getBool('flag'), isTrue);
    expect(prefs.getInt('count'), 7);
    expect(prefs.getDouble('ratio'), 0.5);
    expect(prefs.getStringList('list'), ['a', 'b']);
    expect(prefs.containsKey('added'), isFalse);
    expect(prefs.getString('state.updates.lastCheck'), 'newer');

    // The data before the restore was saved first.
    final saved = downloads.listSync(recursive: true).whereType<File>().toList();
    expect(saved, hasLength(2));
  });

  test('extras go along', () async {
    SharedPreferences.setMockInitialValues({});
    Object? store = {'listings': 3};
    final extras = {
      'async_prefs': FullBackupExtra(
        export: () async => store,
        restore: (data) async => store = data,
      ),
    };
    final b = await make(extras: extras);
    final r = await b.backupNow();
    store = null;
    expect(await b.restoreFile(backupFile(r).path), FullBackupRestore.restored);
    expect(store, {'listings': 3});
  });

  test('refuses other files and other apps', () async {
    SharedPreferences.setMockInitialValues({'k': 'v'});
    File('${docs.path}/a.json').writeAsStringSync('a');
    final b = await make();
    final junk = File('${tmp.path}/junk.tar.gz')..writeAsBytesSync(gzip.encode(utf8.encode('nope')));
    expect(await b.restoreFile(junk.path), FullBackupRestore.notABackup);

    final r = await b.backupNow();
    appId = 'ch.example.other';
    expect(await b.restoreFile(backupFile(r).path), FullBackupRestore.otherApp);
    expect(File('${docs.path}/a.json').readAsStringSync(), 'a');

    picked = null;
    expect(await b.restoreFromPicker(), FullBackupRestore.cancelled);
  });

  test('a new install offers a restore once; a used one never', () async {
    SharedPreferences.setMockInitialValues({'state.updates.lastCheck': 'x'});
    expect((await make()).looksFresh, isTrue);
    SharedPreferences.setMockInitialValues({'tasks': 'x'});
    expect((await make()).looksFresh, isFalse);
    SharedPreferences.setMockInitialValues({FullBackup.offeredKey: true});
    expect((await make()).looksFresh, isFalse);
    // Data only in files (no preferences) is a used install too.
    SharedPreferences.setMockInitialValues({});
    File('${docs.path}/tasks.json').writeAsStringSync('[]');
    expect((await make()).looksFresh, isFalse);
    File('${docs.path}/tasks.json').deleteSync();
    expect((await make()).looksFresh, isTrue);
    // Excluded folders don't count (an early log isn't data).
    Directory('${support.path}/logs').createSync();
    File('${support.path}/logs/app.log').writeAsStringSync('x');
    expect((await make(excluded: {'logs'})).looksFresh, isTrue);
    expect((await make()).looksFresh, isFalse);
  });

  test('beforeUpdate writes a backup', () async {
    SharedPreferences.setMockInitialValues({});
    final b = await make();
    await b.beforeUpdate(const UpdateResult(UpdateStatus.available, version: '2.0.0', build: 50), 'x.apk');
    expect(b.last.value?.reason, 'before-update');
  });
}
