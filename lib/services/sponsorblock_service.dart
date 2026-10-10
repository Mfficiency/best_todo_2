import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../models/youtube_feed.dart';
import 'log_service.dart';

/// Looks up crowd-sourced skip segments (sponsor reads, "like and
/// subscribe" reminders, non-music intros, ...) for a YouTube video from
/// the public SponsorBlock API (https://sponsor.ajay.app — no key needed).
/// `MusicAudioHandler` seeks past them while a Subscriptions-feed video
/// plays.
class SponsorBlockService {
  SponsorBlockService._();

  static final SponsorBlockService instance = SponsorBlockService._();

  /// Lets tests answer without the network.
  @visibleForTesting
  http.Client? clientOverride;

  /// Segments for [videoId] in [categories], sorted by start. Never throws:
  /// no segments (SponsorBlock answers 404), offline, or a malformed reply
  /// all just mean nothing gets skipped.
  Future<List<SkipSegment>> segmentsFor(
    String videoId,
    Set<SponsorBlockCategory> categories,
  ) async {
    if (categories.isEmpty) return const [];
    final uri = Uri.https('sponsor.ajay.app', '/api/skipSegments', {
      'videoID': videoId,
      'categories': jsonEncode([for (final c in categories) c.key]),
    });
    final client = clientOverride ?? http.Client();
    try {
      final response =
          await client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];
      final segments = parseSponsorBlockSegments(response.body);
      if (segments.isNotEmpty) {
        LogService.add('Feed',
            'SponsorBlock: ${segments.length} segment(s) to skip in $videoId');
      }
      return segments;
    } catch (e) {
      LogService.add('Feed', 'SponsorBlock lookup for $videoId failed: $e');
      return const [];
    } finally {
      if (clientOverride == null) client.close();
    }
  }
}

/// Parses a `/api/skipSegments` response body. Only plain "skip" segments
/// count — "mute"/"full"/"poi" action types aren't ranges to jump over.
List<SkipSegment> parseSponsorBlockSegments(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const [];
  final segments = <SkipSegment>[];
  for (final entry in decoded.whereType<Map>()) {
    final range = entry['segment'];
    final action = entry['actionType'] as String? ?? 'skip';
    if (action != 'skip' || range is! List || range.length < 2) continue;
    final start = range[0], end = range[1];
    if (start is! num || end is! num || end <= start) continue;
    segments.add(SkipSegment(
      start: Duration(milliseconds: (start * 1000).round()),
      end: Duration(milliseconds: (end * 1000).round()),
      category: entry['category'] as String? ?? '',
    ));
  }
  segments.sort((a, b) => a.start.compareTo(b.start));
  return segments;
}
