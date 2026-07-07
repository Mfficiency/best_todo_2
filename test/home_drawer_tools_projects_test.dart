import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
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
  });

  testWidgets('Projects lives under Tools in the drawer and opens the page',
      (tester) async {
    await StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // Projects is not a top-level drawer entry anymore.
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Tools'), findsOneWidget);

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);

    // Scroll the expanded entry into view if needed and open it.
    await tester.ensureVisible(find.text('Projects'));
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();

    expect(find.text('All Tasks'), findsOneWidget);
    expect(find.text('Project 1'), findsOneWidget);
  });
}
