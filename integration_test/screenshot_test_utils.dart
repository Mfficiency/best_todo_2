import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/config.dart';
import 'package:besttodo/main.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final IntegrationTestWidgetsFlutterBinding integrationBinding =
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();

String _safeName(String value) {
  return value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

Future<Map<String, Object>> startSession(String testName) async {
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
  final sessionId = '${datePrefix}_${_safeName(testName)}';
  final sessionDir = Directory('${sessionsRoot.path}/$sessionId');
  await sessionDir.create(recursive: true);
  return <String, Object>{
    'id': sessionId,
    'testName': testName,
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
  final durationSeconds = finishedAt.difference(startedAt).inMilliseconds / 1000;

  List<Map<String, Object?>> sessions = <Map<String, Object?>>[];
  if (await indexFile.exists()) {
    try {
      final decoded = jsonDecode(await indexFile.readAsString());
      final parsed = decoded is Map<String, dynamic> ? decoded['sessions'] : null;
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

  sessions.removeWhere((entry) => entry['id'] == session['id']);
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
    await integrationBinding
        .takeScreenshot('${step.toString().padLeft(2, '0')}_${_safeName(name)}');
  } catch (_) {
    // Fallback below for environments where integration screenshot APIs
    // are unavailable.
  }

  final boundaryContext = repaintBoundaryKey.currentContext;
  if (boundaryContext == null) {
    fail('Could not find repaint boundary context for screenshot.');
  }
  final boundary = boundaryContext.findRenderObject() as RenderRepaintBoundary?;
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

Future<void> resetAppState() async {
  final storage = StorageService();
  await storage.saveTaskList(<Task>[]);
  await storage.saveDeletedTaskList(<Task>[]);
  await storage.saveDailyTaskStats({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('intro_shown', true);

  Config.defaultDelaySeconds = 0.2;
  Config.swipeLeftDelete = true;
  Config.darkMode = false;
  Config.enableNotifications = false;
  Config.defaultNotificationDelaySeconds = 3;
  Config.quietHoursEnabled = false;
  Config.quietHoursStartMinutes = 22 * 60;
  Config.quietHoursEndMinutes = 7 * 60;
  Config.useIconTabs = false;
  Config.showWidgetProgressLine = true;
  Config.addNewTasksToTop = true;
  Config.startTabIndex = 0;
}

Finder addTaskFieldFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.labelText == 'Add task' &&
        widget.enabled != false,
    description: 'Add task text field',
  );
}

Future<void> launchApp(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
}) async {
  await resetAppState();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: const MyApp(showIntro: false),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> addTask(WidgetTester tester, String title) async {
  await tester.enterText(addTaskFieldFinder(), title);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add).first);
  await tester.pumpAndSettle();
  expect(find.text(title), findsOneWidget);
}

Future<void> expandTask(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
  expect(find.widgetWithText(TextField, 'Title'), findsWidgets);
}

Future<void> collapseExpandedTask(WidgetTester tester) async {
  final collapse = find.byIcon(Icons.expand_less);
  expect(collapse, findsWidgets);
  await tester.tap(collapse.first);
  await tester.pumpAndSettle();
}

Future<void> tapWhenPresent(WidgetTester tester, List<Finder> finders) async {
  for (final finder in finders) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('None of the target controls were found.');
}
