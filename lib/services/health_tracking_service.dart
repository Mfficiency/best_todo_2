import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/health_metrics.dart';

/// Persists manually-entered body weight and personal-best records for the
/// Fitness Activity page's "Weight & personal bests" section, separate from
/// the read-only Health Connect data the rest of that page shows. Weight
/// entries go to `weight_log.json`, personal bests to `personal_bests.json`,
/// both in the app documents directory. Persistence is unavailable on
/// platforms without a documents directory (e.g. Flutter web and widget
/// tests), so failures are swallowed and the in-memory lists keep working.
class HealthTrackingService {
  HealthTrackingService._();

  static final HealthTrackingService instance = HealthTrackingService._();

  static const _weightFileName = 'weight_log.json';
  static const _personalBestsFileName = 'personal_bests.json';

  final ValueNotifier<List<WeightEntry>> weightEntries =
      ValueNotifier<List<WeightEntry>>(<WeightEntry>[]);
  bool _weightLoaded = false;

  final ValueNotifier<List<PersonalBest>> personalBests =
      ValueNotifier<List<PersonalBest>>(<PersonalBest>[]);
  bool _personalBestsLoaded = false;

  Future<File> _fileNamed(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name');
  }

  /// Sorts newest-first, which is how both lists are always shown.
  void _sortByDateDesc<T>(List<T> items, DateTime Function(T) dateOf) =>
      items.sort((a, b) => dateOf(b).compareTo(dateOf(a)));

  Future<void> loadWeightEntries() async {
    if (_weightLoaded) return;
    _weightLoaded = true;
    try {
      final file = await _fileNamed(_weightFileName);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        final loaded = [
          for (final entry in data)
            if (entry is Map)
              WeightEntry.fromJson(Map<String, dynamic>.from(entry)),
        ];
        _sortByDateDesc(loaded, (e) => e.date);
        weightEntries.value = loaded;
      }
    } catch (_) {}
  }

  Future<void> saveWeightEntry(WeightEntry entry) async {
    final next = [...weightEntries.value];
    final idx = next.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      next[idx] = entry;
    } else {
      next.add(entry);
    }
    _sortByDateDesc(next, (e) => e.date);
    weightEntries.value = next;
    await _saveWeightEntries();
  }

  Future<void> deleteWeightEntry(String id) async {
    weightEntries.value =
        weightEntries.value.where((e) => e.id != id).toList();
    await _saveWeightEntries();
  }

  Future<void> _saveWeightEntries() async {
    try {
      final file = await _fileNamed(_weightFileName);
      final jsonString =
          jsonEncode(weightEntries.value.map((e) => e.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  Future<void> loadPersonalBests() async {
    if (_personalBestsLoaded) return;
    _personalBestsLoaded = true;
    try {
      final file = await _fileNamed(_personalBestsFileName);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        final loaded = [
          for (final entry in data)
            if (entry is Map)
              PersonalBest.fromJson(Map<String, dynamic>.from(entry)),
        ];
        _sortByDateDesc(loaded, (e) => e.date);
        personalBests.value = loaded;
      }
    } catch (_) {}
  }

  Future<void> savePersonalBest(PersonalBest best) async {
    final next = [...personalBests.value];
    final idx = next.indexWhere((b) => b.id == best.id);
    if (idx >= 0) {
      next[idx] = best;
    } else {
      next.add(best);
    }
    _sortByDateDesc(next, (b) => b.date);
    personalBests.value = next;
    await _savePersonalBests();
  }

  Future<void> deletePersonalBest(String id) async {
    personalBests.value =
        personalBests.value.where((b) => b.id != id).toList();
    await _savePersonalBests();
  }

  Future<void> _savePersonalBests() async {
    try {
      final file = await _fileNamed(_personalBestsFileName);
      final jsonString =
          jsonEncode(personalBests.value.map((b) => b.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    weightEntries.value = <WeightEntry>[];
    _weightLoaded = false;
    personalBests.value = <PersonalBest>[];
    _personalBestsLoaded = false;
  }
}
