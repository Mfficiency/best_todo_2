import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/auto_tag_group.dart';
import 'package:besttodo/services/auto_tag_service.dart';
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
    AutoTagService.instance.resetForTest();
    Config.autoTagEnabled = true;
  });

  File rulesFile() => File('${tempDir.path}/auto_tag_rules.json');

  test('first load seeds the default groups and persists them', () async {
    await AutoTagService.instance.load();

    expect(AutoTagService.instance.list, isNotEmpty);
    expect(AutoTagService.instance.list.every((g) => g.keywords.isNotEmpty),
        isTrue);
    expect(await rulesFile().exists(), isTrue);
    final data = jsonDecode(await rulesFile().readAsString()) as List;
    expect(data.length, AutoTagService.instance.list.length);
  });

  test('tagsFor matches whole words only, case-insensitively', () async {
    await AutoTagService.instance.load();

    expect(AutoTagService.instance.tagsFor('Fix my bike'), contains('bike'));
    expect(AutoTagService.instance.tagsFor('BIKE tune-up'), contains('bike'));
    // "workshop" contains "work" but not as a whole word, so it must not match.
    expect(AutoTagService.instance.tagsFor('Sign up for the workshop'),
        isNot(contains('work')));
    expect(
        AutoTagService.instance.tagsFor('Prep for the work meeting tomorrow'),
        contains('work'));
  });

  test('a tag fires on any word in its group, not just one', () async {
    await AutoTagService.instance.load();

    // "gym", "workout" and "cardio" are different words in the same
    // "fitness" group.
    expect(AutoTagService.instance.tagsFor('Hit the gym'), contains('fitness'));
    expect(
        AutoTagService.instance.tagsFor('Evening workout'), contains('fitness'));
    expect(
        AutoTagService.instance.tagsFor('Cardio day'), contains('fitness'));
  });

  test('tagsFor only adds a tag once even if several of its words match',
      () async {
    await AutoTagService.instance.load();

    // Both "work" and "meeting" belong to the "work" group.
    final tags = AutoTagService.instance.tagsFor('Work meeting at 3pm');
    expect(tags.where((t) => t == 'work').length, 1);
  });

  test('tagsFor returns nothing for blank text', () async {
    await AutoTagService.instance.load();
    expect(AutoTagService.instance.tagsFor('   '), isEmpty);
  });

  test('withAutoTags appends matched tags without duplicating existing ones',
      () async {
    await AutoTagService.instance.load();

    expect(AutoTagService.instance.withAutoTags('Fix my bike', ''), 'bike');
    // Already labeled "bike" (any case) - not duplicated.
    expect(AutoTagService.instance.withAutoTags('Fix my bike', 'Bike, urgent'),
        'Bike, urgent');
    // No match leaves the label untouched.
    expect(AutoTagService.instance.withAutoTags('Feed the fish', 'errand'),
        'errand');
  });

  test('withAutoTags is a no-op when auto-tagging is disabled', () async {
    await AutoTagService.instance.load();
    Config.autoTagEnabled = false;

    expect(AutoTagService.instance.withAutoTags('Fix my bike', ''), '');
  });

  test('save persists a user-edited dictionary and survives a reload',
      () async {
    await AutoTagService.instance.load();

    await AutoTagService.instance.save(
        [AutoTagGroup(tag: 'kitchen', keywords: ['lemon', 'lime'])]);
    expect(AutoTagService.instance.tagsFor('Buy lemon'), contains('kitchen'));
    expect(AutoTagService.instance.tagsFor('Buy lime'), contains('kitchen'));

    AutoTagService.instance.resetForTest();
    await AutoTagService.instance.load();
    expect(AutoTagService.instance.list.length, 1);
    expect(AutoTagService.instance.list.first.tag, 'kitchen');
    expect(AutoTagService.instance.list.first.keywords,
        containsAll(['lemon', 'lime']));
  });

  test('save merges groups that share a tag and dedupes their keywords',
      () async {
    await AutoTagService.instance.load();

    await AutoTagService.instance.save([
      AutoTagGroup(tag: 'kitchen', keywords: ['lemon']),
      AutoTagGroup(tag: 'Kitchen', keywords: ['lemon', 'lime']),
    ]);

    expect(AutoTagService.instance.list.length, 1);
    expect(AutoTagService.instance.list.first.keywords, ['lemon', 'lime']);
  });

  test('save drops groups left with an empty tag or no keywords', () async {
    await AutoTagService.instance.load();

    await AutoTagService.instance.save([
      AutoTagGroup(tag: '', keywords: ['lemon']),
      AutoTagGroup(tag: 'kitchen', keywords: []),
      AutoTagGroup(tag: 'valid', keywords: ['lemon']),
    ]);

    expect(AutoTagService.instance.list.length, 1);
    expect(AutoTagService.instance.list.first.tag, 'valid');
  });

  test('a legacy one-keyword-per-tag file (pre-groups) still loads',
      () async {
    await rulesFile().create(recursive: true);
    await rulesFile().writeAsString(jsonEncode([
      {'keyword': 'lemon', 'tag': 'kitchen'},
      {'keyword': 'lime', 'tag': 'kitchen'},
    ]));

    await AutoTagService.instance.load();
    expect(AutoTagService.instance.list.length, 1);
    expect(AutoTagService.instance.list.first.tag, 'kitchen');
    expect(AutoTagService.instance.list.first.keywords,
        containsAll(['lemon', 'lime']));
  });

  test('a corrupt rules file keeps the in-memory default groups', () async {
    await rulesFile().create(recursive: true);
    await rulesFile().writeAsString('not json');

    await AutoTagService.instance.load();
    expect(AutoTagService.instance.list, isNotEmpty);
  });

  test('load only reads the file once per session', () async {
    await AutoTagService.instance.load();
    await AutoTagService.instance
        .save([AutoTagGroup(tag: 'kitchen', keywords: ['lemon'])]);

    await rulesFile().writeAsString('garbage');
    await AutoTagService.instance.load();
    expect(AutoTagService.instance.list.length, 1);
    expect(AutoTagService.instance.list.first.tag, 'kitchen');
  });
}
