import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_repository.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/todoist_api_client.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
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

/// A minimal in-memory stand-in for Todoist's unified API v1, routed through
/// `http.testing.MockClient` so `TodoistSyncService` talks to it exactly as
/// it would talk to the real API. Only active tasks are tracked — closing a
/// task removes it, matching the real API having no completed-task listing.
class _FakeTodoist {
  int _nextId = 1;
  final Map<String, Map<String, dynamic>> tasks = {};
  final Map<String, Map<String, dynamic>> projects = {};
  bool failAuth = false;

  String _newId() => '${_nextId++}';

  String seedInboxProject() {
    final id = _newId();
    projects[id] = {'id': id, 'name': 'Inbox', 'is_inbox_project': true};
    return id;
  }

  String seedTask({
    required String content,
    String description = '',
    Map<String, dynamic>? due,
    String? projectId,
    List<String> labels = const [],
  }) {
    final id = _newId();
    tasks[id] = {
      'id': id,
      'content': content,
      'description': description,
      'project_id': projectId,
      'labels': labels,
      'due': due,
    };
    return id;
  }

  // v1's `due` has a single `date` field (unlike REST v2's separate
  // `date`/`datetime` keys) that holds either a bare date or a full
  // datetime string — see `TodoistSyncService._applyRemoteDue`.
  Map<String, dynamic>? _dueFromBody(Map<String, dynamic> body) {
    if (body['due_datetime'] != null) {
      return {'date': body['due_datetime'], 'string': ''};
    }
    if (body['due_date'] != null) {
      return {'date': body['due_date'], 'string': ''};
    }
    return null;
  }

  // `http.Response(String, ...)` defaults to Latin-1 when no charset is
  // given, which breaks on the trailer's non-Latin-1 punctuation (⸻, —) —
  // the real Todoist API is UTF-8 throughout, so the fake has to say so too.
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
    if (method == 'POST' && path == '/api/v1/tasks') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = _newId();
      final task = <String, dynamic>{
        'id': id,
        'content': body['content'],
        'description': body['description'] ?? '',
        'project_id': body['project_id'],
        'labels': body['labels'] ?? [],
        'due': _dueFromBody(body),
      };
      tasks[id] = task;
      return _json(task);
    }
    if (method == 'POST' && path == '/api/v1/projects') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = _newId();
      final project = <String, dynamic>{'id': id, 'name': body['name']};
      projects[id] = project;
      return _json(project);
    }
    final projectIdMatch =
        RegExp(r'^/api/v1/projects/([^/]+)$').firstMatch(path);
    if (method == 'POST' && projectIdMatch != null) {
      final id = projectIdMatch.group(1)!;
      final existing = projects[id];
      if (existing == null) return http.Response('', 404);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      existing['name'] = body['name'] ?? existing['name'];
      return _json(existing);
    }
    final closeMatch =
        RegExp(r'^/api/v1/tasks/([^/]+)/close$').firstMatch(path);
    if (method == 'POST' && closeMatch != null) {
      final id = closeMatch.group(1)!;
      if (!tasks.containsKey(id)) return http.Response('', 404);
      tasks.remove(id);
      return http.Response('', 204);
    }
    final reopenMatch =
        RegExp(r'^/api/v1/tasks/([^/]+)/reopen$').firstMatch(path);
    if (method == 'POST' && reopenMatch != null) {
      return http.Response('', 204);
    }
    final moveMatch = RegExp(r'^/api/v1/tasks/([^/]+)/move$').firstMatch(path);
    if (method == 'POST' && moveMatch != null) {
      final id = moveMatch.group(1)!;
      final existing = tasks[id];
      if (existing == null) return http.Response('', 404);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      existing['project_id'] = body['project_id'];
      return _json(existing);
    }
    final idMatch = RegExp(r'^/api/v1/tasks/([^/]+)$').firstMatch(path);
    if (method == 'POST' && idMatch != null) {
      final id = idMatch.group(1)!;
      final existing = tasks[id];
      if (existing == null) return http.Response('', 404);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      existing['content'] = body['content'] ?? existing['content'];
      existing['description'] =
          body['description'] ?? existing['description'];
      existing['labels'] = body['labels'] ?? existing['labels'];
      if (body['due_string'] == 'no date') {
        existing['due'] = null;
      } else if (body['due_datetime'] != null || body['due_date'] != null) {
        existing['due'] = _dueFromBody(body);
      }
      return _json(existing);
    }
    if (method == 'DELETE' && idMatch != null) {
      final id = idMatch.group(1)!;
      if (!tasks.containsKey(id)) return http.Response('', 404);
      tasks.remove(id);
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  late Directory docsDir;
  late _FakeTodoist fake;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('todoist_sync_docs');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    // Opts out of the one-time Todo.md → wishlist import loadTaskList runs
    // on first load, which would otherwise show up as extra local tasks.
    await File('${docsDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    StorageService.resetJournalBaselineForTest();
    ProjectService.instance.resetForTest();
    TodoistSyncService.resetForTest();
    fake = _FakeTodoist();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);
    Config.todoistSyncEnabled = true;
    Config.todoistApiToken = 'test-token';
  });

  tearDown(() {
    Config.todoistSyncEnabled = false;
    Config.todoistApiToken = '';
    TodoistSyncService.resetForTest();
  });

  test('syncNow is a no-op when disabled or without a token', () async {
    Config.todoistSyncEnabled = false;
    expect(await TodoistSyncService.instance.syncNow(), isNull);

    Config.todoistSyncEnabled = true;
    Config.todoistApiToken = '';
    expect(await TodoistSyncService.instance.syncNow(), isNull);
    expect(fake.tasks, isEmpty);
  });

  test('a new local task is pushed to Todoist and the mapping is stable',
      () async {
    await StorageService().saveTaskList([
      Task(
        title: 'Write report',
        description: 'Quarterly numbers',
        note: 'ask Sam first',
        label: 'work',
      ),
    ]);

    final entry = await TodoistSyncService.instance.syncNow();

    expect(entry!.success, isTrue);
    expect(entry.itemCount, 1);
    expect(fake.tasks.length, 1);
    final remote = fake.tasks.values.single;
    expect(remote['content'], 'Write report');
    expect(remote['description'], contains('Quarterly numbers'));
    expect(remote['description'], contains('sync-data:'));
    expect(remote['description'], contains('ask Sam first'));
    expect(remote['labels'], contains('work'));

    // A second sync with nothing changed on either side is a true no-op:
    // no duplicate task, no wasted API calls.
    final second = await TodoistSyncService.instance.syncNow();
    expect(second!.itemCount, 0);
    expect(fake.tasks.length, 1);
  });

  test('a label added on the Todoist side (native labels, not the '
      'description trailer) is pulled into the local task', () async {
    await StorageService().saveTaskList([
      Task(title: 'Write report', label: 'work'),
    ]);
    await TodoistSyncService.instance.syncNow();
    final remoteId = fake.tasks.keys.single;

    // Simulate editing the task's labels directly in Todoist's own UI: only
    // the native `labels` field changes, never the description trailer.
    fake.tasks[remoteId]!['labels'] = ['work', 'urgent'];
    final second = await TodoistSyncService.instance.syncNow();

    expect(second!.itemCount, 1);
    final tasks = await ItemRepository.instance.loadItems();
    final pulled = tasks.firstWhere((t) => t.title == 'Write report');
    expect(pulled.label, 'work, urgent');
  });

  test('a label removed on the Todoist side is pulled into the local task',
      () async {
    await StorageService().saveTaskList([
      Task(title: 'Write report', label: 'work, urgent'),
    ]);
    await TodoistSyncService.instance.syncNow();
    final remoteId = fake.tasks.keys.single;

    fake.tasks[remoteId]!['labels'] = ['work'];
    final second = await TodoistSyncService.instance.syncNow();

    expect(second!.itemCount, 1);
    final tasks = await ItemRepository.instance.loadItems();
    final pulled = tasks.firstWhere((t) => t.title == 'Write report');
    expect(pulled.label, 'work');
  });

  test('the sync mapping survives a restart (no duplicate is created)',
      () async {
    await StorageService().saveTaskList([Task(title: 'Once')]);
    await TodoistSyncService.instance.syncNow();
    expect(fake.tasks.length, 1);

    TodoistSyncService.resetForTest();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 0);
    expect(fake.tasks.length, 1);
  });

  test('editing a synced task pushes the update', () async {
    await StorageService()
        .saveTaskList([Task(title: 'Draft', description: 'v1')]);
    await TodoistSyncService.instance.syncNow();
    final id = fake.tasks.keys.single;

    final tasks = await StorageService().loadTaskList();
    tasks.single.description = 'v2';
    await StorageService().saveTaskList(tasks);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    expect(fake.tasks[id]!['description'], contains('v2'));
  });

  test('completing a task locally closes it on Todoist', () async {
    await StorageService().saveTaskList([Task(title: 'Ship it')]);
    await TodoistSyncService.instance.syncNow();
    expect(fake.tasks.length, 1);

    final tasks = await StorageService().loadTaskList();
    tasks.single.isDone = true;
    await StorageService().saveTaskList(tasks);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    expect(fake.tasks, isEmpty);
  });

  test('deleting a task locally deletes it on Todoist', () async {
    await StorageService().saveTaskList([Task(title: 'Cancel me')]);
    await TodoistSyncService.instance.syncNow();
    expect(fake.tasks.length, 1);

    await StorageService().saveTaskList(<Task>[]);
    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    expect(fake.tasks, isEmpty);
  });

  test('a task created in Todoist is pulled into the local list', () async {
    fake.seedTask(content: 'From Todoist', description: 'entered on the go');

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);

    final tasks = await ItemRepository.instance.loadItems();
    expect(tasks.single.title, 'From Todoist');
    expect(tasks.single.description, 'entered on the go');
  });

  test('a task completed in Todoist is marked done locally', () async {
    await StorageService().saveTaskList([Task(title: 'Finish slides')]);
    await TodoistSyncService.instance.syncNow();
    final id = fake.tasks.keys.single;
    fake.tasks.remove(id); // simulate completion on Todoist's side

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    final tasks = await ItemRepository.instance.loadItems();
    expect(tasks.single.isDone, isTrue);
  });

  test('conflicting edits on both sides favor the local edit', () async {
    await StorageService()
        .saveTaskList([Task(title: 'Original', description: 'v1')]);
    await TodoistSyncService.instance.syncNow();
    final id = fake.tasks.keys.single;

    final tasks = await StorageService().loadTaskList();
    tasks.single.description = 'local edit';
    await StorageService().saveTaskList(tasks);
    fake.tasks[id]!['description'] = 'remote edit';

    await TodoistSyncService.instance.syncNow();

    expect(fake.tasks[id]!['description'], contains('local edit'));
    final reloaded = await ItemRepository.instance.loadItems();
    expect(reloaded.single.description, 'local edit');
  });

  test('recurring tasks are never synced', () async {
    await StorageService().saveTaskList([
      Task(title: 'Repeats', isRecurring: true, dueDate: DateTime.now()),
    ]);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 0);
    expect(fake.tasks, isEmpty);
  });

  test('a wishlist item pushes into a dedicated Wishlist Todoist project',
      () async {
    await StorageService()
        .saveTaskList([Task(title: 'Someday', isWish: true)]);

    final entry = await TodoistSyncService.instance.syncNow();

    expect(entry!.itemCount, 1);
    expect(fake.projects.values.single['name'], 'Wishlist');
    final remote = fake.tasks.values.single;
    expect(remote['project_id'], fake.projects.keys.single);

    // A second sync with nothing changed is a true no-op.
    final second = await TodoistSyncService.instance.syncNow();
    expect(second!.itemCount, 0);
  });

  test(
      'an undated, unprojected task pushes into a dedicated Future Todoist '
      'project', () async {
    await StorageService().saveTaskList([Task(title: 'Someday, maybe')]);

    final entry = await TodoistSyncService.instance.syncNow();

    expect(entry!.itemCount, 1);
    expect(fake.projects.values.single['name'], 'Future');
    final remote = fake.tasks.values.single;
    expect(remote['project_id'], fake.projects.keys.single);

    final second = await TodoistSyncService.instance.syncNow();
    expect(second!.itemCount, 0);
  });

  test('a dated or projected task never lands in Wishlist or Future',
      () async {
    await StorageService().saveTaskList([
      Task(title: 'Due today', dueDate: DateTime.now()),
    ]);

    await TodoistSyncService.instance.syncNow();

    expect(fake.projects, isEmpty);
    expect(fake.tasks.values.single['project_id'], isNull);
  });

  test('the wishlist flag wins over a Kanban project assignment, and '
      'toggling it off actually moves the Todoist task', () async {
    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch'));
    await StorageService()
        .saveTaskList([Task(title: 'Ship', projectId: 'p1', isWish: true)]);

    await TodoistSyncService.instance.syncNow();
    expect(fake.projects.values.single['name'], 'Wishlist');
    final taskId = fake.tasks.keys.single;

    final tasks = await StorageService().loadTaskList();
    tasks.single.isWish = false;
    await StorageService().saveTaskList(tasks);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    final launchProjectId =
        fake.projects.values.firstWhere((p) => p['name'] == 'Launch')['id'];
    // The move actually happened on the Todoist side, not just in local
    // bookkeeping — updateTask alone can't reassign a task's project.
    expect(fake.tasks[taskId]!['project_id'], launchProjectId);
  });

  test('a task leaving the wishlist with no other project moves back to '
      'Todoist Inbox', () async {
    final inboxId = fake.seedInboxProject();
    await StorageService().saveTaskList([Task(title: 'Ship', isWish: true)]);
    await TodoistSyncService.instance.syncNow();
    expect(fake.projects.values.firstWhere((p) => p['name'] == 'Wishlist'),
        isNotNull);
    final taskId = fake.tasks.keys.single;

    final tasks = await StorageService().loadTaskList();
    tasks.single.isWish = false;
    tasks.single.dueDate = DateTime.now();
    await StorageService().saveTaskList(tasks);

    await TodoistSyncService.instance.syncNow();

    expect(fake.tasks[taskId]!['project_id'], inboxId);
  });

  test(
      'a task already synced to Inbox before this app routed undated tasks '
      'to Future moves there once the mapping is recomputed', () async {
    const uid = 'legacy-undated-uid';
    final remoteId = fake.seedTask(content: 'Old undated task');
    // Simulate a sync map entry written by a version of this app with no
    // Future-project routing: pushed to Inbox (todoistProjectId: null), its
    // fingerprint computed without the project key this app now folds in —
    // any stale value forces the next run to treat it as locally changed.
    final stateFile = File('${docsDir.path}/todoist_sync_state.json');
    await stateFile.writeAsString(jsonEncode({
      'taskEntries': [
        {
          'localUid': uid,
          'todoistId': remoteId,
          'localFingerprint': 'stale',
          'remoteFingerprint': 'stale',
          'syncedAt': DateTime.now().toIso8601String(),
        }
      ],
      'projectMap': <String, dynamic>{},
    }));
    await StorageService()
        .saveTaskList([Task(uid: uid, title: 'Old undated task')]);

    await TodoistSyncService.instance.syncNow();

    final futureProjectId =
        fake.projects.values.firstWhere((p) => p['name'] == 'Future')['id'];
    expect(fake.tasks[remoteId]!['project_id'], futureProjectId);
  });

  test('a task pulled from the Wishlist Todoist project becomes a local '
      'wishlist item', () async {
    const wishlistProjectId = 'remote-wishlist-project';
    fake.projects[wishlistProjectId] = {
      'id': wishlistProjectId,
      'name': 'Wishlist',
    };
    fake.seedTask(
        content: 'From Todoist wishlist', projectId: wishlistProjectId);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    final tasks = await ItemRepository.instance.loadItems();
    final pulled = tasks.firstWhere((t) => t.title == 'From Todoist wishlist');
    expect(pulled.isWish, isTrue);
    expect(pulled.projectId, isNull);
  });

  test('a task pulled from the Future Todoist project stays unassigned '
      'locally, not flagged as a wishlist item', () async {
    const futureProjectId = 'remote-future-project';
    fake.projects[futureProjectId] = {'id': futureProjectId, 'name': 'Future'};
    fake.seedTask(content: 'From Todoist future', projectId: futureProjectId);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.itemCount, 1);
    final tasks = await ItemRepository.instance.loadItems();
    final pulled = tasks.firstWhere((t) => t.title == 'From Todoist future');
    expect(pulled.isWish, isFalse);
    expect(pulled.projectId, isNull);
  });

  test(
      'due dates round-trip: explicit time via datetime, date-only defaults '
      'to 18:00', () async {
    await StorageService().saveTaskList([
      Task(
        title: 'Timed',
        dueDate: DateTime(2026, 9, 1, 14, 30),
        hasExplicitTime: true,
      ),
      Task(title: 'DateOnly', dueDate: DateTime(2026, 9, 2, 18, 0)),
    ]);

    await TodoistSyncService.instance.syncNow();

    final timed = fake.tasks.values.firstWhere((t) => t['content'] == 'Timed');
    expect(timed['due']['date'], contains('T'));
    final dateOnly =
        fake.tasks.values.firstWhere((t) => t['content'] == 'DateOnly');
    expect(dateOnly['due']['date'], '2026-09-02');

    fake.seedTask(
      content: 'PulledDated',
      due: {'date': '2026-09-05'},
    );
    await TodoistSyncService.instance.syncNow();
    final tasks = await ItemRepository.instance.loadItems();
    final pulled = tasks.firstWhere((t) => t.title == 'PulledDated');
    expect(pulled.hasExplicitTime, isFalse);
    expect(pulled.dueDate, DateTime(2026, 9, 5, 18, 0));
  });

  test('a task with a project pushes into a same-named Todoist project',
      () async {
    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch'));
    await StorageService()
        .saveTaskList([Task(title: 'Ship', projectId: 'p1')]);

    await TodoistSyncService.instance.syncNow();

    expect(fake.projects.values.single['name'], 'Launch');
    final remoteTask = fake.tasks.values.single;
    expect(remoteTask['project_id'], fake.projects.keys.single);
  });

  test('renaming a Kanban project locally renames its Todoist project',
      () async {
    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch'));
    await StorageService()
        .saveTaskList([Task(title: 'Ship', projectId: 'p1')]);
    await TodoistSyncService.instance.syncNow();
    final remoteProjectId = fake.projects.keys.single;

    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch v2'));
    final second = await TodoistSyncService.instance.syncNow();

    expect(second!.itemCount, 1);
    expect(fake.projects[remoteProjectId]!['name'], 'Launch v2');
  });

  test('renaming a Todoist project pulls the new name into the matching '
      'Kanban project', () async {
    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch'));
    await StorageService()
        .saveTaskList([Task(title: 'Ship', projectId: 'p1')]);
    await TodoistSyncService.instance.syncNow();
    final remoteProjectId = fake.projects.keys.single;

    fake.projects[remoteProjectId]!['name'] = 'Launch (renamed in Todoist)';
    final second = await TodoistSyncService.instance.syncNow();

    expect(second!.itemCount, 1);
    expect(ProjectService.instance.byId('p1')!.name,
        'Launch (renamed in Todoist)');
  });

  test('a project mapping that predates name-sync adopts the local name as '
      'its baseline instead of pushing a spurious rename', () async {
    await ProjectService.instance
        .upsert(const Project(id: 'p1', name: 'Launch'));
    await StorageService()
        .saveTaskList([Task(title: 'Ship', projectId: 'p1')]);
    await TodoistSyncService.instance.syncNow();
    final remoteProjectId = fake.projects.keys.single;

    // Wipe just the state file's baseline, as if it came from a build before
    // project-name sync existed: the mapping survives, but with no synced
    // name recorded yet.
    final stateFile = File('${docsDir.path}/todoist_sync_state.json');
    final state = jsonDecode(await stateFile.readAsString()) as Map;
    state.remove('projectNameMap');
    await stateFile.writeAsString(jsonEncode(state));
    TodoistSyncService.resetForTest();
    TodoistSyncService.instance.apiClientFactory =
        (token) => TodoistApiClient(apiToken: token, client: fake.client);

    final second = await TodoistSyncService.instance.syncNow();

    expect(second!.itemCount, 0);
    expect(fake.projects[remoteProjectId]!['name'], 'Launch');
  });

  test('an API failure records a failed sync entry and lights the flag',
      () async {
    fake.failAuth = true;
    await StorageService().saveTaskList([Task(title: 'X')]);

    final entry = await TodoistSyncService.instance.syncNow();
    expect(entry!.success, isFalse);
    expect(entry.message, isNotEmpty);
    expect(TodoistSyncService.instance.hasUnseenError.value, isTrue);
  });

  test('quitting syncs exactly once until the app is resumed', () async {
    await StorageService().saveTaskList([Task(title: 'Alpha')]);
    final service = TodoistSyncService.instance;

    service.onLifecycleChanged(AppLifecycleState.inactive);
    service.onLifecycleChanged(AppLifecycleState.hidden);
    await service.pendingQuitSync;
    service.onLifecycleChanged(AppLifecycleState.paused);
    service.onLifecycleChanged(AppLifecycleState.detached);
    await service.pendingQuitSync;

    expect(service.entries.value.length, 1);
    expect(service.entries.value.single.trigger, 'app quit');

    service.onLifecycleChanged(AppLifecycleState.resumed);
    service.onLifecycleChanged(AppLifecycleState.paused);
    await service.pendingQuitSync;

    expect(service.entries.value.length, 2);
  });

  test('the lifecycle hook does nothing without a token', () async {
    Config.todoistApiToken = '';
    final service = TodoistSyncService.instance;

    service.onLifecycleChanged(AppLifecycleState.paused);

    expect(service.pendingQuitSync, isNull);
    expect(service.entries.value, isEmpty);
  });

  group('startFirstLaunchImport (first-launch desktop import)', () {
    String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

    test('is a no-op when disabled or without a token', () async {
      Config.todoistSyncEnabled = false;
      expect(await TodoistSyncService.instance.startFirstLaunchImport(),
          isNull);

      Config.todoistSyncEnabled = true;
      Config.todoistApiToken = '';
      expect(await TodoistSyncService.instance.startFirstLaunchImport(),
          isNull);
    });

    test(
        "loads today's (and overdue) tasks synchronously, and the rest "
        'finishes in the background', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      final nextWeek = today.add(const Duration(days: 7));
      fake.seedTask(content: 'Due today', due: {'date': isoDate(today)});
      fake.seedTask(content: 'Overdue', due: {'date': isoDate(yesterday)});
      fake.seedTask(content: 'Next week', due: {'date': isoDate(nextWeek)});
      fake.seedTask(content: 'Someday'); // no due date -> Future bucket

      final result = await TodoistSyncService.instance.startFirstLaunchImport();
      expect(result, isNotNull);
      expect(result!.todayCount, 2);

      // Today's tasks are already on disk — the caller can open the home
      // screen right now — but the rest hasn't landed yet.
      final afterPhaseOne = await ItemRepository.instance.loadItems();
      expect(afterPhaseOne.map((t) => t.title).toSet(),
          {'Due today', 'Overdue'});
      expect(TodoistSyncService.instance.syncing.value, isTrue);

      final entry = await result.finishInBackground();
      expect(entry!.success, isTrue);
      expect(entry.itemCount, 4);
      expect(TodoistSyncService.instance.syncing.value, isFalse);

      final afterPhaseTwo = await ItemRepository.instance.loadItems();
      expect(afterPhaseTwo.map((t) => t.title).toSet(),
          {'Due today', 'Overdue', 'Next week', 'Someday'});
      expect(
        afterPhaseTwo.firstWhere((t) => t.title == 'Someday').dueDate,
        isNull,
      );
    });

    test('a task added locally while the background phase runs survives it',
        () async {
      fake.seedTask(content: 'Due today', due: {'date': isoDate(DateTime.now())});
      fake.seedTask(content: 'Later',
          due: {'date': isoDate(DateTime.now().add(const Duration(days: 3)))});

      final result = await TodoistSyncService.instance.startFirstLaunchImport();
      // Simulates the user adding a task while exploring the home screen,
      // before the background phase has saved anything of its own yet.
      final duringImport = await ItemRepository.instance.loadItems();
      duringImport.add(Task(title: 'Added while importing'));
      await ItemRepository.instance.saveItems(duringImport);

      await result!.finishInBackground();

      final finalTasks = await ItemRepository.instance.loadItems();
      expect(finalTasks.map((t) => t.title).toSet(),
          {'Due today', 'Later', 'Added while importing'});
    });

    test('an API failure surfaces to the caller and is logged', () async {
      fake.failAuth = true;

      await expectLater(
        TodoistSyncService.instance.startFirstLaunchImport(),
        throwsA(isA<TodoistApiException>()),
      );

      expect(TodoistSyncService.instance.syncing.value, isFalse);
      final logged = TodoistSyncService.instance.entries.value.single;
      expect(logged.success, isFalse);
      expect(logged.trigger, 'first_launch_import');

      // The in-flight guard was released on failure — a later import isn't
      // permanently blocked.
      fake.failAuth = false;
      expect(await TodoistSyncService.instance.startFirstLaunchImport(),
          isNotNull);
    });
  });
}
