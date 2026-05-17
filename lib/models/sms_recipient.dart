class SmsRecipient {
  String nickname;
  String phoneNumber;

  SmsRecipient({required this.nickname, required this.phoneNumber});

  factory SmsRecipient.fromJson(Map<String, dynamic> json) => SmsRecipient(
        nickname: (json['nickname'] as String?) ?? '',
        phoneNumber: (json['phoneNumber'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'phoneNumber': phoneNumber,
      };
}
