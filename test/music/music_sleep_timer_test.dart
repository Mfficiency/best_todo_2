import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/main_music.dart';
import 'package:besttodo/services/music_sleep_timer.dart';
import 'package:besttodo/ui/music_settings_page.dart';
import 'package:besttodo/ui/music_theme.dart';
import 'package:besttodo/ui/sleep_timer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  final timer = MusicSleepTimer.instance;
  late Directory tempDir;
  var pauses = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    pauses = 0;
    timer.pausePlayback = () async => pauses++;
    timer.cancel();
    Config.darkMode = false;
    MusicTheme.darkMode.value = false;
  });

  tearDown(() async {
    timer.cancel();
    await tempDir.delete(recursive: true);
  });

  group('MusicSleepTimer', () {
    // testWidgets for its fake clock: tester.pump(d) advances timers.
    testWidgets('pauses playback once the time is up, then switches itself off',
        (tester) async {
      timer.start(const Duration(minutes: 30));
      expect(timer.state.value.isActive, isTrue);

      await tester.pump(const Duration(minutes: 29));
      expect(pauses, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(pauses, 1);
      expect(timer.state.value.isActive, isFalse);
    });

    testWidgets('extend pushes the end back; cancel stops it firing',
        (tester) async {
      timer.start(const Duration(minutes: 10));
      timer.extend(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 15));
      expect(pauses, 0);
      timer.cancel();
      await tester.pump(const Duration(minutes: 30));
      expect(pauses, 0);
    });

    test('end-of-song mode is used up by the first finished song', () {
      expect(timer.consumeEndOfTrack(), isFalse);
      timer.startEndOfTrack();
      expect(timer.state.value.endOfTrack, isTrue);
      expect(timer.consumeEndOfTrack(), isTrue);
      expect(timer.state.value.isActive, isFalse);
      expect(timer.consumeEndOfTrack(), isFalse);
    });

    test('describe reads as minutes, hours or end of song', () {
      final now = DateTime(2026, 1, 1, 22);
      expect(
          MusicSleepTimer.describe(
              SleepTimerState.at(now.add(const Duration(minutes: 23))),
              now: now),
          '23 min');
      expect(
          MusicSleepTimer.describe(
              SleepTimerState.at(now.add(const Duration(minutes: 65))),
              now: now),
          '1 h 5 min');
      expect(MusicSleepTimer.describe(const SleepTimerState.endOfTrack()),
          'End of song');
      expect(MusicSleepTimer.describe(const SleepTimerState.off()), 'Off');
    });
  });

  testWidgets('the sleep timer button opens the picker and sets a timer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [SleepTimerButton()]))));

    await tester.tap(find.byTooltip('Sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();

    expect(timer.state.value.endsAt, isNotNull);
    expect(find.byTooltip('Sleep timer: 30 min'), findsOneWidget);

    await tester.tap(find.byTooltip('Sleep timer: 30 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off sleep timer'));
    await tester.pumpAndSettle();
    expect(timer.state.value.isActive, isFalse);
  });

  testWidgets('Settings offers dark mode and the sleep timer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();

    expect(find.text('Sleep timer'), findsOneWidget);
    await tester.ensureVisible(find.text('Dark mode'));
    await tester.tap(find.text('Dark mode'));
    await tester.pump();
    expect(MusicTheme.darkMode.value, isTrue);
    expect(Config.darkMode, isTrue);
  });

  testWidgets('Best Music uses BestToDo\'s blue and follows the dark mode switch',
      (tester) async {
    await tester.pumpWidget(const BestMusicApp());
    await tester.pumpAndSettle();
    BuildContext ctx() => tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx()).colorScheme.primary, musicSeedColor);
    expect(Theme.of(ctx()).brightness, Brightness.light);

    MusicTheme.darkMode.value = true;
    await tester.pumpAndSettle();
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    MusicTheme.darkMode.value = false;
  });
}
