import 'package:besttodo/config.dart';
import 'package:besttodo/services/speaker_play_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool external;
  late bool playing;

  setUp(() {
    external = false;
    playing = false;
    Config.musicConfirmSpeakerPlay = true;
    SpeakerPlayGuard.externalOutputOverride = () async => external;
    SpeakerPlayGuard.isPlayingOverride = () => playing;
  });

  tearDown(() {
    SpeakerPlayGuard.externalOutputOverride = null;
    SpeakerPlayGuard.isPlayingOverride = null;
    Config.musicConfirmSpeakerPlay = true;
  });

  /// Pumps a button that runs [SpeakerPlayGuard.confirmPlay] and records the
  /// answer in the returned list.
  Future<List<bool>> pumpGuard(WidgetTester tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              answers.add(await SpeakerPlayGuard.confirmPlay(context)),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('phone speaker only, nothing playing: asks first',
      (tester) async {
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsOneWidget);
    expect(answers, isEmpty);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('Cancel keeps it quiet', (tester) async {
    final answers = await pumpGuard(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });

  testWidgets('a Bluetooth speaker/headphones connected: plays straight away',
      (tester) async {
    external = true;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });

  testWidgets('music already playing: never asks', (tester) async {
    playing = true;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });

  testWidgets('turned off in settings: never asks', (tester) async {
    Config.musicConfirmSpeakerPlay = false;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });
}
