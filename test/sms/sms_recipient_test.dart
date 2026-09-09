import 'package:besttodo/models/sms_message_template.dart';
import 'package:besttodo/models/sms_recipient.dart';
import 'package:besttodo/models/sms_report_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SmsRecipient recipient(String nickname, {bool enabled = true}) =>
      SmsRecipient(
        nickname: nickname,
        phoneNumber: '+123$nickname',
        enabled: enabled,
      );

  test('recipients are enabled by default and round-trip the flag', () {
    final fresh = SmsRecipient(nickname: 'Ann', phoneNumber: '+1');
    expect(fresh.enabled, isTrue);

    final paused = SmsRecipient(
      nickname: 'Bob',
      phoneNumber: '+2',
      enabled: false,
    );
    final restored = SmsRecipient.fromJson(paused.toJson());
    expect(restored.enabled, isFalse);
    expect(restored.nickname, 'Bob');
    expect(restored.phoneNumber, '+2');
  });

  test('recipients saved before the pause switch stay enabled', () {
    // Legacy payload: no "enabled" key at all.
    final legacy = SmsRecipient.fromJson({
      'nickname': 'Cara',
      'phoneNumber': '+3',
    });
    expect(legacy.enabled, isTrue);
  });

  test('activeRecipients skips disabled ones but keeps them in the list', () {
    final config = SmsReportConfig(recipients: [
      recipient('Ann'),
      recipient('Bob', enabled: false),
      recipient('Cara'),
    ]);

    expect(config.recipients.length, 3);
    expect(
      config.activeRecipients.map((r) => r.nickname).toList(),
      ['Ann', 'Cara'],
    );

    config.recipients[1].enabled = true;
    expect(config.activeRecipients.length, 3);
  });

  test('all-disabled leaves nothing to send to', () {
    final config = SmsReportConfig(
      recipients: [recipient('Ann', enabled: false)],
    );
    expect(config.recipients, isNotEmpty);
    expect(config.activeRecipients, isEmpty);
  });

  test('config JSON round-trip preserves per-recipient enabled state', () {
    final config = SmsReportConfig(
      enabled: true,
      recipients: [recipient('Ann'), recipient('Bob', enabled: false)],
    );
    final restored = config.copy();
    expect(restored.recipients.map((r) => r.enabled).toList(), [true, false]);
    expect(restored.activeRecipients.single.nickname, 'Ann');
  });

  test('recipients saved before per-recipient template/timing stay on defaults',
      () {
    // Legacy payload: no templateId/hour/minute keys at all.
    final legacy = SmsRecipient.fromJson({
      'nickname': 'Cara',
      'phoneNumber': '+3',
    });
    expect(legacy.templateId, isNull);
    expect(legacy.hour, isNull);
    expect(legacy.minute, isNull);
  });

  test('recipient templateId/hour/minute round-trip through JSON', () {
    final r = SmsRecipient(
      nickname: 'Ann',
      phoneNumber: '+1',
      templateId: 'tpl_1',
      hour: 8,
      minute: 30,
    );
    final restored = SmsRecipient.fromJson(r.toJson());
    expect(restored.templateId, 'tpl_1');
    expect(restored.hour, 8);
    expect(restored.minute, 30);
  });

  test('config.templateBodyFor falls back to the default template', () {
    final config = SmsReportConfig(
      template: 'DEFAULT BODY',
      templates: [SmsMessageTemplate(id: 'tpl_1', name: 'Cheerful', body: 'CHEERFUL BODY')],
    );
    final noOverride = recipient('Ann');
    expect(config.templateBodyFor(noOverride), 'DEFAULT BODY');

    final withOverride = recipient('Bob')..templateId = 'tpl_1';
    expect(config.templateBodyFor(withOverride), 'CHEERFUL BODY');

    // A stale reference (template since deleted) also falls back.
    final stale = recipient('Cara')..templateId = 'gone';
    expect(config.templateBodyFor(stale), 'DEFAULT BODY');
  });

  test('config.timeFor falls back to the global send time', () {
    final config = SmsReportConfig(hour: 22, minute: 0);
    final noOverride = recipient('Ann');
    expect(config.timeFor(noOverride), (hour: 22, minute: 0));

    final withOverride = recipient('Bob')
      ..hour = 8
      ..minute = 15;
    expect(config.timeFor(withOverride), (hour: 8, minute: 15));
  });

  test('config JSON round-trip preserves named templates', () {
    final config = SmsReportConfig(
      templates: [
        SmsMessageTemplate(id: 'tpl_1', name: 'Cheerful', body: 'A'),
        SmsMessageTemplate(id: 'tpl_2', name: 'Stern', body: 'B'),
      ],
    );
    final restored = config.copy();
    expect(restored.templates.map((t) => t.name).toList(),
        ['Cheerful', 'Stern']);
    expect(restored.templates.map((t) => t.body).toList(), ['A', 'B']);
  });
}
