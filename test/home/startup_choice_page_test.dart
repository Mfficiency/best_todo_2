import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/todoist_api_client.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:besttodo/ui/startup_choice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Minimal fake of Todoist's unified API v1, just enough for
/// [TodoistSyncService.testConnection] and a first pull-only [syncNow] run —
/// see `test/sync/todoist_sync_service_test.dart` for the full version.
class _FakeTodoist {
  bool failAuth = false;
  final Map<String, Map<String, dynamic>> tasks = {};
  final Map<String, Map<String, dynamic>> projects = {};

  http.Response _json(Object data, [int status = 200]) => http.Response(
        jsonEncode(data),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  late final http.Client client = MockClient((request) async {
    if (failAuth) return http.Response('Unauthorized', 401);
    final path = request.url.path;
    final method = request.method;
    if (method == 'GET' && path == '/api/v1/tasks') {
      return _json({'results': tasks.values.toList(), 'next_cursor': null});
    }
    if (method == 'GET' && path == '/api/v1/projects') {
      return _json(
          {'results': projects.values.toList(), 'next_cursor': null});
    }
    return http.Response('not found', 404);
  });
}

void main() {
  late Directory docsDir;
  late _FakeTodoist fake;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('startup_choice');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    // Opts out of the one-time Todo.md → wishlist import on first load.
    await File('${docsDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    StorageService.resetJournalBaselineForTest();
    ProjectService.instance.resetForTest();
    TodoistSyncService.resetForTest();
    fake = _FakeTodoist();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);
  });

  tearDown(() {
    Config.todoistSyncEnabled = false;
    Config.todoistApiToken = '';
    TodoistSyncService.resetForTest();
  });

  /// Walks real-event-loop slices so dart:io futures started inside the fake
  /// zone (API calls, Config.save, storage writes) complete — see
  /// test/README.md.
  Future<void> settleIo(WidgetTester tester, {int rounds = 150}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('Start fresh finishes immediately with no dialog',
      (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: StartupChoicePage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Start fresh'));
    await tester.pumpAndSettle();

    expect(finished, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    // Start fresh never touches Todoist config.
    expect(Config.todoistSyncEnabled, isFalse);
  });

  testWidgets('Import from Todoist requires a token first', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: StartupChoicePage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(FilledButton, 'Import from Todoist'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Todoist'), findsOneWidget);

    await tester.tap(find.text('Connect & Import'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an API token first'), findsOneWidget);
    expect(finished, isFalse);
  });

  testWidgets(
      "a valid token pulls in today's tasks and finishes onboarding without "
      "waiting for the rest — TodoistSyncService.startFirstLaunchImport's "
      'background phase is covered deterministically at the service level '
      'in test/sync/todoist_sync_service_test.dart', (tester) async {
    final today = DateTime.now();
    final isoToday = '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    fake.tasks['1'] = {
      'id': '1',
      'content': 'Buy milk',
      'description': '',
      'project_id': null,
      'labels': <String>[],
      'due': {'date': isoToday}, // today -> lands in the synchronous phase
    };
    // Undated -> Future bucket, only pulled in by the background phase —
    // deliberately not asserted on here (see the test name).
    fake.tasks['2'] = {
      'id': '2',
      'content': 'Someday',
      'description': '',
      'project_id': null,
      'labels': <String>[],
      'due': null,
    };

    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: StartupChoicePage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(FilledButton, 'Import from Todoist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-123');
    await tester.tap(find.text('Connect & Import'));
    await settleIo(tester);

    expect(finished, isTrue);
    expect(Config.todoistSyncEnabled, isTrue);
    expect(Config.todoistApiToken, 'tok-123');
    expect(
      find.text("Imported 1 of today's task(s) from Todoist — the rest is "
          'syncing in the background'),
      findsOneWidget,
    );

    final tasks = await tester.runAsync(() => StorageService().loadTaskList());
    expect(tasks!.map((t) => t.title), contains('Buy milk'));
  });

  testWidgets('an invalid token shows an error and does not finish',
      (tester) async {
    fake.failAuth = true;

    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: StartupChoicePage(onFinished: () => finished = true),
    ));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(FilledButton, 'Import from Todoist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bad-token');
    await tester.tap(find.text('Connect & Import'));
    await settleIo(tester);

    expect(finished, isFalse);
    expect(find.text('Invalid API token'), findsOneWidget);

    // Cancel returns to the choice page without finishing onboarding.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(finished, isFalse);
  });
}
