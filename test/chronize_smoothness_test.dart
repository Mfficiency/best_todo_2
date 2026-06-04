import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/chronize_page.dart';

/// Smoothness tests for the Chronize timeline.
///
/// Perceptual smoothness can't be asserted directly, so these tests pin the
/// invariants that *produce* it:
///   * every row is identical height with no gaps (so scrolling never jumps
///     between rows);
///   * the timeline scrolls infinitely in both directions;
///   * the timeline and the wheels stay in sync;
///   * a month change is animated and its visible motion is bounded to a single
///     glide (the "fake smooth" scroll) instead of teleporting the viewport.
/// Plus basic coverage of the zoom controls and the Today button.
void main() {
  const double rowHeight = 64; // _rowHeight
  const double glideDistance = 8 * rowHeight; // _glideDistance

  // Wheels with the hour wheel hidden (the default): day = picker 0, month = 1.
  const int dayWheel = 0;
  const int monthWheel = 1;

  Future<void> pumpPage(WidgetTester tester) async {
    final now = DateTime.now();
    final tasks = [
      Task(
        title: 'Today task',
        dueDate: DateTime(now.year, now.month, now.day, 18),
        listRanking: 1,
      ),
      Task(
        title: 'Tomorrow task',
        dueDate: DateTime(now.year, now.month, now.day + 1, 9),
        listRanking: 2,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ChronizePage(tasks: tasks)),
    );
    await tester.pumpAndSettle();
  }

  // The timeline's scroll position. Each row contains a (non-scrolling) task
  // ListView, so there are many Scrollables under the CustomScrollView; the
  // timeline's own is the outermost, hence first in tree order.
  ScrollPosition timeline(WidgetTester tester) {
    return tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
  }

  // The selected item of wheel [index]. A CupertinoPicker's wheel is a
  // _FixedExtentScrollable (a Scrollable subclass that find.byType won't match),
  // so read its FixedExtentScrollController off the ListWheelScrollView instead.
  int wheelItem(WidgetTester tester, int index) {
    final wheels = tester
        .widgetList<ListWheelScrollView>(find.byType(ListWheelScrollView))
        .toList();
    final controller = wheels[index].controller as FixedExtentScrollController;
    return controller.selectedItem;
  }

  int topItem(WidgetTester tester) =>
      (timeline(tester).pixels / rowHeight).round();

  testWidgets('every row is the same height with no gaps between them',
      (tester) async {
    await pumpPage(tester);

    final top = topItem(tester);
    final a = find.byKey(ValueKey('chronize-row-$top'));
    final b = find.byKey(ValueKey('chronize-row-${top + 1}'));
    final c = find.byKey(ValueKey('chronize-row-${top + 2}'));

    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(c, findsOneWidget);

    expect(tester.getSize(a).height, rowHeight);
    expect(tester.getSize(b).height, rowHeight);
    expect(tester.getSize(c).height, rowHeight);

    final ay = tester.getTopLeft(a).dy;
    final by = tester.getTopLeft(b).dy;
    final cy = tester.getTopLeft(c).dy;
    expect(by - ay, moreOrLessEquals(rowHeight, epsilon: 0.01));
    expect(cy - by, moreOrLessEquals(rowHeight, epsilon: 0.01));
  });

  testWidgets('timeline scrolls infinitely into the future and the past',
      (tester) async {
    await pumpPage(tester);
    final pos = timeline(tester);

    pos.jumpTo(pos.pixels + 1000 * 24 * rowHeight);
    await tester.pump();
    final future = topItem(tester);
    expect(find.byKey(ValueKey('chronize-row-$future')), findsOneWidget);

    pos.jumpTo(-1000 * 24 * rowHeight);
    await tester.pump();
    final past = topItem(tester);
    expect(past, lessThan(0));
    expect(find.byKey(ValueKey('chronize-row-$past')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the timeline keeps the day wheel in sync',
      (tester) async {
    await pumpPage(tester);

    // Item 50 == 50 hours after today 00:00 == calendar day 2 (50 ~/ 24).
    timeline(tester).jumpTo(50 * rowHeight);
    await tester.pump();
    await tester.pump();

    expect(topItem(tester), 50);
    expect(wheelItem(tester, dayWheel), 2);
  });

  testWidgets('spinning the day wheel scrolls the timeline to that day',
      (tester) async {
    await pumpPage(tester);

    // Low-velocity gesture so the wheel settles on a known item (+3 days).
    final center = tester.getCenter(find.byType(CupertinoPicker).at(dayWheel));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -3 * 32 - 20)); // 3 items + touch slop
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200)); // fire settle debounce
    await tester.pumpAndSettle(); // glide

    final dayWheelItem = wheelItem(tester, dayWheel);
    // The day implied by the row at the top matches the day wheel.
    expect((topItem(tester) / 24).floor(), dayWheelItem);
    expect(dayWheelItem, greaterThan(0));
  });

  testWidgets('a month change glides smoothly instead of teleporting',
      (tester) async {
    await pumpPage(tester);

    final center = tester.getCenter(find.byType(CupertinoPicker).at(monthWheel));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(0, -40)); // just past half an item + slop
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 140)); // fire settle -> glide

    final samples = <double>[];
    for (var i = 0; i < 30; i++) {
      samples.add(timeline(tester).pixels);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final settled = timeline(tester).pixels;

    for (final offset in samples) {
      expect(
        (offset - settled).abs(),
        lessThanOrEqualTo(glideDistance + 1),
        reason: 'timeline jumped more than one glide from its destination',
      );
    }
    expect(samples.toSet().length, greaterThan(1)); // it animated
    // It really moved a month (far beyond one glide), so the bound above proves
    // a faked glide rather than a tiny hop.
    expect(topItem(tester).abs(), greaterThan(8));
  });

  testWidgets('zoom controls change the row time unit', (tester) async {
    await pumpPage(tester);

    expect(find.text('1 h'), findsOneWidget); // default

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pumpAndSettle();
    expect(find.text('30 min'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.pumpAndSettle();
    expect(find.text('2 h'), findsOneWidget);
  });

  testWidgets('the Today button returns the timeline to now', (tester) async {
    await pumpPage(tester);
    final start = topItem(tester);

    timeline(tester).jumpTo(timeline(tester).pixels + 500 * rowHeight);
    await tester.pump();
    expect(topItem(tester), isNot(start));

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(topItem(tester), start);
  });
}
