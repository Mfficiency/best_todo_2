import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/task_tile.dart';

void main() {
  // Regression test: the swipe-to-move default used to auto-commit to
  // whichever tab sorted first with the current tab removed (index 0 for
  // any non-Today page), so swiping a task on Tomorrow snapped it back to
  // Today instead of moving it forward to Day after tomorrow. The default
  // must always be "move forward one tab", matching _moveTaskToNextPage.
  testWidgets(
      'swiping to move auto-commits to the next tab, not just the first '
      'other tab', (tester) async {
    int? movedTo;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: Task(title: 'Pay rent'),
          onChanged: () {},
          onToggle: () {},
          onMove: (dest) => movedTo = dest,
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 1, // Tomorrow
        ),
      ),
    ));

    // swipeLeftDelete defaults to true, so dragging right opens Move options.
    await tester.drag(find.text('Pay rent').first, const Offset(300, 0));
    await tester.pump();

    // Let the options overlay's countdown auto-commit the default choice.
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));

    // Tab 2 is "Day After Tomorrow" — the tab right after Tomorrow (1), not
    // tab 0 (Today), which is what a plain ascending-sort default would pick.
    expect(movedTo, 2);
  });
}
