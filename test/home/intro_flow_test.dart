import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/ui/intro_page.dart';
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
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    // Config is global state shared with the rest of the suite.
    Config.simpleMode = false;
    Config.modeChosen = false;
  });

  Future<void> advance(WidgetTester tester) async {
    // The mode handler awaits Config.save() before the callback, so walk fixed
    // rounds of the real event loop (see test/README.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('intro shows the slides and ends with the mode choice',
      (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: IntroPage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    // Slide one, then through the rest of the slides.
    expect(find.text('Privacy First'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Open Source & Fast'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Minimal Interactions'), findsOneWidget);

    // The last slide leads into the mode question instead of ending the intro.
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(finished, isFalse);
    expect(find.text('How do you want to use BestToDo?'), findsOneWidget);
    expect(find.text('Simple mode'), findsOneWidget);
    expect(find.text('Full mode'), findsOneWidget);
    // No button that would let the question be skipped.
    expect(find.text('Next'), findsNothing);
    expect(find.text('Get Started'), findsNothing);

    // The second card sits below the fold on a phone-sized test window.
    await tester.ensureVisible(find.text('Use everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use everything'));
    await advance(tester);

    expect(finished, isTrue);
    expect(Config.simpleMode, isFalse);
    expect(Config.modeChosen, isTrue);
  });

  testWidgets('picking simple mode from the intro persists it', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: IntroPage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    for (final label in ['Next', 'Next', 'Get Started']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Start simple'));
    await advance(tester);

    expect(finished, isTrue);
    Config.simpleMode = false;
    Config.modeChosen = false;
    await tester.runAsync(Config.load);
    expect(Config.simpleMode, isTrue);
    expect(Config.modeChosen, isTrue);
  });
}
