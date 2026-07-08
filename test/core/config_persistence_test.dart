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
    Config.swipeLeftDelete = false;
    Config.useIconTabs = true;
    Config.enableNotifications = true;
    Config.addNewTasksToTop = true;
    Config.defaultDelaySeconds = 7.5;
    Config.use24HourFormat = false;
    Config.dateFormat = 'yyyy-MM-dd';
    Config.startTool = 'productivity_stats';
    await Config.save();

    // Reset to defaults
    Config.darkMode = false;
    Config.swipeLeftDelete = true;
    Config.useIconTabs = false;
    Config.enableNotifications = false;
    Config.addNewTasksToTop = false;
    Config.defaultDelaySeconds = 5.0;
    Config.use24HourFormat = true;
    Config.dateFormat = Config.dateFormats.first;
    Config.startTool = 'tasks';

    await Config.load();

    expect(Config.darkMode, isTrue);
    expect(Config.swipeLeftDelete, isFalse);
    expect(Config.useIconTabs, isTrue);
    expect(Config.enableNotifications, isTrue);
    expect(Config.addNewTasksToTop, isTrue);
    expect(Config.defaultDelaySeconds, 7.5);
    expect(Config.use24HourFormat, isFalse);
    expect(Config.dateFormat, 'yyyy-MM-dd');
    expect(Config.startTool, 'productivity_stats');
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

