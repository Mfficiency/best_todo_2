import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'add_note_screenshot_test';

  testWidgets('add a note to a task and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Note task target';
    const note = 'This is a task note.';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      await addTask(tester, taskTitle);
      await expandTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_note',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note').first,
        note,
      );
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'note_entered',
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
          'note_saved',
          step: 3,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      expect(find.text(note), findsOneWidget);
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
