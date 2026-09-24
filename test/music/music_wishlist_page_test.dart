import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/shared_wishlist_store.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/music_wishlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Best Music's Wishlist tool: a plain list over the same [Task] records
/// (flagged [Task.isWish]) BestToDo's own Wishlist writes to `tasks.json` —
/// the same JSON shape, but each app's own `tasks.json`. This page never
/// touches [SharedWishlistStore] (BestToDo's Wishlist still can, unchanged),
/// so checking an item off here never marks it done in BestToDo and vice
/// versa; each row is just a checkbox and a title, with no other chrome.
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
    // Real Best Music behavior: StorageService skips its BestToDo-only
    // Todo.md backlog import entirely when this is set (see main_music.dart).
    Config.isBestMusic = true;
    // Also opt out via the flag file, so tests that don't care about the
    // import either way still only see their own items.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  tearDown(() {
    Config.isBestMusic = false;
  });

  /// Pumps rounds of real-event-loop delay + frame pumps until [finder]
  /// finds something, or [rounds] is exhausted — the pattern real `dart:io`
  /// work inside a widget needs under `testWidgets`'s fake-async zone (see
  /// CLAUDE.md).
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
      {int rounds = 300}) async {
    for (var i = 0; i < rounds && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
  }

  /// A save started by a tap handler is awaited before the write actually
  /// lands on disk; a fixed number of runAsync rounds lets it finish before
  /// the test reads storage back.
  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> pumpWishlist(
    WidgetTester tester, {
    required List<Task> tasks,
    required Finder marker,
  }) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: MusicWishlistPage()));
    await pumpUntilFound(tester, marker);
  }

  testWidgets(
      'shows only wish-flagged items, as a checkbox and title with no other chrome',
      (tester) async {
    final wish = Task(
      title: 'Learn to sail',
      label: 'priority-medium',
      isWish: true,
      createdAt: DateTime.now(),
    );
    final regularTask = Task(title: 'Buy milk', createdAt: DateTime.now());
    await pumpWishlist(tester,
        tasks: [wish, regularTask], marker: find.text('Learn to sail'));

    expect(find.text('Learn to sail'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);

    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.leading, isA<Checkbox>());
    expect(tile.trailing, isNull);
    final checkbox = tile.leading as Checkbox;
    expect(checkbox.value, isFalse);
  });

  testWidgets(
      'tapping the checkbox marks an item done and persists it, without '
      'opening the editor', (tester) async {
    final wish = Task(
      title: 'Mark me done',
      isWish: true,
      createdAt: DateTime.now(),
    );
    await pumpWishlist(tester,
        tasks: [wish], marker: find.text('Mark me done'));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('Edit wishlist item'), findsNothing);
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    final checkbox = tile.leading as Checkbox;
    expect(checkbox.value, isTrue);
    expect((tile.title as Text).style?.decoration, TextDecoration.lineThrough);

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    expect(saved!.single.isDone, isTrue);
    expect(saved.single.completedAt, isNotNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await settleWrites(tester);
    final unsaved =
        await tester.runAsync(() => StorageService().loadTaskList());
    expect(unsaved!.single.isDone, isFalse);
    expect(unsaved.single.completedAt, isNull);
  });

  testWidgets('empty state shown when there are no wishlist items',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: const [],
      marker: find.textContaining('No wishlist items yet'),
    );

    expect(find.textContaining('No wishlist items yet'), findsOneWidget);
  });

  testWidgets('tapping an item opens its description, priority and tags',
      (tester) async {
    final wish = Task(
      title: 'New headphones',
      description: 'Over-ear, noise cancelling',
      label: 'priority-high, gift-idea',
      isWish: true,
      createdAt: DateTime.now(),
    );
    await pumpWishlist(tester,
        tasks: [wish], marker: find.text('New headphones'));

    await tester.tap(find.text('New headphones'));
    await tester.pumpAndSettle();

    expect(find.text('Edit wishlist item'), findsOneWidget);
    expect(find.text('Over-ear, noise cancelling'), findsOneWidget);
    expect(find.text('gift-idea'), findsOneWidget);
    final highChip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'high'));
    expect(highChip.selected, isTrue);
  });

  testWidgets('editing title and description saves back to storage',
      (tester) async {
    final wish = Task(
      title: 'Old title',
      isWish: true,
      createdAt: DateTime.now(),
    );
    await pumpWishlist(tester, tasks: [wish], marker: find.text('Old title'));

    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'New title');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'A new description');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('New title'), findsOneWidget);

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    final savedWish = saved!.single;
    expect(savedWish.title, 'New title');
    expect(savedWish.description, 'A new description');
    expect(savedWish.isWish, isTrue);
  });

  testWidgets('adding a new item via the FAB creates a wish-flagged task',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: const [],
      marker: find.textContaining('No wishlist items yet'),
    );

    await tester.tap(find.byTooltip('Add wishlist item'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Concert tickets');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Concert tickets'), findsOneWidget);
    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    expect(saved!.single.isWish, isTrue);
    expect(saved.single.title, 'Concert tickets');
  });

  testWidgets('deleting an item from the editor removes it from the list',
      (tester) async {
    final wish = Task(
      title: 'To be deleted',
      isWish: true,
      createdAt: DateTime.now(),
    );
    await pumpWishlist(tester,
        tasks: [wish], marker: find.text('To be deleted'));

    await tester.tap(find.text('To be deleted'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('To be deleted'), findsNothing);
    expect(find.textContaining('No wishlist items yet'), findsOneWidget);

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    expect(saved, isEmpty);
  });

  group('does not sync with BestToDo', () {
    late Directory sharedDir;

    setUp(() async {
      sharedDir = await Directory.systemTemp.createTemp('shared_');
      SharedWishlistStore.sharedDirectoryOverride = sharedDir;
    });

    tearDown(() {
      SharedWishlistStore.sharedDirectoryOverride = null;
      SharedWishlistStore.connectionOverride = null;
    });

    testWidgets(
        'an item already sitting in the shared external-storage file never '
        'shows up here', (tester) async {
      await tester.runAsync(() => SharedWishlistStore.instance.save(
          [Task(title: 'From BestToDo', isWish: true, createdAt: DateTime.now())]));

      await pumpWishlist(
        tester,
        tasks: const [],
        marker: find.textContaining('No wishlist items yet'),
      );

      expect(find.text('From BestToDo'), findsNothing);
    });

    testWidgets(
        'checking an item off here never writes to the shared '
        'external-storage file BestToDo reads', (tester) async {
      final wish = Task(
        title: 'Only in Best Music',
        isWish: true,
        createdAt: DateTime.now(),
      );
      await pumpWishlist(tester,
          tasks: [wish], marker: find.text('Only in Best Music'));

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await settleWrites(tester);

      final shared =
          await tester.runAsync(() => SharedWishlistStore.instance.load());
      expect(shared!.fileExisted, isFalse);
      expect(shared.items, isEmpty);
    });
  });
}
