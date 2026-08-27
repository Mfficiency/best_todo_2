import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/countdown_timer.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/countdown_timer_page.dart';
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
    required List<CountdownTimerItem> timers,
    required String marker,
  }) async {
    await tester.runAsync(() => StorageService().saveCountdownTimers(timers));
    await tester.pumpWidget(const MaterialApp(home: CountdownTimerPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'CountdownTimerPage never loaded the timers');
  }

  testWidgets('a timer with tags shows them as chips', (tester) async {
    await pumpPage(
      tester,
      timers: [
        CountdownTimerItem(
          label: 'Launch',
          target: DateTime.now().add(const Duration(days: 30)),
          tags: 'work, deadline',
        ),
      ],
      marker: 'Launch',
    );

    expect(find.text('work'), findsOneWidget);
    expect(find.text('deadline'), findsOneWidget);
  });

  testWidgets(
      'Settings → Filtering rules can hide a timer by its own tag',
      (tester) async {
    Config.viewFilterRules = {
      ViewFilterRules.countdown: ViewFilterRules(excludeTags: ['personal']),
    };
    await pumpPage(
      tester,
      timers: [
        CountdownTimerItem(
          label: 'Launch',
          target: DateTime.now().add(const Duration(days: 30)),
          tags: 'work',
        ),
        CountdownTimerItem(
          label: 'Vacation',
          target: DateTime.now().add(const Duration(days: 10)),
          tags: 'personal',
        ),
      ],
      marker: 'Launch',
    );

    expect(find.text('Launch'), findsOneWidget);
    expect(find.text('Vacation'), findsNothing);
  });

  testWidgets('a reserved tag (e.g. "Wish") renders as a protected chip',
      (tester) async {
    await pumpPage(
      tester,
      timers: [
        CountdownTimerItem(
          label: 'Launch',
          target: DateTime.now().add(const Duration(days: 30)),
          tags: 'Wish',
        ),
      ],
      marker: 'Launch',
    );

    final chipContainer = tester.widget<Container>(find.ancestor(
      of: find.text('Wish'),
      matching: find.byType(Container),
    ).first);
    final decoration = chipContainer.decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
  });
}
