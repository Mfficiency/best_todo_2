import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:besttodo/ui/agent_desk_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory desk: no file I/O inside testWidgets (see CLAUDE.md).
class _FakeDesk extends AgentDeskService {
  _FakeDesk(this.projects) : super(device: 'test');

  List<DeskProject>? projects;
  final List<DeskDecision> sent = [];
  bool seeded = false;

  @override
  Future<String> folder() async => '/desk';

  @override
  Future<DeskSnapshot?> load() async {
    final p = projects;
    if (p == null) return null;
    return DeskSnapshot(folder: '/desk', projects: [
      for (final project in p)
        DeskProject(
          id: project.id,
          name: project.name,
          summary: project.summary,
          state: project.state,
          where: project.where,
          questions: project.questions,
          decisions: [
            ...project.decisions,
            ...sent.where((d) => d.projectId == project.id),
          ],
        ),
    ]);
  }

  @override
  Future<DeskDecision> decide({
    required String projectId,
    required String text,
    String? questionId,
    String topic = '',
    String via = 'text',
  }) async {
    final d = DeskDecision(
      id: 'd${sent.length}',
      projectId: projectId,
      at: DateTime(2026, 11, 7, 10),
      text: text,
      questionId: questionId,
      topic: topic,
      via: via,
      device: device,
    );
    sent.add(d);
    return d;
  }

  @override
  Future<void> seed() async {
    seeded = true;
    projects = [const DeskProject(id: 'a', name: 'Seeded')];
  }
}

DeskQuestion _q(String id, String project,
        {DeskPriority p = DeskPriority.normal, List<String> options = const [], int day = 1}) =>
    DeskQuestion(
      id: id,
      projectId: project,
      text: 'Question $id?',
      options: options,
      priority: p,
      at: DateTime(2026, 11, day),
    );

List<DeskProject> _projects() => [
      DeskProject(
        id: 'printer',
        name: '3D builder',
        state: DeskState.working,
        where: 'both',
        summary: 'Slicing a test cube',
        questions: [
          _q('lan', 'printer', options: ['Yes', 'Not yet'], day: 1),
          _q('later1', 'printer', p: DeskPriority.later, day: 1),
        ],
      ),
      DeskProject(
        id: 'photos',
        name: 'Photos',
        questions: [
          _q('drive', 'photos', day: 2),
          _q('kids', 'photos', day: 3),
          _q('fourth', 'photos', day: 4),
        ],
      ),
    ];

Future<void> _pumpDesk(WidgetTester tester, _FakeDesk desk,
    {Size size = const Size(1400, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: AgentDeskPage(
      service: desk,
      pollInterval: null,
      clock: () => DateTime(2026, 11, 7, 12),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the top three and every project', (tester) async {
    final desk = _FakeDesk(_projects());
    await _pumpDesk(tester, desk);

    expect(find.text('DECIDE NOW'), findsOneWidget);
    expect(find.text('Question lan?'), findsOneWidget);
    expect(find.text('Question drive?'), findsOneWidget);
    expect(find.text('Question kids?'), findsOneWidget);
    expect(find.text('Question fourth?'), findsNothing);
    expect(find.text('Question later1?'), findsNothing);
    expect(find.text('+1 more waiting'), findsOneWidget);
    expect(find.text('3D builder'), findsOneWidget);
    expect(find.text('Slicing a test cube'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
  });

  testWidgets('tapping a suggested answer sends it and the next one moves up',
      (tester) async {
    final desk = _FakeDesk(_projects());
    await _pumpDesk(tester, desk);

    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    expect(desk.sent.single.questionId, 'lan');
    expect(desk.sent.single.text, 'Not yet');
    expect(desk.sent.single.via, 'option');
    expect(find.text('Sent to 3D builder'), findsOneWidget);
    expect(find.text('Question lan?'), findsNothing);
    expect(find.text('Question fourth?'), findsOneWidget);
  });

  testWidgets('a typed answer is sent with the send button', (tester) async {
    final desk = _FakeDesk(_projects());
    await _pumpDesk(tester, desk, size: const Size(600, 1600));

    final field = find.byType(TextField).at(1); // the "drive" card
    await tester.enterText(field, 'It is E:');
    await tester.tap(find.byTooltip('Send answer').at(1));
    await tester.pumpAndSettle();

    expect(desk.sent.single.questionId, 'drive');
    expect(desk.sent.single.text, 'It is E:');
    expect(desk.sent.single.via, 'text');
  });

  testWidgets('no folder: the setup card seeds the desk', (tester) async {
    final desk = _FakeDesk(null);
    await _pumpDesk(tester, desk);

    expect(find.text('No desk yet'), findsOneWidget);
    await tester.tap(find.text('Set up the desk'));
    await tester.pumpAndSettle();

    expect(desk.seeded, isTrue);
    expect(find.text('Seeded'), findsOneWidget);
    expect(find.text('Nothing is waiting on you.'), findsOneWidget);
  });

  testWidgets('project page: parked questions, instructions to the agent',
      (tester) async {
    final desk = _FakeDesk(_projects());
    await _pumpDesk(tester, desk);

    await tester.tap(find.text('3D builder'));
    await tester.pumpAndSettle();

    expect(find.text('LATER'), findsOneWidget);
    expect(find.text('Question later1?'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Tell the agent what to do next'),
        'Print a 20 mm cube');
    await tester.tap(find.byTooltip('Send to agent'));
    await tester.pumpAndSettle();

    expect(desk.sent.single.projectId, 'printer');
    expect(desk.sent.single.questionId, isNull);
    expect(find.text('Print a 20 mm cube'), findsOneWidget);
  });
}
