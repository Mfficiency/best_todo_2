import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/shared_wishlist_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SharedWishlistStore] is what makes a Wishlist item genuinely the same
/// record in both BestToDo and Best Music (two separately-sandboxed Android
/// apps) rather than merely the same JSON shape: both apps read/write one
/// file under [SharedWishlistStore.sharedDirectoryOverride] (real devices
/// use a fixed path under external storage instead).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    SharedWishlistStore.sharedDirectoryOverride = tempDir;
  });

  tearDown(() {
    SharedWishlistStore.sharedDirectoryOverride = null;
    SharedWishlistStore.connectionOverride = null;
  });

  group('isConnected / isSupported', () {
    test('the test override counts as connected and supported', () async {
      expect(SharedWishlistStore.instance.isSupported, isTrue);
      expect(await SharedWishlistStore.instance.isConnected(), isTrue);
    });
  });

  group('save / load round-trip', () {
    test('an item saved by one "app" is read back by another', () async {
      final item = Task(title: 'Shared idea', isWish: true, label: 'priority-high');
      final saved = await SharedWishlistStore.instance.save([item]);
      expect(saved, isTrue);

      // A second store instance pointed at the same override directory
      // stands in for the other app reading the same shared file.
      final result = await SharedWishlistStore.instance.load();
      expect(result.fileExisted, isTrue);
      expect(result.items, hasLength(1));
      expect(result.items.single.title, 'Shared idea');
      expect(result.items.single.uid, item.uid);
      expect(result.items.single.label, 'priority-high');
    });

    test('load reports fileExisted=false before anything has been saved',
        () async {
      final result = await SharedWishlistStore.instance.load();
      expect(result.fileExisted, isFalse);
      expect(result.items, isEmpty);
    });

    test('a deletion (saving a smaller set) is visible on the next load',
        () async {
      final a = Task(title: 'Keep', isWish: true);
      final b = Task(title: 'Delete me', isWish: true);
      await SharedWishlistStore.instance.save([a, b]);

      await SharedWishlistStore.instance.save([a]);

      final result = await SharedWishlistStore.instance.load();
      expect(result.items.map((t) => t.title), ['Keep']);
    });

    test('an empty saved list still reports fileExisted=true', () async {
      await SharedWishlistStore.instance.save(<Task>[]);
      final result = await SharedWishlistStore.instance.load();
      expect(result.fileExisted, isTrue);
      expect(result.items, isEmpty);
    });
  });

  group('reconcileWishlist', () {
    test('an existing shared file wins over local, deletions included', () {
      final localOnly = Task(title: 'Local only, not yet pushed', isWish: true);
      final sharedItem = Task(title: 'From the shared file', isWish: true);
      final shared = SharedWishlistLoadResult(
        items: [sharedItem],
        fileExisted: true,
      );
      final result = reconcileWishlist([localOnly, sharedItem], shared);
      expect(result, [sharedItem]);
    });

    test('local seeds the result when the shared file does not exist yet',
        () {
      final local = [Task(title: 'Not yet shared', isWish: true)];
      const shared = SharedWishlistLoadResult(items: <Task>[], fileExisted: false);
      expect(reconcileWishlist(local, shared), local);
    });
  });

  group('not connected', () {
    test('save/load no-op when unsupported and unoverridden', () async {
      SharedWishlistStore.sharedDirectoryOverride = null;
      // Platform.isAndroid is false on the host running `flutter test`, so
      // with no override this store is unsupported/unconnected.
      expect(SharedWishlistStore.instance.isSupported, isFalse);
      expect(await SharedWishlistStore.instance.isConnected(), isFalse);
      expect(await SharedWishlistStore.instance.save([Task(title: 'x')]),
          isFalse);
      final result = await SharedWishlistStore.instance.load();
      expect(result.fileExisted, isFalse);
      expect(result.items, isEmpty);
    });
  });
}
