import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:besttodo/config.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  test('Config persists settings to disk', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    // Set and save custom values
    Config.darkMode = true;
    Config.minimalistMode = true;
    Config.swipeLeftDelete = false;
    Config.useIconTabs = true;
    Config.enableNotifications = true;
    Config.addNewTasksToTop = true;
    Config.enterSavesNewTask = false;
    Config.defaultAddTabIndex = 5;
    Config.defaultDelaySeconds = 7.5;
    Config.use24HourFormat = false;
    Config.dateFormat = 'yyyy-MM-dd';
    Config.startTool = 'productivity_stats';
    Config.showFailureDotOnMenu = true;
    await Config.save();

    // Reset to defaults
    Config.darkMode = false;
    Config.minimalistMode = false;
    Config.swipeLeftDelete = true;
    Config.useIconTabs = false;
    Config.enableNotifications = false;
    Config.addNewTasksToTop = false;
    Config.enterSavesNewTask = true;
    Config.defaultAddTabIndex = Config.addToCurrentTab;
    Config.defaultDelaySeconds = 5.0;
    Config.use24HourFormat = true;
    Config.dateFormat = Config.dateFormats.first;
    Config.startTool = 'tasks';
    Config.showFailureDotOnMenu = false;

    await Config.load();

    expect(Config.darkMode, isTrue);
    expect(Config.minimalistMode, isTrue);
    expect(Config.swipeLeftDelete, isFalse);
    expect(Config.useIconTabs, isTrue);
    expect(Config.enableNotifications, isTrue);
    expect(Config.addNewTasksToTop, isTrue);
    expect(Config.enterSavesNewTask, isFalse);
    expect(Config.defaultAddTabIndex, 5);
    expect(Config.defaultDelaySeconds, 7.5);
    expect(Config.use24HourFormat, isFalse);
    expect(Config.dateFormat, 'yyyy-MM-dd');
    expect(Config.startTool, 'productivity_stats');
    expect(Config.showFailureDotOnMenu, isTrue);

    // Restore the defaults so other tests see a clean config.
    Config.showFailureDotOnMenu = false;
    Config.enterSavesNewTask = true;
    Config.defaultAddTabIndex = Config.addToCurrentTab;
  });

  test('out-of-range default add buckets are clamped on load', () {
    Config.applyMap({'defaultAddTabIndex': 99});
    expect(Config.defaultAddTabIndex, Config.tabs.length - 1);

    Config.applyMap({'defaultAddTabIndex': -7});
    expect(Config.defaultAddTabIndex, Config.addToCurrentTab);

    // Settings written before the option existed keep the current value.
    Config.defaultAddTabIndex = 2;
    Config.applyMap({});
    expect(Config.defaultAddTabIndex, 2);

    // Restore the default so other tests see a clean config.
    Config.defaultAddTabIndex = Config.addToCurrentTab;
  });

  test('unknown startTool values are ignored on load', () {
    Config.startTool = 'tasks';
    Config.applyMap({'startTool': 'does_not_exist'});
    expect(Config.startTool, 'tasks');

    Config.applyMap({'startTool': 'chronize'});
    expect(Config.startTool, 'chronize');

    // Restore the default so other tests see a clean config.
    Config.startTool = 'tasks';
  });
}
