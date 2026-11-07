import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late AgentDeskService service;
  final now = DateTime.utc(2026, 11, 7, 9);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('desk');
    service = AgentDeskService(
        folder: '${tempDir.path}/AgentDesk', device: 'Beast PC', clock: () => now);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('no folder yet loads as null', () async {
    expect(await service.load(), isNull);
  });

  test('seed creates the five starter projects with their questions', () async {
    await service.seed();
    final snapshot = (await service.load())!;
    expect(snapshot.projects.map((p) => p.name).toList(), [
      '3D builder',
      'Photos and videos',
      'Network and devices',
      'Sensitive documents',
      'Deals',
    ]);
    final photos = snapshot.project('2-photos')!;
    expect(photos.where, 'beast');
    expect(photos.goal, startsWith('Bring all photos'));
    expect(photos.goal, endsWith('add the stories from photo evenings to them.'));
    expect(photos.openQuestions, hasLength(3));
    // Parked questions never reach the top three.
    final top = snapshot.topQuestions();
    expect(top, hasLength(3));
    expect(top.every((q) => q.priority != DeskPriority.later), isTrue);
    expect(snapshot.project('5-deals')!.openQuestions.every(
        (q) => q.priority == DeskPriority.later), isTrue);
  });

  test('seed never overwrites what is already there', () async {
    await service.seed();
    final brief = File('${tempDir.path}/AgentDesk/1-3d-builder/brief.md');
    await brief.writeAsString('# My printer project\n\nMine.\n');
    await service.seed();
    final snapshot = (await service.load())!;
    expect(snapshot.project('1-3d-builder')!.name, 'My printer project');
  });

  test('a decision goes to this device\'s file and answers its question',
      () async {
    await service.seed();
    final d = await service.decide(
        projectId: '1-3d-builder',
        text: 'Not yet',
        questionId: 'p2s-lan-mode',
        via: 'option');
    expect(d.device, 'beast-pc');
    final file =
        File('${tempDir.path}/AgentDesk/1-3d-builder/decisions-beast-pc.jsonl');
    final line = jsonDecode((await file.readAsLines()).single) as Map;
    expect(line['questionId'], 'p2s-lan-mode');
    expect(line['via'], 'option');

    final project = (await service.load())!.project('1-3d-builder')!;
    expect(project.openQuestions, isEmpty);
    expect(project.answerTo('p2s-lan-mode')!.text, 'Not yet');
  });

  test('decisions from another device count too', () async {
    await service.seed();
    final other = AgentDeskService(
        folder: '${tempDir.path}/AgentDesk', device: 'huwy', clock: () => now);
    await other.decide(
        projectId: '2-photos', text: 'E:', questionId: 'external-drive');
    final project = (await service.load())!.project('2-photos')!;
    expect(project.openQuestions.map((q) => q.id), isNot(contains('external-drive')));
  });

  test('status, log tail and broken lines', () async {
    final dir = Directory('${tempDir.path}/AgentDesk/x');
    await dir.create(recursive: true);
    await Directory('${tempDir.path}/AgentDesk/.git').create();
    await File('${dir.path}/status.json').writeAsString(jsonEncode({
      'state': 'working',
      'summary': 'Printing',
      'where': 'cloud',
      'updatedAt': '2026-11-07T08:00:00Z',
    }));
    await File('${dir.path}/questions.jsonl').writeAsString(
        '{"id":"a","text":"First?"}\nnot json\n{"id":"","text":"no id"}\n');
    await File('${dir.path}/log.md').writeAsString(
        List.generate(60, (i) => 'line $i').join('\n'));
    final snapshot = (await service.load())!;
    expect(snapshot.projects.map((p) => p.id), ['x']);
    final p = snapshot.projects.single;
    expect(p.name, 'x');
    expect(p.state, DeskState.working);
    expect(p.where, 'cloud');
    expect(p.questions.map((q) => q.id), ['a']);
    expect(p.logTail, hasLength(AgentDeskService.logTailLines));
    expect(p.logTail.last, 'line 59');
  });

  test('ranking: blocking, then deadline, then oldest; later last', () {
    DeskQuestion q(String id, DeskPriority p, {DateTime? at, DateTime? deadline}) =>
        DeskQuestion(id: id, projectId: 'p', text: id, priority: p, at: at, deadline: deadline);
    final sorted = AgentDeskRanking.sort([
      q('later', DeskPriority.later, at: DateTime(2020)),
      q('old', DeskPriority.normal, at: DateTime(2026, 1)),
      q('new', DeskPriority.normal, at: DateTime(2026, 6)),
      q('due', DeskPriority.normal, at: DateTime(2026, 9), deadline: DateTime(2026, 12)),
      q('block', DeskPriority.blocking, at: DateTime(2026, 10)),
    ]);
    expect(sorted.map((e) => e.id), ['block', 'due', 'old', 'new', 'later']);
    final snapshot = DeskSnapshot(folder: '', projects: [
      DeskProject(id: 'p', name: 'P', questions: sorted),
    ]);
    expect(snapshot.topQuestions().map((e) => e.id), ['block', 'due', 'old']);
  });
}
