import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const forceFailure = bool.fromEnvironment(
    'FORCE_CREATE_TASK_SCREENSHOT_FAILURE',
    defaultValue: false,
  );
  const updateGoldens = bool.fromEnvironment(
    'UPDATE_CREATE_TASK_GOLDENS',
    defaultValue: false,
  );
  const testName = 'create_task_screenshot_test';
  const goldenRootPath = 'integration_test/goldens/create_task';

  String _safeName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  Future<Map<String, Object>> startSession(String name) async {
    final root = Directory('build/e2e_screenshots');
    final sessionsRoot = Directory('${root.path}/sessions');
    await sessionsRoot.create(recursive: true);
    final startedAt = DateTime.now().toUtc();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final datePrefix =
        '${startedAt.year}'
        '${twoDigits(startedAt.month)}'
        '${twoDigits(startedAt.day)}_'
        '${twoDigits(startedAt.hour)}'
        '${twoDigits(startedAt.minute)}'
        '${twoDigits(startedAt.second)}';
    final sessionId =
        '${datePrefix}_${_safeName(name)}';
    final sessionDir = Directory('${sessionsRoot.path}/$sessionId');
    await sessionDir.create(recursive: true);
    return <String, Object>{
      'id': sessionId,
      'testName': name,
      'startedAt': startedAt.toIso8601String(),
      'startedAtEpochSeconds': startedAt.millisecondsSinceEpoch ~/ 1000,
      'sessionDirPath': sessionDir.path,
    };
  }

  Future<void> finalizeSession(
    Map<String, Object> session, {
    required bool passed,
    required List<String> screenshotFiles,
  }) async {
    final root = Directory('build/e2e_screenshots');
    final sessionsRoot = Directory('${root.path}/sessions');
    await sessionsRoot.create(recursive: true);
    final indexFile = File('${root.path}/sessions_index.json');
    final finishedAt = DateTime.now().toUtc();

    final startedAt = DateTime.parse(session['startedAt']! as String);
    final durationSeconds =
        finishedAt.difference(startedAt).inMilliseconds / 1000.0;

    List<Map<String, Object?>> sessions = <Map<String, Object?>>[];
    if (await indexFile.exists()) {
      try {
        final decoded = jsonDecode(await indexFile.readAsString());
        final parsed = decoded is Map<String, dynamic>
            ? decoded['sessions']
            : null;
        if (parsed is List) {
          sessions = parsed
              .whereType<Map>()
              .map((entry) => Map<String, Object?>.from(entry))
              .toList();
        }
      } catch (_) {
        sessions = <Map<String, Object?>>[];
      }
    }

    final newSession = <String, Object?>{
      'id': session['id'],
      'testName': session['testName'],
      'status': passed ? 'passed' : 'failed',
      'startedAt': session['startedAt'],
      'finishedAt': finishedAt.toIso8601String(),
      'startedAtEpochSeconds': session['startedAtEpochSeconds'],
      'finishedAtEpochSeconds': finishedAt.millisecondsSinceEpoch ~/ 1000,
      'durationSeconds': durationSeconds,
      'screenshotCount': screenshotFiles.length,
      'screenshotFiles': screenshotFiles,
    };

    final newId = session['id'];
    sessions.removeWhere((entry) => entry['id'] == newId);
    sessions.add(newSession);
    sessions.sort(
      (a, b) => (b['startedAtEpochSeconds'] as int)
          .compareTo(a['startedAtEpochSeconds'] as int),
    );

    final keepSessions = sessions.take(5).toList(growable: false);
    final keepIds = keepSessions.map((entry) => entry['id']).toSet();

    if (await sessionsRoot.exists()) {
      for (final entity in sessionsRoot.listSync()) {
        if (entity is! Directory) {
          continue;
        }
        final segments = entity.path.split(Platform.pathSeparator);
        final dirName = segments.isEmpty ? entity.path : segments.last;
        if (!keepIds.contains(dirName)) {
          await entity.delete(recursive: true);
        }
      }
    }

    final payload = <String, Object?>{
      'maxSessions': 5,
      'updatedAt': finishedAt.toIso8601String(),
      'sessions': keepSessions,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await indexFile.writeAsString('${encoder.convert(payload)}\n', flush: true);
  }

  Future<void> compareWithGoldenReference(List<String> screenshotFiles) async {
    final goldenRoot = Directory(goldenRootPath);
    await goldenRoot.create(recursive: true);

    for (final screenshotPath in screenshotFiles) {
      final screenshotFile = File(screenshotPath);
      final screenshotName = screenshotFile.uri.pathSegments.last;
      final goldenFile = File('${goldenRoot.path}/$screenshotName');

      if (updateGoldens) {
        await screenshotFile.copy(goldenFile.path);
        continue;
      }

      if (!await goldenFile.exists()) {
        fail(
          'Golden reference missing for "$screenshotName". '
          'Create it by running with '
          '--dart-define=UPDATE_CREATE_TASK_GOLDENS=true',
        );
      }

      final actualBytes = await screenshotFile.readAsBytes();
      final goldenBytes = await goldenFile.readAsBytes();
      final isMatch = listEquals(actualBytes, goldenBytes);
      expect(
        isMatch,
        isTrue,
        reason:
            'Screenshot "$screenshotName" does not match historical golden '
            'reference at "${goldenFile.path}".',
      );
    }
  }

  Future<String> captureStep(
    WidgetTester tester,
    String name, {
    required int step,
    required GlobalKey repaintBoundaryKey,
    required String sessionDirPath,
  }) async {
    final fileName = '${step.toString().padLeft(2, '0')}_${_safeName(name)}.png';
    final filePath = '$sessionDirPath/$fileName';

    try {
      await binding
          .takeScreenshot('${step.toString().padLeft(2, '0')}_${_safeName(name)}');
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
    return filePath;
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
    final session = await startSession(testName);
    final screenshotFiles = <String>[];
    var testPassed = false;

    const taskTitle = 'POC integration task';
    final appBoundaryKey = GlobalKey();
    final addTaskField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Add task' &&
          widget.enabled != false,
      description: 'Add task text field',
    );

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: appBoundaryKey,
          child: const MyApp(showIntro: false),
        ),
      );
      await tester.pumpAndSettle();
      screenshotFiles.add(
        await captureStep(
          tester,
          'home_loaded',
          step: 1,
          repaintBoundaryKey: appBoundaryKey,
          sessionDirPath: session['sessionDirPath']! as String,
        ),
      );

      await tester.enterText(addTaskField, taskTitle);
      await tester.pumpAndSettle();
      final step2Path = await captureStep(
        tester,
        'task_title_entered',
        step: 2,
        repaintBoundaryKey: appBoundaryKey,
        sessionDirPath: session['sessionDirPath']! as String,
      );
      screenshotFiles.add(step2Path);

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      final step3Path = await captureStep(
        tester,
        'task_created',
        step: 3,
        repaintBoundaryKey: appBoundaryKey,
        sessionDirPath: session['sessionDirPath']! as String,
      );
      screenshotFiles.add(step3Path);

      expect(find.text(taskTitle), findsOneWidget);

      await compareWithGoldenReference(screenshotFiles);

      final step2Bytes = await File(step2Path).readAsBytes();
      final step3Bytes = await File(step3Path).readAsBytes();
      final areEqual = listEquals(step2Bytes, step3Bytes);
      if (forceFailure) {
        expect(
          areEqual,
          isTrue,
          reason:
              'Intentional failure mode is ON. Step 2 and Step 3 screenshots '
              'should normally differ, so this assertion is expected to fail.',
        );
      } else {
        expect(
          areEqual,
          isFalse,
          reason:
              'Step 2 and Step 3 screenshots are identical, but UI should have '
              'changed after creating a task.',
        );
      }
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
