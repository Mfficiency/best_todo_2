import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the platform wiring that keeps BestToDo/Best Music to ONE running
/// copy. File-content checks because the behaviour lives in the Android
/// manifest and the Windows runner, which unit tests can't launch — and a
/// regression (back to singleTop + taskAffinity="") is silent until a
/// notification/widget/share launch opens a second copy on a real phone.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('Android MainActivity is singleTask with the default task affinity',
      () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final start = manifest.indexOf('android:name=".MainActivity"');
    expect(start, isNonNegative);
    final activity =
        manifest.substring(start, manifest.indexOf('>', start));

    expect(activity, contains('android:launchMode="singleTask"'));
    expect(activity, isNot(contains('android:taskAffinity=""')));
  });

  test('Windows runner refuses a second instance and fronts the first', () {
    final main = read('windows/runner/main.cpp');

    expect(main, contains('CreateMutexW'));
    expect(main, contains('ERROR_ALREADY_EXISTS'));
    expect(main, contains('SetForegroundWindow'));
  });
}
