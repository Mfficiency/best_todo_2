import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/config.dart';
import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/project_board_page.dart';
import 'package:besttodo/ui/projects_page.dart';
import 'package:besttodo/ui/streak_flame_button.dart';
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

    // Render at a phone-portrait resolution (1080x2400 @ pixelRatio 2.0,
    // a common Android FHD+ panel) so the screenshot changelog always shows
    // phone-shaped screenshots regardless of the Windows CI runner's actual
    // window size — the boundary capture below renders offscreen from the
    // layer tree, so this virtual size is what ends up in the PNG.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

      // A handful of sections push their own subpage/dialog; capture those
      // right after their section, while it's expanded, rather than
      // re-navigating to Settings a second time later.
      if (title == 'Tasks') {
        await tester.tap(find.text('Auto-tag rules'));
        await tester.pumpAndSettle();
        await capture('auto_tag_rules_page');
        await popCurrentPage();

        await tester.tap(find.text('Approval quick tags'));
        await tester.pumpAndSettle();
        await capture('approval_quick_tags_page');
        await popCurrentPage();
      } else if (title == 'SMS report') {
        await tester.tap(find.text('Sent message history'));
        await tester.pumpAndSettle();
        await capture('sms_report_log_page');
        await popCurrentPage();
      } else if (title == 'Streak') {
        await tester.tap(find.widgetWithText(TextButton, 'Set goal').first);
        await tester.pumpAndSettle();
        await capture('streak_goal_dialog');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
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

    // Task detail page: a board card's own full-page view, distinct from
    // the home list's inline expansion (task_open_with_attachment below).
    final boardPage = find.byType(ProjectBoardPage);
    await tester.tap(
        find.descendant(of: boardPage, matching: find.text('Get milk')));
    await tester.pumpAndSettle();
    await capture('task_detail_page');
    await popCurrentPage();

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

    await tester.tap(find.byTooltip('Deleted items (bin)'));
    await tester.pumpAndSettle();
    await capture('deleted_bin_page');
    await popCurrentPage();

    await popCurrentPage();

    // Widget Previews lives directly in the drawer too (dev-only tool
    // mocking the four Android home-screen widgets, since these
    // integration tests run on Windows/desktop where the real RemoteViews
    // widgets drawn by the OS home screen can't be captured).
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await ensureCenterOnScreen(
      find.text('Widget Previews'),
      find
          .descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Widget Previews'));
    await tester.pumpAndSettle();
    await capture('widget_previews_page');
    await popCurrentPage();

    // Wishlist plus every remaining Tools entry — Projects and Productivity
    // Stats already have their own screenshots above. [onOpen] runs after
    // the tool's own screenshot, for tools with a reachable subpage/dialog
    // worth its own capture; it must leave the tool's own page as the top
    // route so the trailing popCurrentPage() lands back on Home.
    Future<void> captureTool(
      String label,
      String screenshotName, {
      Future<void> Function()? onOpen,
    }) async {
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
      if (onOpen != null) await onOpen();
      await popCurrentPage();
    }

    await captureTool('Wishlist', 'wishlist_page');
    await captureTool('Alarms', 'alarms_page', onOpen: () async {
      await tester.tap(find.byTooltip('Add alarm'));
      await tester.pumpAndSettle();
      await capture('alarm_edit_page');
      await popCurrentPage();

      await tester.tap(find.byTooltip('Alarm reliability log'));
      await tester.pumpAndSettle();
      await capture('alarm_log_page');
      await popCurrentPage();
    });
    await captureTool('Countdown', 'countdown_page', onOpen: () async {
      // The draft composer at the top of the page is always present, so
      // tapping its "Add" button creates one timer with the auto-generated
      // default name/target — enough to expand and reach the milestones
      // dialog from its tag icon.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Timer 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tag));
      await tester.pumpAndSettle();
      await capture('countdown_milestones_dialog');
      await popCurrentPage();
    });
    await captureTool('Food Diary', 'food_diary_page');
    await captureTool('Chronize', 'chronize_page');
    await captureTool('Usage Data', 'usage_data_page');
    await captureTool('Test Results', 'test_results_page');
    await captureTool('Weekly Hours Planner', 'weekly_hours_planner_page');
    await captureTool('Research', 'research_page');
    await captureTool('Fitness Activity', 'fitness_activity_page');
    // Same shared pages Best Music ships standalone — captured again here
    // embedded in BestToDo's own Tools menu (no music folder seeded, so
    // Music Player shows its empty state, same as Best Music's own test).
    await captureTool('MP3 Downloader', 'todo_mp3_downloader_page');
    await captureTool('Music Player', 'todo_music_player_page');

    // Drawer items outside the Tools submenu that don't have their own
    // screenshot yet.
    Future<void> captureDrawerItem(String label, String screenshotName) async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await capture(screenshotName);
      await popCurrentPage();
    }

    await captureDrawerItem('Waiting for Approval', 'waiting_approval_page');
    await captureDrawerItem('Changelog', 'changelog_page');
    await captureDrawerItem('About', 'about_page');
    await captureDrawerItem('App Logs', 'app_logs_page');
    await captureDrawerItem('Startup Times', 'startup_times_page');

    // Schedule view: toggles the home body in place rather than pushing a
    // route, so there's no popCurrentPage() — tap the same tooltip again
    // (now reading "List view") to switch back before continuing.
    await tester.tap(find.byTooltip('Schedule view'));
    await tester.pumpAndSettle();
    await capture('calendar_view_page');
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();

    // Streak page (via the app bar's flame button — its tooltip/icon vary
    // with streak state, so target the button by type) and, from its
    // "Longest streak ever" stat, the streak calendar. StreakPage owns a
    // perpetual `_flicker` AnimationController (repeat(reverse: true)), so
    // pumpAndSettle() never settles anywhere it's mounted — including
    // underneath StreakCalendarPage — so this whole block pumps a fixed
    // page-transition duration instead, all the way back out to Home.
    Future<void> pumpTransition() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.tap(find.descendant(
      of: find.byType(StreakFlameButton),
      matching: find.byType(IconButton),
    ));
    await pumpTransition();
    await capture('streak_page');
    await tester.tap(find.text('Longest streak ever'));
    await pumpTransition();
    await capture('streak_calendar_page');
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await pumpTransition();
    navigator.pop();
    await pumpTransition();

    // A task expanded in place on the main screen (tapping a tile toggles
    // its inline editor, including the AttachmentsField), once for a task
    // carrying an attachment and once for one that has none. The "with
    // attachment" task is the dev-mode demo note seeded in
    // home_page._loadTasks onto Config.initialTasks[1]; the "without" task
    // is another seeded starter task nothing else in this test has touched.
    final withAttachmentTile = find.text(Config.initialTasks[1]);
    await tester.tap(withAttachmentTile);
    await tester.pumpAndSettle();
    await capture('task_open_with_attachment');
    // Collapse via the tile's own "Collapse" button (shown while expanded)
    // rather than tapping the tile again, which would risk the double-tap
    // menu instead of a plain toggle. Keeps each screenshot to one open task.
    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();

    final noAttachmentTile = find.text(Config.initialTasks[2]);
    await tester.tap(noAttachmentTile);
    await tester.pumpAndSettle();
    await capture('task_open_no_attachment');

    // Recurrence editor: appears inline once the "Recurring" switch on this
    // same expanded tile is turned on.
    await tester.tap(find.descendant(
      of: find.widgetWithText(Row, 'Recurring'),
      matching: find.byType(Switch),
    ));
    await tester.pumpAndSettle();
    await capture('recurrence_editor');
  });
}
