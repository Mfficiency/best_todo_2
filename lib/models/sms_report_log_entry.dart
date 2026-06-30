/// 'send' = actual SMS delivery attempt; 'diag' = diagnostic/trace event.
enum SmsLogKind { send, diag }

class SmsReportLogEntry {
  final DateTime sentAt;
  final SmsLogKind kind;
  final String recipientNickname;
  final String recipientPhone;
  final String message;
  final bool success;
  final String? error;
  final int completedCount;
  final int uncompletedCount;

  SmsReportLogEntry({
    required this.sentAt,
    this.kind = SmsLogKind.send,
    this.recipientNickname = '',
    this.recipientPhone = '',
    required this.message,
    this.success = true,
    this.error,
    this.completedCount = 0,
    this.uncompletedCount = 0,
  });

  factory SmsReportLogEntry.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String?;
    return SmsReportLogEntry(
      sentAt:
          DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
      kind: kindStr == 'diag' ? SmsLogKind.diag : SmsLogKind.send,
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
        'kind': kind == SmsLogKind.diag ? 'diag' : 'send',
        'recipientNickname': recipientNickname,
        'recipientPhone': recipientPhone,
        'message': message,
        'success': success,
        if (error != null) 'error': error,
        'completedCount': completedCount,
        'uncompletedCount': uncompletedCount,
      };
}
