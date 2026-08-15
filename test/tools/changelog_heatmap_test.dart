import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/ui/changelog_page.dart';

const String _sampleChangelog = '''
# Changelog

## [0.2.0] - 2026-08-05
- Added the heatmap button
- Tapping a day shows its changes

## [0.1.9] - 2026-08-05
- Fixed a typo

## [0.1.8] - 2026-07-20
- Older change
''';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final String contents;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));
  }
}

Widget _wrap(String changelog) {
  return MaterialApp(
    home: DefaultAssetBundle(
      bundle: _FakeBundle(changelog),
      child: const ChangelogPage(),
    ),
  );
}

void main() {
  group('parseChangelogReleases', () {
    test('parses versions, dates and bullet entries', () {
      final releases = parseChangelogReleases(_sampleChangelog);
      expect(releases.length, 3);
      expect(releases.first.version, '0.2.0');
      expect(releases.first.date, DateTime(2026, 8, 5));
      expect(releases.first.entries, [
        'Added the heatmap button',
        'Tapping a day shows its changes',
      ]);
      expect(releases.last.version, '0.1.8');
      expect(releases.last.date, DateTime(2026, 7, 20));
    });

    test('ignores the title heading and undated headings', () {
      final releases = parseChangelogReleases(
        '# Changelog\n\n## Unreleased\n- floating note\n\n'
        '## [1.0.0] - 2026-01-02\n- real change\n',
      );
      expect(releases.length, 1);
      expect(releases.single.version, '1.0.0');
      expect(releases.single.entries, ['real change']);
    });

    test('joins wrapped continuation lines into the previous bullet', () {
      final releases = parseChangelogReleases(
        '## [1.0.0] - 2026-01-02\n- first line\n  second line\n',
      );
      expect(releases.single.entries, ['first line second line']);
    });

    test('returns nothing when no release has a parsable date', () {
      expect(parseChangelogReleases('# Changelog\n\n- stray bullet\n'), isEmpty);
    });
  });

  group('ChangelogPage heatmap', () {
    testWidgets('toggles between the markdown text and the heatmap',
        (tester) async {
      await tester.pumpWidget(_wrap(_sampleChangelog));
      await tester.pumpAndSettle();

      expect(find.text('Updates over time'), findsNothing);

      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();
      expect(find.text('Updates over time'), findsOneWidget);
      expect(find.textContaining('3 releases'), findsWidgets);

      await tester.tap(find.byTooltip('Show changelog text'));
      await tester.pumpAndSettle();
      expect(find.text('Updates over time'), findsNothing);
    });

    testWidgets('opens on the newest release day and lists its changes',
        (tester) async {
      await tester.pumpWidget(_wrap(_sampleChangelog));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();

      expect(find.text('2026-08-05'), findsOneWidget);
      expect(find.text('Version 0.2.0'), findsOneWidget);
      expect(find.text('Version 0.1.9'), findsOneWidget);
      expect(find.text('Added the heatmap button'), findsOneWidget);
      expect(find.text('Fixed a typo'), findsOneWidget);
      expect(find.text('Older change'), findsNothing);
    });

    testWidgets('tapping another day shows that day\'s changes',
        (tester) async {
      await tester.pumpWidget(_wrap(_sampleChangelog));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();

      final cell = find.byTooltip('2026-07-20: 1 release, 1 change');
      expect(cell, findsOneWidget);
      await tester.tap(cell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('2026-07-20'), findsOneWidget);
      expect(find.text('Version 0.1.8'), findsOneWidget);
      expect(find.text('Older change'), findsOneWidget);
      expect(find.text('Added the heatmap button'), findsNothing);
    });

    testWidgets('month labels carry the year on the first column and on a '
        'year switch', (tester) async {
      await tester.pumpWidget(_wrap('''
# Changelog

## [0.2.0] - 2026-01-05
- New year change

## [0.1.0] - 2025-12-01
- Old year change
'''));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();

      expect(find.text('Dec 2025'), findsOneWidget);
      expect(find.text('Jan 2026'), findsOneWidget);
      expect(find.text('Dec'), findsNothing);
      expect(find.text('Jan'), findsNothing);
    });

    testWidgets('months inside the same year keep the bare month name',
        (tester) async {
      await tester.pumpWidget(_wrap(_sampleChangelog));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();

      expect(find.text('Jul 2026'), findsOneWidget); // first column
      expect(find.text('Aug'), findsOneWidget);
    });

    testWidgets('a day without releases says so', (tester) async {
      await tester.pumpWidget(_wrap(_sampleChangelog));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show update heatmap'));
      await tester.pumpAndSettle();

      final empty = find.byTooltip('2026-07-21: no updates');
      expect(empty, findsOneWidget);
      await tester.tap(empty, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('No updates on this day.'), findsOneWidget);
    });
  });
}
