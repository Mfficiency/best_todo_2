/// One completed (or failed) background sync run, as shown on the App Logs
/// page: when it ran, how long it took, how many tasks were written and — for
/// failures — what went wrong.
class SyncLogEntry {
  DateTime at;
  int durationMs;
  int itemCount;
  bool success;
  String message;

  /// What started the sync: 'app quit' (the lifecycle hook), 'manual', or
  /// 'pull_to_refresh' (pulling down on the home page's task list).
  String trigger;

  SyncLogEntry({
    required this.at,
    required this.durationMs,
    required this.itemCount,
    required this.success,
    this.message = '',
    this.trigger = 'manual',
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'durationMs': durationMs,
        'itemCount': itemCount,
        'success': success,
        'message': message,
        'trigger': trigger,
      };

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        durationMs: (json['durationMs'] as num?)?.round() ?? 0,
        itemCount: (json['itemCount'] as num?)?.round() ?? 0,
        success: json['success'] as bool? ?? false,
        message: json['message'] as String? ?? '',
        trigger: json['trigger'] as String? ?? 'manual',
      );
}
