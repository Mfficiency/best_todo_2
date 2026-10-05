import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for any non-2xx response from the Jev API (401 bad key, 422
/// validation, 429 rate limit, 529 overloaded).
class JevDecisionException implements Exception {
  final int statusCode;
  final String message;

  JevDecisionException(this.statusCode, this.message);

  @override
  String toString() => 'JevDecisionException($statusCode): $message';
}

/// One answered `choice` question.
class JevChoice {
  final String choice;
  final double confidence;
  final int inputTokens;

  JevChoice({
    required this.choice,
    required this.confidence,
    required this.inputTokens,
  });
}

/// Thin client for TypeSafe's Jev "decision model"
/// (https://docs.typesafe.ai/api): instead of generating text it takes a
/// `state` plus typed questions and returns bounded answers with
/// probabilities. That makes it a cheap, fast (~70-500 ms, output tokens are
/// free) replacement for an LLM wherever the app only needs to *pick* from a
/// known set — e.g. which tag a task belongs to. Takes an [http.Client] so
/// tests can substitute `http.testing.MockClient`, same pattern as
/// `ClaudeRoutineService`.
class JevDecisionService {
  static JevDecisionService instance = JevDecisionService();

  static const String endpoint = 'https://api.typesafe.ai/v1/systemone';
  static const String model = 'jev-latest';

  final http.Client _client;

  JevDecisionService({http.Client? client}) : _client = client ?? http.Client();

  /// Asks a single `choice` question about [state]. [criteria] maps each
  /// option name to a short description of when it applies (max 255).
  Future<JevChoice> choose({
    required String apiKey,
    required String state,
    required String instructions,
    required Map<String, String> criteria,
  }) async {
    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'state': state,
            'questions': {
              'pick': {
                'type': 'choice',
                'instructions': instructions,
                'criteria': criteria,
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JevDecisionException(
        response.statusCode,
        response.body.isNotEmpty ? response.body : response.reasonPhrase ?? '',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final answer = (decoded['answers'] as Map?)?['pick'] as Map?;
    final usage = decoded['usage'] as Map?;
    return JevChoice(
      choice: answer?['choice'] as String? ?? '',
      confidence: (answer?['confidence'] as num?)?.toDouble() ?? 0,
      inputTokens: (usage?['input_tokens'] as num?)?.toInt() ?? 0,
    );
  }
}
