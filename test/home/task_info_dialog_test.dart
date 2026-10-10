import 'package:besttodo/models/item_event.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/task_change_source.dart';
import 'package:besttodo/ui/task_detail_page.dart';
import 'package:besttodo/ui/task_info_dialog.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:flutter_test/flutter_test.dart';

ItemEvent _created(String uid, String source, {bool seeded = false}) =>
    ItemEvent(
      itemId: uid,
      seq: 1,
      at: DateTime(2026, 9, 1),
      type: ItemEvent.typeCreated,
      source: source,
      seeded: seeded,
    );

void main() {
  group('resolveTaskOrigin', () {
    test('an explicit origin stamp wins and is not marked inferred', () {
      final task = Task(title: 't', origin: TaskChangeSource.share);
      final origin =
          resolveTaskOrigin(task, [_created(task.uid, TaskChangeSource.user)]);
      expect(origin.source, TaskChangeSource.share);
      expect(origin.inferred, isFalse);
      expect(describeTaskOrigin(origin),
          'Shared into the app (Android share sheet)');
    });

    test('approval traces on an unstamped task mean Todoist', () {
      for (final task in [
        Task(title: 'a', pendingSourceTitle: 'Chat'),
        Task(title: 'b', approvedAt: DateTime(2026, 9, 1)),
        Task(title: 'c', label: waitingApprovalToken),
      ]) {
        final origin = resolveTaskOrigin(task, const []);
        expect(origin.source, TaskChangeSource.sync, reason: task.title);
        expect(describeTaskOrigin(origin),
            'Automatically via Todoist (approval path) (inferred)');
      }
    });

    test('falls back to the journal\'s live created event, not a seeded one',
        () {
      final task = Task(title: 't');
      expect(
        resolveTaskOrigin(task, [_created(task.uid, TaskChangeSource.user)])
            .source,
        TaskChangeSource.user,
      );
      final unknown = resolveTaskOrigin(
          task, [_created(task.uid, TaskChangeSource.system, seeded: true)]);
      expect(unknown.source, isNull);
      expect(describeTaskOrigin(unknown),
          'Unknown — created before origin tracking');
    });

    test('an unstamped recurring occurrence is app automation', () {
      final task = Task(title: 't', recurrenceParentUid: 'master');
      expect(resolveTaskOrigin(task, const []).source,
          TaskChangeSource.automation);
    });
  });

  test('a label change that drops the approval tag reads as Approved', () {
    final event = ItemEvent(
      itemId: 'x',
      seq: 2,
      at: DateTime(2026, 9, 2),
      type: ItemEvent.typeLabeled,
      patch: [FieldChange('label', 'work, $waitingApprovalToken', 'work')],
    );
    expect(describeItemEvent(event), 'Approved');
  });
}
