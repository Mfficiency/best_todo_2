import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/agent_desk.dart';
import '../utils/label_utils.dart';
import 'todoist_api_client.dart';

/// The Agent Desk's connection to Todoist (SPEC §10.6s).
///
/// The desk talks to Todoist itself and only ever touches tasks labelled
/// [agentDeskToken]. It never reads or writes the local task list and doesn't
/// need the two-way sync switched on, only the token: a PC whose full sync is
/// off (or stale) can use the desk without its local list reaching Todoist.
/// A device that does run the full sync mirrors desk tasks read-only and keeps
/// them out of every other view (`TodoistSyncService`, `ItemViews`).
///
/// The contract for agents:
///
/// - **Question:** a task labelled `agentdesk` in the project's Todoist
///   project. The title is the question, the description the context in
///   Markdown, with marker lines `[Option: Yes]` (one per suggested answer),
///   `[Topic: Printer]` and `[Priority: blocking|normal|later]`; the due date
///   is the deadline. Files go on comments.
/// - **Status:** one task per project labelled `agentdesk` and
///   `agentdesk_status`. The title is the one-line summary, the description
///   holds the brief and the log, with `[State: working|waiting|idle|error]`,
///   `[Where: beast|cloud|both]` and `[Updated: <ISO time>]`.
/// - **Answer:** the desk posts a comment `[Answer] <text>` and adds the label
///   `agentdesk_answered`. The agent reads it and closes the task when done.
/// - **Instruction:** a new task from you, labelled `agentdesk` and
///   `agentdesk_instruction`. The agent closes it when done.
class AgentDeskService {
  static AgentDeskService instance = AgentDeskService();

  static const String cacheFileName = 'agent_desk_cache.json';

  final http.Client Function()? _httpClient;
  final String? _tokenOverride;

  AgentDeskService({http.Client Function()? httpClient, String? token})
      : _httpClient = httpClient,
        _tokenOverride = token;

  String get _token => (_tokenOverride ?? Config.todoistApiToken).trim();

  /// Whether a Todoist token is set on this device.
  bool get connected => _token.isNotEmpty;

  TodoistApiClient _client([String? token]) => TodoistApiClient(
        apiToken: token ?? _token,
        client: _httpClient?.call(),
      );

  Future<T> _withClient<T>(Future<T> Function(TodoistApiClient) run) async {
    final client = _client();
    try {
      return await run(client);
    } finally {
      client.close();
    }
  }

  /// Checks [token] against Todoist and saves it. Throws when it's refused.
  /// The full sync's own on/off switch stays as it is.
  Future<void> connect(String token) async {
    final trimmed = token.trim();
    final client = _client(trimmed);
    try {
      await client.fetchProjects();
    } finally {
      client.close();
    }
    Config.todoistApiToken = trimmed;
    await Config.save();
  }

  static Map<String, String> _projectNames(
          List<Map<String, dynamic>> projects) =>
      {
        for (final p in projects)
          // The Inbox reads as "General": every unfiled task lands there, its
          // name says nothing about a project.
          if (p['is_inbox_project'] != true)
            p['id'].toString(): p['name'] as String? ?? '',
      };

  /// The whole desk from Todoist; the local cache is updated. Throws on a
  /// network or API failure, so the page can say so and keep what it shows.
  Future<DeskBoard> refresh() async {
    final (tasks, projects) = await _withClient((client) async => (
          await client.fetchTasksWithLabel(agentDeskToken),
          await client.fetchProjects(),
        ));
    final names = _projectNames(projects);
    await _writeCache(tasks, names);
    return DeskBoard.fromRemote(tasks, names);
  }

  /// The desk as last fetched, so opening it shows something at once. Null
  /// when there is no cache yet (or no file system).
  Future<DeskBoard?> loadCached() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      return DeskBoard.fromRemote(
        (json['tasks'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        Map<String, String>.from(json['projects'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
      List<Map<String, dynamic>> tasks, Map<String, String> names) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonEncode({'tasks': tasks, 'projects': names}),
          flush: true);
    } catch (_) {
      // Only a head start for the next launch; the desk works without it.
    }
  }

  Future<File> _cacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}${Platform.pathSeparator}$cacheFileName');
  }

  /// A task's comments, oldest first: notes, files and earlier answers.
  Future<List<DeskComment>> comments(DeskItem item) => _withClient((c) async => [
        for (final json in await c.fetchComments(item.id))
          DeskComment.fromJson(json),
      ]);

  /// Answers [item]: the comment first, because it's what the agent acts on;
  /// the label then takes the item out of the queue on every device.
  Future<void> answer(DeskItem item, String text) => _withClient((c) async {
        await c.addComment(item.id, '${DeskComment.answerPrefix} ${text.trim()}');
        await c.updateTaskLabels(
          item.id,
          {...item.labels, agentDeskAnsweredToken}.toList(),
        );
      });

  /// Tells [project]'s agent what to do next.
  Future<void> instruct(String project, String text) =>
      _createAll([_Draft(project, text.trim(), '', const [agentDeskInstructionToken])]);

  /// Closes [item] on Todoist.
  Future<void> close(DeskItem item) =>
      _withClient((c) => c.closeTask(item.id));

  /// Creates the five starter projects with their status items and the
  /// questions already known. Only offered while the desk is empty.
  Future<void> seed() => _createAll(_starterDrafts);

  Future<void> _createAll(List<_Draft> drafts) => _withClient((c) async {
        final projects = await c.fetchProjects();
        final ids = {
          for (final p in projects)
            if (p['is_inbox_project'] != true)
              (p['name'] as String? ?? '').toLowerCase(): p['id'].toString(),
        };
        for (final draft in drafts) {
          String? projectId;
          if (draft.project != deskGeneralProject) {
            final key = draft.project.toLowerCase();
            projectId = ids[key];
            if (projectId == null) {
              final created = await c.createProject(draft.project);
              projectId = created['id'].toString();
              ids[key] = projectId;
            }
          }
          await c.createTask(
            content: draft.title,
            description: draft.description,
            projectId: projectId,
            labels: [agentDeskToken, ...draft.labels],
          );
        }
      });

  /// Headers to load an attachment with. The token only ever goes to Todoist.
  Map<String, String> headersFor(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    final isTodoist = uri?.scheme == 'https' &&
        (host == 'todoist.com' || host.endsWith('.todoist.com'));
    return isTodoist ? {'Authorization': 'Bearer $_token'} : const {};
  }

  /// [item] on the Todoist website.
  static String todoistUrl(DeskItem item) =>
      'https://app.todoist.com/app/task/${item.id}';
}

class _Draft {
  final String project;
  final String title;
  final String description;
  final List<String> labels;
  const _Draft(this.project, this.title, this.description, this.labels);
}

_Draft _status(String project, String summary, String where, String brief) =>
    _Draft(project, summary, '[State: idle]\n[Where: $where]\n\n$brief',
        const [agentDeskStatusToken]);

_Draft _question(
  String project,
  String text, {
  required String topic,
  String priority = 'normal',
  List<String> options = const [],
}) =>
    _Draft(
      project,
      text,
      [
        '[Topic: $topic]',
        '[Priority: $priority]',
        for (final o in options) '[Option: $o]',
      ].join('\n'),
      const [],
    );

final List<_Draft> _starterDrafts = [
  _status('3D builder', 'Milestone (a): text to printed part. Not started.',
      'both', '''
From a photo and a sentence ("duplicate this, with a hole in the middle") to a
finished object on the Bambu Lab P2S, with the vent handled.

## Rules
- Never alone: start a print, change the printer's network mode, push to main.
- Code work runs in the cloud (Best3DBuilder repo); printer work on the Beast.'''),
  _question(
    '3D builder',
    'Switch the P2S to LAN only + Developer mode, so the Beast can start prints? Bambu cloud and Handy remote access stop working then.',
    topic: 'Printer',
    options: const ['Yes, switch it', 'Not yet'],
  ),
  _status('Photos and videos', 'Batch 1 not started. Immich runs.', 'beast', '''
Bring all photos and videos into Immich on the Beast, keep only the useful ones
(at most 700 GB), and add the stories from photo evenings to them.

## Rules
- Never alone: delete anything, from any source.
- Plan: laptop-builder `beast/photos/README.md`.'''),
  _question(
    'Photos and videos',
    'Videos: re-compress large ones to HEVC on the GPU (often half the size), or only delete the ones you pick?',
    topic: 'Clean-up',
    options: const ['Re-compress', 'Delete only'],
  ),
  _question(
    'Photos and videos',
    'Which people get thinned, and who is on the keep list? Name them in Immich (Explore > People) first.',
    topic: 'Clean-up',
  ),
  _question(
    'Photos and videos',
    'Plug in the external hard drive and say its drive letter, so batch 1 can be scanned.',
    topic: 'Sources',
  ),
  _status('Network and devices',
      'Plan ready. All smart devices are still on my_stuffs.', 'beast', '''
Move everything onto UniFi, split into Home, Servers, IoT, Cameras, Printer and
Guest networks, and watch what the devices send out.

## Rules
- Never alone: any router, firewall or Wi-Fi change.
- Plans: laptop-builder `minipc/WIFI-REBUILD.md`, `home-assistant/docs/IOT_SECURITY.md`.'''),
  _question(
    'Network and devices',
    'Which UniFi router do you have, and is there a UniFi switch or access point? Port mirroring depends on it.',
    topic: 'UniFi',
    priority: 'later',
  ),
  _status('Sensitive documents',
      'Vault: the password manager, if it can hold files.', 'beast', '''
Passport scans and the like, in an encrypted vault with off-site copies. The
agents set it up but never see inside it.

## Rules
- Never: the password manager's login, a session in it, or its export file.'''),
  _question(
    'Sensitive documents',
    'Can your password manager store files? Yes or no is enough.',
    topic: 'Vault',
    priority: 'later',
    options: const ['Yes', 'No'],
  ),
  _status('Deals', 'Parked until the desk works.', 'cloud', '''
Flights, things you use up, network hardware, second-hand solar and a battery,
an apartment to rent: find good prices so the setup pays for itself.

## Rules
- It advises, you buy. Never pay, book, bid or message a seller alone.'''),
  _question(
    'Deals',
    'Which airport(s) do you fly from, and which trips do you have in mind?',
    topic: 'Flights',
    priority: 'later',
  ),
  _question('Deals', 'What should it watch first?',
      topic: 'Shopping', priority: 'later'),
  _question(
    'Deals',
    'The apartment: to live in or to rent out as an investment? Where, and the budget?',
    topic: 'Apartment',
    priority: 'later',
  ),
  _question(
    'Deals',
    'May the deals agent read order confirmations in Gmail to learn what you buy and what you paid?',
    topic: 'Shopping',
    priority: 'later',
    options: const ['Yes', 'No, I keep the list'],
  ),
];
