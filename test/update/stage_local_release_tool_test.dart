import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/stage_local_release.dart' as tool;

/// `tool/stage_local_release.dart` keeps `github_releases/` at the newest two
/// APKs, which is what the About page's update + rollback buttons read. Pure
/// helpers are tested directly; the copy/prune round trip runs the tool's
/// `main` against a temp folder.
void main() {
  group('version ordering of APK file names', () {
    test('reads the numeric components, build number included', () {
      expect(tool.versionNumbers('best_todo_0.1.143+115.apk'),
          [0, 1, 143, 115]);
      expect(tool.versionNumbers('BestToDo-0.1.74+45.apk'), [0, 1, 74, 45]);
      expect(tool.versionNumbers('app-release.apk'), isEmpty);
    });

    test('orders by major/minor/patch then build', () {
      expect(
          tool.compareVersionedNames(
                  'best_todo_0.1.143+115.apk', 'best_todo_0.1.142+114.apk') >
              0,
          isTrue);
      expect(
          tool.compareVersionedNames(
                  'best_todo_0.2.0+1.apk', 'best_todo_0.1.999+999.apk') >
              0,
          isTrue);
      expect(
          tool.compareVersionedNames(
              'best_todo_0.1.1+1.apk', 'best_todo_0.1.1+1.apk'),
          0);
    });
  });

  group('namesToPrune', () {
    test('keeps the newest two and returns the rest oldest first', () {
      expect(
          tool.namesToPrune([
            'best_todo_0.1.143+115.apk',
            'best_todo_0.1.141+113.apk',
            'best_todo_0.1.145+117.apk',
            'best_todo_0.1.142+114.apk',
          ]),
          ['best_todo_0.1.141+113.apk', 'best_todo_0.1.142+114.apk']);
    });

    test('nothing to prune while the folder holds two or fewer', () {
      expect(tool.namesToPrune(['best_todo_0.1.143+115.apk']), isEmpty);
      expect(
          tool.namesToPrune(
              ['best_todo_0.1.143+115.apk', 'best_todo_0.1.142+114.apk']),
          isEmpty);
    });

    test('leaves non-APK files (the folder README) alone', () {
      final prune = tool.namesToPrune([
        'README.md',
        'best_todo_0.1.141+113.apk',
        'best_todo_0.1.142+114.apk',
        'best_todo_0.1.143+115.apk',
      ]);
      expect(prune, ['best_todo_0.1.141+113.apk']);
    });

    test('honours a different keep count', () {
      expect(
          tool.namesToPrune([
            'best_todo_0.1.143+115.apk',
            'best_todo_0.1.142+114.apk',
          ], keep: 1),
          ['best_todo_0.1.142+114.apk']);
    });
  });

  test('stagedNameFor matches the committed naming', () {
    expect(tool.stagedNameFor('0.1.143+115'), 'best_todo_0.1.143+115.apk');
  });

  group('main', () {
    late Directory temp;
    late String previousCwd;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('stage_release_test');
      previousCwd = Directory.current.path;
      Directory.current = temp;
      File('${temp.path}/pubspec.yaml')
          .writeAsStringSync('name: besttodo\nversion: 0.1.145+117\n');
    });

    tearDown(() {
      Directory.current = previousCwd;
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold the handle briefly; the temp dir is disposable.
      }
    });

    File apk(String path) {
      final file = File('${temp.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('apk bytes for $path');
      return file;
    }

    test('copies the build in and deletes the oldest kept APK', () async {
      apk('build/app/outputs/flutter-apk/best_todo_0.1.145+117.apk');
      final dir = Directory('${temp.path}/github_releases')
        ..createSync(recursive: true);
      File('${dir.path}/README.md').writeAsStringSync('kept releases');
      File('${dir.path}/best_todo_0.1.143+115.apk').writeAsStringSync('old');
      File('${dir.path}/best_todo_0.1.142+114.apk')
          .writeAsStringSync('older');

      await tool.main([]);

      final names = dir
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(names, [
        'README.md',
        'best_todo_0.1.143+115.apk',
        'best_todo_0.1.145+117.apk',
      ]);
      expect(File('${dir.path}/best_todo_0.1.145+117.apk').readAsStringSync(),
          contains('best_todo_0.1.145+117.apk'));
    });

    test('creates the folder on the first build and finds app-release.apk',
        () async {
      apk('build/app/outputs/flutter-apk/app-release.apk');

      await tool.main([]);

      expect(
          File('${temp.path}/github_releases/best_todo_0.1.145+117.apk')
              .existsSync(),
          isTrue);
    });

    test('a dry run reports without touching the folder', () async {
      apk('build/app/outputs/flutter-apk/best_todo_0.1.145+117.apk');
      final dir = Directory('${temp.path}/github_releases')
        ..createSync(recursive: true);
      File('${dir.path}/best_todo_0.1.143+115.apk').writeAsStringSync('old');
      File('${dir.path}/best_todo_0.1.142+114.apk')
          .writeAsStringSync('older');

      await tool.main(['--dry-run']);

      expect(dir.listSync().length, 2);
      expect(
          File('${dir.path}/best_todo_0.1.145+117.apk').existsSync(), isFalse);
    });

    test('missing APK fails instead of staging nothing silently', () async {
      await tool.main([]);

      expect(exitCode, 1);
      exitCode = 0;
      expect(Directory('${temp.path}/github_releases').existsSync(), isFalse);
    });
  });
}
