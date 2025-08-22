import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:best_todo_2/config.dart';

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
    Config.defaultDelaySeconds = 7.5;
    await Config.save();

    // Reset to defaults
    Config.darkMode = false;
    Config.swipeLeftDelete = true;
    Config.useIconTabs = false;
    Config.enableNotifications = false;
    Config.defaultDelaySeconds = 5.0;

    await Config.load();

    expect(Config.darkMode, isTrue);
    expect(Config.swipeLeftDelete, isFalse);
    expect(Config.useIconTabs, isTrue);
    expect(Config.enableNotifications, isTrue);
    expect(Config.defaultDelaySeconds, 7.5);
  });
}
