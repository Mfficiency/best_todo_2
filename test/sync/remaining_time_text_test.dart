import 'package:besttodo/models/sync_log_entry.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:besttodo/ui/remaining_time_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 10, 15, 12);
    SharedPreferences.setMockInitialValues({});
  });

  Widget host({
    required bool active,
    double? done,
    Duration? typical,
    String? durationKey,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: RemainingTimeText(
            active: active,
            done: done,
            typical: typical,
            durationKey: durationKey,
            clock: clock,
          ),
        ),
      );

  Future<void> advance(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('counts down a long job from its typical duration',
      (tester) async {
    await tester.pumpWidget(
        host(active: true, typical: const Duration(minutes: 2)));
    expect(find.byKey(const Key('remaining-time')), findsNothing);

    await advance(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('remaining-time')), findsNothing,
        reason: 'nothing during the first 3 seconds');

    await advance(tester, const Duration(seconds: 8));
    expect(find.text('00:01:50 remaining'), findsOneWidget);

    await advance(tester, const Duration(seconds: 50));
    expect(find.text('00:01:00 remaining'), findsOneWidget);

    await tester.pumpWidget(
        host(active: false, typical: const Duration(minutes: 2)));
    expect(find.byKey(const Key('remaining-time')), findsNothing);
  });

  testWidgets('shows nothing for a job of 30 seconds or less',
      (tester) async {
    await tester.pumpWidget(
        host(active: true, typical: const Duration(seconds: 20)));
    await advance(tester, const Duration(seconds: 10));
    expect(find.byKey(const Key('remaining-time')), findsNothing);
    await tester.pumpWidget(host(active: false));
  });

  testWidgets('extrapolates from a progress fraction', (tester) async {
    await tester.pumpWidget(host(active: true, done: 0));
    await advance(tester, const Duration(seconds: 20));
    await tester.pumpWidget(host(active: true, done: 0.25));
    // 20 s for a quarter → 60 s for the rest (80 s in total).
    expect(find.text('00:01:00 remaining'), findsOneWidget);
    await tester.pumpWidget(host(active: false));
  });

  testWidgets('shows nothing without anything to go on', (tester) async {
    await tester.pumpWidget(host(active: true));
    await advance(tester, const Duration(minutes: 1));
    expect(find.byKey(const Key('remaining-time')), findsNothing);
    await tester.pumpWidget(host(active: false));
  });

  testWidgets('a durationKey remembers how long the job took last time',
      (tester) async {
    await tester.pumpWidget(host(active: true, durationKey: 'scan'));
    await advance(tester, const Duration(seconds: 90));
    expect(find.byKey(const Key('remaining-time')), findsNothing,
        reason: 'the first run has nothing to go on');
    await tester.pumpWidget(host(active: false, durationKey: 'scan'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(await tester.runAsync(() => RemainingTimeText.lastDuration('scan')),
        const Duration(seconds: 90));

    await tester.pumpWidget(host(active: true, durationKey: 'scan'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await advance(tester, const Duration(seconds: 30));
    expect(find.text('00:01:00 remaining'), findsOneWidget);
    await tester.pumpWidget(host(active: false, durationKey: 'scan'));
  });

  group('TodoistSyncService.typicalDuration', () {
    setUp(TodoistSyncService.resetForTest);
    tearDown(TodoistSyncService.resetForTest);

    SyncLogEntry entry(int ms, String trigger, {bool success = true}) =>
        SyncLogEntry(
          at: DateTime(2026),
          durationMs: ms,
          itemCount: 1,
          success: success,
          trigger: trigger,
        );

    test('newest successful run of the same kind, else the other kind', () {
      final service = TodoistSyncService.instance;
      expect(service.typicalDuration(), isNull);
      service.entries.value = [
        entry(5000, 'manual', success: false),
        entry(45000, 'manual'),
        entry(90000, 'first_launch_import'),
        entry(20000, 'manual'),
      ];
      expect(service.typicalDuration(), const Duration(seconds: 45));
      expect(service.typicalDuration(firstImport: true),
          const Duration(seconds: 90));
      service.entries.value = [entry(45000, 'app quit')];
      expect(service.typicalDuration(firstImport: true),
          const Duration(seconds: 45));
    });
  });
}
