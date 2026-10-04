import 'package:besttodo/config.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/media_volume.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/volume_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// No app volume: the phone's own media volume is remembered separately
/// for music and for videos and switched when playback goes between them
/// (SPEC.md §10.6m). Only the video boost lives in the app.
void main() {
  /// The phone's media volume, and what the app set it to.
  late double phone;
  late List<(double, bool)> sets;

  setUp(() {
    Config.musicPhoneVolume = null;
    Config.videoPhoneVolume = null;
    Config.phoneVolumeKind = '';
    YoutubeFeedService.instance.settings.value = const YoutubeFeedSettings();
    phone = 0.5;
    sets = [];
    MediaVolume.getOverride = () async => phone;
    MediaVolume.setOverride = (v, {bool showUi = false}) async {
      phone = v;
      sets.add((v, showUi));
    };
  });

  tearDown(() {
    MediaVolume.getOverride = null;
    MediaVolume.setOverride = null;
    Config.musicPhoneVolume = null;
    Config.videoPhoneVolume = null;
    Config.phoneVolumeKind = '';
  });

  test('switching between music and videos swaps the phone volume', () async {
    phone = 0.3;
    await MediaVolume.onPlaying(VolumeKind.music);
    expect(sets, isEmpty); // the first track leaves the phone alone
    expect(Config.phoneVolumeKind, 'music');

    await MediaVolume.onPlaying(VolumeKind.video);
    expect(Config.musicPhoneVolume, 0.3);
    expect(sets, isEmpty); // nothing remembered for videos yet

    phone = 0.8; // turned up with the volume buttons during the video
    await MediaVolume.onPlaying(VolumeKind.video); // next video: no change
    expect(sets, isEmpty);

    await MediaVolume.onPlaying(VolumeKind.music);
    expect(Config.videoPhoneVolume, 0.8);
    expect(sets, [(0.3, true)]);
    expect(phone, 0.3);

    phone = 0.25; // turned down a little for music
    await MediaVolume.onPlaying(VolumeKind.video);
    expect(Config.musicPhoneVolume, 0.25);
    expect(phone, 0.8);
  });

  test('the sheet changes the phone only for what is playing', () async {
    Config.phoneVolumeKind = 'music';
    await MediaVolume.choose(VolumeKind.music, 0.4, persist: false);
    expect(phone, 0.4);
    expect(Config.musicPhoneVolume, 0.4);

    await MediaVolume.choose(VolumeKind.video, 0.9, persist: false);
    expect(phone, 0.4); // music still playing at its own level
    expect(Config.videoPhoneVolume, 0.9);
    expect(await MediaVolume.current(VolumeKind.video), 0.9);
    expect(await MediaVolume.current(VolumeKind.music), 0.4);
  });

  test('videoBoostDb round-trips and clamps; old app volumes are ignored', () {
    const settings = YoutubeFeedSettings(videoBoostDb: 6);
    final back = YoutubeFeedSettings.fromJson(settings.toJson());
    expect(back.videoBoostDb, 6);
    expect(settings.toJson().containsKey('videoVolume'), isFalse);

    final wild =
        YoutubeFeedSettings.fromJson({'videoVolume': 0.2, 'videoBoostDb': 99});
    expect(wild.videoBoostDb, YoutubeFeedSettings.maxBoostDb);

    final old = YoutubeFeedSettings.fromJson({});
    expect(old.videoBoostDb, 0.0);
  });

  testWidgets('the music sheet shows and moves the phone volume',
      (tester) async {
    Config.phoneVolumeKind = 'music';
    phone = 0.4;
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VolumeSheet(video: false))));
    await tester.pump();
    expect(find.text('Music volume'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.byKey(const ValueKey('boostSlider')), findsNothing);

    await tester.drag(
        find.byKey(const ValueKey('volumeSlider')), const Offset(-2000, 0));
    await tester.pump();

    expect(phone, 0.0);
    expect(Config.musicPhoneVolume, 0.0);
    expect(Config.videoPhoneVolume, isNull);
  });

  testWidgets('the video sheet while music plays only remembers its level',
      (tester) async {
    Config.phoneVolumeKind = 'music';
    phone = 0.4;
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VolumeSheet(video: true))));
    await tester.pump();
    expect(find.text('Video volume'), findsOneWidget);

    await tester.drag(
        find.byKey(const ValueKey('volumeSlider')), const Offset(2000, 0));
    await tester.pump();

    expect(Config.videoPhoneVolume, 1.0);
    expect(phone, 0.4);
    expect(sets, isEmpty);
  });

  test('labels', () {
    expect(formatVolume(0.55), '55%');
    expect(formatBoost(0), 'Off');
    expect(formatBoost(6), '+6 dB');
    expect(describeRememberedVolume(VolumeKind.music), 'Not remembered yet');
    Config.musicPhoneVolume = 0.3;
    expect(describeRememberedVolume(VolumeKind.music), '30%');
  });
}
