import 'package:besttodo/config.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/volume_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Config.musicVolume = 1.0;
    YoutubeFeedService.instance.settings.value = const YoutubeFeedSettings();
  });

  test('feed settings keep video volume and boost, clamped, across JSON', () {
    const settings = YoutubeFeedSettings(videoVolume: 0.9, videoBoostDb: 6);
    final back = YoutubeFeedSettings.fromJson(settings.toJson());
    expect(back.videoVolume, 0.9);
    expect(back.videoBoostDb, 6);
    expect(back.playbackSpeed, 1.0);

    final wild =
        YoutubeFeedSettings.fromJson({'videoVolume': 3, 'videoBoostDb': 99});
    expect(wild.videoVolume, 1.0);
    expect(wild.videoBoostDb, YoutubeFeedSettings.maxBoostDb);

    final old = YoutubeFeedSettings.fromJson({});
    expect(old.videoVolume, 1.0);
    expect(old.videoBoostDb, 0.0);
  });

  testWidgets('the music volume sheet changes only the music volume',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VolumeSheet(video: false))));
    expect(find.text('Music volume'), findsOneWidget);
    expect(find.byKey(const ValueKey('boostSlider')), findsNothing);

    await tester.drag(
        find.byKey(const ValueKey('volumeSlider')), const Offset(-2000, 0));
    await tester.pump();

    expect(Config.musicVolume, 0.0);
    expect(YoutubeFeedService.instance.settings.value.videoVolume, 1.0);
  });

  testWidgets('the video volume sheet changes only the video volume',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VolumeSheet(video: true))));
    expect(find.text('Video volume'), findsOneWidget);

    await tester.drag(
        find.byKey(const ValueKey('volumeSlider')), const Offset(-2000, 0));
    await tester.pump();

    expect(YoutubeFeedService.instance.settings.value.videoVolume, 0.0);
    expect(Config.musicVolume, 1.0);
  });

  test('labels', () {
    expect(formatVolume(0.55), '55%');
    expect(formatBoost(0), 'Off');
    expect(formatBoost(6), '+6 dB');
  });
}
