import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:besttodo/ui/agent_desk_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The PC layout with a filled desk, without Todoist.
class _DemoDesk extends AgentDeskService {
  _DemoDesk() : super(token: 'demo');

  static Map<String, dynamic> _task(String id, String project, String title,
          String description, [List<String> extra = const []]) =>
      {
        'id': id,
        'content': title,
        'project_id': project,
        'description': description,
        'labels': ['agentdesk', ...extra],
        'added_at': '2026-11-07T05:00:00Z',
      };

  @override
  Future<DeskBoard?> loadCached() async => null;

  @override
  Future<DeskBoard> refresh() async => DeskBoard.fromRemote([
        _task('s1', 'a', 'Batch 1 is running, 40% scanned',
            '[State: working]\n[Where: beast]\n\nAll photos into Immich.',
            ['agentdesk_status']),
        _task('s2', 'b', 'Milestone (a): text to printed part',
            '[State: waiting]\n[Where: both]', ['agentdesk_status']),
        _task('s3', 'c', 'Parked until the desk works',
            '[State: idle]\n[Where: cloud]', ['agentdesk_status']),
        _task(
          'q1',
          'b',
          'Switch the P2S to LAN only + Developer mode, so the Beast can start prints?',
          '[Topic: Printer]\n[Priority: blocking]\n[Option: Yes, switch it]\n[Option: Not yet]\n\n'
              '## What changes\n\nBambu cloud and Handy remote access **stop working**.\n\n'
              '- The Beast starts prints over the local network\n'
              '- Prints from the phone need the LAN too\n\n'
              '## What I checked\n\nFirmware 01.08 supports it. It can be switched back at any time.',
        ),
        _task('q2', 'a',
            'Videos: re-compress large ones to HEVC, or only delete the ones you pick?',
            '[Topic: Clean-up]\n[Option: Re-compress]\n[Option: Delete only]'),
        _task('q3', 'a', 'Which people get thinned, and who is on the keep list?',
            '[Topic: Clean-up]'),
        _task('q4', 'c', 'Which airports do you fly from?',
            '[Topic: Flights]\n[Priority: later]'),
      ], const {
        'a': 'Photos and videos',
        'b': '3D builder',
        'c': 'Deals',
      });

  @override
  Future<List<DeskComment>> comments(DeskItem item) async => [
        const DeskComment(
          content: '',
          attachment:
              DeskAttachment(name: 'printer-settings.pdf', url: 'https://x.y/a.pdf'),
        ),
        const DeskComment(
          content: '',
          attachment:
              DeskAttachment(name: 'firmware-notes.md', url: 'https://x.y/b.md'),
        ),
        DeskComment(
          content: 'I tried this on the spare network first, it held for a day.',
          at: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the desk on a PC', (tester) async {
    final boundary = GlobalKey();
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AgentDeskPage(service: _DemoDesk(), pollInterval: null),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('DECIDE'), findsOneWidget);
    await binding.delayed(const Duration(milliseconds: 200));

    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/e2e_screenshots')..createSync(recursive: true);
    File('${dir.path}/agent_desk_pc.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
  });
}
