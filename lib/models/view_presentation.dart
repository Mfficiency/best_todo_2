import 'view_filter_rules.dart';

/// A view's presentation configuration: rules for *how* the items a view's
/// [ViewFilterRules] already selected are displayed and edited, as opposed to
/// which items belong there. This is the second half of the filtering
/// redesign described in `docs/architecture/presentation-layer.md` — data
/// filters (which items) live in [ViewFilterRules]; this is where
/// presentation filters (how those items look) live, so a new view can be
/// added mostly by defining one of each rather than hand-rolling another
/// tile widget from scratch.
///
/// Every field defaults to today's actual behavior (every section always
/// shown), so [forView] is additive: a view nobody has opted in yet renders
/// exactly as before. Keyed by the same view ids as [ViewFilterRules]
/// ([ViewFilterRules.viewIds]) so the two configs stay easy to look up
/// together.
class ViewPresentation {
  /// Whether Task Details offers the one-tap "remind me" reminder section.
  /// Off for a task that is already archived or deleted — reminding about
  /// something that's over is never useful, and the reminder itself would
  /// have already been removed by [ReminderSyncService] once the task left
  /// the active list.
  final bool showReminderSection;

  /// Whether Task Details offers the "add countdown to due date" section.
  /// Off for the same reason as [showReminderSection].
  final bool showCountdownSection;

  const ViewPresentation({
    this.showReminderSection = true,
    this.showCountdownSection = true,
  });

  /// A terminal-state presentation: item-linked capabilities that only make
  /// sense for something still active are hidden. Used by [forView] for
  /// [ViewFilterRules.archived] and [ViewFilterRules.bin].
  static const ViewPresentation terminal = ViewPresentation(
    showReminderSection: false,
    showCountdownSection: false,
  );

  /// The presentation configured for [viewId], or the all-shown default for
  /// a view with nothing special configured (including null/unknown ids).
  static ViewPresentation forView(String? viewId) {
    switch (viewId) {
      case ViewFilterRules.archived:
      case ViewFilterRules.bin:
        return terminal;
      default:
        return const ViewPresentation();
    }
  }
}
