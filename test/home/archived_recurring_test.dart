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

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    // Opt out of the one-time Todo.md -> wishlist import so the Future tab
    // stays empty and does not interfere with the dated instances below.
    await File(
            '${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  testWidgets(
      'an already-archived recurring occurrence is not resurrected on load, '
      'and the rest of the series is untouched', (tester) async {
    final today = _dateOnly(DateTime.now());
    final parent = Task(
      title: 'Water the plants',
      dueDate: today,
      createdAt: DateTime.now(),
      isRecurring: true,
      recurrenceIntervalDays: 1,
      recurrenceEndDate: today.add(const Duration(days: 3)),
    );
    // Simulate a prior session where the +1 day occurrence was already
    // generated and then manually archived (swiped away) — exactly the
    // sequence HomePage._deleteTask produces, just pre-seeded on disk so a
    // single load is enough to expose whether the refresh recreates it.
    final archivedInstance = Task(
      title: parent.title,
      dueDate: today.add(const Duration(days: 1)),
      recurrenceParentUid: parent.uid,
      recurrenceInstanceKey: 'seed',
      deletedAt: DateTime.now(),
    );

    await tester.runAsync(() async {
      await StorageService().saveTaskList([parent]);
      await StorageService().saveDeletedTaskList([archivedInstance]);
    });

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text('Water the plants');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsWidgets, reason: 'HomePage never loaded the tasks');
    // The startup refresh's own save is a fire-and-forget real file write
    // that starts *after* the marker above is already on screen (see
    // CLAUDE.md on real file I/O inside testWidgets) — poll a fixed round so
    // it actually lands before reading storage back below.
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final reloaded =
        (await tester.runAsync(() => StorageService().loadTaskList()))!;
    final instances =
        reloaded.where((t) => t.recurrenceParentUid == parent.uid).toList();

    // The archived date must not have been resurrected...
    expect(
      instances.any(
          (t) => _dateOnly(t.dueDate!) == today.add(const Duration(days: 1))),
      isFalse,
    );
    // ...but the rest of the series still generated normally.
    expect(
      instances.any(
          (t) => _dateOnly(t.dueDate!) == today.add(const Duration(days: 2))),
      isTrue,
    );
    expect(
      instances.any(
          (t) => _dateOnly(t.dueDate!) == today.add(const Duration(days: 3))),
      isTrue,
    );

    // The archived instance itself is still there, untouched (a dev build
    // also backfills unrelated seed entries into the archive, so check
    // membership rather than an exact single-item list).
    final archived =
        await tester.runAsync(() => StorageService().loadDeletedTaskList());
    expect(archived!.any((t) => t.uid == archivedInstance.uid), isTrue);
  });
}
