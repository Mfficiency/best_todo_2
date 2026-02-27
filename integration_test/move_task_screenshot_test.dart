import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'move_task_screenshot_test';

  testWidgets('move a task to another tab and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Move task target';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'source_list_before_move',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.tap(find.byTooltip('Reschedule').first);
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'move_options_open',
          step: 2,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      final tomorrowButton = find.byWidgetPredicate(
        (widget) =>
            widget is TextButton &&
            widget.child is Text &&
            ((widget.child as Text).data ?? '').contains('Tomorrow'),
      );
      expect(tomorrowButton, findsWidgets);
      await tester.tap(tomorrowButton.first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tomorrow').first);
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'destination_list_after_move',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.text(taskTitle), findsOneWidget);
      testPassed = true;
    } finally {
      await finalizeSession(
        session,
        passed: testPassed,
        screenshotFiles: screenshotFiles,
      );
    }
  });
}
