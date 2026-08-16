import 'package:flutter/material.dart';

/// The three daily streak challenges the flame tracks.
///
/// Each kind keeps its own day history in `streak.json` and its own flame
/// colour, so the home-page flame can cycle through them: orange for finishing,
/// green for creating, blue for planning ahead. The [id]s are persisted (in
/// the streak file and in the settings), so keep them stable.
enum StreakKind {
  /// The original streak: complete at least one task on the day.
  complete(
    id: 'complete',
    label: 'Finish a task',
    short: 'Finish',
    description: 'Complete at least one task every day',
    callToAction: 'Complete one task today to light the flame.',
    icon: Icons.task_alt,
    cold: Color(0xFFFFA726), // orange 400
    warm: Color(0xFFFF5722), // deep orange 500
    hot: Color(0xFFD32F2F), // red 700
  ),

  /// Create at least one task on the day — you keep feeding the list.
  create(
    id: 'create',
    label: 'Create a task',
    short: 'Create',
    description: 'Add at least one new task every day',
    callToAction: 'Add one task today to light the flame.',
    icon: Icons.add_task,
    cold: Color(0xFF9CCC65), // light green 400
    warm: Color(0xFF43A047), // green 600
    hot: Color(0xFF00796B), // teal 700
  ),

  /// Plan ahead: move a task to another day, or finish everything that was
  /// due today. Both mean the day's list was actually dealt with instead of
  /// left to rot.
  plan(
    id: 'plan',
    label: 'Plan ahead',
    short: 'Plan',
    description: "Move a task to another day, or complete the whole day's list",
    callToAction:
        "Move a task to another day — or finish today's list — to light the "
        'flame.',
    icon: Icons.event_repeat,
    cold: Color(0xFF4FC3F7), // light blue 300
    warm: Color(0xFF3F51B5), // indigo 500
    hot: Color(0xFF7B1FA2), // purple 700
  );

  const StreakKind({
    required this.id,
    required this.label,
    required this.short,
    required this.description,
    required this.callToAction,
    required this.icon,
    required this.cold,
    required this.warm,
    required this.hot,
  });

  /// Persisted key — do not rename.
  final String id;

  /// Full name, used in settings and on the streak page.
  final String label;

  /// One-word name for tight spots (the flame selector chips).
  final String short;

  /// What has to happen for the day to count.
  final String description;

  /// Shown while the streak is cold: what to do today to light it.
  final String callToAction;

  final IconData icon;

  /// Flame colours from a fresh streak ([cold]) through [warm] to a full year
  /// of fire ([hot]).
  final Color cold;
  final Color warm;
  final Color hot;

  /// The kind with this [id], or null for an unknown (future/legacy) key.
  static StreakKind? fromId(String? id) {
    for (final kind in StreakKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  /// Flame colour for a streak progress between 0 (no streak, cold grey) and
  /// 1 (maximum fire after a full year).
  Color flameColor(double progress, ThemeData theme) {
    if (progress <= 0) return theme.disabledColor;
    if (progress < 0.5) return Color.lerp(cold, warm, progress * 2)!;
    return Color.lerp(warm, hot, (progress - 0.5) * 2)!;
  }
}
