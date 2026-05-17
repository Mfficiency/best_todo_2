import 'sms_recipient.dart';

/// Default template tokens:
///   {hello}        -> "Hello {nickname}" or empty if no nickname
///   {nickname}     -> recipient nickname
///   {completed}    -> number of tasks completed today
///   {uncompleted}  -> number of remaining (uncompleted) tasks for today
///   {date}         -> today's date YYYY-MM-DD
///   {list}         -> bulleted list of uncompleted task titles
const String kDefaultSmsTemplate =
    '{hello}\n'
    'Today you completed {completed} tasks and have {uncompleted} left.\n'
    'Remaining:\n'
    '{list}';

class SmsReportConfig {
  bool enabled;
  int hour;
  int minute;
  String template;
  List<SmsRecipient> recipients;

  /// Android SIM subscription id for sending. -1 = system default.
  /// On dual-SIM devices try 0, 1, or actual subscription ids from
  /// Android Settings → SIMs if the default fails silently.
  int subscriptionId;

  SmsReportConfig({
    this.enabled = false,
    this.hour = 22,
    this.minute = 0,
    this.template = kDefaultSmsTemplate,
    List<SmsRecipient>? recipients,
    this.subscriptionId = -1,
  }) : recipients = recipients ?? <SmsRecipient>[];

  factory SmsReportConfig.fromJson(Map<String, dynamic> json) {
    final list = json['recipients'];
    return SmsReportConfig(
      enabled: json['enabled'] as bool? ?? false,
      hour: (json['hour'] as num?)?.toInt().clamp(0, 23) ?? 22,
      minute: (json['minute'] as num?)?.toInt().clamp(0, 59) ?? 0,
      template: (json['template'] as String?) ?? kDefaultSmsTemplate,
      recipients: list is List
          ? list
              .whereType<Map>()
              .map((e) => SmsRecipient.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <SmsRecipient>[],
      subscriptionId: (json['subscriptionId'] as num?)?.toInt() ?? -1,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'template': template,
        'recipients': recipients.map((r) => r.toJson()).toList(),
        'subscriptionId': subscriptionId,
      };

  SmsReportConfig copy() => SmsReportConfig.fromJson(toJson());
}
