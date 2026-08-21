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

/// Thin wrapper over the Todoist REST API v2 (`api.todoist.com/rest/v2`).
/// Takes an [http.Client] so tests can substitute `http.testing.MockClient`
/// instead of hitting the network.
class TodoistApiClient {
  static const String baseUrl = 'https://api.todoist.com/rest/v2';

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

  /// A cheap authenticated call used to validate a token before it's saved.
  Future<List<Map<String, dynamic>>> fetchProjects() async {
    final response =
        await _client.get(Uri.parse('$baseUrl/projects'), headers: _headers);
    final data = _decode(response);
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> createProject(String name) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/projects'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  /// All active (open) tasks. Todoist's REST API has no endpoint for
  /// completed tasks, so a task's disappearance from this list is how
  /// completion/deletion on the Todoist side is detected — see
  /// `TodoistSyncService`.
  Future<List<Map<String, dynamic>>> fetchActiveTasks() async {
    final response =
        await _client.get(Uri.parse('$baseUrl/tasks'), headers: _headers);
    final data = _decode(response);
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

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
