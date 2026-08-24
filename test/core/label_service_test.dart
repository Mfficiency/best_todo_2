import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/label.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/label_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  group('label_utils', () {
    test('splits on commas/whitespace, trims, dedupes case-insensitively',
        () {
      expect(splitLabelTokens('priority-high, urgent  Urgent,gift'),
          ['priority-high', 'urgent', 'gift']);
      expect(splitLabelTokens(''), isEmpty);
      expect(splitLabelTokens('  ,  '), isEmpty);
    });

    test('joins back in canonical comma-space form', () {
      expect(joinLabelTokens(['a', 'b']), 'a, b');
    });

    test('classifies tokens into kinds', () {
      expect(labelKindFor('priority-high'), Label.kindPriority);
      expect(labelKindFor('Priority-Low'), Label.kindPriority);
      expect(labelKindFor('old'), Label.kindSystem);
      expect(labelKindFor('Waiting_for_approval'), Label.kindSystem);
      expect(labelKindFor('waiting_FOR_approval'), Label.kindSystem);
      // The pre-0.1.260 spelling still classifies as a system token.
      expect(labelKindFor('waiting-for-approval'), Label.kindSystem);
      expect(labelKindFor('urgent'), Label.kindTag);
    });

    test('labelHasToken matches case-insensitively', () {
      expect(labelHasToken('work, Waiting_For_Approval', waitingApprovalToken),
          isTrue);
      expect(labelHasToken('work, urgent', waitingApprovalToken), isFalse);
      expect(labelHasToken('', waitingApprovalToken), isFalse);
    });

    test('the approval token is one whitespace-proof tag, not three', () {
      expect(splitLabelTokens(waitingApprovalToken), [waitingApprovalToken]);
      expect(splitLabelTokens('work, $waitingApprovalToken').length, 2);
      // What a spaced-out Todoist label would have done instead.
      expect(splitLabelTokens('Waiting for Approval').length, 3);
    });

    test('hasWaitingApprovalToken accepts current and legacy spellings', () {
      expect(hasWaitingApprovalToken('work, Waiting_for_approval'), isTrue);
      expect(hasWaitingApprovalToken('work, waiting-for-approval'), isTrue);
      expect(hasWaitingApprovalToken('work, urgent'), isFalse);
      expect(hasWaitingApprovalToken(''), isFalse);
    });

    test('removeWaitingApprovalToken strips every spelling, keeps the rest',
        () {
      expect(
          removeWaitingApprovalToken(
              'work, Waiting_For_Approval, urgent'),
          'work, urgent');
      expect(
          removeWaitingApprovalToken('work, waiting-for-approval, urgent'),
          'work, urgent');
      expect(removeWaitingApprovalToken('work'), 'work');
    });

    test('addLabelToken adds once and is idempotent', () {
      expect(addLabelToken('work', waitingApprovalToken),
          'work, Waiting_for_approval');
      expect(
          addLabelToken('work, Waiting_for_approval', waitingApprovalToken),
          'work, Waiting_for_approval');
      expect(addLabelToken('', waitingApprovalToken), 'Waiting_for_approval');
    });

    test('removeLabelToken drops only the matching token', () {
      expect(
          removeLabelToken('work, Waiting_For_Approval, urgent',
              waitingApprovalToken),
          'work, urgent');
      expect(removeLabelToken('work', waitingApprovalToken), 'work');
    });
  });

  group('LabelService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      LabelService.instance.resetForTest();
    });

    test('registers unknown tokens with derived kinds and persists them',
        () async {
      LabelService.instance
          .registerTokens(['urgent', 'priority-high', 'old']);
      await LabelService.instance.pendingWrites;

      final byName = {
        for (final l in LabelService.instance.list) l.name: l.kind
      };
      expect(byName, {
        'urgent': Label.kindTag,
        'priority-high': Label.kindPriority,
        'old': Label.kindSystem,
      });

      final file = File('${tempDir.path}/${LabelService.fileName}');
      expect(file.existsSync(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as List;
      expect(decoded, hasLength(3));
    });

    test('re-registering known tokens is a no-op (no duplicates, no write)',
        () async {
      LabelService.instance.registerTokens(['urgent']);
      await LabelService.instance.pendingWrites;
      final file = File('${tempDir.path}/${LabelService.fileName}');
      final before = await file.lastModified();

      LabelService.instance.registerTokens(['Urgent', 'URGENT']);
      await LabelService.instance.pendingWrites;
      expect(LabelService.instance.list, hasLength(1));
      expect(await file.lastModified(), before);
    });

    test('upsert keeps colour across a reload', () async {
      LabelService.instance.registerTokens(['gift']);
      await LabelService.instance.pendingWrites;
      final gift = LabelService.instance.byName('gift')!;
      gift.color = 0xFFE53935;
      await LabelService.instance.upsert(gift);

      LabelService.instance.resetForTest();
      await LabelService.instance.ensureLoaded();
      expect(LabelService.instance.byName('GIFT')?.color, 0xFFE53935);
    });

    test('task saves feed the registry (dual-write)', () async {
      StorageService.resetJournalBaselineForTest();
      ItemEventJournal.instance.resetForTest();
      await File(
              '${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
          .writeAsString('done');

      final service = StorageService();
      await service.saveTaskList([
        Task(title: 'wrap presents', label: 'gift, priority-medium'),
        Task(title: 'untagged'),
      ]);
      await LabelService.instance.pendingWrites;

      expect(LabelService.instance.byName('gift')?.kind, Label.kindTag);
      expect(LabelService.instance.byName('priority-medium')?.kind,
          Label.kindPriority);
      expect(LabelService.instance.list, hasLength(2));
    });
  });
}
