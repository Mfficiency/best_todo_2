import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/projects_page.dart';
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

    // Drags [scrollable] until [target]'s center point lands inside
    // [scrollable]'s own rect. Drawer entries and the settings chip row are
    // built eagerly (plain ListView/Row, not builders), so the finder exists
    // in the tree from the very first frame; that makes
    // WidgetController.scrollUntilVisible/dragUntilVisible a no-op (their
    // loop only drags while the finder can't be found at all) and leaves the
    // single Scrollable.ensureVisible() call as the only thing standing
    // between a long list and an off-window tap. Measuring and nudging
    // ourselves — checking the exact point tester.tap() will use — is what
    // actually guarantees the tap lands on-screen.
    Future<void> ensureCenterOnScreen(
      Finder target,
      Finder scrollable, {
      bool horizontal = false,
    }) async {
      for (var attempt = 0; attempt < 24; attempt++) {
        final center = tester.getCenter(target);
        final viewport = tester.getRect(scrollable);
        final onScreen = horizontal
            ? center.dx >= viewport.left && center.dx <= viewport.right
            : center.dy >= viewport.top && center.dy <= viewport.bottom;
        if (onScreen) break;
        final before =
            horizontal ? center.dx < viewport.left : center.dy < viewport.top;
        final step = horizontal
            ? Offset(before ? 140 : -140, 0)
            : Offset(0, before ? 140 : -140);
        await tester.drag(scrollable, step);
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await capture('home_page');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await capture('menu_open');

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await capture('settings_page');

    // Every collapsible section in Settings, expanded one at a time via its
    // jump-to chip in the pinned header — the chip's onSelected both scrolls
    // the section into view and expands it (SettingsPage._jumpToSection).
    const settingsSectionTitles = [
      'Appearance',
      'Mode & features',
      'Tasks',
      'Widget',
      'Notifications',
      'Streak',
      'Dice timer',
      'SMS report',
      'Sync & export',
      'Backup',
      'Todoist sync',
      'Updates',
      'Filtering rules',
    ];
    final settingsChipScrollable = find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final title in settingsSectionTitles) {
      final chip = find.widgetWithText(ChoiceChip, title);
      await ensureCenterOnScreen(
        chip,
        settingsChipScrollable,
        horizontal: true,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final slug = title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      await capture('settings_section_$slug');
    }

    await popCurrentPage();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    // Productivity Stats lives in the collapsible Tools section now.
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await ensureCenterOnScreen(
      find.text('Productivity Stats'),
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
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
    await ensureCenterOnScreen(
      find.text('Projects'),
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    // Scope both ends of the drag to the Projects page: the home page stays
    // in the tree behind the pushed route, so an unscoped "Get milk" can
    // resolve to the tile underneath, and "Project 1" also renders as a chip
    // on every task the dev seed already assigned.
    final projectsPage = find.byType(ProjectsPage);
    final milkTile =
        find.descendant(of: projectsPage, matching: find.text('Get milk'));
    await tester.scrollUntilVisible(
      milkTile,
      80,
      scrollable: find
          .descendant(of: projectsPage, matching: find.byType(Scrollable))
          .first,
    );
    final projectCard = find.descendant(
      of: find.byType(DragTarget<Task>),
      matching: find.text('Project 1'),
    );

    final drag = await tester.startGesture(tester.getCenter(milkTile));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await drag.moveTo(tester.getCenter(projectCard));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();
    await capture('projects_page');

    // Per-project Kanban board with the assigned card. Target the project
    // card via its DragTarget — after the assignment "Project 1" also appears
    // as a chip on the task row, whose ListTile owns an InkWell of its own.
    await tester.tap(projectCard);
    await tester.pumpAndSettle();
    await capture('project_board_page');

    // Project edit dialog (name + description).
    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    await capture('project_edit_dialog');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back to the home page: ProjectBoardPage -> ProjectsPage -> Home. The
    // drawer (and its "Open navigation menu" button) only exists on Home.
    await popCurrentPage();
    await popCurrentPage();

    // Archived Items lives directly in the drawer, outside the Tools section.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archived Items'));
    await tester.pumpAndSettle();
    await capture('archived_items_page');
    await popCurrentPage();

    // Wishlist plus every remaining Tools entry — Projects and Productivity
    // Stats already have their own screenshots above.
    Future<void> captureTool(String label, String screenshotName) async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      final entry = find.text(label);
      await ensureCenterOnScreen(
        entry,
        find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await capture(screenshotName);
      await popCurrentPage();
    }

    await captureTool('Wishlist', 'wishlist_page');
    await captureTool('Alarms', 'alarms_page');
    await captureTool('Countdown', 'countdown_page');
    await captureTool('Food Diary', 'food_diary_page');
    await captureTool('Chronize', 'chronize_page');
    await captureTool('Usage Data', 'usage_data_page');
    await captureTool('Test Results', 'test_results_page');
  });
}
