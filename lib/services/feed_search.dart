import 'dart:math' as math;

import '../models/youtube_feed.dart';

/// Which part of a feed video the Subscriptions search looks at.
enum FeedSearchField {
  all('All'),
  title('Title'),
  channel('Channel'),
  date('Date');

  const FeedSearchField(this.label);
  final String label;
}

const _monthNames = [
  'january', 'february', 'march', 'april', 'may', 'june', 'july', //
  'august', 'september', 'october', 'november', 'december',
];
const _weekdayNames = [
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday',
  'sunday',
];

/// Everything a date query might be typed as: `2026-10-03`, `3/10`,
/// `10/3`, `3.10.2026`, `oct`, `october`, `fri`, `friday`, `today`,
/// `yesterday`, the year and the day of the month.
String feedDateSearchText(DateTime? published, {DateTime? now}) {
  if (published == null) return '';
  final d = published.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final month = _monthNames[d.month - 1];
  final weekday = _weekdayNames[d.weekday - 1];
  final today = now ?? DateTime.now();
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  return [
    '${d.year}-${two(d.month)}-${two(d.day)}',
    '${d.day}/${d.month}/${d.year}',
    '${two(d.day)}/${two(d.month)}/${d.year}',
    '${d.month}/${d.day}/${d.year}',
    '${two(d.month)}/${two(d.day)}/${d.year}',
    '${d.day}.${d.month}.${d.year}',
    '${two(d.day)}.${two(d.month)}.${d.year}',
    '$month ${month.substring(0, 3)}',
    '$weekday ${weekday.substring(0, 3)}',
    if (days == 0) 'today',
    if (days == 1) 'yesterday',
  ].join(' ');
}

String _normalize(String s) => s.toLowerCase();

/// Splits on spaces and on the punctuation people put between words
/// (`-`, `/` and `.` stay: they hold dates together).
List<String> _words(String s) => _normalize(s)
    .split(RegExp(r'''[\s,;:!?|()\[\]{}"'“”‘’]+'''))
    .where((w) => w.isNotEmpty)
    .toList();

/// Optimal string alignment distance (Levenshtein plus adjacent swaps),
/// giving up once it exceeds [max].
int _editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prevPrev = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        v = math.min(v, prevPrev[j - 2] + 1);
      }
      cur[j] = v;
      rowMin = math.min(rowMin, v);
    }
    if (rowMin > max) return max + 1;
    prevPrev = prev;
    prev = cur;
  }
  return prev[b.length];
}

/// How well one query word matches [text] (0 = not at all, up to 1):
/// a word starting with it scores best, then containing it, then a typo
/// or two away from a word (or a word's start), then its letters in
/// order within one word ("lfi" → "lofi"). Numbers never match fuzzily —
/// "3" shouldn't find "4".
double fuzzyWordScore(String token, String text) {
  final t = _normalize(token);
  if (t.isEmpty) return 1;
  if (RegExp(r'\d').hasMatch(t)) {
    // Whole numbers only: "3" finds "3/10/2026" and "Top 3", not "30".
    return RegExp('(?<!\\d)${RegExp.escape(t)}(?!\\d)')
            .hasMatch(_normalize(text))
        ? 1
        : 0;
  }
  final words = _words(text);
  if (words.any((w) => w.startsWith(t))) return 1;
  if (_normalize(text).contains(t)) return 0.85;
  if (t.length < 3) return 0;

  final allowed = t.length >= 7 ? 2 : 1;
  var best = 0.0;
  for (final w in words) {
    var d = _editDistance(t, w, allowed);
    if (w.length > t.length) {
      d = math.min(d, _editDistance(t, w.substring(0, t.length), allowed));
    }
    if (d <= allowed) best = math.max(best, d == 1 ? 0.7 : 0.55);
    if (best < 0.4 && _isSubsequence(t, w)) best = 0.4;
  }
  return best;
}

bool _isSubsequence(String needle, String hay) {
  if (needle.length > hay.length) return false;
  var i = 0;
  for (var j = 0; j < hay.length && i < needle.length; j++) {
    if (hay.codeUnitAt(j) == needle.codeUnitAt(i)) i++;
  }
  // Letters spread over a much longer word are a coincidence, not a match.
  return i == needle.length && hay.length <= needle.length * 2;
}

/// How well [query] matches [video] (0 = no match). Every word of the
/// query has to match the title, the channel or the upload date (only
/// [field] when it isn't [FeedSearchField.all]); the score adds up how
/// well each did.
double feedSearchScore(FeedVideo video, String query,
    {FeedSearchField field = FeedSearchField.all, DateTime? now}) {
  final tokens = _words(query);
  if (tokens.isEmpty) return 1;
  final texts = [
    if (field == FeedSearchField.all || field == FeedSearchField.title)
      video.title,
    if (field == FeedSearchField.all || field == FeedSearchField.channel)
      video.channelName,
    if (field == FeedSearchField.all || field == FeedSearchField.date)
      feedDateSearchText(video.published, now: now),
  ];
  var total = 0.0;
  for (final token in tokens) {
    var best = 0.0;
    for (final text in texts) {
      best = math.max(best, fuzzyWordScore(token, text));
      if (best == 1) break;
    }
    if (best == 0) return 0;
    total += best;
  }
  return total / tokens.length;
}

/// The videos of [feed] matching [query], best matches first and the
/// newest first among equally good ones.
List<FeedVideo> searchFeed(List<FeedVideo> feed, String query,
    {FeedSearchField field = FeedSearchField.all, DateTime? now}) {
  if (query.trim().isEmpty) return feed;
  final scored = <(FeedVideo, double, int)>[];
  for (var i = 0; i < feed.length; i++) {
    final score = feedSearchScore(feed[i], query, field: field, now: now);
    if (score > 0) scored.add((feed[i], score, i));
  }
  scored.sort((a, b) {
    // Bucket the score so a near-tie doesn't beat a newer upload.
    final byScore = (b.$2 * 10).round().compareTo((a.$2 * 10).round());
    return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
  });
  return [for (final s in scored) s.$1];
}
