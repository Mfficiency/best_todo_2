import 'dart:convert';

import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _task(
  String id,
  String title, {
  String project = 'p1',
  String description = '',
  List<String> labels = const ['agentdesk'],
  String? due,
  String? added,
}) =>
    {
      'id': id,
      'content': title,
      'project_id': project,
      'description': description,
      'labels': labels,
      if (due != null) 'due': {'date': due},
      if (added != null) 'added_at': added,
    };

const _projects = {'p1': 'Photos', 'p2': 'Deals'};

void main() {
  group('parseDeskMarkers', () {
    test('takes the markers out of the Markdown', () {
      final (body, markers) = parseDeskMarkers(
          '[Topic: Printer]\n[Option: Yes, switch it]\n[Option: Not yet]\n\n'
          '# Context\n\nA [real link](https://x.y) stays.');
      expect(markers['topic'], ['Printer']);
      expect(markers['option'], ['Yes, switch it', 'Not yet']);
      expect(body, '# Context\n\nA [real link](https://x.y) stays.');
    });

    test('drops the trailer a full sync may have added', () {
      final (body, _) = parseDeskMarkers(
          'Context\n\n⸻ BestToDo sync — generated, do not edit below\n'
          'sync-data: {"uid":"u"}');
      expect(body, isNot(contains('sync-data')));
      expect(body, startsWith('Context'));
    });
  });

  group('DeskBoard', () {
    test('sorts tasks into questions, answers, instructions and status', () {
      final board = DeskBoard.fromRemote([
        _task('s', 'Batch 1 running', labels: ['agentdesk', 'agentdesk_status'],
            description: '[State: working]\n[Where: beast]\n\nThe brief.'),
        _task('q', 'A question?'),
        _task('a', 'Answered', labels: ['agentdesk', 'agentdesk_answered']),
        _task('i', 'Do this', labels: ['agentdesk', 'agentdesk_instruction']),
        _task('other', 'Not on the desk', labels: ['home']),
      ], _projects);

      expect(board.projects, hasLength(1));
      final p = board.projects.single;
      expect(p.name, 'Photos');
      expect(p.state, DeskState.working);
      expect(p.where, 'beast');
      expect(p.summary, 'Batch 1 running');
      expect(p.brief, 'The brief.');
      expect(p.open.map((i) => i.id), ['q']);
      expect(p.answered.map((i) => i.id), ['a']);
      expect(p.instructions.map((i) => i.id), ['i']);
    });

    test('ranks blocking, then deadline, then oldest, later last', () {
      final board = DeskBoard.fromRemote([
        _task('later', 'l', description: '[Priority: later]', due: '2020-01-01'),
        _task('old', 'o', added: '2026-01-01T00:00:00Z'),
        _task('new', 'n', added: '2026-06-01T00:00:00Z'),
        _task('due', 'd', project: 'p2', due: '2026-12-01'),
        _task('block', 'b', description: '[Priority: blocking]'),
      ], _projects);
      expect(board.open.map((i) => i.id),
          ['block', 'due', 'old', 'new', 'later']);
    });

    test('a task in the Inbox lands in General', () {
      final board = DeskBoard.fromRemote(
          [_task('q', 'Q', project: 'inbox')], _projects);
      expect(board.projects.single.name, deskGeneralProject);
    });
  });

  group('DeskComment', () {
    test('reads an answer and a file attachment', () {
      final answer = DeskComment.fromJson({'content': '[Answer] Yes'});
      expect(answer.isAnswer, isTrue);
      expect(answer.text, 'Yes');

      final file = DeskComment.fromJson({
        'content': '',
        'file_attachment': {
          'file_name': 'shot.PNG',
          'file_url': 'https://files.todoist.com/shot.PNG',
          'file_type': 'image/png',
        },
      });
      expect(file.attachment!.name, 'shot.PNG');
      expect(file.attachment!.isImage, isTrue);
      expect(DeskComment.fromJson({'content': 'x'}).attachment, isNull);
    });
  });

  group('AgentDeskService', () {
    late List<http.Request> requests;

    AgentDeskService service(
        http.Response Function(http.Request) respond) {
      requests = [];
      return AgentDeskService(
        token: 'secret',
        httpClient: () => MockClient((r) async {
          requests.add(r);
          return respond(r);
        }),
      );
    }

    http.Response page(List<Map<String, dynamic>> results) =>
        http.Response(jsonEncode({'results': results, 'next_cursor': null}), 200);

    test('asks Todoist for the desk label only', () async {
      final s = service((r) => r.url.path.endsWith('/projects')
          ? page([
              {'id': 'p1', 'name': 'Photos'},
            ])
          : page([_task('q', 'Q')]));
      final board = await s.refresh();
      expect(board.open.single.project, 'Photos');
      final tasksCall = requests.firstWhere((r) => r.url.path.endsWith('/tasks'));
      expect(tasksCall.url.queryParameters['label'], 'agentdesk');
    });

    test('an answer is a comment plus a label, and touches nothing else',
        () async {
      final s = service((_) => http.Response('{}', 200));
      await s.answer(
        const DeskItem(
            id: '7', project: 'P', title: 'Q', labels: ['agentdesk', 'mine']),
        ' Yes ',
      );
      final comment = requests[0];
      expect(comment.url.path, endsWith('/comments'));
      expect(jsonDecode(comment.body),
          {'task_id': '7', 'content': '[Answer] Yes'});
      final label = requests[1];
      expect(label.url.path, endsWith('/tasks/7'));
      expect(jsonDecode(label.body), {
        'labels': ['agentdesk', 'mine', 'agentdesk_answered'],
      });
    });

    test('an instruction goes into the project, created if it is new',
        () async {
      final s = service((r) {
        if (r.url.path.endsWith('/projects') && r.method == 'GET') {
          return page([]);
        }
        if (r.url.path.endsWith('/projects')) {
          return http.Response(jsonEncode({'id': 'new'}), 200);
        }
        return http.Response(jsonEncode({'id': 't'}), 200);
      });
      await s.instruct('Deals', 'Watch flights');
      final created = jsonDecode(requests.last.body);
      expect(created['content'], 'Watch flights');
      expect(created['project_id'], 'new');
      expect(created['labels'], ['agentdesk', 'agentdesk_instruction']);
    });

    test('the token only ever goes to Todoist', () {
      final s = AgentDeskService(token: 'secret');
      expect(s.headersFor('https://files.todoist.com/a.png'),
          {'Authorization': 'Bearer secret'});
      expect(s.headersFor('https://evil.example/a.png'), isEmpty);
      expect(s.headersFor('https://todoist.com.evil.example/a.png'), isEmpty);
      expect(s.headersFor('http://files.todoist.com/a.png'), isEmpty);
    });
  });

  group('ItemViews gate', () {
    test('desk tasks a full sync mirrored stay out of every other view', () {
      final desk = Task(title: 'Q', label: 'agentdesk');
      expect(ItemViews.isVisibleInMainViews(desk), isFalse);
      expect(
          ItemViews.isVisibleInMainViews(desk, includeWorklistItems: true),
          isFalse);
      final stamped = Task(title: 'Q', label: 'agentdesk, Waiting_for_approval');
      expect(ItemViews.waitingApproval([stamped]), isEmpty);
    });
  });
}
