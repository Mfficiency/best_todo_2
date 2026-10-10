import '../config.dart';
import '../models/streak_goal.dart';
import '../models/streak_kind.dart';
import 'project_service.dart';
import 'streak_service.dart';

/// Resolved text for one flame: fixed for [StreakKind.complete], derived from
/// its [StreakGoal] (or the lack of one) for the customizable green
/// ([StreakKind.create]) and blue ([StreakKind.plan]) slots. Everything that
/// shows a flame's title/description/call-to-action reads this instead of
/// the [StreakKind] constants directly, so a user-defined goal shows through
/// everywhere at once.
class StreakFlameInfo {
  /// Short name shown on chips and headings — the goal's own title once set.
  final String short;

  /// Full title shown on the streak page.
  final String title;

  /// What has to happen for the day to count.
  final String description;

  /// Shown while the flame is cold: what to do to light it.
  final String callToAction;

  /// False only for a green/blue flame with no goal set yet.
  final bool configured;

  /// True when a configured goal's task or project no longer exists.
  final bool missing;

  const StreakFlameInfo({
    required this.short,
    required this.title,
    required this.description,
    required this.callToAction,
    required this.configured,
    required this.missing,
  });
}

/// Resolves the display info for [kind], given the currently configured
/// goals. [kind] must be one of [StreakKind.values].
StreakFlameInfo streakFlameInfo(StreakKind kind) {
  if (kind == StreakKind.complete) {
    return StreakFlameInfo(
      short: kind.short,
      title: kind.label,
      description: kind.description,
      callToAction: kind.callToAction,
      configured: true,
      missing: false,
    );
  }

  final goal = Config.streakGoals[kind.id];
  if (goal == null) {
    return StreakFlameInfo(
      short: kind.short,
      title: '${kind.short} · no goal set',
      description: 'Choose a recurring task or project to track.',
      callToAction: 'Set a goal for this flame in Streak settings.',
      configured: false,
      missing: false,
    );
  }

  final missing = goal.target == StreakGoalTarget.task
      ? StreakService.instance.isGoalMissing(kind)
      : ProjectService.instance.byId(goal.targetId) == null;
  if (missing) {
    return StreakFlameInfo(
      short: goal.title,
      title: goal.title,
      description: goal.target == StreakGoalTarget.task
          ? 'The recurring task this goal tracked was deleted.'
          : 'The project this goal tracked was deleted.',
      callToAction: 'Pick a new goal for this flame in Streak settings.',
      configured: true,
      missing: true,
    );
  }

  final what = goal.target == StreakGoalTarget.task
      ? "Complete '${goal.title}'"
      : "Complete a task in '${goal.title}'";
  return StreakFlameInfo(
    short: goal.title,
    title: goal.title,
    description: '$what every day',
    callToAction: '$what today to light the flame.',
    configured: true,
    missing: false,
  );
}
