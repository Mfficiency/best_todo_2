import 'dart:io';

import 'package:besttodo/models/label.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/wishlist_migration.dart';
import 'package:besttodo/services/wishlist_shipped.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// A wishlist item as the pre-0.1.232 import created it: right title and
/// `old` label, but a random uid.
Task _legacyImported(String title, {String? description}) => Task(
      title: title,
      description: description ?? '',
      label: legacyTodoImportLabel,
      isWish: true,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  group('stable backlog ids', () {
    test('every entry has a unique, prefixed uid', () {
      final uids = legacyTodoWishlistItems.map((item) => item.uid).toList();
      expect(uids.toSet().length, legacyTodoWishlistItems.length);
      expect(uids.every((uid) => uid.startsWith(legacyTodoUidPrefix)), isTrue);
      expect(uids.every((uid) => uid.length > legacyTodoUidPrefix.length),
          isTrue);
    });

    test('every shipped wish points at a backlog entry or a real uuid', () {
      // A registry entry addresses either a shared backlog id or the uuid of
      // a hand-added wish on one install; a typo in either is silent (the
      // item simply never gets ticked off), so pin the shapes down here.
      final uuid = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
      for (final shipped in shippedWishes) {
        final known = legacyTodoItemsByUid.containsKey(shipped.uid);
        expect(known || uuid.hasMatch(shipped.uid), isTrue,
            reason: '${shipped.uid} is neither a backlog id nor a uuid');
        if (!known) {
          expect(shipped.uid.startsWith(legacyTodoUidPrefix), isFalse,
              reason: '${shipped.uid} looks like a backlog id but is not one');
        }
      }
      // No uid listed twice, which would make the "which release" note
      // ambiguous.
      expect(shippedWishes.map((w) => w.uid).toSet().length,
          shippedWishes.length);
    });

    test('the autocompleted tag registers as a system label', () {
      expect(labelKindFor(autoCompletedLabel), Label.kindSystem);
    });
  });

  group('backfillLegacyWishUids', () {
    test('re-identifies items the old import created', () {
      final item = _legacyImported('calendar view');
      final randomUid = item.uid;

      expect(backfillLegacyWishUids(<Task>[item]), isTrue);
      expect(item.uid, 'wish-calendar-view');
      expect(item.uid, isNot(randomUid));
    });

    test('leaves a user\'s own same-titled item alone', () {
      // Same normalized title, but no `old` token: the user wrote this one.
      final mine = Task(title: 'Calendar  View', label: 'ui', isWish: true);
      final mineUid = mine.uid;

      expect(backfillLegacyWishUids(<Task>[mine]), isFalse);
      expect(mine.uid, mineUid);
    });

    test('never hands out a uid another item already holds', () {
      final alreadyStable = _legacyImported('calendar view')
        ..uid = 'wish-calendar-view';
      final duplicate = _legacyImported('calendar  view');
      final duplicateUid = duplicate.uid;

      backfillLegacyWishUids(<Task>[alreadyStable, duplicate]);

      expect(alreadyStable.uid, 'wish-calendar-view');
      expect(duplicate.uid, duplicateUid);
    });

    test('is a no-op the second time', () {
      final items = <Task>[_legacyImported('web version')];
      expect(backfillLegacyWishUids(items), isTrue);
      expect(backfillLegacyWishUids(items), isFalse);
    });
  });

  group('applyShippedWishes', () {
    Task shippedItem() => Task(
          uid: 'wish-calendar-view',
          title: 'calendar view',
          label: legacyTodoImportLabel,
          isWish: true,
        );

    test('ticks the item off, tags it and records the release', () {
      final item = shippedItem();
      final at = DateTime(2026, 8, 18, 9);

      expect(applyShippedWishes(<Task>[item], now: at), isTrue);
      expect(item.isDone, isTrue);
      expect(item.completedAt, at);
      expect(splitLabelTokens(item.label),
          <String>[legacyTodoImportLabel, autoCompletedLabel]);
      expect(item.note, contains('v0.1.232'));
    });

    test('runs once: re-running changes nothing, so an undo sticks', () {
      final item = shippedItem();
      applyShippedWishes(<Task>[item]);

      // The user re-opens the wish by hand; the tag documents what happened.
      item.isDone = false;
      final note = item.note;

      expect(applyShippedWishes(<Task>[item]), isFalse);
      expect(item.isDone, isFalse);
      expect(item.note, note);
      expect(
        splitLabelTokens(item.label)
            .where((t) => t == autoCompletedLabel)
            .length,
        1,
      );
    });

    test('keeps a completion the user got to first', () {
      final theirs = DateTime(2026, 1, 2, 3, 4);
      final item = shippedItem()
        ..isDone = true
        ..completedAt = theirs;

      expect(applyShippedWishes(<Task>[item], now: DateTime(2026, 8, 18)),
          isTrue);
      expect(item.completedAt, theirs);
      expect(splitLabelTokens(item.label), contains(autoCompletedLabel));
    });

    test('ignores unshipped wishes and non-wish tasks', () {
      final unshipped = Task(
          uid: 'wish-ios-mode', title: 'ios mode', isWish: true);
      final notAWish =
          Task(uid: 'wish-calendar-view', title: 'calendar view');

      expect(applyShippedWishes(<Task>[unshipped, notAWish]), isFalse);
      expect(unshipped.isDone, isFalse);
      expect(notAWish.isDone, isFalse);
    });
  });

  group('storage integration', () {
    test('a fresh install imports the backlog with its stable uids', () async {
      final items = await StorageService().loadWishlist();

      final calendar = items.firstWhere((t) => t.title == 'calendar view');
      expect(calendar.uid, 'wish-calendar-view');
      expect(items.map((t) => t.uid).toSet().length, items.length);
    });

    test('loadTaskList auto-completes wishes whose feature shipped', () async {
      final service = StorageService();
      final tasks = await service.loadTaskList();

      final calendar = tasks.firstWhere((t) => t.uid == 'wish-calendar-view');
      expect(calendar.isDone, isTrue);
      expect(splitLabelTokens(calendar.label), contains(autoCompletedLabel));

      // Everything else in the backlog is left open.
      final iosMode = tasks.firstWhere((t) => t.uid == 'wish-ios-mode');
      expect(iosMode.isDone, isFalse);

      // Persisted, so the next launch has nothing left to do.
      final reloaded = await service.loadTaskList();
      final again = reloaded.firstWhere((t) => t.uid == 'wish-calendar-view');
      expect(again.isDone, isTrue);
      expect(
        splitLabelTokens(again.label)
            .where((t) => t == autoCompletedLabel)
            .length,
        1,
      );
    });

    test('an install carrying pre-0.1.232 random uids is upgraded in place',
        () async {
      final service = StorageService();
      // Opt out of the import: this install already ran it, back when it
      // still minted random uids.
      await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
          .writeAsString('done');
      final imported = _legacyImported('calendar view');
      final randomUid = imported.uid;
      await service.saveTaskList(<Task>[
        Task(title: 'a real task'),
        imported,
      ]);

      final tasks = await service.loadTaskList();

      final calendar =
          tasks.firstWhere((t) => t.title == 'calendar view');
      expect(calendar.uid, 'wish-calendar-view');
      expect(calendar.uid, isNot(randomUid));
      expect(calendar.isDone, isTrue);
      expect(splitLabelTokens(calendar.label), contains(autoCompletedLabel));
      expect(tasks.any((t) => t.title == 'a real task'), isTrue);
    });
  });
}
