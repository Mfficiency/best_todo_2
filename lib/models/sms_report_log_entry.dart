class SmsReportLogEntry {
  final DateTime sentAt;
  final String recipientNickname;
  final String recipientPhone;
  final String message;
  final bool success;
  final String? error;
  final int completedCount;
  final int uncompletedCount;

  SmsReportLogEntry({
    required this.sentAt,
    required this.recipientNickname,
    required this.recipientPhone,
    required this.message,
    required this.success,
    this.error,
    required this.completedCount,
    required this.uncompletedCount,
  });

  factory SmsReportLogEntry.fromJson(Map<String, dynamic> json) {
    return SmsReportLogEntry(
      sentAt:
          DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
      recipientNickname: (json['recipientNickname'] as String?) ?? '',
      recipientPhone: (json['recipientPhone'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      success: json['success'] as bool? ?? false,
      error: json['error'] as String?,
      completedCount: (json['completedCount'] as num?)?.toInt() ?? 0,
      uncompletedCount: (json['uncompletedCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'sentAt': sentAt.toIso8601String(),
        'recipientNickname': recipientNickname,
        'recipientPhone': recipientPhone,
        'message': message,
        'success': success,
        if (error != null) 'error': error,
        'completedCount': completedCount,
        'uncompletedCount': uncompletedCount,
      };
}
