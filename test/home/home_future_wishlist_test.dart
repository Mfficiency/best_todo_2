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

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    // Opt out of the one-time Todo.md import so the Future tab shows only
    // the wishlist items this test saves.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    required List<Task> tasks,
    required List<Task> wishlist,
    required String marker,
    int initialTabIndex = 0,
  }) async {
    // All real file I/O (pre-saving, HomePage's initState loads) must run on
    // the real event loop via runAsync, not the fake-async test zone.
    await tester.runAsync(() async {
      final storage = StorageService();
      await storage.saveTaskList(tasks);
      await storage.saveWishlist(wishlist);
    });
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialTabIndex: initialTabIndex)),
    );
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(markerFinder, findsOneWidget,
        reason: 'HomePage never loaded the tasks');
  }

  final futureDue = DateTime(2300, 1, 1);

  testWidgets('wishlist items appear on the Future tab tagged "wish"',
      (tester) async {
    await pumpHome(
      tester,
      tasks: [Task(title: 'Plan world trip', dueDate: futureDue)],
      wishlist: [
        Task(
          title: 'Buy a telescope',
          description: 'For stargazing weekends',
          label: 'gift',
        ),
      ],
      marker: 'Plan world trip',
      initialTabIndex: 5,
    );

    // Wishlist items are regular tasks in the one task list (merged from the
    // legacy wishlist.json); undated, they bucket into the Future tab and
    // render as full task tiles with a "wish" tag plus their own labels.
    expect(find.text('Buy a telescope'), findsOneWidget);
    expect(find.text('wish'), findsOneWidget);
    expect(find.text('gift'), findsOneWidget);
    // The description sits behind a chevron toggle, tags first.
    expect(find.text('For stargazing weekends'), findsNothing);
    await tester.tap(find.text('Description'));
    await tester.pump();
    expect(find.text('For stargazing weekends'), findsOneWidget);
  });

  testWidgets('wishlist items do not appear on the Today tab',
      (tester) async {
    await pumpHome(
      tester,
      tasks: [Task(title: 'Feed the zebra', dueDate: DateTime.now())],
      wishlist: [Task(title: 'Buy a telescope', label: 'gift')],
      marker: 'Feed the zebra',
    );

    expect(find.text('Buy a telescope'), findsNothing);
    expect(find.text('wish'), findsNothing);
  });
}
