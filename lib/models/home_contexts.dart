import '../utils/label_utils.dart';

/// Which work contexts the home list shows — the drawer's Home row folds out
/// one toggle per context. "Todo" is every item that carries neither the
/// [worklistToken] (MLR/Migros) nor the [lemmonToken] label. Defaults keep
/// the home list exactly as it was before the toggles existed: regular items
/// only, MLR and Lemmon items in their own tools. Persisted in `settings.json`
/// (`Config.homeContexts`); applies only to the in-app home list (tabs and
/// schedule view), never the home-screen widget, Wear or the sync files.
class HomeContexts {
  final bool todo;
  final bool mlr;
  final bool lemmon;

  const HomeContexts({this.todo = true, this.mlr = false, this.lemmon = false});

  static const HomeContexts defaults = HomeContexts();

  bool get isDefault => todo && !mlr && !lemmon;

  /// Whether a task with [label] passes the toggles. A task carrying both
  /// context labels shows when either toggle is on.
  bool allows(String label) {
    final isMlr = hasWorklistToken(label);
    final isLemmon = hasLemmonToken(label);
    if (!isMlr && !isLemmon) return todo;
    return (isMlr && mlr) || (isLemmon && lemmon);
  }

  HomeContexts copyWith({bool? todo, bool? mlr, bool? lemmon}) => HomeContexts(
        todo: todo ?? this.todo,
        mlr: mlr ?? this.mlr,
        lemmon: lemmon ?? this.lemmon,
      );

  Map<String, dynamic> toJson() => {'todo': todo, 'mlr': mlr, 'lemmon': lemmon};

  factory HomeContexts.fromJson(Map<String, dynamic> json) => HomeContexts(
        todo: json['todo'] as bool? ?? true,
        mlr: json['mlr'] as bool? ?? false,
        lemmon: json['lemmon'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is HomeContexts &&
      other.todo == todo &&
      other.mlr == mlr &&
      other.lemmon == lemmon;

  @override
  int get hashCode => Object.hash(todo, mlr, lemmon);
}
