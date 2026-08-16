import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final storage = StorageService();
    await storage.saveTaskList(<Task>[]);
    await storage.saveDeletedTaskList(<Task>[]);
    await storage.saveDailyTaskStats({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
  });

  testWidgets('capture home page screenshot', (tester) async {
    final appBoundaryKey = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: appBoundaryKey,
        child: const MyApp(showIntro: false),
      ),
    );
    await tester.pumpAndSettle();

    final folder = Directory('build/e2e_screenshots');
    await folder.create(recursive: true);
    Future<void> capture(String name) async {
      final filePath = '${folder.path}/$name.png';
      try {
        await binding.takeScreenshot(name);
      } catch (_) {
        // Fallback for platforms where integration_test screenshot capture
        // is not implemented.
      }

      final boundaryContext = appBoundaryKey.currentContext;
      if (boundaryContext == null) {
        fail('Could not find repaint boundary context for screenshot.');
      }
      final boundary =
          boundaryContext.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        fail('Could not find repaint boundary render object for screenshot.');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        fail('Could not encode screenshot for "$name".');
      }
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await File(filePath).writeAsBytes(bytes, flush: true);
    }

    Future<void> popCurrentPage() async {
      final backButton = find.byTooltip('Back');
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle();
        return;
      }
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();
    }

    await capture('home_page');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await capture('menu_open');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await capture('settings_page');

    await popCurrentPage();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    // Productivity Stats lives in the collapsible Tools section now.
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Productivity Stats'),
      80,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Productivity Stats'));
    await tester.pumpAndSettle();
    await capture('your_stats_page');
    await popCurrentPage();

    // Search: type a query into the app-bar search field and capture the
    // filtered home list ("Get milk" is one of the seeded initial tasks).
    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search tasks',
    );
    await tester.enterText(searchField, 'milk');
    await tester.pumpAndSettle();
    await capture('search_active');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    // Projects tool (Tools → Projects): assign a task by long-press drag so
    // the screenshot shows the tag chips and the project task count.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Projects'));
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    final drag = await tester
        .startGesture(tester.getCenter(find.text('Get milk').first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await drag.moveTo(tester.getCenter(find.text('Project 1')));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    await capture('projects_page');

    // Per-project Kanban board with the assigned card. Target the project
    // card via its DragTarget — after the assignment "Project 1" also appears
    // as a chip on the task row, whose ListTile owns an InkWell of its own.
    await tester.tap(find.descendant(
      of: find.byType(DragTarget<Task>),
      matching: find.text('Project 1'),
    ));
    await tester.pumpAndSettle();
    await capture('project_board_page');

    // Project edit dialog (name + description).
    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    await capture('project_edit_dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
