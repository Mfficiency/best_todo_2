import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:besttodo/ui/agent_desk_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory desk: no file I/O or network inside testWidgets (see CLAUDE.md).
class _FakeDesk extends AgentDeskService {
  _FakeDesk(this.tasks, {this.isConnected = true}) : super(token: 't');

  List<Map<String, dynamic>> tasks;
  bool isConnected;
  bool failAnswers = false;
  bool seeded = false;
  String? token;
  final List<String> answers = [];
  final List<String> instructions = [];
  List<DeskComment> commentList = const [];

  DeskBoard get _board => DeskBoard.fromRemote(tasks, const {'p': 'Photos'});

  @override
  bool get connected => isConnected;

  @override
  Future<DeskBoard?> loadCached() async => null;

  @override
  Future<DeskBoard> refresh() async => _board;

  @override
  Future<List<DeskComment>> comments(DeskItem item) async => commentList;

  @override
  Future<void> answer(DeskItem item, String text) async {
    if (failAnswers) throw Exception('offline');
    answers.add('${item.id}: $text');
    final task = tasks.firstWhere((t) => t['id'] == item.id);
    task['labels'] = [...task['labels'] as List, 'agentdesk_answered'];
  }

  @override
  Future<void> instruct(String project, String text) async {
    instructions.add('$project: $text');
  }

  @override
  Future<void> seed() async {
    seeded = true;
  }

  @override
  Future<void> connect(String token) async {
    this.token = token;
    isConnected = true;
  }
}

Map<String, dynamic> _q(String id, String title,
        {String description = '', List<String> extra = const []}) =>
    {
      'id': id,
      'content': title,
      'project_id': 'p',
      'description': description,
      'labels': ['agentdesk', ...extra],
    };

Future<void> _pump(WidgetTester tester, _FakeDesk desk,
    {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AgentDeskPage(service: desk, pollInterval: null),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('on a PC: queue, the top item with its description, projects',
      (tester) async {
    final desk = _FakeDesk([
      _q('s', 'Batch 1 running',
          description: '[State: working]', extra: ['agentdesk_status']),
      _q('1', 'First question',
          description: '[Priority: blocking]\n[Option: Yes]\n\nThe **context**'),
      _q('2', 'Second question'),
    ]);
    desk.commentList = const [
      DeskComment(
        content: '',
        attachment: DeskAttachment(name: 'plan.pdf', url: 'https://x.y/plan.pdf'),
      ),
      DeskComment(content: 'A note from the agent'),
    ];
    await _pump(tester, desk);

    expect(find.text('DECIDE'), findsOneWidget);
    expect(find.text('PROJECTS'), findsOneWidget);
    expect(find.widgetWithText(DeskProjectTile, 'Photos'), findsOneWidget);
    expect(find.text('Batch 1 running'), findsOneWidget);
    // The top of the queue is open: title twice (row and pane).
    expect(find.text('First question'), findsNWidgets(2));
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.textContaining('A note from the agent'), findsOneWidget);

    await tester.tap(find.text('Second question'));
    await tester.pumpAndSettle();
    expect(find.text('Second question'), findsNWidgets(2));
    expect(find.text('Yes'), findsNothing);
  });

  testWidgets('answering by option moves on to the next question',
      (tester) async {
    final desk = _FakeDesk([
      _q('1', 'First question', description: '[Option: Yes]'),
      _q('2', 'Second question'),
    ]);
    await _pump(tester, desk);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(desk.answers, ['1: Yes']);
    expect(find.text('Sent to Photos'), findsOneWidget);
    expect(find.text('ANSWERED'), findsOneWidget);
    expect(find.text('Second question'), findsNWidgets(2));
  });

  testWidgets('a failed answer keeps the typed text and the question',
      (tester) async {
    final desk = _FakeDesk([_q('1', 'First question')])..failAnswers = true;
    await _pump(tester, desk);

    await tester.enterText(find.byType(TextField), 'My answer');
    await tester.tap(find.byTooltip('Send answer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not sent'), findsOneWidget);
    expect(find.text('My answer'), findsOneWidget);
    expect(find.text('ANSWERED'), findsNothing);
  });

  testWidgets('a project shows its brief and takes an instruction',
      (tester) async {
    final desk = _FakeDesk([
      _q('s', 'Batch 1 running',
          description: '[State: idle]\n\nThe long brief', extra: ['agentdesk_status']),
    ]);
    await _pump(tester, desk);

    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The long brief'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Start batch 2');
    await tester.tap(find.byTooltip('Send to agent'));
    await tester.pumpAndSettle();
    expect(desk.instructions, ['Photos: Start batch 2']);
  });

  testWidgets('narrow: one list, an item opens on its own page',
      (tester) async {
    final desk = _FakeDesk([_q('1', 'First question', description: 'Context')]);
    await _pump(tester, desk, size: const Size(420, 800));

    expect(find.text('Context'), findsNothing);
    await tester.tap(find.text('First question'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Context'), findsOneWidget);
  });

  testWidgets('an empty desk offers the starter projects', (tester) async {
    final desk = _FakeDesk([]);
    await _pump(tester, desk);
    await tester.tap(find.text('Set up the desk'));
    await tester.pumpAndSettle();
    expect(desk.seeded, isTrue);
  });

  testWidgets('no token: asks for one', (tester) async {
    final desk = _FakeDesk([_q('1', 'First question')], isConnected: false);
    await _pump(tester, desk);

    expect(find.text('Connect Todoist'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'tok');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(desk.token, 'tok');
    expect(find.text('DECIDE'), findsOneWidget);
  });
}
