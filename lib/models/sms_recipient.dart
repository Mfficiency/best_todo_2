class SmsRecipient {
  String nickname;
  String phoneNumber;

  /// When false the recipient is kept in the list but skipped by the daily
  /// report — a pause switch, so a contact does not have to be deleted and
  /// re-typed whenever they should not be messaged for a while.
  bool enabled;

  /// Id of an [SmsMessageTemplate] in [SmsReportConfig.templates] this
  /// recipient's message is rendered from. Null (or an id that no longer
  /// exists) falls back to the config's global default `template` — so
  /// recipients saved before named templates existed keep working unchanged.
  String? templateId;

  /// Per-recipient send time, overriding [SmsReportConfig.hour]/`.minute`.
  /// Both null (the case for every recipient saved before per-recipient
  /// timing existed) means "use the report's global send time".
  int? hour;
  int? minute;

  SmsRecipient({
    required this.nickname,
    required this.phoneNumber,
    this.enabled = true,
    this.templateId,
    this.hour,
    this.minute,
  });

  factory SmsRecipient.fromJson(Map<String, dynamic> json) => SmsRecipient(
        nickname: (json['nickname'] as String?) ?? '',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        // Recipients saved before the pause switch existed were always sent to.
        enabled: json['enabled'] as bool? ?? true,
        templateId: json['templateId'] as String?,
        hour: (json['hour'] as num?)?.toInt().clamp(0, 23),
        minute: (json['minute'] as num?)?.toInt().clamp(0, 59),
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'phoneNumber': phoneNumber,
        'enabled': enabled,
        'templateId': templateId,
        'hour': hour,
        'minute': minute,
      };
}
