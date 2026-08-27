import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/food_diary_page.dart';
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
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  tearDown(() {
    Config.viewFilterRules = {};
  });

  testWidgets(
      'a configured Food Diary rule hides entries that do not carry the tag',
      (tester) async {
    Config.viewFilterRules[ViewFilterRules.foodDiary] =
        ViewFilterRules(includeTags: ['sugar']);

    final tasks = [
      Task(
        title: 'Keep this',
        isEatingHabit: true,
        label: 'sugar',
        dueDate: DateTime.now(),
        hasExplicitTime: true,
      ),
      Task(
        title: 'Hide this',
        isEatingHabit: true,
        label: 'protein',
        dueDate: DateTime.now(),
        hasExplicitTime: true,
      ),
    ];
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: FoodDiaryPage()));
    final markerFinder = find.text('Keep this');
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();

    expect(find.text('Keep this'), findsOneWidget);
    expect(find.text('Hide this'), findsNothing);
  });
}
