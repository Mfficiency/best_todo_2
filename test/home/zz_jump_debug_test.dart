import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/ui/settings_page.dart';
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
  testWidgets('debug: can we reach the streak section by dragging?',
      (tester) async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    debugPrint('simpleMode=${Config.simpleMode} '
        'streakFeature=${Config.isFeatureEnabled('streak')}');

    final list = find.byType(CustomScrollView);
    for (var i = 0; i < 40; i++) {
      if (find.text('Show streak').evaluate().isNotEmpty) {
        debugPrint('found after $i drags');
        break;
      }
      await tester.drag(list, const Offset(0, -400));
      await tester.pump();
    }
    expect(find.text('Show streak'), findsOneWidget);
  });
}
