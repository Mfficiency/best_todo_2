import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/attachment.dart';

void main() {
  test('attachments generate unique ids and default type/text', () {
    final a = Attachment(type: Attachment.typeText);
    final b = Attachment(type: Attachment.typeText);
    expect(a.uid, isNotEmpty);
    expect(a.uid, isNot(b.uid));
    expect(a.text, isEmpty);
    expect(a.fileName, isEmpty);
    expect(a.relativePath, isNull);
  });

  test('toJson omits empty text/fileName/relativePath', () {
    final attachment = Attachment(type: Attachment.typeText, text: '');
    final json = attachment.toJson();
    expect(json.containsKey('text'), isFalse);
    expect(json.containsKey('fileName'), isFalse);
    expect(json.containsKey('relativePath'), isFalse);
    expect(json['type'], Attachment.typeText);
    expect(json['uid'], attachment.uid);
  });

  test('round-trips a text attachment', () {
    final attachment = Attachment(type: Attachment.typeText, text: 'hello');
    final decoded = Attachment.fromJson(attachment.toJson());
    expect(decoded.uid, attachment.uid);
    expect(decoded.type, Attachment.typeText);
    expect(decoded.text, 'hello');
    expect(decoded.createdAt, attachment.createdAt);
  });

  test('round-trips a file-backed attachment', () {
    final attachment = Attachment(
      type: Attachment.typeImage,
      fileName: 'cat.jpg',
      relativePath: 'attachments/task1/uid1.jpg',
    );
    final decoded = Attachment.fromJson(attachment.toJson());
    expect(decoded.type, Attachment.typeImage);
    expect(decoded.fileName, 'cat.jpg');
    expect(decoded.relativePath, 'attachments/task1/uid1.jpg');
  });

  test('fromJson tolerates a missing/legacy payload', () {
    final decoded = Attachment.fromJson(<String, dynamic>{});
    expect(decoded.type, Attachment.typeText);
    expect(decoded.text, isEmpty);
    expect(decoded.fileName, isEmpty);
    expect(decoded.relativePath, isNull);
    expect(decoded.uid, isNotEmpty);
  });
}
