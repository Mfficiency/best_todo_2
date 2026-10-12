import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/pc_watcher_status.dart';
import 'package:besttodo/services/pc_watcher_service.dart';
import 'package:besttodo/ui/pc_watcher_page.dart';

/// A status as `dev-build-watch.ps1` writes it (PowerShell's 7-digit
/// fractions included).
final Map<String, dynamic> _status = {
  'schema': 1,
  'machine': 'DESKTOP-30LDPTO',
  'updatedAt': '2026-10-12T19:52:22.5187673+02:00',
  'lastCheckAt': '2026-10-12T19:52:22.5187673+02:00',
  'channels': [
    {
      'app': 'BestTodo',
      'key': 'best_todo_2',
      'branch': 'dev',
      'repo': 'Mfficiency/best_todo_2',
      'state': 'building',
      'remoteHead': 'e159e36aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'builtHead': '',
      'since': '2026-10-12T19:40:00.0000000+02:00',
      'lastCheckAt': '2026-10-12T19:52:22.5187673+02:00',
      'lastError': null,
    },
    {
      'app': 'BestCollage',
      'key': 'BestCollage',
      'branch': 'main',
      'state': 'idle',
      'remoteHead': 'ef372fe',
      'builtHead': 'ef372fe',
    },
  ],
  'builds': [
    {
      'id': 'best_todo_2-staging-20261012175538',
      'app': 'BestTodo',
      'branch': 'staging',
      'sha': '154f248',
      'buildNumber': 3566383,
      'trigger': 'push',
      'startedAt': '2026-10-12T17:55:38.0000000+02:00',
      'finishedAt': '2026-10-12T18:04:29.0000000+02:00',
      'durationSeconds': 531,
      'result': 'published',
      'published': [
        {
          'app': 'BestToDo',
          'version': '0.2.109+3566383',
          'channel': 'staging',
          'tag': 'v0.2.109-3566383-staging',
          'repo': 'Mfficiency/best_todo_2',
          'apkSizeBytes': 23464767,
        }
      ],
      'error': null,
      'log': null,
    },
    {
      'id': 'hally_remote-dev-20261012160000',
      'app': 'Hally Remote',
      'branch': 'dev',
      'sha': 'fe9eb94',
      'startedAt': '2026-10-12T16:00:00.0000000+02:00',
      'finishedAt': '2026-10-12T16:02:00.0000000+02:00',
      'durationSeconds': 120,
      'result': 'failed',
      'published': [],
      'error': 'tool\\build.ps1 release failed (exit 1)',
      'log': 'FAILURE: Build failed with an exception.',
    },
    {
      'id': 'BestCollage-main-20261012174041',
      'app': 'BestCollage',
      'branch': 'main',
      'sha': 'adc51f8',
      'startedAt': '2026-10-12T17:40:41.0000000+02:00',
      'durationSeconds': 3,
      'result': 'unchanged',
    },
  ],
};

http.Client _client({int statusCode = 200, bool actions = true}) =>
    MockClient((request) async {
      if (request.url.path.endsWith('/contents/pc_watcher.json')) {
        expect(request.url.queryParameters['ref'], 'status');
        expect(request.headers['Authorization'], 'Bearer tok');
        return http.Response(
            statusCode == 200 ? jsonEncode(_status) : '{}', statusCode);
      }
      if (request.url.path.endsWith('/actions/runs')) {
        if (!actions) return http.Response('{}', 403);
        return http.Response(
            jsonEncode({
              'workflow_runs': [
                {
                  'display_title': 'Build Vesta Immo dev 1234567',
                  'status': 'queued',
                  'created_at': '2026-10-12T17:50:00Z',
                },
                {
                  'display_title': 'Build BestTodo main 7654321',
                  'status': 'completed',
                  'created_at': '2026-10-12T17:00:00Z',
                },
              ]
            }),
            200);
      }
      return http.Response('not found', 404);
    });

final DateTime _now = DateTime.parse('2026-10-12T19:55:00+02:00').toLocal();

Future<void> _pumpPage(WidgetTester tester, PcWatcherService service) async {
  await tester.pumpWidget(MaterialApp(
    home: PcWatcherPage(service: service, clock: () => _now),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('pc_watcher is a registered tool and feature', () {
    expect(Config.featureKeys, contains('pc_watcher'));
    expect(Config.startToolOptions, contains('pc_watcher'));
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });

  test('parses the builder status, newest build first', () {
    final status = PcWatcherStatus.fromJson(_status);
    expect(status.machine, 'DESKTOP-30LDPTO');
    expect(status.lastCheckAt!.toUtc(), DateTime.utc(2026, 10, 12, 17, 52, 22, 518, 767));
    expect(status.builds.map((b) => b.sha), ['154f248', 'adc51f8', 'fe9eb94']);
    expect(status.builds.first.apkSizeBytes, 23464767);
    expect(status.builds.first.result, PcBuildResult.published);
    expect(status.builds.last.result, PcBuildResult.failed);
    expect(status.pending.map((c) => c.app), ['BestTodo']);
    expect(status.apps, ['BestTodo', 'BestCollage', 'Hally Remote']);
  });

  test('tolerates missing keys and an empty file', () {
    final status = PcWatcherStatus.fromJson({
      'builds': [
        {'app': 'X'}
      ],
      'channels': 'nonsense',
    });
    expect(status.builds.single.result, PcBuildResult.unknown);
    expect(status.builds.single.apkSizeBytes, isNull);
    expect(status.channels, isEmpty);
  });

  test('a channel whose check failed counts as pending', () {
    const channel = PcWatcherChannel(
        app: 'BestMusic', key: 'BestMusic', branch: 'dev', lastError: 'x');
    expect(channel.isPending, isTrue);
  });

  test('formats durations and sizes', () {
    expect(formatBuildDuration(45), '45s');
    expect(formatBuildDuration(531), '8m 51s');
    expect(formatBuildDuration(3720), '1h 02m');
    expect(formatApkSize(23464767), '22.4 MB');
  });

  test('fetch explains a rejected token and caches a good download',
      () async {
    final bad = PcWatcherService(client: _client(statusCode: 401));
    await expectLater(
        bad.fetch('tok'),
        throwsA(isA<PcWatcherException>().having(
            (e) => e.message, 'message', contains('rejected the token'))));

    final good = PcWatcherService(client: _client(actions: false));
    final snapshot = await good.fetch('tok');
    expect(snapshot.runnerJobs, isNull);
    final cached = await good.loadCached();
    expect(cached!.status.builds, hasLength(3));
  });

  testWidgets('without a token it explains how to add one', (tester) async {
    await _pumpPage(tester, PcWatcherService(client: _client()));
    expect(find.text('Watch the build PC'), findsOneWidget);
    expect(find.text('Add token'), findsOneWidget);
  });

  testWidgets('shows the PC, pending work and the build log', (tester) async {
    SharedPreferences.setMockInitialValues({'pc_watcher_token': 'tok'});
    await _pumpPage(tester, PcWatcherService(client: _client()));

    expect(find.text('DESKTOP-30LDPTO'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('pc-watcher-machine-state')))
            .data,
        'Online');
    expect(find.text('Building BestTodo (dev) since 15 min'), findsOneWidget);
    expect(find.text('Pending (2)'), findsOneWidget);
    expect(find.text('Build Vesta Immo dev 1234567'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.text('BestTodo 0.2.109+3566383 · staging'), 200);
    expect(find.textContaining('8m 51s · 22.4 MB'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Failed'), -200);
    await tester.tap(find.text('Failed'));
    await tester.pump();
    expect(find.text('BestTodo 0.2.109+3566383 · staging'), findsNothing);
    expect(find.text('Hally Remote · dev'), findsOneWidget);

    await tester.tap(find.text('Hally Remote · dev'));
    await tester.pumpAndSettle();
    expect(find.text('End of the build output'), findsOneWidget);
    expect(find.text('FAILURE: Build failed with an exception.'),
        findsOneWidget);
  });

  testWidgets('a failed refresh keeps the last download', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pc_watcher_token': 'tok',
      'pc_watcher_cache': jsonEncode(_status),
      'pc_watcher_cache_at': '2026-10-12T17:00:00Z',
    });
    await _pumpPage(tester, PcWatcherService(client: _client(statusCode: 404)));
    expect(find.textContaining('No status found'), findsOneWidget);
    expect(find.text('DESKTOP-30LDPTO'), findsOneWidget);
  });
}
