import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/todoist_api_client.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:besttodo/ui/web_data_choice_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Same minimal Todoist API v1 fake as startup_choice_page_test.
class _FakeTodoist {
  bool failAuth = false;
  final Map<String, Map<String, dynamic>> tasks = {};

  http.Response _json(Object data) => http.Response(
        jsonEncode(data),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  late final http.Client client = MockClient((request) async {
    if (failAuth) return http.Response('Unauthorized', 401);
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/v1/tasks') {
      return _json({'results': tasks.values.toList(), 'next_cursor': null});
    }
    if (request.method == 'GET' && path == '/api/v1/projects') {
      return _json({'results': <Object>[], 'next_cursor': null});
    }
    return http.Response('not found', 404);
  });
}

void main() {
  late Directory docsDir;
  late _FakeTodoist fake;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('web_data_choice');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    SharedPreferences.setMockInitialValues({});
    StorageService.resetJournalBaselineForTest();
    StorageService.resetWebRealDataForTest();
    ProjectService.instance.resetForTest();
    TodoistSyncService.resetForTest();
    fake = _FakeTodoist();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);
  });

  tearDown(() {
    Config.webRealData = false;
    Config.todoistSyncEnabled = false;
    Config.todoistApiToken = '';
    StorageService.resetWebRealDataForTest();
    TodoistSyncService.resetForTest();
  });

  Future<void> settleIo(WidgetTester tester, {int rounds = 150}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  test('seedDevData is off once a session loads real data', () {
    expect(Config.seedDevData, Config.isDev);
    Config.webRealData = true;
    expect(Config.seedDevData, isFalse);
  });

  test('a real-data session keeps the task list in memory', () async {
    Config.webRealData = true;
    final storage = StorageService();
    expect(await storage.loadTaskList(), isEmpty);
    await storage.saveTaskList([Task(title: 'From memory')]);
    // A fresh instance sees it too, like the home page after the import.
    final reloaded = await StorageService().loadTaskList();
    expect(reloaded.map((t) => t.title), ['From memory']);
    expect(File('${docsDir.path}/tasks.json').existsSync(), isFalse);
  });

  testWidgets('Use demo finishes without touching Todoist', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: WebDataChoicePage(onFinished: () => finished = true),
    ));
    await tester.pump();

    await tester.tap(find.text('Use demo'));
    await tester.pump();

    expect(finished, isTrue);
    expect(Config.webRealData, isFalse);
    expect(Config.todoistSyncEnabled, isFalse);
  });

  testWidgets('Load real data requires a token', (tester) async {
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: WebDataChoicePage(onFinished: () => finished = true),
    ));
    await settleIo(tester, rounds: 5);

    await tester.ensureVisible(find.text('Load real data'));
    await tester.pump();
    await tester.tap(find.text('Load real data'));
    await tester.pump();

    expect(find.text('Enter your Todoist API token first'), findsOneWidget);
    expect(finished, isFalse);
  });

  testWidgets('a valid token imports every Todoist task before finishing',
      (tester) async {
    fake.tasks['1'] = {
      'id': '1',
      'content': 'Real task',
      'description': '',
      'project_id': null,
      'labels': <String>[],
      'due': null,
    };
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: WebDataChoicePage(onFinished: () => finished = true),
    ));
    await settleIo(tester, rounds: 5);

    await tester.enterText(find.byType(TextField), 'good-token');
    await tester.ensureVisible(find.text('Load real data'));
    await tester.pump();
    await tester.tap(find.text('Load real data'));
    await settleIo(tester);

    expect(finished, isTrue);
    expect(Config.webRealData, isTrue);
    expect(Config.todoistApiToken, 'good-token');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WebDataChoicePage.tokenPrefKey), 'good-token');
    // Undated, so only the background phase pulls it — awaited here.
    final tasks =
        await tester.runAsync(() => StorageService().loadTaskList());
    expect(tasks!.map((t) => t.title), contains('Real task'));
  });

  testWidgets('an invalid token shows an error and stays on demo storage',
      (tester) async {
    fake.failAuth = true;
    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: WebDataChoicePage(onFinished: () => finished = true),
    ));
    await settleIo(tester, rounds: 5);

    await tester.enterText(find.byType(TextField), 'bad-token');
    await tester.ensureVisible(find.text('Load real data'));
    await tester.pump();
    await tester.tap(find.text('Load real data'));
    await settleIo(tester, rounds: 40);

    expect(find.text('Invalid API token'), findsOneWidget);
    expect(finished, isFalse);
    expect(Config.webRealData, isFalse);
  });
}
