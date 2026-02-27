import 'package:besttodo/config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screenshot_test_utils.dart';

void main() {
  const testName = 'set_notification_screenshot_test';

  testWidgets('set task notification and capture screenshots', (tester) async {
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    final appBoundaryKey = GlobalKey();
    var testPassed = false;
    const taskTitle = 'Notification task target';

    try {
      await launchApp(tester, boundaryKey: appBoundaryKey);
      Config.enableNotifications = true;
      await addTask(tester, taskTitle);
      await expandTask(tester, taskTitle);
      screenshotFiles.add(
        await captureStep(
          tester,
          'before_notification',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.tap(find.byIcon(Icons.notifications_none).first);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'notification_result',
          step: 2,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      final hasNotificationFeedback = find.textContaining('Notification').evaluate().isNotEmpty;
      expect(hasNotificationFeedback, isTrue);
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
