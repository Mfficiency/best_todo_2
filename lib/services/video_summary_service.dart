import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'video_transcript_service.dart';

/// A video's "quick summary": a short overview, the key points and the
/// conclusion the video reaches.
class VideoSummary {
  const VideoSummary({
    required this.overview,
    required this.keyPoints,
    required this.conclusion,
    required this.byClaude,
  });

  final String overview;
  final List<String> keyPoints;
  final String conclusion;

  /// True when Claude wrote it; false for the on-device extractive summary
  /// used when no Claude API key is set (or the call failed).
  final bool byClaude;

  /// The summary as Markdown body text (no title).
  String toMarkdown() {
    final b = StringBuffer();
    if (overview.isNotEmpty) b.writeln('## Summary\n\n$overview\n');
    if (keyPoints.isNotEmpty) {
      b.writeln('## Key points\n');
      for (final p in keyPoints) {
        b.writeln('- $p');
      }
      b.writeln();
    }
    if (conclusion.isNotEmpty) b.writeln('## Conclusion\n\n$conclusion');
    return b.toString().trim();
  }
}

/// Thrown when the Claude API call fails; [message] is user-facing.
class VideoSummaryException implements Exception {
  VideoSummaryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Summarizes a [VideoTranscript]. With a Claude API key (Best Music
/// Settings → Transcripts & summaries) Claude writes the summary; without
/// one an on-device extractive summary picks the transcript's most
/// representative sentences and uses its ending as the conclusion.
class VideoSummaryService {
  VideoSummaryService({http.Client? client}) : _client = client;

  static VideoSummaryService instance = VideoSummaryService();

  final http.Client? _client;

  static const model = 'claude-opus-5-5';
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  Future<VideoSummary> summarize({
    required String title,
    required String channel,
    required VideoTranscript transcript,
  }) async {
    final key = Config.claudeApiKey.trim();
    if (key.isEmpty) return extractiveSummary(transcript);
    return _summarizeWithClaude(key, title, channel, transcript);
  }

  Future<VideoSummary> _summarizeWithClaude(String apiKey, String title,
      String channel, VideoTranscript transcript) async {
    final client = _client ?? http.Client();
    try {
      final body = {
        'model': model,
        'max_tokens': 16000,
        // Re-run on Anthropic's recommended model if the request is
        // declined, rather than returning the refusal.
        'fallbacks': 'default',
        'output_config': {
          'effort': 'low',
          'format': {
            'type': 'json_schema',
            'schema': {
              'type': 'object',
              'properties': {
                'overview': {'type': 'string'},
                'key_points': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
                'conclusion': {'type': 'string'},
              },
              'required': ['overview', 'key_points', 'conclusion'],
              'additionalProperties': false,
            },
          },
        },
        'system': 'You summarize YouTube videos from their transcripts for '
            "the user's research notes. Write in the transcript's language. "
            'overview: 2-3 sentences on what the video is about. '
            'key_points: the 3-7 most important points, one sentence each. '
            'conclusion: the conclusion, verdict or main takeaway the video '
            "reaches, in 1-3 sentences. Stick to what's in the transcript; "
            'auto-generated captions may misspell names.',
        'messages': [
          {
            'role': 'user',
            'content': 'Title: $title\nChannel: $channel\n\n'
                '<transcript>\n${transcript.text}\n</transcript>',
          },
        ],
      };
      final http.Response response;
      try {
        response = await client
            .post(
              _endpoint,
              headers: {
                'content-type': 'application/json',
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
                'anthropic-beta': 'server-side-fallback-2026-07-01',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(minutes: 3));
      } catch (e) {
        throw VideoSummaryException("Couldn't reach Claude: $e");
      }
      final decoded = _tryDecode(response.bodyBytes);
      if (response.statusCode != 200) {
        final error = decoded is Map ? decoded['error'] : null;
        final message = error is Map ? error['message'] : null;
        throw VideoSummaryException('Claude API error '
            '${response.statusCode}${message != null ? ': $message' : ''}');
      }
      if (decoded is! Map) {
        throw VideoSummaryException('Unexpected reply from Claude');
      }
      if (decoded['stop_reason'] == 'refusal') {
        throw VideoSummaryException('Claude declined to summarize this video');
      }
      final text = [
        for (final block in (decoded['content'] as List? ?? const []))
          if (block is Map && block['type'] == 'text') block['text'] as String,
      ].join();
      return parseClaudeSummary(text);
    } finally {
      if (_client == null) client.close();
    }
  }

  static Object? _tryDecode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }

  /// Reads Claude's JSON reply; falls back to treating it as plain text.
  static VideoSummary parseClaudeSummary(String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return VideoSummary(
        overview: (json['overview'] as String? ?? '').trim(),
        keyPoints: [
          for (final p in (json['key_points'] as List? ?? const []))
            if (p.toString().trim().isNotEmpty) p.toString().trim(),
        ],
        conclusion: (json['conclusion'] as String? ?? '').trim(),
        byClaude: true,
      );
    } catch (_) {
      return VideoSummary(
          overview: text.trim(),
          keyPoints: const [],
          conclusion: '',
          byClaude: true);
    }
  }

  static const _stopWords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'so', 'of', 'to', 'in', 'on', //
    'at', 'for', 'with', 'is', 'are', 'was', 'were', 'be', 'been', 'it',
    'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'we', 'they',
    'me', 'my', 'your', 'our', 'their', 'his', 'her', 'its', 'as', 'by',
    'from', 'if', 'then', 'than', 'not', 'no', 'do', 'does', 'did', 'have',
    'has', 'had', 'just', 'like', 'um', 'uh', 'yeah', 'okay', 'ok', 'really',
    'very', 'what', 'which', 'who', 'there', 'here', 'about', 'can', 'will',
    'would', 'could', 'should', 'all', 'some', 'get', 'got', 'know', 'going',
    'gonna', 'right', 'oh', 'well', 'also', 'one', 'out', 'up', 'into',
  };

  /// Splits [text] into sentences; auto-generated captions have no
  /// punctuation, so long runs are cut into ~25-word chunks instead.
  static List<String> _sentences(String text) {
    final out = <String>[];
    for (final raw in text.split(RegExp(r'(?<=[.!?])\s+'))) {
      final words =
          raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      for (var i = 0; i < words.length; i += 25) {
        final chunk = words.sublist(i, (i + 25).clamp(0, words.length));
        if (chunk.length >= 4) out.add(chunk.join(' '));
      }
    }
    return out;
  }

  static String _capitalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    final first = t[0].toUpperCase() + t.substring(1);
    return RegExp(r'[.!?…]$').hasMatch(first) ? first : '$first…';
  }

  /// On-device summary: scores each sentence by how many of the
  /// transcript's frequent content words it contains, keeps the best five
  /// in their original order, and takes the last sentences as the
  /// conclusion (where videos usually wrap up).
  static VideoSummary extractiveSummary(VideoTranscript transcript) {
    final sentences = _sentences(transcript.text);
    if (sentences.isEmpty) {
      return const VideoSummary(
          overview: '', keyPoints: [], conclusion: '', byClaude: false);
    }
    List<String> words(String s) => s
        .toLowerCase()
        .split(RegExp(r"[^\p{L}\p{N}']+", unicode: true))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .toList();
    final freq = <String, int>{};
    for (final s in sentences) {
      for (final w in words(s)) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    final conclusionCount = sentences.length >= 6 ? 2 : 1;
    final body = sentences.length > conclusionCount + 1
        ? sentences.sublist(0, sentences.length - conclusionCount)
        : sentences;
    final scored = [
      for (var i = 0; i < body.length; i++)
        (
          index: i,
          score: () {
            final w = words(body[i]);
            if (w.isEmpty) return 0.0;
            return w.fold<int>(0, (sum, x) => sum + (freq[x] ?? 0)) /
                (w.length + 4);
          }(),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));
    final picked = (scored.take(5).map((s) => s.index).toList()..sort())
        .map((i) => _capitalize(body[i]))
        .toList();
    final conclusion = sentences.length > conclusionCount + 1
        ? sentences
            .sublist(sentences.length - conclusionCount)
            .map(_capitalize)
            .join(' ')
        : '';
    final minutes = transcript.segments.isEmpty
        ? 0
        : transcript.segments.last.start.inMinutes;
    final top = (freq.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();
    final overview = 'A ${minutes > 0 ? '$minutes-minute ' : ''}video '
        '(${transcript.wordCount} words) mostly about: ${top.join(', ')}.';
    return VideoSummary(
      overview: overview,
      keyPoints: picked,
      conclusion: conclusion,
      byClaude: false,
    );
  }
}
