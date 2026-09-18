import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/shared_wishlist_store.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/music_wishlist_page.dart';
import 'package:besttodo/ui/wishlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// End-to-end proof that a wishlist item is genuinely shared between
/// BestToDo and Best Music, not just the same JSON shape sitting in two
/// unrelated local databases: each app gets its own fake app-private
/// storage directory (mirroring their real, separately-sandboxed
/// `applicationId`s), and [SharedWishlistStore.sharedDirectoryOverride]
/// stands in for the one external-storage file both real apps read/write.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory todoLocalDir;
  late Directory musicLocalDir;
  late Directory sharedDir;

  // Real dart:io work, so every call site wraps this in `tester.runAsync` —
  // called directly inside a `testWidgets` body (not `setUp`), it would
  // otherwise hang forever in the fake-async zone (see CLAUDE.md's "Real
  // file I/O hangs inside testWidgets" note).
  Future<void> useTodoStorage(WidgetTester tester) async {
    PathProviderPlatform.instance = _FakePathProvider(todoLocalDir.path);
    await tester.runAsync(() => File(
            '${todoLocalDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done'));
  }

  Future<void> useMusicStorage(WidgetTester tester) async {
    PathProviderPlatform.instance = _FakePathProvider(musicLocalDir.path);
    await tester.runAsync(() => File(
            '${musicLocalDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done'));
  }

  setUp(() async {
    todoLocalDir = await Directory.systemTemp.createTemp('todo_');
    musicLocalDir = await Directory.systemTemp.createTemp('music_');
    sharedDir = await Directory.systemTemp.createTemp('shared_');
    SharedWishlistStore.sharedDirectoryOverride = sharedDir;
    Config.wishlistSyncBannerDismissed = false;
  });

  tearDown(() {
    SharedWishlistStore.sharedDirectoryOverride = null;
    SharedWishlistStore.connectionOverride = null;
    Config.wishlistSyncBannerDismissed = false;
  });

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
      {int rounds = 300}) async {
    for (var i = 0; i < rounds && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
  }

  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets(
      'an item added in BestToDo (once connected) shows up in Best Music',
      (tester) async {
    // Start "not connected" so BestToDo's Connect banner is exercised for
    // real, exactly like a fresh install of either app.
    SharedWishlistStore.connectionOverride = false;

    // BestToDo: add a wishlist item and connect sync. A non-empty seed
    // keeps the page's dev-mode demo-wish seeding (which only fires on a
    // truly empty list) out of the way, so the shared file ends up with
    // exactly the one item this test adds.
    await useTodoStorage(tester);
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'placeholder', createdAt: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: WishlistPage()));
    await pumpUntilFound(tester, find.text('Connect'));

    await tester.tap(find.text('Connect'));
    await settleWrites(tester);

    await tester.tap(find.byTooltip('Add wishlist item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'),
        'Shared across both apps');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Shared across both apps'), findsOneWidget);

    // Best Music: a fresh page, its own separate local storage, but the
    // same shared external file — it should see BestToDo's item without
    // ever having written it locally itself.
    await useMusicStorage(tester);
    await tester.runAsync(() => StorageService().saveTaskList(const []));
    await tester.pumpWidget(const MaterialApp(home: MusicWishlistPage()));
    await pumpUntilFound(
        tester, find.text('Shared across both apps'));

    expect(find.text('Shared across both apps'), findsOneWidget);

    final musicLocal =
        await tester.runAsync(() => StorageService().loadTaskList());
    expect(musicLocal!.single.title, 'Shared across both apps');
    expect(musicLocal.single.isWish, isTrue);
  });

  testWidgets('a deletion in Best Music is reflected back in BestToDo',
      (tester) async {
    // Seed the shared file directly, as if BestToDo had already pushed two
    // items there.
    final keep = Task(title: 'Keep', isWish: true, createdAt: DateTime.now());
    final removeMe =
        Task(title: 'Remove me', isWish: true, createdAt: DateTime.now());
    await tester
        .runAsync(() => SharedWishlistStore.instance.save([keep, removeMe]));

    // Best Music: already connected (like BestToDo, in this test) — loading
    // the page alone should pull both shared items in and delete one.
    await useMusicStorage(tester);
    await tester.runAsync(() => StorageService().saveTaskList(const []));
    await tester.pumpWidget(const MaterialApp(home: MusicWishlistPage()));
    await pumpUntilFound(tester, find.text('Remove me'));

    await tester.tap(find.text('Remove me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Remove me'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);

    // BestToDo: opening the Wishlist tool should no longer show the item
    // Best Music deleted.
    await useTodoStorage(tester);
    await tester.runAsync(() => StorageService().saveTaskList(const []));
    await tester.pumpWidget(const MaterialApp(home: WishlistPage()));
    await pumpUntilFound(tester, find.text('Keep'));

    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Remove me'), findsNothing);
  });
}
