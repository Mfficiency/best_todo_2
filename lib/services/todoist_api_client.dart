import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for any non-2xx Todoist REST API response, including a bad/expired
/// token (401).
class TodoistApiException implements Exception {
  final int statusCode;
  final String message;

  TodoistApiException(this.statusCode, this.message);

  @override
  String toString() => 'TodoistApiException($statusCode): $message';
}

/// Thin wrapper over Todoist's unified API v1 (`api.todoist.com/api/v1`) —
/// the old REST v2 (`rest/v2`) and Sync v9 (`sync/v9`) endpoints were
/// sunset, and now respond with a deprecation notice instead of data.
/// Takes an [http.Client] so tests can substitute `http.testing.MockClient`
/// instead of hitting the network.
class TodoistApiClient {
  static const String baseUrl = 'https://api.todoist.com/api/v1';

  final String apiToken;
  final http.Client _client;

  TodoistApiClient({required this.apiToken, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TodoistApiException(
        response.statusCode,
        response.body.isNotEmpty ? response.body : response.reasonPhrase ?? '',
      );
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// v1 list endpoints (`tasks`, `projects`) return one cursor-paginated
  /// page at a time as `{"results": [...], "next_cursor": ...}`, unlike REST
  /// v2's bare array — this walks every page and returns the combined list.
  Future<List<Map<String, dynamic>>> _fetchAllPages(String path) async {
    final results = <Map<String, dynamic>>[];
    String? cursor;
    while (true) {
      final uri = Uri.parse('$baseUrl/$path').replace(
        queryParameters: cursor == null ? null : {'cursor': cursor},
      );
      final response = await _client.get(uri, headers: _headers);
      final data = _decode(response);
      final page = data is Map ? Map<String, dynamic>.from(data) : const {};
      results.addAll((page['results'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)));
      cursor = page['next_cursor'] as String?;
      if (cursor == null) break;
    }
    return results;
  }

  /// A cheap authenticated call used to validate a token before it's saved.
  Future<List<Map<String, dynamic>>> fetchProjects() =>
      _fetchAllPages('projects');

  Future<Map<String, dynamic>> createProject(String name) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  /// All active (open) tasks. Todoist's API has no endpoint for completed
  /// tasks, so a task's disappearance from this list is how
  /// completion/deletion on the Todoist side is detected — see
  /// `TodoistSyncService`.
  Future<List<Map<String, dynamic>>> fetchActiveTasks() =>
      _fetchAllPages('tasks');

  Future<Map<String, dynamic>> createTask({
    required String content,
    required String description,
    String? projectId,
    String? dueDate,
    String? dueDatetime,
    List<String> labels = const [],
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
      body: jsonEncode({
        'content': content,
        'description': description,
        if (projectId != null) 'project_id': projectId,
        if (dueDatetime != null) 'due_datetime': dueDatetime,
        if (dueDatetime == null && dueDate != null) 'due_date': dueDate,
        if (labels.isNotEmpty) 'labels': labels,
      }),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  /// Updates an existing task. A null [dueDate]/[dueDatetime] pair clears the
  /// due date (Todoist: `due_string: "no date"`); the caller decides which of
  /// the two to send based on [Task.hasExplicitTime].
  Future<void> updateTask(
    String taskId, {
    required String content,
    required String description,
    String? dueDate,
    String? dueDatetime,
    bool clearDue = false,
    List<String> labels = const [],
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/tasks/$taskId'),
      headers: _headers,
      body: jsonEncode({
        'content': content,
        'description': description,
        if (clearDue) 'due_string': 'no date',
        if (!clearDue && dueDatetime != null) 'due_datetime': dueDatetime,
        if (!clearDue && dueDatetime == null && dueDate != null)
          'due_date': dueDate,
        'labels': labels,
      }),
    );
    _decode(response);
  }

  /// Moves a task to a different project. Unlike other fields, a task's
  /// project can't be changed through [updateTask] — v1 (like the REST v2
  /// and Sync APIs before it) only accepts a project reassignment through
  /// this dedicated endpoint.
  Future<void> moveTask(String taskId, {required String projectId}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/tasks/$taskId/move'),
      headers: _headers,
      body: jsonEncode({'project_id': projectId}),
    );
    _decode(response);
  }

  Future<void> closeTask(String taskId) async {
    final response = await _client
        .post(Uri.parse('$baseUrl/tasks/$taskId/close'), headers: _headers);
    _decode(response);
  }

  Future<void> reopenTask(String taskId) async {
    final response = await _client
        .post(Uri.parse('$baseUrl/tasks/$taskId/reopen'), headers: _headers);
    _decode(response);
  }

  Future<void> deleteTask(String taskId) async {
    final response = await _client
        .delete(Uri.parse('$baseUrl/tasks/$taskId'), headers: _headers);
    _decode(response);
  }

  void close() => _client.close();
}
