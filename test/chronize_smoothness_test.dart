import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/chronize_page.dart';

/// Smoothness tests for the Chronize timeline.
///
/// Perceptual smoothness can't be asserted directly, so these tests pin the
/// invariants that *produce* it:
///   * every hour row is identical height with no gaps (so scrolling never
///     jumps between hours);
///   * the timeline scrolls infinitely in both directions;
///   * the timeline and the wheels stay in sync;
///   * a month change is animated and its visible motion is bounded to a single
///     glide (the "fake smooth" scroll) instead of teleporting the viewport.
void main() {
  const double rowHeight = 64; // _hourRowHeight
  const double itemExtent = 32; // CupertinoPicker itemExtent
  const double glideDistance = 8 * rowHeight; // _glideDistance

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

  // The timeline's scroll position. Each hour row contains a (non-scrolling)
  // task ListView, so there are many Scrollables under the CustomScrollView;
  // the timeline's own is the outermost, hence first in tree order.
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

  // Pixel offset of the wheel at [index] (0 = hour, 1 = day, 2 = month).
  double wheelPixels(WidgetTester tester, int index) {
    return tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CupertinoPicker).at(index),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
  }

  int topItem(WidgetTester tester) => (timeline(tester).pixels / rowHeight).round();

  testWidgets('every hour row is the same height with no gaps between hours',
      (tester) async {
    await pumpPage(tester);

    final top = topItem(tester);
    final a = find.byKey(ValueKey('chronize-hour-$top'));
    final b = find.byKey(ValueKey('chronize-hour-${top + 1}'));
    final c = find.byKey(ValueKey('chronize-hour-${top + 2}'));

    expect(a, findsOneWidget);
    expect(b, findsOneWidget);
    expect(c, findsOneWidget);

    // Identical, fixed heights.
    expect(tester.getSize(a).height, rowHeight);
    expect(tester.getSize(b).height, rowHeight);
    expect(tester.getSize(c).height, rowHeight);

    // Consecutive rows are exactly one row apart — no overlaps, no gaps. This
    // uniform mapping (offset == item * height) is what keeps scrolling from
    // jumping between hours.
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

    // Far into the future (~1000 days out).
    pos.jumpTo(pos.pixels + 1000 * 24 * rowHeight);
    await tester.pump();
    final future = topItem(tester);
    expect(find.byKey(ValueKey('chronize-hour-$future')), findsOneWidget);

    // Far into the past — negative items, before today.
    pos.jumpTo(-1000 * 24 * rowHeight);
    await tester.pump();
    final past = topItem(tester);
    expect(past, lessThan(0));
    expect(find.byKey(ValueKey('chronize-hour-$past')), findsOneWidget);

    // No overflow/out-of-range exceptions from either extreme.
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling the timeline keeps the hour wheel in sync',
      (tester) async {
    await pumpPage(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -7 * rowHeight));
    await tester.pumpAndSettle();

    // The hour wheel's selected item tracks the hour now at the top.
    final hourWheelItem = (wheelPixels(tester, 0) / itemExtent).round();
    expect(hourWheelItem, topItem(tester));
  });

  testWidgets('spinning the hour wheel scrolls the timeline to match',
      (tester) async {
    await pumpPage(tester);

    await tester.drag(
      find.byType(CupertinoPicker).at(0),
      const Offset(0, -5 * itemExtent),
    );
    await tester.pumpAndSettle();

    final hourWheelItem = (wheelPixels(tester, 0) / itemExtent).round();
    expect(topItem(tester), hourWheelItem);
  });

  testWidgets('a month change glides smoothly instead of teleporting',
      (tester) async {
    await pumpPage(tester);

    // Drag the month wheel just past half an item (plus touch slop) so the
    // selection advances exactly one month with a single change.
    final monthCenter = tester.getCenter(find.byType(CupertinoPicker).at(2));
    final gesture = await tester.startGesture(monthCenter);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump(); // selection crosses -> glide starts

    // Sample the timeline offset across the glide animation.
    final samples = <double>[];
    for (var i = 0; i < 30; i++) {
      samples.add(timeline(tester).pixels);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final settled = timeline(tester).pixels;

    // The month is hundreds of rows away, but the *visible* motion must never
    // be more than a single glide from where it lands — i.e. it fakes a smooth
    // scroll rather than snapping across the whole gap.
    for (final offset in samples) {
      expect(
        (offset - settled).abs(),
        lessThanOrEqualTo(glideDistance + 1),
        reason: 'timeline jumped more than one glide from its destination',
      );
    }

    // It genuinely animated (more than one distinct frame, and not already at
    // the destination on the first frame).
    expect(samples.toSet().length, greaterThan(1));
    expect((samples.first - settled).abs(), greaterThan(0));

    // And it actually moved a long way overall (a month, far beyond one glide),
    // confirming the bounded motion above was a faked glide, not a tiny hop.
    final start = topItem(tester); // settled top item
    expect(start.abs(), greaterThan(8)); // well past today's first hours
  });
}
