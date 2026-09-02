import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/approval_quick_tag.dart';
import 'package:besttodo/services/approval_quick_tag_service.dart';
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
    ApprovalQuickTagService.instance.resetForTest();
  });

  File tagsFile() => File('${tempDir.path}/approval_quick_tags.json');

  test('first load seeds the default Wishlist/Research pair and persists it',
      () async {
    await ApprovalQuickTagService.instance.load();

    expect(ApprovalQuickTagService.instance.list.map((t) => t.label),
        ['Wishlist', 'Research']);
    expect(
      ApprovalQuickTagService.instance.list.map((t) => t.target),
      [ApprovalQuickTag.wishlistTarget, ApprovalQuickTag.researchTarget],
    );
    expect(await tagsFile().exists(), isTrue);
    final data = jsonDecode(await tagsFile().readAsString()) as List;
    expect(data.length, 2);
  });

  test('save persists a user-edited list and survives a reload', () async {
    await ApprovalQuickTagService.instance.load();

    await ApprovalQuickTagService.instance.save([
      ApprovalQuickTag(
          label: 'Rabbit hole', target: ApprovalQuickTag.researchTarget),
    ]);
    expect(ApprovalQuickTagService.instance.list.length, 1);
    expect(ApprovalQuickTagService.instance.list.first.label, 'Rabbit hole');

    ApprovalQuickTagService.instance.resetForTest();
    await ApprovalQuickTagService.instance.load();
    expect(ApprovalQuickTagService.instance.list.length, 1);
    expect(ApprovalQuickTagService.instance.list.first.label, 'Rabbit hole');
    expect(ApprovalQuickTagService.instance.list.first.target,
        ApprovalQuickTag.researchTarget);
  });

  test('save drops an entry with an empty label or an unknown target',
      () async {
    await ApprovalQuickTagService.instance.load();

    await ApprovalQuickTagService.instance.save([
      ApprovalQuickTag(label: '', target: ApprovalQuickTag.wishlistTarget),
      ApprovalQuickTag(label: 'Ghost', target: 'not-a-real-tool'),
      ApprovalQuickTag(label: 'Valid', target: ApprovalQuickTag.researchTarget),
    ]);

    expect(ApprovalQuickTagService.instance.list.length, 1);
    expect(ApprovalQuickTagService.instance.list.first.label, 'Valid');
  });

  test('a corrupt tags file keeps the in-memory default pair', () async {
    await tagsFile().create(recursive: true);
    await tagsFile().writeAsString('not json');

    await ApprovalQuickTagService.instance.load();
    expect(ApprovalQuickTagService.instance.list, isNotEmpty);
  });

  test('load only reads the file once per session', () async {
    await ApprovalQuickTagService.instance.load();
    await ApprovalQuickTagService.instance.save([
      ApprovalQuickTag(label: 'Kept', target: ApprovalQuickTag.wishlistTarget),
    ]);

    await tagsFile().writeAsString('garbage');
    await ApprovalQuickTagService.instance.load();
    expect(ApprovalQuickTagService.instance.list.length, 1);
    expect(ApprovalQuickTagService.instance.list.first.label, 'Kept');
  });
}
