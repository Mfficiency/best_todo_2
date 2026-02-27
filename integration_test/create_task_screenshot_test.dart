import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> captureStep(
    WidgetTester tester,
    String name, {
    required int step,
    required GlobalKey repaintBoundaryKey,
  }) async {
    final folder = Directory('build/e2e_screenshots');
    await folder.create(recursive: true);
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filePath =
        '${folder.path}/${step.toString().padLeft(2, '0')}_$safeName.png';

    try {
      await binding
          .takeScreenshot('${step.toString().padLeft(2, '0')}_$safeName');
    } catch (_) {
      // Fallback for platforms where integration_test screenshot capture
      // is not implemented.
    }

    final boundaryContext = repaintBoundaryKey.currentContext;
    if (boundaryContext == null) {
      fail('Could not find repaint boundary context for screenshot.');
    }
    final boundary =
        boundaryContext.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      fail('Could not find repaint boundary render object for screenshot.');
    }
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      fail('Could not encode screenshot for step "$name".');
    }
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  setUpAll(() async {
    final storage = StorageService();
    await storage.saveTaskList(<Task>[]);
    await storage.saveDeletedTaskList(<Task>[]);
    await storage.saveDailyTaskStats({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
  });

  testWidgets('create task on home page and save screenshots', (tester) async {
    const taskTitle = 'POC integration task';
    final appBoundaryKey = GlobalKey();
    final addTaskField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Add task' &&
          widget.enabled != false,
      description: 'Add task text field',
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: appBoundaryKey,
        child: const MyApp(showIntro: false),
      ),
    );
    await tester.pumpAndSettle();
    await captureStep(
      tester,
      'home_loaded',
      step: 1,
      repaintBoundaryKey: appBoundaryKey,
    );

    await tester.enterText(addTaskField, taskTitle);
    await tester.pumpAndSettle();
    await captureStep(
      tester,
      'task_title_entered',
      step: 2,
      repaintBoundaryKey: appBoundaryKey,
    );

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await captureStep(
      tester,
      'task_created',
      step: 3,
      repaintBoundaryKey: appBoundaryKey,
    );

    expect(find.text(taskTitle), findsOneWidget);
  });
}
