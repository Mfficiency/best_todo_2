/// Splits an artist credit like "49th & Main feat. SKYLAR" into the main
/// act ("49th & Main") and who's featured on it ("SKYLAR"), so the Artists
/// tab can group by the act that actually released a track instead of
/// treating every "X feat. Y" combination as a separate artist. Recognizes
/// "feat.", "feat", "ft.", "ft" and "featuring" (case-insensitive) as the
/// separator; a credit with none of those returns an empty [featuring].
class ArtistCredit {
  const ArtistCredit(this.mainArtist, this.featuring);

  final String mainArtist;
  final String featuring;
}

final RegExp _featuringSeparator =
    RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+', caseSensitive: false);

ArtistCredit splitArtistCredit(String artist) {
  final trimmed = artist.trim();
  final match = _featuringSeparator.firstMatch(trimmed);
  if (match == null) return ArtistCredit(trimmed, '');
  return ArtistCredit(
    trimmed.substring(0, match.start).trim(),
    trimmed.substring(match.end).trim(),
  );
}
