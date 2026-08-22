import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/auto_tag_rule.dart';
import '../utils/label_utils.dart';

/// Auto-tagging, take one: a small user-editable keyword → tag dictionary.
/// When a new task/wish is created and [Config.autoTagEnabled] is on, its
/// title is scanned for whole-word (case-insensitive) matches against
/// [rules] and every matched tag is appended to the item's label. Rules are
/// persisted to `auto_tag_rules.json`, seeded with a handful of generic
/// starters on first run so the setting does something out of the box.
///
/// Deliberately dumb — a fixed dictionary, no NLP — so it's cheap and
/// predictable today. A later pass can swap [tagsFor] for an on-device LLM
/// without touching callers (they only ever see the resulting tag list).
class AutoTagService {
  AutoTagService._();

  static final AutoTagService instance = AutoTagService._();

  static const String fileName = 'auto_tag_rules.json';

  static List<AutoTagRule> _defaultRules() => [
        AutoTagRule(keyword: 'work', tag: 'work'),
        AutoTagRule(keyword: 'meeting', tag: 'work'),
        AutoTagRule(keyword: 'email', tag: 'work'),
        AutoTagRule(keyword: 'bike', tag: 'bike'),
        AutoTagRule(keyword: 'cycling', tag: 'bike'),
        AutoTagRule(keyword: 'gym', tag: 'health'),
        AutoTagRule(keyword: 'workout', tag: 'health'),
        AutoTagRule(keyword: 'groceries', tag: 'shopping'),
        AutoTagRule(keyword: 'shopping', tag: 'shopping'),
      ];

  final ValueNotifier<List<AutoTagRule>> rules =
      ValueNotifier<List<AutoTagRule>>(_defaultRules());
  bool _loaded = false;

  List<AutoTagRule> get list => rules.value;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Loads rules from disk (only once). Seeds and persists the default
  /// rules when no file exists yet, mirroring ProjectService's load.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        await _save();
        return;
      }
      final List<dynamic> data = jsonDecode(await file.readAsString());
      rules.value = data
          .whereType<Map>()
          .map((e) => AutoTagRule.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.keyword.trim().isNotEmpty && r.tag.trim().isNotEmpty)
          .toList();
    } catch (_) {}
  }

  Future<void> save(List<AutoTagRule> next) async {
    rules.value = next;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(rules.value.map((r) => r.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  /// Tags whose keyword appears as a whole word in [text] (case-insensitive),
  /// order-preserving and deduplicated (by tag, case-insensitive).
  List<String> tagsFor(String text) {
    if (text.trim().isEmpty) return const [];
    final lower = text.toLowerCase();
    final seenTags = <String>{};
    final tags = <String>[];
    for (final rule in rules.value) {
      final keyword = rule.keyword.trim().toLowerCase();
      final tag = rule.tag.trim();
      if (keyword.isEmpty || tag.isEmpty) continue;
      final pattern = RegExp(r'\b' + RegExp.escape(keyword) + r'\b');
      if (pattern.hasMatch(lower) && seenTags.add(tag.toLowerCase())) {
        tags.add(tag);
      }
    }
    return tags;
  }

  /// Appends any tag matches for [title] to [label] (when
  /// [Config.autoTagEnabled] is on), deduplicated against tokens already
  /// present. The one entry point new-item flows call.
  String withAutoTags(String title, String label) {
    if (!Config.autoTagEnabled) return label;
    final matched = tagsFor(title);
    if (matched.isEmpty) return label;
    final tokens = splitLabelTokens(label);
    final existing = tokens.map((t) => t.toLowerCase()).toSet();
    for (final tag in matched) {
      if (existing.add(tag.toLowerCase())) tokens.add(tag);
    }
    return joinLabelTokens(tokens);
  }

  @visibleForTesting
  void resetForTest() {
    rules.value = _defaultRules();
    _loaded = false;
  }
}
