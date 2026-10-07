import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/bpm_preset.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_metadata_csv.dart';
import 'package:besttodo/services/music_metadata_extractor.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/bpm_range_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Best Music's Songs by BPM page (SPEC.md §10.6n): a BPM per track (ID3
/// `TBPM`, Track info, CSV), a two-handled range slider filtering the
/// library, presets, and play-as-queue / save-as-playlist.
void main() {
  late Directory tempDir;

  Track song(String title, int? bpm) => Track.local(
      filePath: '/music/$title.mp3', title: title, artist: 'A', bpm: bpm);

  final library = [
    song('Slow', 80),
    song('Walk', 110),
    song('Groove', 124),
    song('House', 128),
    song('Run', 170),
    song('Unknown', null),
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    MusicLibraryService.instance.tracks.value = library;
    Config.musicBpmPresets = [];
  });

  tearDown(() async {
    Config.musicBpmPresets = [];
    MusicLibraryService.instance.resetForTest();
    await tempDir.delete(recursive: true);
  });

  /// Lets real file writes (Config.save, playlists.json) finish.
  Future<void> settleIo(WidgetTester tester, [int rounds = 60]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  group('BPM data', () {
    test('parseBpm reads TBPM values', () {
      expect(parseBpm('128'), 128);
      expect(parseBpm('127.6'), 128);
      expect(parseBpm('99,4'), 99);
      expect(parseBpm('120 BPM'), 120);
      expect(parseBpm('0'), isNull);
      expect(parseBpm('fast'), isNull);
      expect(parseBpm(''), isNull);
      expect(parseBpm(null), isNull);
    });

    test('Track keeps its BPM through JSON and copyWith', () {
      final t = song('House', 128);
      expect(Track.fromJson(t.toJson()).bpm, 128);
      expect(song('X', null).toJson().containsKey('bpm'), isFalse);
      expect(t.copyWith(playCount: 3).bpm, 128);
    });

    test('the metadata CSV has a bpm column both ways', () {
      final csv = MusicMetadataCsv.encode([song('House', 128)]);
      expect(csv.split('\r\n')[1], contains(',128,'));
      final rows = MusicMetadataCsv.decode('id,bpm\r\nlocal:/music/a.mp3,96\r\n'
          'local:/music/b.mp3,\r\n');
      expect(rows[0].bpm, 96);
      expect(rows[1].bpm, isNull);
    });

    test('a CSV import fills in BPM, a blank cell keeps it', () async {
      final lib = MusicLibraryService.instance;
      await lib.applyMetadataRows(MusicMetadataCsv.decode(
          'id,bpm\r\nlocal:/music/Unknown.mp3,140\r\nlocal:/music/Run.mp3,\r\n'));
      expect(lib.byId('local:/music/Unknown.mp3')!.bpm, 140);
      expect(lib.byId('local:/music/Run.mp3')!.bpm, 170);
    });

    test('tracksInBpmRange / bpmBounds', () {
      expect([for (final t in tracksInBpmRange(library, 110, 130)) t.title],
          ['Walk', 'Groove', 'House']);
      expect(bpmBounds(library), (min: 80, max: 170));
      expect(bpmBounds([song('Only', 100)]), (min: 100, max: 101));
      expect(bpmBounds([song('None', null)]), isNull);
    });

    test('BpmPreset JSON tolerates swapped and missing ends', () {
      const p = BpmPreset(name: 'Run', min: 160, max: 175);
      final back = BpmPreset.fromJson(p.toJson())!;
      expect((back.name, back.min, back.max), ('Run', 160, 175));
      final swapped = BpmPreset.fromJson({'name': 'x', 'min': 130, 'max': 90})!;
      expect((swapped.min, swapped.max), (90, 130));
      expect(BpmPreset.fromJson({'name': 'x'}), isNull);
      expect(p.matches(165), isTrue);
      expect(p.matches(null), isFalse);
    });
  });

  group('BpmRangePage', () {
    testWidgets('lists every song with a BPM, slowest first', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BpmRangePage()));
      expect(find.text('80 – 170 BPM'), findsOneWidget);
      expect(find.text("5 songs · 1 without a BPM aren't shown"),
          findsOneWidget);
      final titles = [
        for (final w in tester.widgetList<ListTile>(find.byType(ListTile)))
          ((w.title as Text).data!),
      ];
      expect(titles, ['Slow', 'Walk', 'Groove', 'House', 'Run']);
      expect(find.text('Unknown'), findsNothing);
    });

    testWidgets('dragging either end of the slider narrows the list',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BpmRangePage()));
      final slider = find.byKey(const ValueKey('bpmRangeSlider'));
      final rect = tester.getRect(slider);
      // The left handle sits at the slider's left end (inside its padding).
      await tester.dragFrom(Offset(rect.left + 24, rect.center.dy),
          Offset(rect.width * 0.3, 0));
      await tester.pump();
      expect(find.text('Slow'), findsNothing);
      expect(find.text('Run'), findsOneWidget);

      await tester.dragFrom(Offset(rect.right - 24, rect.center.dy),
          Offset(-rect.width * 0.3, 0));
      await tester.pump();
      expect(find.text('Run'), findsNothing);
      expect(find.text('House'), findsOneWidget);
    });

    testWidgets('a preset chip applies its range; Play as queue plays it',
        (tester) async {
      Config.musicBpmPresets = [
        const BpmPreset(name: 'Dance', min: 120, max: 130),
      ];
      final played = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: BpmRangePage(
          playQueue: (queue, {int startIndex = 0}) async =>
              played.add('${[for (final t in queue) t.title]} @$startIndex'),
        ),
      ));
      await tester.tap(find.text('Dance · 120–130'));
      await tester.pump();
      expect(find.text('120 – 130 BPM'), findsOneWidget);
      expect(find.text('Groove'), findsOneWidget);
      expect(find.text('Walk'), findsNothing);

      await tester.tap(find.text('Play as queue'));
      await tester.pump();
      expect(played.last, '[Groove, House] @0');

      await tester.tap(find.text('House'));
      await tester.pump();
      expect(played.last, '[Groove, House] @1');
    });

    testWidgets('Save preset remembers the range', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: BpmRangePage()));
      await tester.tap(find.text('Save preset'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Everything');
      await tester.tap(find.text('Save'));
      await settleIo(tester);

      expect(Config.musicBpmPresets.single.name, 'Everything');
      expect(Config.musicBpmPresets.single.min, 80);
      expect(Config.musicBpmPresets.single.max, 170);
      expect(find.text('Everything · 80–170'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete preset Everything'));
      await settleIo(tester);
      expect(Config.musicBpmPresets, isEmpty);
    });

    testWidgets('Save as playlist stores the listed songs', (tester) async {
      Config.musicBpmPresets = [
        const BpmPreset(name: 'Dance', min: 120, max: 130),
      ];
      await tester.pumpWidget(const MaterialApp(home: BpmRangePage()));
      await tester.tap(find.text('Dance · 120–130'));
      await tester.pump();
      await tester.tap(find.text('Save as playlist'));
      await tester.pumpAndSettle();
      expect(find.text('120–130 BPM'), findsOneWidget); // suggested name
      await tester.tap(find.text('Save'));
      await settleIo(tester);

      final saved = MusicPlaylistService.instance.playlists.value
          .singleWhere((p) => p.name == '120–130 BPM');
      expect(saved.trackIds,
          ['local:/music/Groove.mp3', 'local:/music/House.mp3']);
    });

    testWidgets('explains where BPM comes from when no song has one',
        (tester) async {
      MusicLibraryService.instance.tracks.value = [song('Unknown', null)];
      await tester.pumpWidget(const MaterialApp(home: BpmRangePage()));
      expect(find.textContaining('None of your songs has a BPM yet'),
          findsOneWidget);
    });
  });
}
