/// One quick-approval tag shown in the Waiting for Approval page's
/// double-tap menu (`waiting_approval_page.dart`): tapping [label] there
/// approves the item and routes it straight into the tool named by
/// [target] — one of [ApprovalQuickTag.targets] — instead of leaving it on
/// the home tabs like a plain Approve does. User editable from Settings >
/// Tasks > Approval quick tags.
class ApprovalQuickTag {
  String label;
  String target;

  /// Target keys this app currently has a dedicated tool for. Kept as a
  /// fixed set (rather than a free-form destination) since routing a task
  /// means flipping one of [Task]'s own membership flags ([Task.isWish],
  /// [Task.isResearch]) — there is nowhere else a quick tag could send it.
  static const String wishlistTarget = 'wishlist';
  static const String researchTarget = 'research';
  static const List<String> targets = <String>[
    wishlistTarget,
    researchTarget,
  ];

  static const Map<String, String> targetLabels = <String, String>{
    wishlistTarget: 'Wishlist',
    researchTarget: 'Research',
  };

  ApprovalQuickTag({required this.label, required this.target});

  factory ApprovalQuickTag.fromJson(Map<String, dynamic> json) =>
      ApprovalQuickTag(
        label: (json['label'] as String? ?? '').trim(),
        target: (json['target'] as String? ?? '').trim(),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'target': target,
      };
}
