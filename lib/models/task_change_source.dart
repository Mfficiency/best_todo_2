/// Where a task-list mutation originated. Recorded on every [ItemEvent] (see
/// `item_event.dart`) so the per-task History timeline — and any future
/// Todoist sync, which needs to tell its own writes apart from the user's —
/// can say who or what made a change.
class TaskChangeSource {
  TaskChangeSource._();

  /// A direct action taken in the app UI.
  static const String user = 'user';

  /// A change pulled in from an external sync target (reserved for the
  /// planned Todoist integration; nothing writes this yet).
  static const String sync = 'sync';

  /// A task created from the Android share sheet.
  static const String share = 'share';

  /// A change the app made on its own: day-rollover archiving, recurring
  /// task generation, shipped-wish auto-completion, and similar housekeeping.
  static const String automation = 'automation';

  /// A change applied by the global Undo action.
  static const String undo = 'undo';

  /// A change applied by the global Redo action.
  static const String redo = 'redo';

  /// Reconstructed history seeded from pre-journal data (see
  /// [ItemEvent.seeded]); predates source tracking so the true origin isn't
  /// known.
  static const String system = 'system';

  static const List<String> all = <String>[
    user,
    sync,
    share,
    automation,
    undo,
    redo,
    system,
  ];

  /// Short label for the History timeline, e.g. "Edited title (Share)".
  static String label(String source) {
    switch (source) {
      case sync:
        return 'Sync';
      case share:
        return 'Share';
      case automation:
        return 'Automation';
      case undo:
        return 'Undo';
      case redo:
        return 'Redo';
      case system:
        return 'System';
      case user:
      default:
        return 'You';
    }
  }
}
