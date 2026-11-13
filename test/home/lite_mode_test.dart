import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/ui/changelog_page.dart';

/// BestToDo Lite (`--flavor lite`, SPEC.md §11 "BestToDo Lite"): the plain
/// task list for old phones. Its gates all hang off [Config.isLite]; these
/// tests flip it with [Config.debugLiteOverride].
void main() {
  setUp(() {
    Config.debugLiteOverride = null;
    Config.simpleMode = false;
    Config.modeChosen = false;
    Config.enableNotifications = true;
    Config.startTool = 'tasks';
  });

  tearDown(() {
    Config.debugLiteOverride = null;
    Config.simpleMode = false;
    Config.enableNotifications = false;
  });

  test('a normal build is not Lite', () {
    expect(Config.isLite, isFalse);
    expect(Config.appName, 'BestToDo');
    expect(Config.changelogAsset, 'CHANGELOG.md');
    expect(AppUpdates.app, UpdatesApp.todo);
    expect(AppUpdates.appId, 'com.mfficiency.best_todo_2');
    expect(AppUpdates.backupConfig.appName, 'BestToDo');
  });

  test('Lite has its own name, changelog, updates, id and backup folder', () {
    Config.debugLiteOverride = true;
    expect(Config.appName, 'BestToDo Lite');
    expect(Config.changelogAsset, 'CHANGELOG_LITE.md');
    expect(AppUpdates.app, UpdatesApp.lite);
    expect(AppUpdates.app.tagPrefix, 'lite-v');
    expect(AppUpdates.appId, 'com.mfficiency.best_todo_lite');
    expect(AppUpdates.backupConfig.appName, 'BestToDoLite');
    final c = AppUpdates.config(AppUpdates.app, version: '1.0.0', build: 1);
    expect(c.tagPrefix, 'lite-v');
    expect(c.appName, 'BestToDo Lite');
  });

  test('Lite keeps only the task list, search and the service pages', () {
    Config.debugLiteOverride = true;
    for (final key in Config.featureKeys) {
      expect(Config.isFeatureEnabled(key), Config.liteFeatures.contains(key),
          reason: key);
    }
    for (final tool in [
      'alarms',
      'projects',
      'wishlist',
      'streak',
      'dice_timer',
      'sms_report',
      'agent_desk',
      'food_diary',
    ]) {
      expect(Config.isFeatureEnabled(tool), isFalse, reason: tool);
    }
    expect(Config.isFeatureEnabled('search'), isTrue);
    expect(Config.isFeatureEnabled('changelog'), isTrue);
    expect(Config.isFeatureEnabled('deleted_items'), isTrue);
  });

  test('Lite ignores the per-feature switches of a copied settings file', () {
    Config.debugLiteOverride = true;
    Config.setFeatureEnabled('alarms', true);
    expect(Config.isFeatureEnabled('alarms'), isFalse);
  });

  test('Lite defaults: simple mode, never asked, notifications off', () {
    Config.debugLiteOverride = true;
    Config.startTool = 'alarms';
    Config.applyLiteDefaults();
    expect(Config.simpleMode, isTrue);
    expect(Config.modeChosen, isTrue);
    expect(Config.enableNotifications, isFalse);
    expect(Config.startTool, 'tasks');
  });

  test('CHANGELOG_LITE.md is bundled and its newest entry is lite/version.yaml',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- CHANGELOG_LITE.md'));
    final version = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
        .firstMatch(File('lite/version.yaml').readAsStringSync())!
        .group(1);
    final releases =
        parseChangelogReleases(File('CHANGELOG_LITE.md').readAsStringSync());
    expect(releases, isNotEmpty);
    expect(releases.first.version, version,
        reason: 'bump lite/version.yaml together with a CHANGELOG_LITE.md '
            'entry (tool/build.ps1 release publishes one Lite release per '
            'version)');
    expect(releases.first.entries, isNotEmpty);
  });
}
