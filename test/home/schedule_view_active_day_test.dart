import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/calendar_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 8);

  late ScrollController controller;
  late List<DateTime> reportedDates;

  setUp(() {
    controller = ScrollController();
    reportedDates = [];
  });

  tearDown(() {
    controller.dispose();
  });

  List<Task> buildTasks() => [
        // Enough today tasks that the list scrolls.
        for (var i = 0; i < 12; i++)
          Task(title: 'Today task $i', dueDate: today),
        Task(
          title: 'Tomorrow task',
          dueDate: today.add(const Duration(days: 1)),
        ),
        Task(
          title: 'Day after task',
          dueDate: today.add(const Duration(days: 2)),
        ),
        Task(
          title: 'Next week task',
          dueDate: today.add(const Duration(days: 5)),
        ),
        Task(
          title: 'Next month task',
          dueDate: today.add(const Duration(days: 40)),
        ),
        Task(title: 'Someday task', dueDate: ScheduleView.futureBucketDate),
      ];

  Widget buildView() {
    return MaterialApp(
      home: Scaffold(
        body: ScheduleView(
          tasks: buildTasks(),
          currentDate: today,
          scrollController: controller,
          tabAnchorKeys: {for (var i = 0; i < 6; i++) i: GlobalKey()},
          buildTile: (t) => SizedBox(
            key: ValueKey(t.uid),
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(t.title),
            ),
          ),
          addTaskRow: const SizedBox(height: 40),
          onReorderSection: (_, __, ___) {},
          onActiveDateChanged: (date) => reportedDates.add(date),
        ),
      ),
    );
  }

  Finder activeHeader() => find.byKey(const ValueKey('active-day-header'));

  String activeHeaderText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: activeHeader(), matching: find.byType(Text)),
      )
      .data!;

  testWidgets('today is the active day initially, no back-to-top arrow',
      (tester) async {
    await tester.pumpWidget(buildView());
    await tester.pumpAndSettle();

    expect(reportedDates, isNotEmpty);
    expect(reportedDates.last, today);
    expect(activeHeaderText(tester), contains('Today'));
    expect(find.byTooltip('Back to top'), findsNothing);
  });

  testWidgets('scrolling highlights the day at the top of the list',
      (tester) async {
    await tester.pumpWidget(buildView());
    await tester.pumpAndSettle();

    // Scroll down in small steps until the +40d day (Aug 17) reaches the
    // top of the list; the step is smaller than any section height so the
    // activation window cannot be jumped over.
    final target = today.add(const Duration(days: 40));
    var found = false;
    for (var offset = 0.0;
        offset <= controller.position.maxScrollExtent;
        offset += 80) {
      controller.jumpTo(offset);
      await tester.pump();
      await tester.pump();
      if (reportedDates.isNotEmpty && reportedDates.last == target) {
        found = true;
        break;
      }
    }

    expect(found, isTrue, reason: 'the +40d day never became active');
    expect(activeHeaderText(tester), contains('Aug 17'));
  });

  testWidgets('back-to-top arrow appears when scrolled and returns to today',
      (tester) async {
    await tester.pumpWidget(buildView());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to top'), findsNothing);

    // The generous bottom padding lets the last section reach the top, so
    // at max scroll the Someday section is the active one.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to top'), findsOneWidget);
    expect(reportedDates.last, ScheduleView.futureBucketDate);
    expect(activeHeaderText(tester), 'Someday');

    await tester.tap(find.byTooltip('Back to top'));
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
    expect(find.byTooltip('Back to top'), findsNothing);
    expect(reportedDates.last, today);
    expect(activeHeaderText(tester), contains('Today'));
  });
}
