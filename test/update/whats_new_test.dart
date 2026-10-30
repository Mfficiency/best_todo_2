import 'package:besttodo/config.dart';
import 'package:besttodo/ui/whats_new_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _changelog = '''
# Changelog

## [0.2.140] - 2026-11-02
- Newest change.
- Local build: 2026-11-02 10:00

## [0.2.139] - 2026-11-01
- Middle change with **bold** text.

## [0.2.138] - 2026-10-31
- Change the user already had.
''';

/// What's new after an update (Settings › Releases, on by default): the
/// changelog entries since the version the user had before, once.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    WhatsNew.resetForTest();
  });

  tearDown(() {
    Config.whatsNewEnabled = true;
    WhatsNew.resetForTest();
  });

  Future<List<String>> versionsShown({
    String? stored,
    String? legacy,
    String current = '0.2.140',
  }) async {
    if (stored != null) await prefs.setString(WhatsNew.lastVersionKey, stored);
    final releases = await WhatsNew.prepare(
      prefs: prefs,
      current: current,
      loadChangelog: () async => _changelog,
      legacyVersion: () async => legacy,
    );
    return [for (final r in releases) r.version];
  }

  test('on by default', () {
    expect(Config.whatsNewEnabled, isTrue);
    expect(Config.toMap()['whatsNewEnabled'], isTrue);
  });

  test('after an update: the releases since the version before, newest first',
      () async {
    expect(await versionsShown(stored: '0.2.138'), ['0.2.140', '0.2.139']);
    expect(prefs.getString(WhatsNew.lastVersionKey), '0.2.140');
  });

  test('build-time notes are left out', () async {
    final releases = await WhatsNew.prepare(
      prefs: prefs..setString(WhatsNew.lastVersionKey, '0.2.139'),
      current: '0.2.140',
      loadChangelog: () async => _changelog,
      legacyVersion: () async => null,
    );
    expect(releases.single.entries, ['Newest change.']);
  });

  test('installs from before the sheet: the data files\' version marker',
      () async {
    expect(await versionsShown(legacy: '0.2.139+445'), ['0.2.140']);
  });

  test('once per update', () async {
    expect(await versionsShown(stored: '0.2.138'), isNotEmpty);
    WhatsNew.resetForTest();
    expect(await versionsShown(), isEmpty);
  });

  test('a fresh install shows nothing', () async {
    expect(await versionsShown(), isEmpty);
    expect(prefs.getString(WhatsNew.lastVersionKey), '0.2.140');
  });

  test('not shown when turned off (and not saved up for later)', () async {
    Config.whatsNewEnabled = false;
    expect(await versionsShown(stored: '0.2.138'), isEmpty);
    expect(prefs.getString(WhatsNew.lastVersionKey), '0.2.140');
  });

  test('compareVersions is numeric and ignores the build', () {
    expect(compareVersions('0.2.10', '0.2.9'), 1);
    expect(compareVersions('0.2.137+445', '0.2.137'), 0);
    expect(compareVersions('0.2.136', '0.2.137'), -1);
  });

  testWidgets('the sheet lists the new entries', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => WhatsNew.show(context),
          child: const Text('open'),
        ),
      ),
    ));
    // Not in a real-async zone: show() awaits this in the test's zone.
    await prefs.setString(WhatsNew.lastVersionKey, '0.2.138');
    await WhatsNew.prepare(
      prefs: prefs,
      current: '0.2.140',
      loadChangelog: () async => _changelog,
      legacyVersion: () async => null,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('Updated to version 0.2.140'), findsOneWidget);
    expect(find.text('0.2.139'), findsOneWidget);
    expect(find.text('Newest change.'), findsOneWidget);
    expect(find.text('Change the user already had.'), findsNothing);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsNothing);

    // Once: a second call shows nothing.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsNothing);
  });

  testWidgets('turned off: no sheet', (tester) async {
    Config.whatsNewEnabled = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => WhatsNew.show(context),
          child: const Text('open'),
        ),
      ),
    ));
    // Not in a real-async zone: show() awaits this in the test's zone.
    await prefs.setString(WhatsNew.lastVersionKey, '0.2.138');
    await WhatsNew.prepare(
      prefs: prefs,
      current: '0.2.140',
      loadChangelog: () async => _changelog,
      legacyVersion: () async => null,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsNothing);
  });
}
