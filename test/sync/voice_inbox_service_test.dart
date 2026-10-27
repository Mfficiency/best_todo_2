import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/claude_routine_service.dart';
import 'package:besttodo/services/item_repository.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/todoist_api_client.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:besttodo/services/voice_inbox_service.dart';
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

/// Just enough of Todoist for a sync run plus comments.
class _FakeTodoist {
  int _nextId = 1;
  final Map<String, Map<String, dynamic>> tasks = {};
  final Map<String, List<String>> comments = {};

  http.Response _json(Object data) => http.Response(jsonEncode(data), 200,
      headers: const {'content-type': 'application/json; charset=utf-8'});

  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    final method = request.method;
    if (method == 'GET' && path == '/api/v1/tasks') {
      return _json({'results': tasks.values.toList(), 'next_cursor': null});
    }
    if (method == 'GET' && path == '/api/v1/projects') {
      return _json({'results': [], 'next_cursor': null});
    }
    if (method == 'POST' && path == '/api/v1/projects') {
      final id = 'p${_nextId++}';
      return _json({'id': id, 'name': jsonDecode(request.body)['name']});
    }
    if (method == 'POST' && path == '/api/v1/tasks') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = '${_nextId++}';
      tasks[id] = {
        'id': id,
        'content': body['content'],
        'description': body['description'] ?? '',
        'project_id': body['project_id'],
        'labels': body['labels'] ?? [],
        'due': null,
      };
      return _json(tasks[id]!);
    }
    if (method == 'GET' && path == '/api/v1/comments') {
      final id = request.url.queryParameters['task_id']!;
      return _json({
        'results': [
          for (final c in comments[id] ?? const <String>[]) {'content': c}
        ],
        'next_cursor': null,
      });
    }
    if (method == 'POST' && path == '/api/v1/comments') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      comments.putIfAbsent(body['task_id'] as String, () => [])
          .add(body['content'] as String);
      return _json({'id': 'c', 'content': body['content']});
    }
    final idMatch = RegExp(r'^/api/v1/tasks/([^/]+)(/move)?$').firstMatch(path);
    if (method == 'POST' && idMatch != null) {
      final existing = tasks[idMatch.group(1)!]!;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      existing.addAll({
        if (body['content'] != null) 'content': body['content'],
        if (body['description'] != null) 'description': body['description'],
        if (body['labels'] != null) 'labels': body['labels'],
        if (body['project_id'] != null) 'project_id': body['project_id'],
      });
      return _json(existing);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  late _FakeTodoist fake;
  late List<String> fired;
  late VoiceInboxService service;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('voice_inbox');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await File('${dir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    StorageService.resetJournalBaselineForTest();
    ProjectService.instance.resetForTest();
    TodoistSyncService.resetForTest();
    fake = _FakeTodoist();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);
    Config.todoistSyncEnabled = true;
    Config.todoistApiToken = 'todoist-token';
    Config.voiceInboxRoutineUrl = 'https://api.example/fire';
    Config.voiceInboxRoutineToken = 'routine-token';
    fired = [];
    service = VoiceInboxService(
      routine: ClaudeRoutineService(
        client: MockClient((request) async {
          fired.add((jsonDecode(request.body) as Map)['text'] as String);
          return http.Response(
              jsonEncode({'claude_code_session_id': 's1'}), 200);
        }),
      ),
    );
  });

  tearDown(() {
    Config.todoistSyncEnabled = false;
    Config.todoistApiToken = '';
    Config.voiceInboxRoutineUrl = '';
    Config.voiceInboxRoutineToken = '';
    TodoistSyncService.resetForTest();
  });

  test('isConfigured needs the routine and Todoist sync', () {
    expect(VoiceInboxService.isConfigured, isTrue);
    Config.todoistSyncEnabled = false;
    expect(VoiceInboxService.isConfigured, isFalse);
  });

  test('parseReplies reads the newest questions, answers and done link', () {
    final reply = VoiceInboxService.parseReplies([
      '[Questions]\n1. Budget?\n2) Timeline?\n- Who for?',
      'just a human note',
      '[Done] obsidian://open?vault=v&file=a.md and some text',
    ]);
    expect(reply.questions, ['Budget?', 'Timeline?', 'Who for?']);
    expect(reply.answered, isFalse);
    expect(reply.doneLink, 'obsidian://open?vault=v&file=a.md');

    final answered = VoiceInboxService.parseReplies(
        ['[Questions]\n1. Budget?', '[Answers]\n1. Budget?\n   → 50']);
    expect(answered.answered, isTrue);
  });

  test('formatAnswers numbers each question and marks skipped ones', () {
    expect(
      VoiceInboxService.formatAnswers(['Budget?', 'Timeline?'], ['50 CHF', '']),
      '[Answers]\n1. Budget?\n   → 50 CHF\n2. Timeline?\n   → (skipped)',
    );
  });

  test(
      'a write-page request syncs the item to Todoist first and fires the '
      'routine with its Todoist id; the [Done] comment brings the link',
      () async {
    final wish = Task(title: 'Widget dark mode', isWish: true);
    await StorageService().saveTaskList([wish]);

    VoiceInboxService.markObsidianRequested(wish);
    final tasks = await ItemRepository.instance.loadItems();
    tasks.single.obsidianRequestedAt = wish.obsidianRequestedAt;
    await ItemRepository.instance.saveItems(tasks);
    final error = await service.runFire(
        wish, () => service.fireWritePage(wish), (t) {});
    expect(error, isNull);

    final remoteId = fake.tasks.keys.single;
    expect(fired.single, startsWith('MODE: write-page\n'));
    final payload = jsonDecode(fired.single.split('\n').skip(1).join('\n'))
        as Map<String, dynamic>;
    expect(payload['todoistTaskId'], remoteId);
    expect(payload['title'], 'Widget dark mode');
    expect(payload['kind'], 'backlog');

    expect(VoiceInboxService.isWaiting(wish), isTrue);
    fake.comments[remoteId] = ['[Done] obsidian://open?file=w.md'];
    expect(await service.refresh(wish), isTrue);
    expect(wish.obsidianLink, 'obsidian://open?file=w.md');
    expect(VoiceInboxService.isWaiting(wish), isFalse);
  });

  test('a failed fire takes the mark back, also on the stored copy',
      () async {
    final failing = VoiceInboxService(
      routine: ClaudeRoutineService(
          client: MockClient((_) async => http.Response('nope', 401))),
    );
    final wish = Task(title: 'Idea', isWish: true);
    VoiceInboxService.markObsidianRequested(wish);
    await StorageService().saveTaskList([wish]);

    final error = await failing.runFire(wish, () => failing.fireWritePage(wish),
        (t) => t.obsidianRequestedAt = null);
    expect(error, 'Claude routine error 401');
    expect(wish.obsidianRequestedAt, isNull);
    final stored = (await ItemRepository.instance.loadItems()).single;
    expect(stored.obsidianRequestedAt, isNull);
  });

  test(
      'the research round: questions arrive as a comment, answers go back as '
      'a comment plus a second fire, the done link makes it ready', () async {
    final item = Task(title: 'Heat battery maths', isResearch: true,
        label: 'release-next');
    VoiceInboxService.markResearchRequested(item);
    await StorageService().saveTaskList([item]);

    await service.fireResearchQuestions(item);
    expect(fired.single, startsWith('MODE: research-questions\n'));
    final remoteId = fake.tasks.keys.single;

    expect(await service.refresh(item), isFalse); // nothing yet
    fake.comments[remoteId] = ['[Questions]\n1. Which size?\n2. Which salt?'];
    expect(await service.refresh(item), isTrue);
    expect(item.researchStage, ResearchStages.questions);
    expect(item.researchQuestions, ['Which size?', 'Which salt?']);

    await service.sendAnswers(item, ['1 m³', '']);
    expect(fake.comments[remoteId]!.last, startsWith('[Answers]'));
    expect(fired.last, startsWith('MODE: research-answers\n'));
    expect(fired.last, contains('"answer": "1 m³"'));

    item.researchStage = ResearchStages.answered;
    fake.comments[remoteId]!.add('[Done] obsidian://open?file=r.md');
    expect(await service.refresh(item), isTrue);
    expect(item.researchStage, ResearchStages.ready);
    expect(item.obsidianLink, 'obsidian://open?file=r.md');
  });
}
