import 'dart:io';

import 'package:besttodo/models/task.dart';
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

Finder get _searchField => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search tasks',
    );

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  testWidgets('the drawer Home entry returns to the start screen',
      (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Alpha', dueDate: now),
          Task(title: 'Beta', dueDate: now),
          Task(title: 'Gamma', dueDate: now.add(const Duration(days: 1))),
        ]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text('Alpha');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');

    // Wander off: search for one task, then switch to another tab. The query
    // is deliberately not a whole title — `find.text` would otherwise also
    // match the search field's own contents.
    await tester.enterText(_searchField, 'Alph');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    // Back on the start tab with the search dropped, so the whole Today list
    // is visible again.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsNothing);
    expect(tester.widget<TextField>(_searchField).controller?.text, '');
  });
}
