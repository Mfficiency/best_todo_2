import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/main.dart' show applyCompactMode;
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/services/auto_backup_service.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../update/update_fakes.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// The Settings layout every Mfficiency app shares (flutter_app_template
/// docs/CONCEPT.md §5): Appearance first; Debugging, Updates, Backup & data
/// last, each with the same first rows in the same order.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() {
    AppUpdates.controller?.dispose();
    AppUpdates.controller = null;
    AppUpdates.backup = null;
    Config.autoBackupFrequency = 'off';
    Config.compactMode = false;
  });

  FullBackup androidBackup() => FullBackup(
        config: AppUpdates.backupConfig,
        version: '0.2.106',
        build: 1000,
        prefs: prefs,
        platform: UpdatePlatform(supported: true),
        roots: () async => {},
      );

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsPage(onImportRequested: () async {}),
    ));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> openSection(WidgetTester tester, String title) async {
    final header = find.byTooltip('Expand $title');
    await tester.scrollUntilVisible(header, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  /// The vertical position of each of [texts] (first match), which must be
  /// strictly increasing.
  void expectInOrder(WidgetTester tester, List<Finder> rows) {
    final ys = [for (final r in rows) tester.getTopLeft(r.first).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]),
          reason: '${rows[i]} should be below ${rows[i - 1]}');
    }
  }

  testWidgets('sections: Appearance first; Debugging, Updates, Backup & data '
      'last', (tester) async {
    await pumpSettings(tester);
    // The section chips list every visible section, in page order.
    // (Sections start collapsed, so the only chips are the section chips.)
    final chips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .map((c) => (c.label as Text).data)
        .toList();
    expect(chips, contains('Debugging'));
    expect(chips.first, 'Appearance');
    expect(chips.sublist(chips.length - 3),
        ['Debugging', 'Updates', 'Backup & data']);
  });

  testWidgets('Appearance: Dark mode, Compact mode, Time format, Date format '
      'first', (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Appearance');
    expectInOrder(tester, [
      find.text('Dark mode'),
      find.text('Compact mode'),
      find.text('Time format'),
      find.text('Date format'),
      find.text('Minimalist mode'),
    ]);
  });

  testWidgets('Compact mode is saved and tightens the theme', (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Appearance');
    await tester.tap(find.text('Compact mode'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(Config.compactMode, isTrue);
    Config.compactMode = false;
    await tester.runAsync(Config.load);
    expect(Config.compactMode, isTrue, reason: 'persisted');
  });

  test('compact theme: denser, touch targets kept', () {
    final base = ThemeData();
    expect(identical(applyCompactMode(base, false), base), isTrue);
    final compact = applyCompactMode(base, true);
    expect(compact.visualDensity, VisualDensity.compact);
    expect(compact.listTileTheme.visualDensity, VisualDensity.compact);
    expect(compact.materialTapTargetSize, MaterialTapTargetSize.padded);
  });

  testWidgets('Debugging: Send a report, GitHub token', (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Debugging');
    expectInOrder(tester, [
      find.byKey(const Key('problemReport.send')),
      find.byKey(const Key('problemReport.settings')),
    ]);
    expect(find.text('Send a report'), findsOneWidget);
  });

  testWidgets('Updates: Check automatically, Check for updates, GitHub token',
      (tester) async {
    fakeController(github: FakeGithub(), downloader: FakeDownloader());
    await pumpSettings(tester);
    await openSection(tester, 'Updates');
    expectInOrder(tester, [
      find.text('Check automatically'),
      find.text('Check for updates'),
      find.byKey(const Key('updates.token')),
    ]);
  });

  testWidgets(
      'Backup & data on Android: the full backup\'s five rows, no folder '
      'backup', (tester) async {
    AppUpdates.backup = androidBackup();
    await pumpSettings(tester);
    await openSection(tester, 'Backup & data');
    expectInOrder(tester, [
      find.byKey(const Key('fullBackup.now')),
      find.byKey(const Key('fullBackup.restore')),
      find.byKey(const Key('fullBackup.location')),
      find.byKey(const Key('fullBackup.schedule')),
      find.byKey(const Key('fullBackup.last')),
    ]);
    expect(find.text('Automatic backup'), findsOneWidget,
        reason: 'one automatic backup only');
    expect(find.text('Backup location'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing,
        reason: 'the folder backup\'s schedule is retired here');
  });

  testWidgets('Backup & data elsewhere: the same rows for the folder backup',
      (tester) async {
    await pumpSettings(tester);
    await openSection(tester, 'Backup & data');
    expectInOrder(tester, [
      find.text('Back up everything'),
      find.text('Restore from a backup'),
      find.text('Backup location'),
      find.text('Automatic backup'),
      find.text('Last backup'),
    ]);
  });

  group('the folder backup on Android', () {
    test('its daily/weekly schedule becomes the full backup\'s, once',
        () async {
      AppUpdates.backup = androidBackup();
      Config.autoBackupFrequency = 'daily';
      await AppUpdates.adoptFolderBackupSchedule(prefs: prefs);
      expect(AppUpdates.backup!.schedule.value, FullBackupSchedule.daily);
      expect(prefs.getString(FullBackup.scheduleKey), 'daily');

      // A schedule picked later is never overwritten.
      await AppUpdates.backup!.setSchedule(FullBackupSchedule.off);
      await AppUpdates.adoptFolderBackupSchedule(prefs: prefs);
      expect(AppUpdates.backup!.schedule.value, FullBackupSchedule.off);
    });

    test('off: the full backup keeps its default (weekly)', () async {
      AppUpdates.backup = androidBackup();
      Config.autoBackupFrequency = 'off';
      await AppUpdates.adoptFolderBackupSchedule(prefs: prefs);
      expect(prefs.containsKey(FullBackup.scheduleKey), isFalse);
      expect(AppUpdates.backup!.schedule.value, FullBackupSchedule.weekly);
    });

    test('does not run any more (one automatic backup)', () async {
      AppUpdates.backup = androidBackup();
      final dir = await Directory.systemTemp.createTemp();
      Config.autoBackupFrequency = 'daily';
      Config.autoBackupDirectory = dir.path;
      addTearDown(() => Config.autoBackupDirectory = '');
      expect(await AutoBackupService.maybeRun(), isNull);
      expect(dir.listSync(), isEmpty);
    });
  });
}
