/// Turns a raw YouTube video title (and its channel name) into the
/// artist/title pair a downloaded track should be filed and tagged under.
///
/// YouTube upload titles are inconsistent — "Artist - Title", "Title
/// (Official Video)", "Title [Lyrics]" — so this splits on the first
/// `Artist - Title` separator when present, falls back to the channel name
/// as the artist otherwise (stripping the "- Topic" suffix YouTube Music's
/// auto-generated artist channels carry), and strips promotional
/// annotations like "(Official Video)" or "(Lyrics)" from both.
class TrackTitleParts {
  const TrackTitleParts({required this.artist, required this.title});

  final String artist;
  final String title;

  /// The name to save the file under (without extension): "Artist - Title",
  /// or just the title when no artist could be worked out.
  String get fileBaseName => artist.isEmpty ? title : '$artist - $title';
}

/// Words that show up inside a `(...)`/`[...]` annotation on a YouTube music
/// upload without adding anything worth keeping once the track is saved
/// locally. An annotation is dropped only when *every* word inside it is
/// one of these, so "(Official Video)", "(Lyrics)", "(Official Music
/// Video)" and "(HD)" all go, but "(Live at Wembley)" or "(feat. Someone)"
/// are left alone.
const Set<String> _junkAnnotationWords = {
  'official',
  'video',
  'audio',
  'lyric',
  'lyrics',
  'music',
  'mv',
  'visualizer',
  'visualiser',
  'original',
  'mix',
  'edit',
  'version',
  'remaster',
  'remastered',
  'explicit',
  'clean',
  'full',
  'only',
  'hd',
  'hq',
  '4k',
  'oficial',
  'clip',
  'stereo',
  'mono',
  'high',
  'quality',
  'topic',
};

bool _isJunkAnnotation(String inner) {
  final words = inner
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return true; // e.g. an empty "()" left behind
  return words.every(_junkAnnotationWords.contains);
}

final RegExp _annotationPattern = RegExp(r'\(([^()]*)\)|\[([^\[\]]*)\]');

String _stripJunkAnnotations(String input) {
  var result = input.replaceAllMapped(_annotationPattern, (m) {
    final inner = m.group(1) ?? m.group(2) ?? '';
    return _isJunkAnnotation(inner) ? '' : m.group(0)!;
  });
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  // An annotation removed from the end can leave a dangling separator
  // behind, e.g. "Song -" or "Song |".
  result = result.replaceAll(RegExp(r'[\s\-–—|:]+$'), '').trim();
  return result;
}

final RegExp _artistTitleSplit = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$');

final RegExp _topicChannelSuffix =
    RegExp(r'\s*-\s*Topic$', caseSensitive: false);

/// Splits [rawTitle] into artist/title, using [channel] as a fallback
/// artist when the title itself has no `Artist - Title` separator.
TrackTitleParts parseTrackTitle(String rawTitle, String channel) {
  var title = _stripJunkAnnotations(rawTitle);
  if (title.isEmpty) title = rawTitle.trim();
  if (title.isEmpty) title = 'audio';

  var artist = _stripJunkAnnotations(
    channel.replaceAll(_topicChannelSuffix, ''),
  );

  final match = _artistTitleSplit.firstMatch(title);
  if (match != null) {
    final left = match.group(1)!.trim();
    final right = match.group(2)!.trim();
    if (left.isNotEmpty && right.isNotEmpty) {
      artist = left;
      title = right;
    }
  }

  return TrackTitleParts(artist: artist, title: title);
}

/// Builds the filename (without extension) a downloaded track should be
/// saved under: `Artist - Title`, cleaned of promotional annotations like
/// "(Official Video)" or "(Lyrics)".
String formatTrackFileBaseName(String rawTitle, String channel) =>
    parseTrackTitle(rawTitle, channel).fileBaseName;
