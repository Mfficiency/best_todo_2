import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/wishlist_migration.dart';
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
  });

  File flagFile() =>
      File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}');

  test('first load imports the Todo.md backlog labelled "old"', () async {
    final items = await StorageService().loadWishlist();

    expect(items.length, legacyTodoWishlistItems.length);
    expect(items.every((t) => t.label == legacyTodoImportLabel), isTrue);
    expect(items.map((t) => t.title), contains('calendar view'));
    expect(items.map((t) => t.title), contains('web version'));

    // The merged list is persisted and the run-once flag written.
    expect(File('${tempDir.path}/wishlist.json').existsSync(), isTrue);
    expect(flagFile().existsSync(), isTrue);
  });

  test('existing items are kept and matching titles are not duplicated',
      () async {
    final service = StorageService();
    // Same title as a backlog entry, differing only in case and whitespace.
    await service.saveWishlist([
      Task(title: 'Buy a telescope', label: 'gift'),
      Task(title: 'Calendar  View', label: 'ui'),
    ]);

    final items = await service.loadWishlist();

    expect(items.map((t) => t.title), contains('Buy a telescope'));
    final calendarish = items
        .where((t) => normalizeWishlistTitle(t.title) == 'calendar view')
        .toList();
    expect(calendarish.length, 1);
    // The user's own item is untouched, including its label.
    expect(calendarish.single.title, 'Calendar  View');
    expect(calendarish.single.label, 'ui');
    expect(items.length, 1 + legacyTodoWishlistItems.length);
  });

  test('import runs only once, so deleting an imported item sticks', () async {
    final service = StorageService();
    final first = await service.loadWishlist();
    first.removeWhere(
        (t) => normalizeWishlistTitle(t.title) == 'web version');
    await service.saveWishlist(first);

    final second = await service.loadWishlist();

    expect(
      second.where((t) => normalizeWishlistTitle(t.title) == 'web version'),
      isEmpty,
    );
    expect(second.length, legacyTodoWishlistItems.length - 1);
  });

  test('an unreadable wishlist file is never overwritten by the import',
      () async {
    final file = File('${tempDir.path}/wishlist.json');
    await file.writeAsString('not json');

    final items = await StorageService().loadWishlist();

    expect(items, isEmpty);
    expect(await file.readAsString(), 'not json');
    // No flag either: the import stays pending until the file is readable.
    expect(flagFile().existsSync(), isFalse);
  });

  test('backlog titles are unique after normalization', () {
    final normalized =
        legacyTodoWishlistItems.map((i) => normalizeWishlistTitle(i.title));
    expect(normalized.toSet().length, legacyTodoWishlistItems.length);
  });
}
