import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/config.dart';
import 'package:besttodo/ui/compass_page.dart';

String _reading(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('compass-reading'))).data!;

void main() {
  test('compassDirection maps degrees to the nearest of 8 points', () {
    expect(compassDirection(0), 'N');
    expect(compassDirection(359), 'N');
    expect(compassDirection(44), 'NE');
    expect(compassDirection(90), 'E');
    expect(compassDirection(200), 'S');
    expect(compassDirection(250), 'W');
    expect(compassDirection(-45), 'NW');
  });

  test('compass is a registered tool and feature', () {
    expect(Config.featureKeys, contains('compass'));
    expect(Config.startToolOptions, contains('compass'));
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });

  testWidgets('shows the live heading and Hold freezes it', (tester) async {
    final headings = StreamController<double>();
    await tester.pumpWidget(
        MaterialApp(home: CompassPage(headings: headings.stream)));
    expect(_reading(tester), '--°');

    headings.add(92);
    await tester.pump();
    expect(_reading(tester), '92° E');

    await tester.tap(find.text('Hold'));
    await tester.pump();
    headings.add(180);
    await tester.pump();
    expect(_reading(tester), '92° E');
    expect(find.text('Release'), findsOneWidget);

    await tester.tap(find.text('Release'));
    await tester.pump();
    headings.add(180);
    await tester.pump();
    expect(_reading(tester), '180° S');
    await headings.close();
  });

  testWidgets('says so when there is no compass sensor', (tester) async {
    final headings = StreamController<double>();
    await tester.pumpWidget(
        MaterialApp(home: CompassPage(headings: headings.stream)));
    headings.addError('no-sensor');
    await tester.pump();
    expect(find.text('No compass sensor on this device'), findsOneWidget);
    await headings.close();
  });
}
