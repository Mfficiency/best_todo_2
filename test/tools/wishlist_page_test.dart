import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/wishlist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('priority swipe shows shortcuts; picking one sets the label',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', label: 'gift', isWish: true)],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(300, 0));
    await tester.pump();
    expect(find.text('high'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    expect(find.text('low'), findsOneWidget);

    await tester.tap(find.text('medium'));
    await tester.pump();
    await settleWrites(tester);

    expect(find.text('priority-medium'), findsOneWidget);
    expect(find.text('gift'), findsOneWidget);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], 'priority-medium, gift');
  });

  testWidgets('priority swipe countdown raises the priority one step',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Buy a telescope', label: 'priority-low', isWish: true),
      ],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(300, 0));
    await tester.pump();
    // Letting the countdown run out applies the default: one step up.
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    expect(find.text('priority-medium'), findsOneWidget);
    final saved = await readJsonList(tester, 'tasks.json');
    expect(saved.single['label'], 'priority-medium');
  });

  testWidgets('delete swipe moves the item to the deleted list',
      (tester) async {
    await pumpWishlist(
      tester,
      tasks: [
        Task(title: 'Buy a telescope', isWish: true),
        Task(title: 'Plan world trip', dueDate: DateTime(2300, 1, 1)),
      ],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(-300, 0));
    await tester.pump();

    // Removed from the list right away, with an undo window like the home
    // page; the move to the deleted list is persisted when it expires.
    expect(find.text('Buy a telescope'), findsNothing);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    final tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks.map((t) => t['title']), ['Plan world trip']);
    final deleted = await readJsonList(tester, 'deleted_tasks.json');
    expect(deleted.single['title'], 'Buy a telescope');
    expect(deleted.single['deletedAt'], isNotNull);
    expect(deleted.single['isWish'], isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('undo restores a swiped-away item', (tester) async {
    await pumpWishlist(
      tester,
      tasks: [Task(title: 'Buy a telescope', isWish: true)],
      marker: 'Buy a telescope',
    );

    await tester.drag(find.text('Buy a telescope'), const Offset(-300, 0));
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
}
