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
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // Iterate real-event-loop slices until HomePage's file loads finish (see
    // home_search_test.dart for why a single delay is not enough).
    final marker = find.text('Alpha');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // Projects is not a top-level drawer entry anymore.
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Tools'), findsOneWidget);

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);

    // Scroll the drawer (not the body list) until the entry is tappable.
    final drawerScrollable =
        find.ancestor(of: find.text('Tools'), matching: find.byType(Scrollable));
    await tester.scrollUntilVisible(find.text('Projects'), 50,
        scrollable: drawerScrollable.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('All Tasks'), findsOneWidget);
    expect(find.text('Project 1'), findsOneWidget);
  });
}
