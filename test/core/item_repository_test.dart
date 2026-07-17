import 'dart:io';

import 'package:besttodo/models/item_event.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/item_repository.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    StorageService.resetJournalBaselineForTest();
    ItemEventJournal.instance.resetForTest();
  });

  test('items round-trip through the repository seam', () async {
    final repo = ItemRepository.instance;
    final task = Task(title: 'through the seam');
    await repo.saveItems([task]);

    final loaded = await repo.loadItems();
    expect(loaded.single.title, 'through the seam');
    expect(loaded.single.uid, task.uid);
  });

  test('deleted items and daily stats delegate to the same stores', () async {
    final repo = ItemRepository.instance;
    final gone = Task(title: 'gone', deletedAt: DateTime(2026, 7, 1));
    await repo.saveDeletedItems([gone]);
    expect((await repo.loadDeletedItems()).single.title, 'gone');
    expect(await repo.loadDailyStats(), isEmpty);
  });

  test('history flows from saves to historyOf', () async {
    final repo = ItemRepository.instance;
    final task = Task(title: 'v1');
    await repo.saveItems([task]);
    task.title = 'v2';
    await repo.saveItems([task]);

    final history = await repo.historyOf(task.uid);
    expect(history.single.type, ItemEvent.typeEdited);
    expect(history.single.patch.single.to, 'v2');
    expect(await repo.allHistory(), isNotEmpty);
  });
}
