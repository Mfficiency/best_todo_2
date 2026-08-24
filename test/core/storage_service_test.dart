import 'dart:io';
import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  /// Opts out of the one-time Todo.md → wishlist import that loadTaskList
  /// runs (via the wishlist merge) on first load.
  Future<void> writeImportFlag(Directory dir) => File(
          '${dir.path}/${StorageService.wishlistImportFlagFileName}')
      .writeAsString('done');

  test('loadTaskList removes completed tasks on new day', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await writeImportFlag(tempDir);

    final service = StorageService();
    final tasks = [
      Task(title: 'done', isDone: true),
      Task(title: 'pending'),
    ];
    await service.saveTaskList(tasks);

    final dateFile = File('${tempDir.path}/last_opened.txt');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await dateFile.writeAsString(yesterday.toIso8601String());

    final loaded = await service.loadTaskList();
    expect(loaded.length, 1);
    expect(loaded.first.title, 'pending');

    final deleted = await service.loadDeletedTaskList();
    expect(deleted.length, 1);
    expect(deleted.first.title, 'done');
  });

  test('loadTaskList merges wishlist.json items into the task list', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await writeImportFlag(tempDir);

    final service = StorageService();
    await service.saveTaskList([Task(title: 'real task')]);
    await service.saveWishlist([
      Task(title: 'telescope', label: 'gift', dueDate: DateTime(2300, 1, 1)),
    ]);

    final loaded = await service.loadTaskList();
    expect(loaded.length, 2);
    final wish = loaded.singleWhere((t) => t.title == 'telescope');
    expect(wish.isWish, isTrue);
    // Wishes are undated; they bucket into the Future tab from that alone.
    expect(wish.dueDate, isNull);
    expect(wish.label, 'gift');
    expect(loaded.singleWhere((t) => t.title == 'real task').isWish, isFalse);

    // The merge is persisted and the legacy file emptied, so a second load
    // does not duplicate anything.
    final wishlistFile = File('${tempDir.path}/wishlist.json');
    expect(jsonDecode(await wishlistFile.readAsString()), isEmpty);
    final again = await service.loadTaskList();
    expect(again.length, 2);
    expect(again.where((t) => t.isWish).length, 1);
  });

  test('loadTaskList picks up wishlist items even without a tasks file',
      () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await writeImportFlag(tempDir);

    final service = StorageService();
    await service.saveWishlist([Task(title: 'only a wish')]);

    final loaded = await service.loadTaskList();
    expect(loaded.length, 1);
    expect(loaded.single.title, 'only a wish');
    expect(loaded.single.isWish, isTrue);
  });

  test('importTaskList assigns unique ids when missing or duplicated', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    final file = File('${tempDir.path}/tasks.json');
    final data = [
      {'title': 'a', 'uid': 'same'},
      {'title': 'b', 'uid': 'same'},
      {'title': 'c'},
    ];
    await file.writeAsString(jsonEncode(data));
    final service = StorageService();
    final tasks = await service.importTaskList(file.path);
    expect(tasks.length, 3);
    final ids = tasks.map((t) => t.uid).toSet();
    expect(ids.length, 3);
  });

  test('loadBinTaskList purges items older than the retention window',
      () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await writeImportFlag(tempDir);

    final originalRetention = Config.deletedItemsRetentionDays;
    addTearDown(() => Config.deletedItemsRetentionDays = originalRetention);
    Config.deletedItemsRetentionDays = 10;

    final service = StorageService();
    final fresh = Task(
      title: 'fresh',
      deletedAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    final stale = Task(
      title: 'stale',
      deletedAt: DateTime.now().subtract(const Duration(days: 30)),
    );
    await service.saveBinTaskList([fresh, stale]);

    final loaded = await service.loadBinTaskList();
    expect(loaded.length, 1);
    expect(loaded.single.title, 'fresh');

    // The purge is persisted, so a second load stays clean without stale
    // ever having been written back.
    final loadedAgain = await service.loadBinTaskList();
    expect(loadedAgain.length, 1);
  });
}

