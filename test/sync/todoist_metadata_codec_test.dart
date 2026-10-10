import 'package:besttodo/services/todoist_metadata_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodoistMetadataCodec', () {
    test('round-trips a description with metadata', () {
      final built = TodoistMetadataCodec.build(
        visible: 'Buy groceries',
        meta: const {
          'uid': 'abc-123',
          'note': 'get oat milk',
          'label': 'errands',
          'kanbanStatus': 'todo',
        },
      );

      expect(built, contains('Buy groceries'));
      expect(built, contains('sync-data:'));

      final parsed = TodoistMetadataCodec.parse(built);
      expect(parsed.visible, 'Buy groceries');
      expect(parsed.meta, isNotNull);
      expect(parsed.meta!['uid'], 'abc-123');
      expect(parsed.meta!['note'], 'get oat milk');
      expect(parsed.meta!['label'], 'errands');
    });

    test('an empty visible description still keeps the trailer', () {
      final built =
          TodoistMetadataCodec.build(visible: '', meta: const {'uid': 'x'});
      final parsed = TodoistMetadataCodec.parse(built);
      expect(parsed.visible, '');
      expect(parsed.meta!['uid'], 'x');
    });

    test('a description with no trailer parses as plain visible text', () {
      final parsed =
          TodoistMetadataCodec.parse('Just a note, never synced before');
      expect(parsed.visible, 'Just a note, never synced before');
      expect(parsed.meta, isNull);
    });

    test('trailing text typed after the trailer does not break parsing', () {
      final built = TodoistMetadataCodec.build(
        visible: 'Task text',
        meta: const {'uid': 'x'},
      );
      final mangled = '$built\nsomeone typed garbage here';
      final parsed = TodoistMetadataCodec.parse(mangled);
      expect(parsed.visible, 'Task text');
      expect(parsed.meta!['uid'], 'x');
    });

    test('a hand-broken sync-data JSON line is ignored, not thrown', () {
      final parsed = TodoistMetadataCodec.parse(
        '\n\n⸻ BestToDo sync — generated, do not edit below this line ⸻\n'
        'sync-data: {uid: x}',
      );
      expect(parsed.visible, '');
      expect(parsed.meta, isNull);
    });

    test('includes human-readable project/label/note summary lines', () {
      final built = TodoistMetadataCodec.build(
        visible: '',
        meta: const {
          'uid': 'x',
          'projectName': 'Launch',
          'kanbanStageLabel': 'Ongoing',
          'label': 'work',
          'note': 'ping Sam',
        },
      );
      expect(built, contains('Project: Launch · Ongoing'));
      expect(built, contains('Label: work'));
      expect(built, contains('Note: ping Sam'));
    });
  });
}
