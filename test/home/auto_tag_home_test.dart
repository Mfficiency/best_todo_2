import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/auto_tag_service.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    AutoTagService.instance.resetForTest();
  });

  tearDown(() {
    Config.autoTagEnabled = true;
  });

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text(tasks.first.title);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  Future<void> addTask(WidgetTester tester, String title) async {
    await tester.enterText(find.byType(TextField).first, title);
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('a new task is auto-tagged from a keyword in its title',
      (tester) async {
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    await addTask(tester, 'Fix my bike');

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final savedTask = saved!.firstWhere((t) => t.title == 'Fix my bike');
    expect(savedTask.label, 'bike');
  });

  testWidgets('auto-tagging is skipped when the setting is off',
      (tester) async {
    Config.autoTagEnabled = false;
    await pumpHome(tester, [
      Task(title: 'Existing today task', dueDate: DateTime.now()),
    ]);

    await addTask(tester, 'Fix my bike');

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final savedTask = saved!.firstWhere((t) => t.title == 'Fix my bike');
    expect(savedTask.label, '');
  });
}
