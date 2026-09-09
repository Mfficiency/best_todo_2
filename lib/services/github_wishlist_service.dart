import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for any non-2xx GitHub REST API response, including a bad/expired
/// token (401) or a token missing the Issues scope (404/403).
class GithubApiException implements Exception {
  final int statusCode;
  final String message;

  GithubApiException(this.statusCode, this.message);

  @override
  String toString() => 'GithubApiException($statusCode): $message';
}

/// Thin wrapper over the GitHub REST API for the one thing the app needs:
/// opening an issue that the wishlist build automation picks up (see
/// `.claude/notes/automation.md`). Takes an [http.Client] so tests can
/// substitute `http.testing.MockClient` instead of hitting the network —
/// same pattern as `TodoistApiClient`.
class GithubWishlistService {
  static GithubWishlistService instance = GithubWishlistService();

  static const String owner = 'Mfficiency';
  static const String repo = 'best_todo_2';

  /// Label every issue opened here carries. The build routine watches for
  /// open issues with this label and picks them up.
  static const String buildLabel = 'wishlist-build';

  final http.Client _client;

  GithubWishlistService({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GithubApiException(
        response.statusCode,
        response.body.isNotEmpty ? response.body : response.reasonPhrase ?? '',
      );
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Opens a [buildLabel]-labeled issue titled [title] with [body]. Returns
  /// the issue's HTML URL. Throws [GithubApiException] on a non-2xx response.
  Future<String> createWishlistIssue({
    required String token,
    required String title,
    required String body,
  }) async {
    final response = await _client.post(
      Uri.parse('https://api.github.com/repos/$owner/$repo/issues'),
      headers: _headers(token),
      body: jsonEncode({
        'title': title,
        'body': body,
        'labels': [buildLabel],
      }),
    );
    final decoded = _decode(response) as Map<String, dynamic>? ?? const {};
    return decoded['html_url'] as String? ?? '';
  }

  /// A cheap authenticated call used to validate a token before it's saved —
  /// same role as `TodoistApiClient.fetchProjects`.
  Future<void> testConnection(String token) async {
    final response = await _client.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo'),
      headers: _headers(token),
    );
    _decode(response);
  }
}
