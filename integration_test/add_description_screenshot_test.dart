import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'add_description_screenshot_test';

  testWidgets('add a description to a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Description task target';
    const description = 'This is a task description.';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      await expandTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_description',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Description').first,
        description,
      );
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'description_entered',
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
          'description_saved',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.text(description), findsOneWidget);
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
