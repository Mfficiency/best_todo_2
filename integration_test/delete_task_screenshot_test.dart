import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'delete_task_screenshot_test';

  testWidgets('delete a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Delete task target';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_delete',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'delete_confirmation',
          step: 2,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.textContaining('Deleted'), findsOneWidget);
      screenshotFiles.add(
        await captureStep(
          tester,
          'after_delete',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

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
