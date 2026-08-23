import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/wishlist_shipped.dart';
import 'package:besttodo/ui/wishlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Config.swipeLeftDelete = true;
    // Opt out of the one-time Todo.md import so tests only see their own
    // items.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpWishlist(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    // Pre-saving and the page's initState load are real file I/O, which must
    // run on the real event loop (runAsync), not the fake-async test zone.
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: WishlistPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'WishlistPage never loaded the tasks');
  }

  /// The save started by a tap/swipe handler is awaited before setState in
  /// some paths; a fixed number of runAsync rounds lets the write finish.
  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<List<dynamic>> readJsonList(WidgetTester tester, String name) async {
    return await tester.runAsync(() async {
      final file = File('${tempDir.path}/$name');
      if (!await file.exists()) return <dynamic>[];
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    }) as List<dynamic>;
  }

  testWidgets('shows only wishlist tasks and no due dates', (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(
          title: 'Buy a telescope',
          description: 'For stargazing weekends',
          label: 'gift',
          isWish: true,
        ),
        Task(title: 'Feed the zebra', dueDate: DateTime.now()),
      ],
      marker: 'Buy a telescope',
    );

    expect(find.text('For stargazing weekends'), findsOneWidget);
    expect(find.text('gift'), findsOneWidget);
    // Non-wish tasks stay out of this pre-filtered view.
    expect(find.text('Feed the zebra'), findsNothing);
    // Wishlist tiles look like task tiles (checkbox included)...
    expect(find.byType(Checkbox), findsOneWidget);
    // ...but never surface anything date-related.
    expect(find.textContaining('Due'), findsNothing);
  });

  testWidgets('the swipe Copy shortcut puts the item on the clipboard',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpWishlist(
      tester,
      tasks: [
        Task(
          title: 'Buy a telescope',
          description: 'For stargazing weekends',
          label: 'gift',
          isWish: true,
        ),
      ],
      marker: 'Buy a telescope',
    );

    // Copy lives behind the swipe options overlay — no per-tile icon.
    await tester.drag(find.text('Buy a telescope'), const Offset(300, 0));
    await tester.pump();
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copied,
        ['Buy a telescope\nFor stargazing weekends\ngift']);
    expect(find.text('Copied "Buy a telescope"'), findsOneWidget);
  });

  testWidgets(
      'swipe right shows Share/Copy shortcuts; Copy copies the item',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', label: 'gift', isWish: true)],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(300, 0));
    await tester.pump();
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copied, ['Buy a telescope\ngift']);
    // The panel closes once an option is picked.
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets(
      'swipe right countdown moves the item back one release step',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Buy a telescope', label: 'release-next', isWish: true),
      ],
      marker: 'Buy a telescope',
    );
    expect(find.text('Next release (1)'), findsOneWidget);

    await tester.drag(find.text('Buy a telescope'), const Offset(300, 0));
    await tester.pump();
    // Letting the countdown run out applies the default: one step back.
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    expect(find.text('Soon (1)'), findsOneWidget);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], 'release-soon');
  });

  testWidgets(
      'swipe left starts selection mode; copy selected as prompt copies '
      'them and exits selection', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Buy a telescope', label: 'gift', isWish: true),
        Task(title: 'Learn Spanish', isWish: true),
      ],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(-300, 0));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Learn Spanish'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy selected as prompt'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(
        copied.single,
        'Build the following items from my BestToDo wishlist:\n\n'
        '- Buy a telescope\n  [gift]\n- Learn Spanish');
    // Selection mode is exited after copying.
    expect(find.text('2 selected'), findsNothing);
    expect(find.text('Wishlist'), findsOneWidget);
  });

  testWidgets('delete selected moves the selected items to the deleted list',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Buy a telescope', isWish: true),
        Task(title: 'Learn Spanish', isWish: true),
        Task(title: 'Plan world trip', dueDate: DateTime(2300, 1, 1)),
      ],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.text('Learn Spanish'));
    await tester.pump();

    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pump();

    // Removed from the list right away, with an undo window like the home
    // page; the move to the deleted list is persisted when it expires.
    expect(find.text('Buy a telescope'), findsNothing);
    expect(find.text('Learn Spanish'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    final tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.map((t) => t['title']), ['Plan world trip']);
    final deleted = await readJsonList(tester, 'deleted_tasks.json');
    expect(deleted.map((t) => t['title']),
        containsAll(['Buy a telescope', 'Learn Spanish']));
    expect(deleted.every((t) => t['deletedAt'] != null), isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('undo restores an item deleted from selection', (tester) async {
    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', isWish: true)],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(-300, 0));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pump();
    // Let the snackbar finish animating in so the Undo action is tappable.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('Buy a telescope'), findsOneWidget);
    final tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.single['title'], 'Buy a telescope');
    final deleted = await readJsonList(tester, 'deleted_tasks.json');
    expect(deleted, isEmpty);
    await tester.pump(Config.delayDuration + const Duration(seconds: 1));
  });

  testWidgets('add dialog puts labels and quick priority above description',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', isWish: true)],
      marker: 'Buy a telescope',
    );

    await tester.tap(find.byTooltip('Add wishlist item'));
    await tester.pumpAndSettle();

    final titleY = tester.getTopLeft(find.text('Title')).dy;
    final labelsY = tester.getTopLeft(find.text('Labels / tags')).dy;
    final quickY = tester.getTopLeft(find.text('Quick priority')).dy;
    final descriptionY = tester.getTopLeft(find.text('Description')).dy;
    expect(titleY, lessThan(labelsY));
    expect(labelsY, lessThan(quickY));
    expect(quickY, lessThan(descriptionY));
  });

  testWidgets('a URL in the description opens externally, not the edit dialog',
      (tester) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    await pumpWishlist(
      tester,
      tasks: [
        Task(
          title: 'Buy a telescope',
          description: 'compare models at https://example.com/scopes first',
          isWish: true,
        ),
      ],
      marker: 'Buy a telescope',
    );

    await tester
        .tapOnText(find.textRange.ofSubstring('https://example.com/scopes'));
    await tester.pump();

    // The link's recognizer wins the gesture arena over the tile's onTap.
    expect(launcher.launched, ['https://example.com/scopes']);
    expect(find.text('Edit wishlist item'), findsNothing);

    // A tap elsewhere on the tile still opens the edit dialog.
    await tester.tap(find.text('Buy a telescope'));
    await tester.pumpAndSettle();
    expect(find.text('Edit wishlist item'), findsOneWidget);
  });

  testWidgets('wishes are ordered by priority', (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'No priority wish', isWish: true),
        Task(title: 'Top wish', label: 'priority-high', isWish: true),
        Task(title: 'Medium wish', label: 'priority-medium', isWish: true),
      ],
      marker: 'Top wish',
    );

    final topY = tester.getTopLeft(find.text('Top wish')).dy;
    final mediumY = tester.getTopLeft(find.text('Medium wish')).dy;
    final noneY = tester.getTopLeft(find.text('No priority wish')).dy;
    expect(topY, lessThan(mediumY));
    expect(mediumY, lessThan(noneY));
  });

  testWidgets('sort menu can order wishes by newest first', (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(
          title: 'Older wish',
          createdAt: DateTime(2026, 8, 1),
          isWish: true,
        ),
        Task(
          title: 'Newer wish',
          createdAt: DateTime(2026, 8, 15),
          isWish: true,
        ),
      ],
      marker: 'Older wish',
    );

    var olderY = tester.getTopLeft(find.text('Older wish')).dy;
    var newerY = tester.getTopLeft(find.text('Newer wish')).dy;
    expect(olderY, lessThan(newerY));

    await tester.tap(find.byTooltip('Sort wishlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();

    olderY = tester.getTopLeft(find.text('Older wish')).dy;
    newerY = tester.getTopLeft(find.text('Newer wish')).dy;
    expect(newerY, lessThan(olderY));
  });

  group('release groups (pure)', () {
    test('tags decide next-release/soon/backlog membership', () {
      final backlog = Task(title: 'No tag', isWish: true);
      final next = Task(title: 'Tagged next', label: 'release-next', isWish: true);
      final soon = Task(title: 'Tagged soon', label: 'release-soon', isWish: true);
      expect(wishReleaseGroupOf(backlog, '1.0.0'), WishReleaseGroup.backlog);
      expect(wishReleaseGroupOf(next, '1.0.0'), WishReleaseGroup.nextRelease);
      expect(wishReleaseGroupOf(soon, '1.0.0'), WishReleaseGroup.soon);
    });

    test(
        'a backlog uid shipped in the running version is newly implemented, '
        'regardless of tags', () {
      final shipped = shippedWishes.first;
      final task = Task(
        uid: shipped.uid,
        title: 'Shipped backlog item',
        label: 'release-next',
        isWish: true,
      );
      expect(wishReleaseGroupOf(task, shipped.version),
          WishReleaseGroup.newlyImplemented);
      // Once the app moves past that release, the tag takes over again.
      expect(
          wishReleaseGroupOf(task, 'not-a-real-version'),
          WishReleaseGroup.nextRelease);
    });

    test('setWishReleaseGroup rewrites only the release tag', () {
      final task = Task(title: 'Wish', label: 'gift, release-soon', isWish: true);
      setWishReleaseGroup(task, WishReleaseGroup.nextRelease);
      expect(task.label, 'gift, release-next');

      setWishReleaseGroup(task, WishReleaseGroup.backlog);
      expect(task.label, 'gift');
    });

    test('proposeForNextPrompt lists titles and tags, empty backlog stays terse',
        () {
      final withItems = proposeForNextPrompt([
        Task(title: 'Learn to sail', label: 'gift', isWish: true),
        Task(title: 'Untagged idea', isWish: true),
      ]);
      expect(withItems, contains('release-next'));
      expect(withItems, contains('- Learn to sail [gift]'));
      expect(withItems, contains('- Untagged idea'));

      final empty = proposeForNextPrompt(const []);
      expect(empty, isNot(contains('Current backlog')));
    });
  });

  testWidgets('items are grouped into release sections with headers',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Next item', label: 'release-next', isWish: true),
        Task(title: 'Soon item', label: 'release-soon', isWish: true),
        Task(title: 'Backlog item', isWish: true),
      ],
      marker: 'Backlog item',
    );

    expect(find.text('Next release (1)'), findsOneWidget);
    expect(find.text('Soon (1)'), findsOneWidget);
    expect(find.text('Backlog (1)'), findsOneWidget);
    // The section order puts Next release above Soon above Backlog.
    final nextY = tester.getTopLeft(find.text('Next release (1)')).dy;
    final soonY = tester.getTopLeft(find.text('Soon (1)')).dy;
    final backlogY = tester.getTopLeft(find.text('Backlog (1)')).dy;
    expect(nextY, lessThan(soonY));
    expect(soonY, lessThan(backlogY));
    // Only the Next release section carries the propose button.
    expect(find.text('Propose for next'), findsOneWidget);
  });

  testWidgets('moving an item to a release group retags and resections it',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', isWish: true)],
      marker: 'Buy a telescope',
    );

    expect(find.text('Backlog (1)'), findsOneWidget);
    expect(find.text('Next release (1)'), findsNothing);

    await tester.tap(find.byTooltip('Move to release group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next release'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Next release (1)'), findsOneWidget);
    expect(find.text('Backlog (1)'), findsNothing);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], 'release-next');
  });

  testWidgets(
      'propose for next copies backlog/soon items, excluding done and '
      'shipped ones', (tester) async {
    Config.resetVersionForTest();
    PackageInfo.setMockInitialValues(
      appName: 'BestToDo',
      packageName: 'com.example.besttodo',
      version: shippedWishes.first.version,
      buildNumber: '1',
      buildSignature: '',
    );
    addTearDown(Config.resetVersionForTest);

    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final doneBacklogItem = Task(title: 'Done idea', isWish: true)
      ..toggleDone();
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Backlog idea', label: 'gift', isWish: true),
        Task(title: 'Soon idea', label: 'release-soon', isWish: true),
        doneBacklogItem,
        Task(
          uid: shippedWishes.first.uid,
          title: 'Shipped idea',
          isWish: true,
        ),
      ],
      marker: 'Backlog idea',
    );

    await tester.tap(find.text('Propose for next'));
    await tester.pump();

    expect(copied, hasLength(1));
    expect(copied.single, contains('- Backlog idea [gift]'));
    expect(copied.single, contains('- Soon idea [release-soon]'));
    expect(copied.single, isNot(contains('Done idea')));
    expect(copied.single, isNot(contains('Shipped idea')));
  });
}
