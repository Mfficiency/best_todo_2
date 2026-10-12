import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the wiring that makes a **Best Music** release build produce
/// `best_music_<MUSIC_VERSION>.apk` (SPEC.md §10.6f/§10.6i).
///
/// This is file-content checking rather than behaviour testing, which is
/// normally a smell — it earns its place because the bug it guards against was
/// *silent*: the music build exited 0, printed nothing alarming, and simply
/// never produced a `best_music_` APK, so nothing downstream had anything to
/// stage. Nobody noticed until an APK was looked for by name. CI never caught
/// it either, because every CI job starts from a clean checkout and the bug
/// only fires when an earlier build's output is still lying around.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path should exist');
    return file.readAsStringSync();
  }

  group('android/app/build.gradle.kts APK rename', () {
    late String gradle;

    setUp(() => gradle = read('android/app/build.gradle.kts'));

    test('registers one rename task per flavor, wired to that flavor', () {
      // The rename must learn the flavor from the task that triggered it.
      expect(gradle, contains(r'createVersioned${capitalized}ReleaseApk'));
      expect(gradle, contains(r'assemble${capitalized}Release'));
    });

    test('does not infer the built flavor from leftover output files', () {
      // The regression: a single shared task looped over the flavors and took
      // the first `app-<flavor>-release.apk` that existed on disk. Since
      // build/app/outputs/flutter-apk/ is never cleaned between builds, a
      // music build matched the previous BestToDo build's leftover and
      // re-copied *that* as best_todo_<pubspec version>.apk, emitting no
      // best_music APK at all.
      expect(
        gradle,
        isNot(contains('for ((flavor, apkPrefix) in flavorPrefixes)')),
        reason: 'the flavor must not be sniffed from whichever '
            'app-<flavor>-release.apk happens to exist',
      );
    });

    test('names a music APK from MUSIC_VERSION, not pubspec.yaml', () {
      expect(gradle, contains('musicVersionFull'));
      expect(gradle, contains('MUSIC_VERSION'));
      expect(gradle, contains('"music" to "best_music"'));
    });
  });

  group('tool/build.ps1 flavor parity with tool/build.sh', () {
    late String ps1;

    setUp(() => ps1 = read('tool/build.ps1'));

    test('offers the music-apk shorthand with the music entrypoint', () {
      expect(ps1, contains('music-apk'));
      expect(ps1, contains('lib/main_music.dart'));
    });

    test('defaults an apk build to the todo flavor', () {
      // `flutter build apk` fails outright once flavorDimensions is set, so a
      // caller that passes no --flavor has to be given one.
      expect(ps1, contains('Get-FlavorArg'));
      expect(ps1, contains('"--flavor", "todo"'));
    });

    test('reads Best Music version from MUSIC_VERSION', () {
      expect(ps1, contains('Get-MusicVersion'));
      expect(ps1, contains('MUSIC_VERSION'));
    });

    test('stages with the per-app prefix and version', () {
      expect(ps1, contains(r'"best_$appFlavor"'));
      expect(ps1, contains('"--prefix", \$prefix, "--version", \$version'));
    });

    test('records a music build in its own changelog', () {
      expect(ps1, contains('"--app", "music"'));
    });

    test('keeps publish_apk.dart BestToDo-only', () {
      // Best Music's update check never reads GitHub releases, so publishing
      // there would mislabel Music's bytes as a BestToDo release.
      expect(ps1, contains(r'$appFlavor -ne "music"'));
    });
  });

  group('`all` builds everything this project ships', () {
    test('tool/build_all.sh includes the Best Music APK', () {
      final sh = read('tool/build_all.sh');
      expect(sh, contains('music-apk'));
      expect(sh, contains(r'$MUSIC'));
      expect(sh, contains('CHANGELOG_MUSIC.md'));
    });

    test('tool/build.ps1 all includes the Best Music APK', () {
      final ps1 = read('tool/build.ps1');
      expect(ps1, contains(r'$env:MUSIC -ne "0"'));
      expect(ps1, contains('CHANGELOG_MUSIC.md'));
    });
  });

  group('Best Music share-sheet entry', () {
    test('the music flavor replaces ShareActivity with a text-only one', () {
      // Shared Spotify/Shazam/YouTube links reach Best Music through the same
      // ShareActivity trampoline as BestToDo; the music flavor's manifest
      // overlay narrows it to text so Best Music isn't offered for photos
      // and PDFs it can't do anything with (lib/main_music.dart).
      final manifest = read('android/app/src/music/AndroidManifest.xml');
      expect(manifest, contains('ShareActivity'));
      expect(manifest, contains('tools:node="replace"'));
      expect(manifest, contains('text/plain'));
      expect(manifest, isNot(contains('image/')));
      expect(manifest, isNot(contains('application/pdf')));
    });
  });

  /// Laptop channel builds (SPEC.md §11): dev/staging/main build the SAME
  /// app (one id, one name) and a published build is never debug-signed.
  group('channel builds', () {
    test('Gradle: one id and label for every channel, versionCode from env',
        () {
      final gradle = read('android/app/build.gradle.kts');
      expect(gradle, contains('System.getenv("BUILD_CHANNEL")'));
      expect(gradle, isNot(contains('applicationIdSuffix')));
      expect(gradle, isNot(contains('channelLabelSuffix')));
      expect(gradle, contains('manifestPlaceholders["appLabel"] = "BestToDo"'));
      expect(gradle, contains('manifestPlaceholders["appLabel"] = "Best Music"'));
      expect(gradle, contains('applicationId = "com.mfficiency.best_music"'));
      expect(gradle, contains('System.getenv("BUILD_NUMBER")'));
      expect(gradle, contains('REQUIRE_RELEASE_KEY'));
    });

    test('build.ps1 release uses BUILD_NUMBER as is', () {
      // The builder already numbers the source commit below any APK
      // commits (minutes since 2020), so no commit-count adjustment.
      final ps1 = read('tool/build.ps1');
      expect(ps1, isNot(contains('rev-list --count')));
      expect(ps1, contains('--build-number=\$buildNumber'));
    });

    test('the manifest label comes from Gradle', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains(r'android:label="${appLabel}"'));
    });

    test('in-app updates are the plugin\'s: no installer code of the app',
        () {
      // The mfficiency_updates plugin brings REQUEST_INSTALL_PACKAGES, its
      // install receiver and the `mfficiency_updates` channel; both apps
      // register it through Flutter's GeneratedPluginRegistrant.
      expect(read('pubspec.yaml'),
          contains('mfficiency_updates:\n    path: packages/mfficiency_updates'));
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      for (final gone in [
        'InstallReceiver',
        'REQUEST_INSTALL_PACKAGES',
        'DOWNLOAD_WITHOUT_NOTIFICATION',
        'fileprovider',
      ]) {
        expect(manifest, isNot(contains(gone)), reason: gone);
      }
      const kotlin = 'android/app/src/main/kotlin/com/example/best_todo_2';
      expect(File('$kotlin/ApkInstaller.kt').existsSync(), isFalse);
      final activity = read('$kotlin/MainActivity.kt');
      expect(activity, isNot(contains('besttodo/update')));
      expect(activity, isNot(contains('DownloadManager')));
    });

    test('build.ps1 release builds both apps and refuses the debug key', () {
      final ps1 = read('tool/build.ps1');
      expect(ps1, contains('Invoke-ChannelRelease'));
      expect(ps1, contains('android/key.properties'));
      expect(ps1, contains(r'$env:REQUIRE_RELEASE_KEY = "1"'));
      expect(ps1, contains('--dart-define=BUILD_CHANNEL='));
      expect(ps1, contains('lib/main_music.dart'));
      expect(ps1, contains('--exists'));
    });
  });
}
