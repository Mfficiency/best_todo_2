import 'task.dart';

/// What a user-configured flame goal is anchored to: a single recurring
/// task's daily instance, or any task filed under a project.
enum StreakGoalTarget { task, project }

/// A user-defined goal for one of the customizable flames ([StreakKind.create]
/// and [StreakKind.plan] — the green and blue slots): the flame lights the
/// day a task matching [target]/[targetId] is completed. [title] is shown on
/// the flame instead of the slot's generic name; it is pre-filled from the
/// chosen task/project's name when the goal is set, and editable afterwards.
class StreakGoal {
  final StreakGoalTarget target;
  final String targetId;
  final String title;

  const StreakGoal({
    required this.target,
    required this.targetId,
    required this.title,
  });

  factory StreakGoal.fromJson(Map<String, dynamic> json) => StreakGoal(
        target: json['target'] == 'project'
            ? StreakGoalTarget.project
            : StreakGoalTarget.task,
        targetId: json['targetId'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'target': target.name,
        'targetId': targetId,
        'title': title,
      };

  /// Whether completing [task] satisfies this goal for the day: the exact
  /// recurring task or one of its generated daily instances, or any task
  /// filed under the chosen project.
  bool matches(Task task) => target == StreakGoalTarget.task
      ? (task.uid == targetId || task.recurrenceParentUid == targetId)
      : task.projectId == targetId;
}
