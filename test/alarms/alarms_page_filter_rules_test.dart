import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/alarm_storage_service.dart';
import 'package:besttodo/ui/alarms_page.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Config.viewFilterRules = {};
  });

  tearDown(() {
    Config.viewFilterRules = {};
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required List<Alarm> alarms,
    required String marker,
  }) async {
    await tester.runAsync(() => AlarmStorageService().saveAlarms(alarms));
    await tester.pumpWidget(const MaterialApp(home: AlarmsPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'AlarmsPage never loaded the alarms');
  }

  testWidgets('an alarm with tags shows them as chips', (tester) async {
    await pumpPage(
      tester,
      alarms: [Alarm(name: 'Wake up', tags: 'work, morning')],
      marker: 'Wake up',
    );
    expect(find.text('work'), findsOneWidget);
    expect(find.text('morning'), findsOneWidget);
  });

  testWidgets('Settings → Filtering rules can hide an alarm by its own tag',
      (tester) async {
    Config.viewFilterRules = {
      ViewFilterRules.alarms: ViewFilterRules(excludeTags: ['personal']),
    };
    await pumpPage(
      tester,
      alarms: [
        Alarm(name: 'Wake up', hour: 7, tags: 'work'),
        Alarm(name: 'Yoga', hour: 8, tags: 'personal'),
      ],
      marker: 'Wake up',
    );
    expect(find.text('Wake up'), findsOneWidget);
    expect(find.text('Yoga'), findsNothing);
  });
}
