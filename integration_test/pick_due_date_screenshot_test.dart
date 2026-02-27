import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'pick_due_date_screenshot_test';

  testWidgets('pick due date for a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Due date task target';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      await expandTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_due_date_picker',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Pick due date').first);
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'due_date_picker_open',
          step: 2,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tapWhenPresent(tester, <Finder>[
        find.widgetWithText(TextButton, 'OK'),
        find.widgetWithText(TextButton, 'Save'),
      ]);

      screenshotFiles.add(
        await captureStep(
          tester,
          'due_date_saved',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.textContaining('Due:'), findsWidgets);
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
