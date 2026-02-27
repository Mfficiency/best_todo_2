import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'modify_task_screenshot_test';

  testWidgets('modify a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Modify task target';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'task_created',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await expandTask(tester, taskTitle);
      await tester.enterText(
        find.widgetWithText(TextField, 'Description').first,
        'Updated description text',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Note').first,
        'Updated note text',
      );
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'task_in_edit_mode',
          step: 2,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'task_after_edit',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.text('Updated description text'), findsOneWidget);
      expect(find.text('Updated note text'), findsOneWidget);
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
