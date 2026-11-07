import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/agent_desk.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/agent_desk_service.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _FakeDesk extends AgentDeskService {
  _FakeDesk() : super(token: 't');

  @override
  Future<DeskBoard?> loadCached() async => null;

  @override
  Future<DeskBoard> refresh() async => DeskBoard.fromRemote([
        {
          'id': '1',
          'content': 'A desk question',
          'project_id': 'p',
          'description': '',
          'labels': ['agentdesk'],
        },
      ], const {
        'p': 'Photos',
      });

  @override
  Future<List<DeskComment>> comments(DeskItem item) async => const [];
}

void main() {
  late AgentDeskService realDesk;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    ProjectService.instance.resetForTest();
    realDesk = AgentDeskService.instance;
    AgentDeskService.instance = _FakeDesk();
  });

  tearDown(() {
    Config.launchOnDesk = false;
    AgentDeskService.instance = realDesk;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> pumpHome(WidgetTester tester, Finder marker) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'A home task', dueDate: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(marker, findsWidgets);
    await settle(tester);
  }

  testWidgets('--desk opens on the desk, the toggle goes to Home and back, '
      'and the menu stays', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    Config.launchOnDesk = true;
    await pumpHome(tester, find.text('A desk question'));

    final onDesk = [
      find.text('Agent Desk').evaluate().isNotEmpty,
      find.byTooltip('Open navigation menu').evaluate().length == 1,
      find.text('A home task').evaluate().isEmpty,
    ];

    await tester.tap(find.text('Home'));
    await settle(tester);
    final onHome = [
      find.text('A home task').evaluate().length == 1,
      find.text('A desk question').evaluate().isEmpty,
      find.byTooltip('Open navigation menu').evaluate().length == 1,
    ];

    await tester.tap(find.text('Agent Desk'));
    await settle(tester);
    final backOnDesk = [
      find.text('A desk question').evaluate().isNotEmpty,
      find.text('A home task').evaluate().isEmpty,
    ];

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump(const Duration(milliseconds: 400));
    final menuOpens = find.text('Settings').evaluate().length == 1;

    debugDefaultTargetPlatformOverride = null;
    expect(onDesk, everyElement(isTrue));
    expect(onHome, everyElement(isTrue));
    expect(backOnDesk, everyElement(isTrue));
    expect(menuOpens, isTrue);
  });

  testWidgets('a phone keeps its app bar: no toggle on Home, one icon back '
      'from the desk', (tester) async {
    Config.launchOnDesk = true;
    await pumpHome(tester, find.text('A desk question'));
    expect(find.byType(SegmentedButton<bool>), findsNothing);

    await tester.tap(find.byTooltip('Home'));
    await settle(tester);
    expect(find.text('A home task'), findsOneWidget);
  });

  testWidgets('without --desk it opens on Home; Ctrl+D switches',
      (tester) async {
    // Keyboard shortcuts are for desktops.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpHome(tester, find.text('A home task'));
    expect(find.text('A desk question'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    final found = find.text('A desk question').evaluate().isNotEmpty;
    final homeHidden = find.text('A home task').evaluate().isEmpty;
    debugDefaultTargetPlatformOverride = null;
    expect(found, isTrue);
    expect(homeHidden, isTrue);
  });
}
