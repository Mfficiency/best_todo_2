import 'dart:convert';

import 'package:besttodo/services/todoist_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('TodoistApiClient', () {
    test('sends a bearer token and parses a task list', () async {
      http.Request? captured;
      final client = TodoistApiClient(
        apiToken: 'secret-token',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {'id': '1', 'content': 'A'},
              {'id': '2', 'content': 'B'},
            ]),
            200,
          );
        }),
      );

      final tasks = await client.fetchActiveTasks();

      expect(captured!.headers['Authorization'], 'Bearer secret-token');
      expect(captured!.url.toString(), '${TodoistApiClient.baseUrl}/tasks');
      expect(tasks.length, 2);
      expect(tasks[0]['content'], 'A');
    });

    test('a non-2xx response throws TodoistApiException with the status code',
        () async {
      final client = TodoistApiClient(
        apiToken: 'bad-token',
        client:
            MockClient((request) async => http.Response('Unauthorized', 401)),
      );

      expect(
        () => client.fetchProjects(),
        throwsA(isA<TodoistApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('createTask posts content, description, due date and labels',
        () async {
      http.Request? captured;
      final client = TodoistApiClient(
        apiToken: 't',
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'id': '9'}), 200);
        }),
      );

      await client.createTask(
        content: 'Title',
        description: 'Desc',
        projectId: 'p1',
        dueDate: '2026-09-01',
        labels: const ['work'],
      );

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['content'], 'Title');
      expect(body['description'], 'Desc');
      expect(body['project_id'], 'p1');
      expect(body['due_date'], '2026-09-01');
      expect(body['labels'], ['work']);
      expect(body.containsKey('due_datetime'), isFalse);
    });

    test('updateTask with clearDue sends due_string "no date"', () async {
      http.Request? captured;
      final client = TodoistApiClient(
        apiToken: 't',
        client: MockClient((request) async {
          captured = request;
          return http.Response('', 204);
        }),
      );

      await client.updateTask('7',
          content: 'Title', description: '', clearDue: true);

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['due_string'], 'no date');
      expect(body.containsKey('due_date'), isFalse);
      expect(body.containsKey('due_datetime'), isFalse);
    });

    test('deleteTask sends a DELETE request to the task id', () async {
      String? method;
      String? path;
      final client = TodoistApiClient(
        apiToken: 't',
        client: MockClient((request) async {
          method = request.method;
          path = request.url.path;
          return http.Response('', 204);
        }),
      );

      await client.deleteTask('42');

      expect(method, 'DELETE');
      expect(path, endsWith('/tasks/42'));
    });

    test('closeTask and reopenTask hit their sub-paths', () async {
      final calledPaths = <String>[];
      final client = TodoistApiClient(
        apiToken: 't',
        client: MockClient((request) async {
          calledPaths.add(request.url.path);
          return http.Response('', 204);
        }),
      );

      await client.closeTask('5');
      await client.reopenTask('5');

      expect(calledPaths, ['/rest/v2/tasks/5/close', '/rest/v2/tasks/5/reopen']);
    });
  });
}
