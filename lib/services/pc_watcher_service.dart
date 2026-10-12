import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pc_watcher_status.dart';

/// Why the PC Watcher couldn't load the laptop's status, in words for the
/// page.
class PcWatcherException implements Exception {
  final String message;

  PcWatcherException(this.message);

  @override
  String toString() => message;
}

/// What one refresh found: the laptop's status plus the runner jobs that
/// haven't finished (null when the token can't read Actions).
class PcWatcherSnapshot {
  final PcWatcherStatus status;
  final List<PcRunnerJob>? runnerJobs;

  /// When this was downloaded (a cached snapshot keeps its old time).
  final DateTime fetchedAt;

  const PcWatcherSnapshot({
    required this.status,
    required this.fetchedAt,
    this.runnerJobs,
  });
}

/// Reads the laptop builder's status from the private
/// Mfficiency/laptop-builder repo (`pc_watcher.json` on its `status` branch,
/// force-pushed by `dev-build-watch.ps1`) with a read-only token the user
/// pastes once. The token and the last download stay in
/// SharedPreferences, so the page opens with the last known log offline.
class PcWatcherService {
  static PcWatcherService instance = PcWatcherService();

  static const String repo = 'Mfficiency/laptop-builder';
  static const String statusPath = 'pc_watcher.json';
  static const String statusBranch = 'status';

  static const String _tokenKey = 'pc_watcher_token';
  static const String _cacheKey = 'pc_watcher_cache';
  static const String _cacheAtKey = 'pc_watcher_cache_at';

  final http.Client _client;

  PcWatcherService({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey)?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  /// Saves [token]; null or empty removes it (and the cached log with it).
  Future<void> saveToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheAtKey);
    } else {
      await prefs.setString(_tokenKey, trimmed);
    }
  }

  /// The last downloaded status, if any.
  Future<PcWatcherSnapshot?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final at = DateTime.tryParse(prefs.getString(_cacheAtKey) ?? '');
      return PcWatcherSnapshot(
        status: PcWatcherStatus.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>()),
        fetchedAt: at?.toLocal() ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers(String token, {bool raw = false}) => {
        'Authorization': 'Bearer $token',
        'Accept':
            raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Downloads the status (and the runner's open jobs) and caches it.
  /// Throws [PcWatcherException] with a readable reason.
  Future<PcWatcherSnapshot> fetch(String token) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$repo/contents/'
                '$statusPath?ref=$statusBranch'),
            headers: _headers(token, raw: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw PcWatcherException('No connection to GitHub');
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 401:
        throw PcWatcherException(
            'GitHub rejected the token (expired or mistyped)');
      case 403:
        throw PcWatcherException(
            'GitHub refused (rate limit, or the token lacks Contents: Read)');
      case 404:
        throw PcWatcherException('No status found: the token needs read '
            'access to $repo, or the laptop has not published yet');
      default:
        throw PcWatcherException('GitHub answered ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    final PcWatcherStatus status;
    try {
      status = PcWatcherStatus.fromJson(
          (jsonDecode(body) as Map).cast<String, dynamic>());
    } catch (_) {
      throw PcWatcherException('The status file could not be read');
    }
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, body);
    await prefs.setString(_cacheAtKey, now.toUtc().toIso8601String());
    return PcWatcherSnapshot(
      status: status,
      fetchedAt: now,
      runnerJobs: await _fetchRunnerJobs(token),
    );
  }

  /// Builds waiting for or running on the laptop's runner; null when the
  /// token has no Actions access (optional) or GitHub can't be asked.
  Future<List<PcRunnerJob>?> _fetchRunnerJobs(String token) async {
    try {
      final response = await _client
          .get(
            Uri.parse(
                'https://api.github.com/repos/$repo/actions/runs?per_page=30'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final runs = decoded is Map ? decoded['workflow_runs'] : null;
      if (runs is! List) return null;
      return runs
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .where((r) => r['status'] != 'completed')
          .map(PcRunnerJob.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }
}
