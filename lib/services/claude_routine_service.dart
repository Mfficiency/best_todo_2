import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/task.dart';

/// Thrown for any non-2xx response from a routine's `/fire` endpoint,
/// including a bad/expired token (401) or a malformed fire URL (404).
class ClaudeRoutineException implements Exception {
  final int statusCode;
  final String message;

  ClaudeRoutineException(this.statusCode, this.message);

  @override
  String toString() => 'ClaudeRoutineException($statusCode): $message';
}

/// The session a successful fire started, as returned by the API.
class ClaudeRoutineFireResult {
  final String sessionId;
  final String sessionUrl;

  ClaudeRoutineFireResult({required this.sessionId, required this.sessionUrl});
}

/// Fires a Claude Code Routine's API trigger to start a new cloud coding
/// session from a task ("Send to Claude" in the task's action menu). See
/// https://code.claude.com/docs/en/routines#add-an-api-trigger. Takes an
/// [http.Client] so tests can substitute `http.testing.MockClient` — same
/// pattern as `GithubWishlistService`.
class ClaudeRoutineService {
  static ClaudeRoutineService instance = ClaudeRoutineService();

  static const String _betaHeader = 'experimental-cc-routine-2026-04-01';

  final http.Client _client;

  ClaudeRoutineService({http.Client? client}) : _client = client ?? http.Client();

  /// Builds the routine's `text` fire payload from a task. The routine's own
  /// saved prompt decides whether/how to act on this — it arrives wrapped as
  /// untrusted context, not as a direct instruction (see routines docs).
  String buildPayload(Task task) {
    final buffer = StringBuffer('Task: ${task.title}');
    if (task.description.trim().isNotEmpty) {
      buffer.write('\n\nDescription: ${task.description.trim()}');
    }
    if (task.note.trim().isNotEmpty) {
      buffer.write('\n\nNote: ${task.note.trim()}');
    }
    if (task.label.trim().isNotEmpty) {
      buffer.write('\n\nLabel: ${task.label.trim()}');
    }
    return buffer.toString();
  }

  /// Sends [text] as the routine's fire payload. [fireUrl] and [token] come
  /// from Settings → Claude Routine (copied from the routine's API trigger at
  /// claude.ai/code/routines). Throws [ClaudeRoutineException] on a non-2xx
  /// response, or [FormatException]/[ArgumentError] for an invalid [fireUrl].
  Future<ClaudeRoutineFireResult> fire({
    required String fireUrl,
    required String token,
    required String text,
  }) async {
    final response = await _client.post(
      Uri.parse(fireUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'anthropic-beta': _betaHeader,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'text': text}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClaudeRoutineException(
        response.statusCode,
        response.body.isNotEmpty ? response.body : response.reasonPhrase ?? '',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return ClaudeRoutineFireResult(
      sessionId: decoded['claude_code_session_id'] as String? ?? '',
      sessionUrl: decoded['claude_code_session_url'] as String? ?? '',
    );
  }
}
