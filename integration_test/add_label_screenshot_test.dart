import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'add_label_screenshot_test';

  testWidgets('add a label to a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Label task target';
    const label = 'Urgent';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      await expandTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_label',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Label').first,
        label,
      );
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'label_entered',
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
          'label_saved',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.text(label), findsOneWidget);
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
