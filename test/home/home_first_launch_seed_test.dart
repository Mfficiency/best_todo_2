import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/wishlist_migration.dart';
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
    // A pristine documents dir: no tasks, no wishlist, no import flag — the
    // state of a genuinely fresh install.
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  testWidgets('a first launch seeds the starter tasks even though the '
      'Todo.md import already filled the task list with wishes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // HomePage._loadTasks is a chain of real file operations started in the
    // fake-async zone; each hop needs a real-event-loop slice plus a pump.
    final marker = find.text(Config.initialTasks.first);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(marker, findsOneWidget,
        reason: 'the starter task list was never seeded');

    // _loadTasks ends in a save whose write only progresses on the real event
    // loop, so give it a fixed number of rounds before reading the file back.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final titles = saved!.map((t) => t.title).toSet();
    for (final starter in Config.initialTasks) {
      expect(titles, contains(starter));
    }
    // The imported backlog survives alongside the starter tasks.
    expect(saved.where((Task t) => t.isWish), isNotEmpty);
    expect(titles, contains(legacyTodoWishlistItems.first.title));
  });
}
