import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/calendar_view_page.dart';

void main() {
  final currentDate = DateTime(2026, 7, 7);

  List<Task> buildTasks() {
    final tasks = <Task>[];
    // A handful of tasks per day across today, tomorrow, next week and
    // next month so the schedule list is long enough to scroll.
    final offsets = [0, 0, 1, 1, 2, 2, 4, 5, 8, 12, 25, 32, 32, 40, 55];
    for (var i = 0; i < offsets.length; i++) {
      tasks.add(
        Task(
          title: 'task $i',
          dueDate: currentDate.add(Duration(days: offsets[i])),
          listRanking: i + 1,
        ),
      );
    }
    for (var i = 0; i < 6; i++) {
      tasks.add(Task(title: 'someday task $i', dueDate: DateTime(2300, 1, 1)));
    }
    return tasks;
  }

  Widget buildHarness({
    required ScrollController controller,
    required void Function(ScheduleSectionInfo) onActive,
    required ScheduleSectionInfo? Function() activeSection,
  }) {
    final tabAnchorKeys = {for (var i = 0; i < 6; i++) i: GlobalKey()};
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ScheduleView(
            tasks: buildTasks(),
            currentDate: currentDate,
            scrollController: controller,
            tabAnchorKeys: tabAnchorKeys,
            buildTile: (task) => SizedBox(
              key: ValueKey(task.uid),
              height: 64,
              child: Text(task.title),
            ),
            addTaskRow: const SizedBox(height: 48),
            onReorderSection: (_, __, ___) {},
            onActiveSectionChanged: (info) => setState(() => onActive(info)),
            highlightedSectionKey: activeSection()?.key,
          ),
        ),
      ),
    );
  }

  testWidgets(
      'scrolling updates the active section and back-to-top arrow scrolls home',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    ScheduleSectionInfo? active;

    await tester.pumpWidget(buildHarness(
      controller: controller,
      onActive: (info) => active = info,
      activeSection: () => active,
    ));
    await tester.pumpAndSettle();

    // At the top the active section is today and no arrow is shown.
    expect(active, isNotNull);
    expect(active!.label, 'Today');
    expect(active!.date, DateTime(2026, 7, 7));
    final opacityFinder = find.ancestor(
      of: find.byTooltip('Back to top'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0);

    // Scroll to the bottom: the Someday section becomes active and the
    // back-to-top arrow appears. maxScrollExtent is an estimate until the
    // trailing children are built, so keep jumping until it stabilizes.
    while (controller.position.pixels <
        controller.position.maxScrollExtent - 0.5) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(active!.key, 'someday');
    expect(active!.date, DateTime(2300, 1, 1));
    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 1);

    // Tapping the arrow scrolls back to the top and today becomes active
    // again.
    await tester.tap(find.byTooltip('Back to top'));
    await tester.pumpAndSettle();
    expect(controller.position.pixels, 0);
    expect(active!.label, 'Today');
    expect(tester.widget<AnimatedOpacity>(opacityFinder).opacity, 0);
  });

  testWidgets('scrolling to a mid-list day reports that day as active',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    ScheduleSectionInfo? active;

    await tester.pumpWidget(buildHarness(
      controller: controller,
      onActive: (info) => active = info,
      activeSection: () => active,
    ));
    await tester.pumpAndSettle();

    // Scroll to the true bottom first so trailing sections are laid out at
    // exact offsets (maxScrollExtent is an estimate until then), then align
    // the Aug 8 (day +32) header with the top of the viewport.
    while (controller.position.pixels <
        controller.position.maxScrollExtent - 0.5) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    final targetDate = currentDate.add(const Duration(days: 32));
    final headerText =
        find.text('Sat, Aug ${targetDate.day}', skipOffstage: false);
    final viewportY = tester
        .getTopLeft(find.byWidgetPredicate(
          (w) => w is Scrollable && w.controller == controller,
        ))
        .dy;
    final headerY = tester.getTopLeft(headerText).dy;
    controller.jumpTo(controller.position.pixels + (headerY - viewportY));
    await tester.pumpAndSettle();

    expect(active, isNotNull);
    expect(active!.date, targetDate);
    expect(active!.label, 'Sat, Aug ${targetDate.day}');
  });
}
