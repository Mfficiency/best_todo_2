import '../utils/label_utils.dart';
import 'task.dart';

/// Which work contexts the home list shows — the drawer's Home row folds out
/// one toggle per context. "Todo" is every item that carries neither the
/// [worklistToken] (MLR/Migros) nor the [lemmonToken] label. "Backlog" shows
/// the wishlist ([Task.isWish]) items on top, even though the Home filter
/// rules hide them by default (see `ItemViews.isOnHomeScreen`); with it off,
/// wishes are ordinary Todo items, shown or hidden by those rules as before.
/// Defaults keep the home list exactly as it was before the toggles existed:
/// regular items only, MLR and Lemmon items in their own tools. Persisted in
/// `settings.json` (`Config.homeContexts`); applies only to the in-app home
/// list (tabs and schedule view), never the home-screen widget, Wear or the
/// sync files.
class HomeContexts {
  final bool todo;
  final bool mlr;
  final bool lemmon;
  final bool backlog;

  const HomeContexts({
    this.todo = true,
    this.mlr = false,
    this.lemmon = false,
    this.backlog = false,
  });

  static const HomeContexts defaults = HomeContexts();

  /// Every context on — what the full-tab callers that renumber
  /// [Task.listRanking] see.
  static const HomeContexts all =
      HomeContexts(todo: true, mlr: true, lemmon: true, backlog: true);

  bool get isDefault => this == defaults;

  /// Whether [task] passes the toggles. A task carrying both context labels
  /// shows when either toggle is on; a wish always shows with [backlog] on.
  bool allows(Task task) {
    if (backlog && task.isWish) return true;
    final isMlr = hasWorklistToken(task.label);
    final isLemmon = hasLemmonToken(task.label);
    if (!isMlr && !isLemmon) return todo;
    return (isMlr && mlr) || (isLemmon && lemmon);
  }

  HomeContexts copyWith({bool? todo, bool? mlr, bool? lemmon, bool? backlog}) =>
      HomeContexts(
        todo: todo ?? this.todo,
        mlr: mlr ?? this.mlr,
        lemmon: lemmon ?? this.lemmon,
        backlog: backlog ?? this.backlog,
      );

  Map<String, dynamic> toJson() =>
      {'todo': todo, 'mlr': mlr, 'lemmon': lemmon, 'backlog': backlog};

  factory HomeContexts.fromJson(Map<String, dynamic> json) => HomeContexts(
        todo: json['todo'] as bool? ?? true,
        mlr: json['mlr'] as bool? ?? false,
        lemmon: json['lemmon'] as bool? ?? false,
        backlog: json['backlog'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is HomeContexts &&
      other.todo == todo &&
      other.mlr == mlr &&
      other.lemmon == lemmon &&
      other.backlog == backlog;

  @override
  int get hashCode => Object.hash(todo, mlr, lemmon, backlog);
}
