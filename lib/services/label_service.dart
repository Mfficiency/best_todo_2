import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/label.dart';
import '../utils/label_utils.dart';

/// Registry of first-class [Label]s (`labels.json`), the structured half of
/// the label dual-write: tasks keep their token string, this service keeps
/// one [Label] per distinct token (kind, colour, stable id).
///
/// Startup-speed contract: nothing loads at app start. Registration happens
/// fire-and-forget on a background chain fed by task saves
/// ([registerTokens]) — a no-op write-free pass when every token is already
/// known, which is the steady state. The file is only read lazily on the
/// first registration or when a caller asks for the registry.
class LabelService {
  LabelService._();

  static LabelService instance = LabelService._();

  static const String fileName = 'labels.json';

  final ValueNotifier<List<Label>> labels =
      ValueNotifier<List<Label>>(<Label>[]);

  Future<void> _chain = Future.value();
  bool _loaded = false;

  List<Label> get list => labels.value;

  /// Case-insensitive lookup by token name.
  Label? byName(String name) {
    final lower = name.toLowerCase();
    for (final label in labels.value) {
      if (label.name.toLowerCase() == lower) return label;
    }
    return null;
  }

  /// Ensures the registry is loaded, then returns it. On-demand only.
  Future<List<Label>> ensureLoaded() async {
    await _enqueue(() async {});
    return labels.value;
  }

  /// Registers any yet-unknown tokens (kind derived via [labelKindFor]).
  /// Returns immediately; the load-merge-save runs on the background chain
  /// and only writes when something new actually appeared.
  void registerTokens(Iterable<String> tokens) {
    final snapshot = tokens.toList();
    if (snapshot.isEmpty) return;
    _enqueue(() async {
      final known =
          labels.value.map((l) => l.name.toLowerCase()).toSet();
      final added = <Label>[];
      for (final token in snapshot) {
        if (known.add(token.toLowerCase())) {
          added.add(Label(name: token, kind: labelKindFor(token)));
        }
      }
      if (added.isEmpty) return;
      labels.value = [...labels.value, ...added];
      await _save();
    });
  }

  /// Convenience: registers every token found on [taskLabelStrings].
  void registerFromLabelStrings(Iterable<String> taskLabelStrings) {
    final tokens = <String>[];
    for (final label in taskLabelStrings) {
      tokens.addAll(splitLabelTokens(label));
    }
    registerTokens(tokens);
  }

  /// Updates a label's metadata (colour, kind). Name is the identity here;
  /// renaming a token is a task-string edit, not a registry edit.
  Future<void> upsert(Label label) async {
    await _enqueue(() async {
      final next = [...labels.value];
      final idx = next.indexWhere(
          (l) => l.name.toLowerCase() == label.name.toLowerCase());
      if (idx >= 0) {
        next[idx] = label;
      } else {
        next.add(label);
      }
      labels.value = next;
      await _save();
    });
  }

  /// Completes when all queued registrations have been flushed (tests).
  Future<void> get pendingWrites => _chain;

  @visibleForTesting
  void resetForTest() {
    labels.value = <Label>[];
    _loaded = false;
    _chain = Future.value();
  }

  Future<void> _enqueue(Future<void> Function() work) {
    return _chain = _chain.then((_) async {
      try {
        await _loadOnce();
        await work();
      } catch (_) {}
    });
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<void> _loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) return;
      final List<dynamic> data = jsonDecode(await file.readAsString());
      final loaded = data
          .whereType<Map>()
          .map((e) => Label.fromJson(Map<String, dynamic>.from(e)))
          .where((l) => l.name.isNotEmpty)
          .toList();
      if (loaded.isNotEmpty) labels.value = loaded;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(labels.value.map((l) => l.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }
}
