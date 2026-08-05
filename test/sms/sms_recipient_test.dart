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
}
