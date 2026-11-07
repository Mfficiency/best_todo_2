import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/task.dart';
import '../utils/voice_inbox.dart';
import 'claude_routine_service.dart';
import 'item_repository.dart';
import 'log_service.dart';
import 'todoist_sync_service.dart';

/// Stages of an Active research item's two-run Claude research
/// (`docs/proposals/voice-inbox.md` §8), stored in [Task.researchStage].
class ResearchStages {
  ResearchStages._();

  /// The routine was fired; waiting for its `[Questions]` comment.
  static const String requested = 'requested';

  /// Questions arrived; waiting for the owner's answers.
  static const String questions = 'questions';

  /// Answers sent; waiting for the routine's `[Done] <link>`.
  static const String answered = 'answered';

  /// The research page exists ([Task.obsidianLink]).
  static const String ready = 'ready';
}

/// What the routine said back in an item's Todoist comments.
class RoutineReply {
  /// The numbered lines of the newest `[Questions]` comment.
  final List<String> questions;

  /// The link of the newest `[Done] <link>` comment.
  final String? doneLink;

  /// Whether the newest `[Answers]` comment is newer than the questions —
  /// i.e. the questions were answered already.
  final bool answered;

  const RoutineReply({
    this.questions = const [],
    this.doneLink,
    this.answered = false,
  });
}

/// The app's side of the voice-inbox routine runs that happen *after* the
/// sorting: writing an approved Backlog item's Obsidian page, and the
/// Research "Active" question round. Both start by firing the routine's API
/// trigger ([ClaudeRoutineService], URL/token in Settings → Claude Routine →
/// Voice inbox) with a `MODE:` line and the item as JSON; the routine answers
/// through the item's Todoist task — comments starting with `[Questions]` or
/// `[Done] <link>` (and an `[Obsidian: …]` line on the description).
///
/// Every routine run works on the Todoist copy, so the item is synced first:
/// that pushes the approval (and creates the Todoist task for an item typed
/// in the app) before the routine looks for it.
class VoiceInboxService {
  VoiceInboxService({ClaudeRoutineService? routine, TodoistSyncService? sync})
      : _routine = routine,
        _sync = sync;

  static VoiceInboxService instance = VoiceInboxService();

  final ClaudeRoutineService? _routine;
  final TodoistSyncService? _sync;

  ClaudeRoutineService get routine => _routine ?? ClaudeRoutineService.instance;
  TodoistSyncService get sync => _sync ?? TodoistSyncService.instance;

  static const String modeWritePage = 'write-page';
  static const String modeResearchQuestions = 'research-questions';
  static const String modeResearchAnswers = 'research-answers';

  /// Whether the routine and Todoist sync (its only way back) are set up.
  static bool get isConfigured =>
      Config.voiceInboxRoutineUrl.trim().isNotEmpty &&
      Config.voiceInboxRoutineToken.trim().isNotEmpty &&
      Config.todoistSyncEnabled &&
      Config.todoistApiToken.trim().isNotEmpty;

  /// The fire payload: a `MODE:` line, then the item as JSON.
  @visibleForTesting
  String buildPayload(String mode, Task task,
      {List<String> questions = const [], List<String> answers = const []}) {
    final entry = sync.entryForLocalUid(task.uid);
    final data = <String, dynamic>{
      'todoistTaskId': entry?.todoistId,
      'uid': task.uid,
      'title': task.title,
      if (task.description.trim().isNotEmpty) 'description': task.description,
      if (task.note.trim().isNotEmpty) 'note': task.note,
      if (task.label.trim().isNotEmpty) 'labels': task.label,
      'kind': task.isResearch ? 'research' : 'backlog',
      'state': BacklogStates.title(backlogStateOf(task)),
      if (task.obsidianProject != null) 'project': task.obsidianProject,
      if (task.transcriptPath != null) 'transcript': task.transcriptPath,
      if (task.pendingSourceTitle != null) 'source': task.pendingSourceTitle,
      if (questions.isNotEmpty)
        'qa': [
          for (var i = 0; i < questions.length; i++)
            {
              'question': questions[i],
              'answer': i < answers.length ? answers[i] : '',
            }
        ],
    };
    return 'MODE: $mode\n${const JsonEncoder.withIndent('  ').convert(data)}';
  }

  Future<void> _fire(String mode, Task task,
      {List<String> questions = const [], List<String> answers = const []}) async {
    // Push first: the routine reads and comments on the Todoist copy.
    await sync.syncNow(trigger: 'voice-inbox');
    final result = await routine.fire(
      fireUrl: Config.voiceInboxRoutineUrl.trim(),
      token: Config.voiceInboxRoutineToken.trim(),
      text: buildPayload(mode, task, questions: questions, answers: answers),
    );
    LogService.add('VoiceInboxService',
        'Fired $mode for "${task.title}" (session ${result.sessionId})');
  }

  // Each request has a synchronous `mark…` step (stamps the task — the page
  // saves it) and an async `fire…` step that syncs and fires without
  // touching the task, so the page's save and the sync's own save of
  // tasks.json never interleave. On a failed fire the page undoes the mark.

  /// Stamps [Task.obsidianRequestedAt] for a write-page request.
  static void markObsidianRequested(Task task) =>
      task.obsidianRequestedAt = DateTime.now();

  /// Asks the routine to write [task]'s Obsidian page.
  Future<void> fireWritePage(Task task) => _fire(modeWritePage, task);

  /// Puts [task] into [ResearchStages.requested] for a research round.
  static void markResearchRequested(Task task) {
    task.researchStage = ResearchStages.requested;
    task.researchQuestions = [];
  }

  /// Starts the research round for an Active research [task].
  Future<void> fireResearchQuestions(Task task) =>
      _fire(modeResearchQuestions, task);

  /// Posts [answers] (index-aligned with [Task.researchQuestions]) as an
  /// `[Answers]` comment and fires the second research run. The caller then
  /// moves the task to [ResearchStages.answered].
  Future<void> sendAnswers(Task task, List<String> answers) async {
    final ok = await sync.addCommentFor(
        task.uid, formatAnswers(task.researchQuestions, answers));
    if (!ok) throw StateError('This item is not on Todoist yet');
    await _fire(modeResearchAnswers, task,
        questions: task.researchQuestions, answers: answers);
  }

  /// Runs [fire] (one of the `fire…` calls, after the page saved the mark).
  /// On failure the mark is taken back with [undo] — on [task] itself and on
  /// the stored copy, since the sync inside [fire] may have rewritten
  /// tasks.json meanwhile — and a short error text is returned for a
  /// SnackBar. Null on success.
  Future<String?> runFire(
    Task task,
    Future<void> Function() fire,
    void Function(Task task) undo,
  ) async {
    try {
      await fire();
      return null;
    } catch (e) {
      LogService.add('VoiceInboxService', 'Fire failed for "${task.title}": $e');
      undo(task);
      try {
        final stored = await ItemRepository.instance.loadItems();
        for (final t in stored) {
          if (t.uid == task.uid) undo(t);
        }
        await ItemRepository.instance.saveItems(stored);
      } catch (_) {}
      return e is ClaudeRoutineException
          ? 'Claude routine error ${e.statusCode}'
          : 'Couldn\'t reach the Claude routine';
    }
  }

  /// Reads [task]'s Todoist comments and moves it along: questions arrive,
  /// or the `[Done]` link. Returns whether anything changed (the caller
  /// persists).
  Future<bool> refresh(Task task) async {
    final comments = await sync.commentsFor(task.uid);
    if (comments == null) return false;
    final reply = parseReplies(
        comments.map((c) => c['content'] as String? ?? '').toList());
    var changed = false;
    final link = reply.doneLink;
    if (link != null && task.obsidianLink != link) {
      task.obsidianLink = link;
      changed = true;
    }
    if (task.isResearch) {
      if (task.obsidianLink != null) {
        if (task.researchStage != ResearchStages.ready) {
          task.researchStage = ResearchStages.ready;
          changed = true;
        }
      } else if (task.researchStage == ResearchStages.requested &&
          reply.questions.isNotEmpty &&
          !reply.answered) {
        task.researchQuestions = reply.questions;
        task.researchStage = ResearchStages.questions;
        changed = true;
      }
    }
    return changed;
  }

  /// Whether [task] is waiting for something from the routine, i.e. worth a
  /// [refresh] when its page opens.
  static bool isWaiting(Task task) {
    if (task.isResearch) {
      return task.researchStage == ResearchStages.requested ||
          task.researchStage == ResearchStages.answered;
    }
    return task.obsidianRequestedAt != null && task.obsidianLink == null;
  }

  /// The `[Answers]` comment for [questions]/[answers].
  static String formatAnswers(List<String> questions, List<String> answers) {
    final b = StringBuffer('[Answers]');
    for (var i = 0; i < questions.length; i++) {
      final answer = i < answers.length ? answers[i].trim() : '';
      b
        ..write('\n${i + 1}. ${questions[i]}')
        ..write('\n   → ${answer.isEmpty ? '(skipped)' : answer}');
    }
    return b.toString();
  }

  /// Reads the routine's replies out of an item's comments (oldest first):
  /// the newest `[Questions]` comment's numbered lines, whether an
  /// `[Answers]` comment came after it, and the newest `[Done] <link>`.
  static RoutineReply parseReplies(List<String> comments) {
    var questions = <String>[];
    var questionsAt = -1;
    var answersAt = -1;
    String? link;
    for (var i = 0; i < comments.length; i++) {
      final text = comments[i].trim();
      final lower = text.toLowerCase();
      if (lower.startsWith('[questions]')) {
        questionsAt = i;
        questions = [
          for (final line in text.substring('[questions]'.length).split('\n'))
            if (line.trim().isNotEmpty)
              line.trim().replaceFirst(RegExp(r'^(\d+[.)]|[-*•])\s*'), ''),
        ];
      } else if (lower.startsWith('[answers]')) {
        answersAt = i;
      } else if (lower.startsWith('[done]')) {
        final rest = text.substring('[done]'.length).trim();
        final match = RegExp(r'\S+').firstMatch(rest);
        if (match != null) link = match.group(0);
      }
    }
    return RoutineReply(
      questions: questions,
      doneLink: link,
      answered: questionsAt >= 0 && answersAt > questionsAt,
    );
  }
}
