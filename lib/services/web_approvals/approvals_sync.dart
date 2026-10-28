import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/task.dart';

/// Keeps the approvals site's page and the Todoist sync from overwriting each
/// other (SPEC §4.2k). Both read the whole list, change it and write it back;
/// a page save landing on top of a sync would drop the tasks that sync just
/// pulled, and the *next* sync deletes a mapped task that's missing locally on
/// Todoist. So:
///
/// * [exclusive] is one lock: a sync run and every page save take it, so they
///   never interleave.
/// * The page doesn't save its whole list: [mergeOver] applies only what the
///   page changed since its [snapshot] over the freshly loaded list.
/// * [requestSoon] coalesces saves into one sync a few seconds later (longer
///   than a deny's undo window, so an undone deny never reaches Todoist).
class ApprovalsSyncCoordinator {
  final Future<String?> Function() runSync;
  final Duration debounce;

  ApprovalsSyncCoordinator({
    required this.runSync,
    this.debounce = const Duration(seconds: 6),
  });

  final ValueNotifier<bool> syncing = ValueNotifier(false);

  /// Bumped after every sync, so the page reloads what it pulled.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// The last sync's error, null after a successful one.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  Future<void> _tail = Future.value();
  Timer? _timer;
  bool _disposed = false;

  /// Runs [action] once every earlier holder of the lock has finished.
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  void requestSoon() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(syncNow()));
  }

  Future<void> syncNow() {
    _timer?.cancel();
    return exclusive(() async {
      if (_disposed) return;
      syncing.value = true;
      try {
        lastError.value = await runSync();
      } catch (e) {
        lastError.value = '$e';
      } finally {
        syncing.value = false;
      }
      revision.value++;
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  /// uid → the task's JSON: what the page last loaded or saved.
  static Map<String, String> snapshot(List<Task> tasks) =>
      {for (final t in tasks) t.uid: jsonEncode(t.toJson())};

  /// [stored] with the page's changes since [baseline] applied:
  /// * a task the page changed replaces the stored one (the page wins), or is
  ///   appended when the page created it;
  /// * a task the page removed (denied) is dropped;
  /// * everything else keeps the stored version — whatever a sync pulled.
  ///   Untouched tasks reuse the page's own instance when the stored one is
  ///   unchanged, so an open editor keeps editing the listed object.
  ///
  /// A task the page changed but a sync removed (completed on Todoist
  /// meanwhile) stays removed — re-adding it would create a duplicate.
  static List<Task> mergeOver({
    required List<Task> stored,
    required List<Task> page,
    required Map<String, String> baseline,
  }) {
    final pageByUid = {for (final t in page) t.uid: t};
    final changed = <String, Task>{
      for (final t in page)
        if (baseline[t.uid] != jsonEncode(t.toJson())) t.uid: t,
    };
    final removed = baseline.keys.where((u) => !pageByUid.containsKey(u));
    final removedSet = removed.toSet();
    final merged = <Task>[];
    final seen = <String>{};
    for (final s in stored) {
      if (removedSet.contains(s.uid) || !seen.add(s.uid)) continue;
      final mine = changed[s.uid];
      if (mine != null) {
        merged.add(mine);
        continue;
      }
      final own = pageByUid[s.uid];
      merged.add(own != null && baseline[s.uid] == jsonEncode(s.toJson())
          ? own
          : s);
    }
    for (final t in changed.values) {
      if (!seen.contains(t.uid) && !baseline.containsKey(t.uid)) {
        merged.add(t);
      }
    }
    return merged;
  }
}
