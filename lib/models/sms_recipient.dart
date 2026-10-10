class SmsRecipient {
  String nickname;
  String phoneNumber;

  /// When false the recipient is kept in the list but skipped by the daily
  /// report — a pause switch, so a contact does not have to be deleted and
  /// re-typed whenever they should not be messaged for a while.
  bool enabled;

  SmsRecipient({
    required this.nickname,
    required this.phoneNumber,
    this.enabled = true,
  });

  factory SmsRecipient.fromJson(Map<String, dynamic> json) => SmsRecipient(
        nickname: (json['nickname'] as String?) ?? '',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
        // Recipients saved before the pause switch existed were always sent to.
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'phoneNumber': phoneNumber,
        'enabled': enabled,
      };
}
