import 'package:besttodo/models/sms_recipient.dart';
import 'package:besttodo/models/sms_report_config.dart';
import 'package:besttodo/services/sms_report_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SmsRecipient recipient(String nickname, {bool enabled = true}) =>
      SmsRecipient(
        nickname: nickname,
        phoneNumber: '+123$nickname',
        enabled: enabled,
      );

  test('no active recipients means no slots to arm', () {
    final config = SmsReportConfig(recipients: [recipient('Ann', enabled: false)]);
    expect(SmsReportScheduler.activeSlotMinutes(config), isEmpty);
  });

  test('recipients without their own time share the global slot', () {
    final config = SmsReportConfig(
      hour: 22,
      minute: 0,
      recipients: [recipient('Ann'), recipient('Bob')],
    );
    expect(SmsReportScheduler.activeSlotMinutes(config), {22 * 60});
  });

  test('a recipient with a custom time gets its own slot', () {
    final config = SmsReportConfig(
      hour: 22,
      minute: 0,
      recipients: [
        recipient('Ann'),
        recipient('Bob')
          ..hour = 8
          ..minute = 30,
      ],
    );
    expect(
      SmsReportScheduler.activeSlotMinutes(config),
      {22 * 60, 8 * 60 + 30},
    );
  });

  test('recipients sharing the same custom time dedupe to one slot', () {
    final config = SmsReportConfig(
      recipients: [
        recipient('Ann')
          ..hour = 8
          ..minute = 30,
        recipient('Bob')
          ..hour = 8
          ..minute = 30,
      ],
    );
    expect(SmsReportScheduler.activeSlotMinutes(config), {8 * 60 + 30});
  });

  test('a disabled recipient with a custom time does not arm a slot', () {
    final config = SmsReportConfig(
      hour: 22,
      minute: 0,
      recipients: [
        recipient('Ann', enabled: false)
          ..hour = 8
          ..minute = 30,
      ],
    );
    expect(SmsReportScheduler.activeSlotMinutes(config), isEmpty);
  });
}
