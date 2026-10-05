import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/track.dart';

/// Thin client for a self-hosted Subsonic/OpenSubsonic-compatible server
/// (Navidrome, Airsonic, Gonic, …), configured in Settings → Music Player.
/// Auth follows the Subsonic API's token scheme: `token =
/// md5(password + salt)`, sent alongside a fresh random `salt` on every
/// request, so the plaintext password never goes on the wire.
///
/// This is intentionally small — enough to browse/search and build a
/// streaming URL — since the app's own local-folder library is the primary
/// source; a server connection is an optional extra one.
class SubsonicClient {
  SubsonicClient._();

  static final SubsonicClient instance = SubsonicClient._();

  static const String apiVersion = '1.16.1';
  static const String clientName = 'besttodo';

  bool get isConfigured =>
      Config.subsonicServerUrl.trim().isNotEmpty &&
      Config.subsonicUsername.trim().isNotEmpty;

  String _randomSalt() {
    final rand = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Map<String, String> _authParams() {
    final salt = _randomSalt();
    final token =
        md5.convert(utf8.encode('${Config.subsonicPassword}$salt')).toString();
    return {
      'u': Config.subsonicUsername,
      't': token,
      's': salt,
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  String get _base =>
      Config.subsonicServerUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Uri _buildUri(String endpoint, [Map<String, String>? extra]) {
    return Uri.parse('$_base/rest/$endpoint').replace(queryParameters: {
      ..._authParams(),
      ...?extra,
    });
  }

  /// The URL a track can be streamed from, for [Track.subsonic] tracks.
  Uri streamUri(String songId) => _buildUri('stream', {'id': songId});

  /// Verifies the server is reachable and the credentials are valid.
  Future<bool> ping() async {
    if (!isConfigured) return false;
    try {
      final response =
          await http.get(_buildUri('ping')).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final subsonicResponse = body['subsonic-response'] as Map<String, dynamic>?;
      return subsonicResponse?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Full-text search across the server's library (artists/albums/songs),
  /// returning just the matching songs as [Track]s.
  Future<List<Track>> search(String query, {int count = 40}) async {
    if (!isConfigured || query.trim().isEmpty) return [];
    try {
      final response = await http
          .get(_buildUri('search3', {'query': query, 'songCount': '$count'}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final subsonicResponse = body['subsonic-response'] as Map<String, dynamic>?;
      final result = subsonicResponse?['searchResult3'] as Map<String, dynamic>?;
      final songs = result?['song'] as List<dynamic>? ?? [];
      return songs
          .whereType<Map>()
          .map((s) => _songToTrack(Map<String, dynamic>.from(s)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Track _songToTrack(Map<String, dynamic> song) {
    final durationSeconds = song['duration'] as num?;
    return Track.subsonic(
      remoteId: song['id']?.toString() ?? '',
      title: song['title'] as String? ?? '',
      artist: song['artist'] as String? ?? '',
      album: song['album'] as String? ?? '',
      durationMs:
          durationSeconds != null ? (durationSeconds * 1000).round() : null,
    );
  }
}
