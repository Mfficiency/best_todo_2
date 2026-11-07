import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/agent_desk.dart';

/// Reads and writes the Agent Desk folder (SPEC §10.6s): one subfolder per
/// project holding
///
/// - `brief.md`: `# Name`, then the goal (first paragraph) and the rules;
/// - `status.json`: `{state, summary, where, updatedAt}` (written by agents);
/// - `questions.jsonl`: one [DeskQuestion] per line (written by agents);
/// - `decisions-<device>.jsonl`: one [DeskDecision] per line, written only
///   by the BestToDo install on that device (append-only);
/// - `log.md`: what the agent did, plain text (written by agents).
///
/// The folder is the whole interface: the agents on the Beast, the cloud
/// sessions (through a git branch the runner pulls in), Hermes (read-only)
/// and this page all meet there. Folders starting with `.` or `_` are not
/// projects. Read errors on single files are skipped so one bad line never
/// hides the rest of the desk.
class AgentDeskService {
  static AgentDeskService instance = AgentDeskService();

  static const String folderPrefKey = 'agent_desk_folder';
  static const int logTailLines = 40;

  final String? _folderOverride;
  final String? _deviceOverride;
  final DateTime Function() _clock;

  AgentDeskService({
    String? folder,
    String? device,
    DateTime Function()? clock,
  })  : _folderOverride = folder,
        _deviceOverride = device,
        _clock = clock ?? DateTime.now;

  /// This device's name, used in its decisions file and on each decision.
  String get device {
    final raw = _deviceOverride ?? _hostname();
    final safe = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-');
    return safe.isEmpty ? 'device' : safe;
  }

  static String _hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'device';
    }
  }

  /// The desk folder: the one chosen in the page's folder dialog, else
  /// `D:\AgentDesk` on a Windows PC with a D: drive, else `AgentDesk` in
  /// the app's documents folder.
  Future<String> folder() async {
    final override = _folderOverride;
    if (override != null) return override;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(folderPrefKey);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (_) {}
    return defaultFolder();
  }

  Future<String> defaultFolder() async {
    if (!kIsWeb && Platform.isWindows && await Directory(r'D:\').exists()) {
      return r'D:\AgentDesk';
    }
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}AgentDesk';
  }

  /// Saves the folder; an empty [path] goes back to [defaultFolder].
  Future<void> setFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path.trim().isEmpty) {
      await prefs.remove(folderPrefKey);
    } else {
      await prefs.setString(folderPrefKey, path.trim());
    }
  }

  String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  /// The whole desk, or null when the folder doesn't exist yet.
  Future<DeskSnapshot?> load() async {
    final root = await folder();
    final dir = Directory(root);
    if (!await dir.exists()) return null;
    final projects = <DeskProject>[];
    final entries = await dir.list().toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (id.startsWith('.') || id.startsWith('_')) continue;
      projects.add(await _loadProject(entry.path, id));
    }
    return DeskSnapshot(folder: root, projects: projects);
  }

  Future<DeskProject> _loadProject(String path, String id) async {
    var name = id;
    var goal = '';
    final brief = await _readText(_join(path, 'brief.md'));
    if (brief != null) {
      final lines = const LineSplitter().convert(brief);
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith('# ')) {
          name = t.substring(2).trim();
          break;
        }
      }
      // The goal: the first paragraph under the title, joined to one line.
      var pastTitle = false;
      final paragraph = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (!pastTitle) {
          pastTitle = t.startsWith('# ');
          continue;
        }
        if (t.startsWith('#')) break;
        if (t.isEmpty) {
          if (paragraph.isNotEmpty) break;
          continue;
        }
        paragraph.add(t);
      }
      goal = paragraph.join(' ');
    }

    Map<String, dynamic> status = const {};
    final statusText = await _readText(_join(path, 'status.json'));
    if (statusText != null) {
      try {
        final decoded = jsonDecode(statusText);
        if (decoded is Map) status = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final questions = <DeskQuestion>[
      for (final json in await _readJsonLines(_join(path, 'questions.jsonl')))
        DeskQuestion.fromJson(id, json),
    ].where((q) => q.id.isNotEmpty && q.text.trim().isNotEmpty).toList();

    final decisions = <DeskDecision>[];
    try {
      await for (final f in Directory(path).list()) {
        if (f is! File) continue;
        final file = f.uri.pathSegments.last;
        if (!file.startsWith('decisions') || !file.endsWith('.jsonl')) continue;
        for (final json in await _readJsonLines(f.path)) {
          decisions.add(DeskDecision.fromJson(id, json));
        }
      }
    } catch (_) {}
    decisions.sort((a, b) => a.at.compareTo(b.at));

    var logTail = <String>[];
    final log = await _readText(_join(path, 'log.md'));
    if (log != null) {
      final lines = const LineSplitter()
          .convert(log)
          .where((l) => l.trim().isNotEmpty)
          .toList();
      logTail = lines.sublist(max(0, lines.length - logTailLines));
    }

    final where = status['where'];
    return DeskProject(
      id: id,
      name: (status['name'] as String?)?.trim().isNotEmpty == true
          ? (status['name'] as String).trim()
          : name,
      goal: goal,
      state: DeskProject.stateFrom(status['state']),
      summary: status['summary'] as String? ?? '',
      where: where is String ? where : '',
      updatedAt: status['updatedAt'] is String
          ? DateTime.tryParse(status['updatedAt'] as String)?.toLocal()
          : null,
      questions: questions,
      decisions: decisions,
      logTail: logTail,
    );
  }

  Future<String?> _readText(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _readJsonLines(String path) async {
    final text = await _readText(path);
    if (text == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) out.add(Map<String, dynamic>.from(decoded));
      } catch (_) {}
    }
    return out;
  }

  /// Appends a decision to this device's decisions file in [projectId].
  /// [questionId] answers that question; without it the text is a free
  /// instruction to the project's agent (optionally about [topic]).
  Future<DeskDecision> decide({
    required String projectId,
    required String text,
    String? questionId,
    String topic = '',
    String via = 'text',
  }) async {
    final now = _clock();
    final decision = DeskDecision(
      id: 'd-${now.toUtc().millisecondsSinceEpoch}-$device',
      projectId: projectId,
      at: now,
      questionId: questionId,
      topic: topic,
      text: text.trim(),
      via: via,
      device: device,
    );
    final root = await folder();
    final dir = Directory(_join(root, projectId));
    await dir.create(recursive: true);
    final file = File(_join(dir.path, 'decisions-$device.jsonl'));
    await file.writeAsString('${jsonEncode(decision.toJson())}\n',
        mode: FileMode.append, flush: true);
    return decision;
  }

  /// Creates the desk folder with the five starter projects and the
  /// questions already known (the parked ones as `later`). Never overwrites
  /// a file that exists.
  Future<void> seed() async {
    final root = await folder();
    await Directory(root).create(recursive: true);
    await _writeIfMissing(_join(root, 'README.md'), _readme);
    final now = _clock().toUtc().toIso8601String();
    for (final p in _starterProjects) {
      final dir = _join(root, p.id);
      await Directory(dir).create(recursive: true);
      await _writeIfMissing(_join(dir, 'brief.md'), p.brief);
      await _writeIfMissing(
          _join(dir, 'status.json'),
          const JsonEncoder.withIndent('  ').convert({
            'state': 'idle',
            'summary': p.summary,
            'where': p.where,
            'updatedAt': now,
          }));
      await _writeIfMissing(
          _join(dir, 'questions.jsonl'),
          p.questions
              .map((q) => '${jsonEncode({...q, 'at': now})}\n')
              .join());
      await _writeIfMissing(_join(dir, 'log.md'),
          '# Log\n\n- ${now.substring(0, 10)}: desk set up, no agent yet.\n');
    }
  }

  Future<void> _writeIfMissing(String path, String content) async {
    final file = File(path);
    if (await file.exists()) return;
    await file.writeAsString(content, flush: true);
  }
}

class _Starter {
  final String id;
  final String brief;
  final String summary;
  final String where;
  final List<Map<String, Object>> questions;
  const _Starter(this.id, this.brief, this.summary, this.where, this.questions);
}

const String _readme = '''# Agent Desk

One folder per project. Who writes what:

| File | Written by |
|---|---|
| `brief.md` | you: `# Name`, the goal, the rules, what the agent may never do alone |
| `status.json` | the agent: `{"state": "working|waiting|idle|error", "summary", "where", "updatedAt"}` |
| `questions.jsonl` | the agent: `{"id", "at", "topic", "text", "options": [], "priority": "blocking|normal|later", "deadline"}` |
| `decisions-<device>.jsonl` | BestToDo on that device: `{"id", "at", "questionId", "topic", "text", "via", "device"}` |
| `log.md` | the agent |

A question is answered once a decision names its id. One writer per file, so
two PCs can sync this folder with git without conflicts.
''';

const List<_Starter> _starterProjects = [
  _Starter(
    '1-3d-builder',
    '''# 3D builder

From a photo and a sentence ("duplicate this, with a hole in the middle") to a
finished object on the Bambu Lab P2S, with the vent handled.

## Rules
- Never alone: start a print, change the printer's network mode, push to main.
- Code work runs in the cloud (Best3DBuilder repo); printer work on the Beast.
''',
    'Milestone (a): text to printed part. Not started.',
    'both',
    [
      {
        'id': 'p2s-lan-mode',
        'topic': 'Printer',
        'text':
            'Switch the P2S to LAN only + Developer mode, so the Beast can start prints? Bambu cloud and Handy remote access stop working then.',
        'options': ['Yes, switch it', 'Not yet'],
        'priority': 'normal',
      },
    ],
  ),
  _Starter(
    '2-photos',
    '''# Photos and videos

Bring all photos and videos into Immich on the Beast, keep only the useful
ones (at most 700 GB), and add the stories from photo evenings to them.

## Rules
- Never alone: delete anything, from any source.
- Plan: laptop-builder `beast/photos/README.md`.
''',
    'Batch 1 not started. Immich runs.',
    'beast',
    [
      {
        'id': 'videos-compress',
        'topic': 'Clean-up',
        'text':
            'Videos: re-compress large ones to HEVC on the GPU (often half the size), or only delete the ones you pick?',
        'options': ['Re-compress', 'Delete only'],
        'priority': 'normal',
      },
      {
        'id': 'kids-thinned',
        'topic': 'Clean-up',
        'text':
            'Which people get thinned, and who is on the keep list? Name them in Immich (Explore > People) first.',
        'priority': 'normal',
      },
      {
        'id': 'external-drive',
        'topic': 'Sources',
        'text':
            'Plug in the external hard drive and say its drive letter, so batch 1 can be scanned.',
        'priority': 'normal',
      },
    ],
  ),
  _Starter(
    '3-network',
    '''# Network and devices

Move everything onto UniFi, split into Home, Servers, IoT, Cameras, Printer and
Guest networks, and watch what the devices send out.

## Rules
- Never alone: any router, firewall or Wi-Fi change.
- Plans: laptop-builder `minipc/WIFI-REBUILD.md`, `home-assistant/docs/IOT_SECURITY.md`.
''',
    'Plan ready. All smart devices are still on my_stuffs.',
    'beast',
    [
      {
        'id': 'unifi-model',
        'topic': 'UniFi',
        'text':
            'Which UniFi router do you have, and is there a UniFi switch or access point? Port mirroring depends on it.',
        'priority': 'later',
      },
    ],
  ),
  _Starter(
    '4-vault',
    '''# Sensitive documents

Passport scans and the like, in an encrypted vault with off-site copies. The
agents set it up but never see inside it.

## Rules
- Never: the password manager's login, a session in it, or its export file.
''',
    'Vault: the password manager, if it can hold files.',
    'beast',
    [
      {
        'id': 'pm-files',
        'topic': 'Vault',
        'text':
            'Can your password manager store files? Yes or no is enough.',
        'options': ['Yes', 'No'],
        'priority': 'later',
      },
    ],
  ),
  _Starter(
    '5-deals',
    '''# Deals

Flights, things you use up, network hardware, second-hand solar and a battery,
an apartment to rent: find good prices so the setup pays for itself.

## Rules
- It advises, you buy. Never pay, book, bid or message a seller alone.
''',
    'Parked until the desk works.',
    'cloud',
    [
      {
        'id': 'deals-flights',
        'topic': 'Flights',
        'text': 'Which airport(s) do you fly from, and which trips do you have in mind?',
        'priority': 'later',
      },
      {
        'id': 'deals-first',
        'topic': 'Shopping',
        'text': 'What should it watch first?',
        'priority': 'later',
      },
      {
        'id': 'deals-apartment',
        'topic': 'Apartment',
        'text':
            'The apartment: to live in or to rent out as an investment? Where, and the budget?',
        'priority': 'later',
      },
      {
        'id': 'deals-gmail',
        'topic': 'Shopping',
        'text':
            'May the deals agent read order confirmations in Gmail to learn what you buy and what you paid?',
        'options': ['Yes', 'No, I keep the list'],
        'priority': 'later',
      },
    ],
  ),
];
