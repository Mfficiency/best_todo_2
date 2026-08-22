import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/auto_tag_group.dart';
import '../utils/label_utils.dart';

/// Auto-tagging: a user-editable dictionary of tag -> group-of-words. When a
/// new task/wish is created and [Config.autoTagEnabled] is on, its title is
/// scanned for whole-word (case-insensitive) matches against every group's
/// [AutoTagGroup.keywords], and every group with a hit contributes its tag to
/// the item's label. Grouping several synonyms under one tag (seeded from
/// online thesaurus data — see the defaults below) is what makes this useful
/// without any real language model: "gym", "workout" and "cardio" all still
/// land on "fitness". Groups are persisted to `auto_tag_rules.json`, seeded
/// with a starter dictionary on first run so the setting does something out
/// of the box, and stay fully user-editable (Settings > Tasks > Auto-tag
/// rules) — add/rename a tag, add/remove words from its group.
///
/// Deliberately dumb — a fixed dictionary, no real NLP — so it's cheap and
/// predictable today. A later pass can swap [tagsFor] for an on-device LLM
/// without touching callers (they only ever see the resulting tag list).
class AutoTagService {
  AutoTagService._();

  static final AutoTagService instance = AutoTagService._();

  static const String fileName = 'auto_tag_rules.json';

  /// Starter dictionary. Word groups curated from online thesaurus results
  /// (thesaurus.com, Merriam-Webster, WordHippo, relatedwords.io) trimmed to
  /// the common, everyday words someone would actually type into a task
  /// title — not every synonym a thesaurus returns.
  static List<AutoTagGroup> _defaultGroups() => [
        AutoTagGroup(tag: 'work', keywords: [
          'work', 'job', 'meeting', 'email', 'office', 'boss', 'client',
          'deadline', 'project', 'career', 'colleague', 'interview', 'shift',
        ]),
        AutoTagGroup(tag: 'bike', keywords: [
          'bike', 'bicycle', 'cycling', 'cycle', 'pedal', 'biking',
        ]),
        AutoTagGroup(tag: 'fitness', keywords: [
          'gym', 'workout', 'exercise', 'fitness', 'cardio', 'yoga',
          'jogging', 'running', 'training', 'stretch',
        ]),
        AutoTagGroup(tag: 'health', keywords: [
          'doctor', 'appointment', 'dentist', 'medicine', 'prescription',
          'checkup', 'hospital', 'pharmacy', 'clinic',
        ]),
        AutoTagGroup(tag: 'shopping', keywords: [
          'shopping', 'shop', 'buy', 'groceries', 'grocery', 'purchase',
          'mall', 'errands', 'store',
        ]),
        AutoTagGroup(tag: 'finance', keywords: [
          'money', 'budget', 'bills', 'bank', 'banking', 'savings', 'taxes',
          'invoice', 'expenses', 'salary', 'pay bills', 'loan', 'invest',
          'investment',
        ]),
        AutoTagGroup(tag: 'travel', keywords: [
          'travel', 'trip', 'vacation', 'flight', 'hotel', 'holiday',
          'passport', 'luggage', 'itinerary', 'booking', 'airport',
        ]),
        AutoTagGroup(tag: 'home', keywords: [
          'clean', 'cleaning', 'laundry', 'chores', 'tidy', 'vacuum',
          'dishes', 'housework', 'mop',
        ]),
        AutoTagGroup(tag: 'family', keywords: [
          'family', 'kids', 'birthday', 'parents', 'anniversary', 'wedding',
          'relatives',
        ]),
        AutoTagGroup(tag: 'food', keywords: [
          'cook', 'cooking', 'recipe', 'dinner', 'lunch', 'breakfast',
          'meal', 'kitchen', 'bake',
        ]),
        AutoTagGroup(tag: 'study', keywords: [
          'study', 'homework', 'school', 'exam', 'lecture', 'assignment',
          'revision',
        ]),
        AutoTagGroup(tag: 'tech', keywords: [
          'computer', 'software', 'app', 'coding', 'code', 'programming',
          'bug', 'laptop',
        ]),
      ];

  final ValueNotifier<List<AutoTagGroup>> groups =
      ValueNotifier<List<AutoTagGroup>>(_defaultGroups());
  bool _loaded = false;

  List<AutoTagGroup> get list => groups.value;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Merges groups that share a tag (case-insensitive), dedupes their
  /// keywords, and drops anything left empty. Used on every load and save so
  /// hand-edited or legacy (one-keyword-per-tag) data always ends up in one
  /// clean group per tag.
  static List<AutoTagGroup> _normalize(List<AutoTagGroup> groups) {
    final byTag = <String, AutoTagGroup>{};
    final order = <String>[];
    for (final group in groups) {
      final tag = group.tag.trim();
      if (tag.isEmpty) continue;
      final seen = <String>{};
      final keywords = <String>[];
      for (final raw in group.keywords) {
        final keyword = raw.trim();
        if (keyword.isEmpty) continue;
        if (seen.add(keyword.toLowerCase())) keywords.add(keyword);
      }
      if (keywords.isEmpty) continue;
      final key = tag.toLowerCase();
      final existing = byTag[key];
      if (existing == null) {
        byTag[key] = AutoTagGroup(tag: tag, keywords: keywords);
        order.add(key);
      } else {
        final existingSeen =
            existing.keywords.map((k) => k.toLowerCase()).toSet();
        for (final keyword in keywords) {
          if (existingSeen.add(keyword.toLowerCase())) {
            existing.keywords.add(keyword);
          }
        }
      }
    }
    return [for (final key in order) byTag[key]!];
  }

  /// Loads groups from disk (only once). Seeds and persists the default
  /// dictionary when no file exists yet, mirroring ProjectService's load.
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
      final parsed = data
          .whereType<Map>()
          .map((e) => AutoTagGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      groups.value = _normalize(parsed);
    } catch (_) {}
  }

  Future<void> save(List<AutoTagGroup> next) async {
    groups.value = _normalize(next);
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(groups.value.map((g) => g.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  /// Tags whose group has at least one keyword appearing as a whole word in
  /// [text] (case-insensitive), order-preserving.
  List<String> tagsFor(String text) {
    if (text.trim().isEmpty) return const [];
    final lower = text.toLowerCase();
    final tags = <String>[];
    for (final group in groups.value) {
      final tag = group.tag.trim();
      if (tag.isEmpty) continue;
      final hasMatch = group.keywords.any((raw) {
        final keyword = raw.trim().toLowerCase();
        if (keyword.isEmpty) return false;
        return RegExp(r'\b' + RegExp.escape(keyword) + r'\b').hasMatch(lower);
      });
      if (hasMatch) tags.add(tag);
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
    groups.value = _defaultGroups();
    _loaded = false;
  }
}
