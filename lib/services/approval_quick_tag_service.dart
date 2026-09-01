import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/approval_quick_tag.dart';

/// The Waiting for Approval page's double-tap quick-tag menu: a user-editable
/// list of tag -> tool mappings (see `ApprovalQuickTag`). Double-tapping a
/// pending item there offers one button per entry; tapping it approves the
/// item and flips the matching `Task` flag ([Task.isWish]/[Task.isResearch])
/// so it lands directly in that tool instead of the home tabs.
///
/// Seeded with the two tools that exist today (Wishlist, Research) on first
/// run, persisted to `approval_quick_tags.json`, and fully user-editable
/// (Settings > Tasks > Approval quick tags) — rename a tag, drop one, or add
/// it back. Mirrors `AutoTagService`'s load/save shape.
class ApprovalQuickTagService {
  ApprovalQuickTagService._();

  static final ApprovalQuickTagService instance = ApprovalQuickTagService._();

  static const String fileName = 'approval_quick_tags.json';

  static List<ApprovalQuickTag> _defaultTags() => [
        ApprovalQuickTag(
            label: 'Wishlist', target: ApprovalQuickTag.wishlistTarget),
        ApprovalQuickTag(
            label: 'Research', target: ApprovalQuickTag.researchTarget),
      ];

  final ValueNotifier<List<ApprovalQuickTag>> tags =
      ValueNotifier<List<ApprovalQuickTag>>(_defaultTags());
  bool _loaded = false;

  List<ApprovalQuickTag> get list => tags.value;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Drops any entry with an empty label or an unrecognized target — hand
  /// edits or a downgrade could otherwise leave a button the page cannot
  /// act on.
  static List<ApprovalQuickTag> _normalize(List<ApprovalQuickTag> tags) => [
        for (final tag in tags)
          if (tag.label.trim().isNotEmpty &&
              ApprovalQuickTag.targets.contains(tag.target))
            ApprovalQuickTag(label: tag.label.trim(), target: tag.target),
      ];

  /// Loads tags from disk (only once). Seeds and persists the default pair
  /// when no file exists yet, mirroring `AutoTagService.load`.
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
          .map((e) => ApprovalQuickTag.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      tags.value = _normalize(parsed);
    } catch (_) {}
  }

  Future<void> save(List<ApprovalQuickTag> next) async {
    tags.value = _normalize(next);
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString = jsonEncode(tags.value.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    tags.value = _defaultTags();
    _loaded = false;
  }
}
