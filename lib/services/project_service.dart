import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/project.dart';
import '../models/task.dart';

/// Single source of truth for projects, shared between the Projects page, the
/// per-project Kanban board and the project/stage tags on task tiles. Holds
/// the projects in a [ValueNotifier] so the UI rebuilds when a project is
/// renamed. Persists to `projects.json` in the app documents directory;
/// seeded with [Project.placeholders] on first run. Persistence is
/// unavailable on platforms without a documents directory (e.g. Flutter web
/// and widget tests), so failures are swallowed and the seeded list keeps
/// working in-memory.
class ProjectService {
  ProjectService._();

  static final ProjectService instance = ProjectService._();

  static const _fileName = 'projects.json';

  final ValueNotifier<List<Project>> projects =
      ValueNotifier<List<Project>>(Project.placeholders);
  bool _loaded = false;

  List<Project> get list => projects.value;

  Project? byId(String? id) {
    if (id == null) return null;
    for (final project in projects.value) {
      if (project.id == id) return project;
    }
    return null;
  }

  /// Display name for a project id; falls back to the raw id for tasks whose
  /// project no longer exists.
  String nameOf(String? id) => byId(id)?.name ?? (id ?? '');

  /// Human-readable name of a Kanban stage id ('todo' → 'To-Do', …).
  static String stageLabel(String status) {
    switch (status) {
      case Task.kanbanOngoing:
        return 'Ongoing';
      case Task.kanbanClosed:
        return 'Closed';
      case Task.kanbanTodo:
      default:
        return 'To-Do';
    }
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads projects from disk (only once). Seeds and persists the placeholder
  /// projects when no file exists yet.
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
      final loaded = data
          .whereType<Map>()
          .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.id.isNotEmpty)
          .toList();
      if (loaded.isNotEmpty) {
        projects.value = loaded;
      }
    } catch (_) {}
  }

  Future<void> upsert(Project project) async {
    final next = [...projects.value];
    final idx = next.indexWhere((p) => p.id == project.id);
    if (idx >= 0) {
      next[idx] = project;
    } else {
      next.add(project);
    }
    projects.value = next;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(projects.value.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    projects.value = Project.placeholders;
    _loaded = false;
  }
}
