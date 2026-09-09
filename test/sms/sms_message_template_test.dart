import 'package:besttodo/models/sms_message_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template JSON round-trip preserves id, name and body', () {
    final t = SmsMessageTemplate(
      id: 'tpl_1',
      name: 'Cheerful',
      body: 'Go {nickname}, you did {completed} today!',
    );
    final restored = SmsMessageTemplate.fromJson(t.toJson());
    expect(restored.id, 'tpl_1');
    expect(restored.name, 'Cheerful');
    expect(restored.body, 'Go {nickname}, you did {completed} today!');
  });

  test('missing keys fall back to empty strings', () {
    final t = SmsMessageTemplate.fromJson(const {});
    expect(t.id, '');
    expect(t.name, '');
    expect(t.body, '');
  });
}
