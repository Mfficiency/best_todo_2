import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/feed_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Subscriptions feed's fuzzy search (SPEC.md §10.6m): title, channel
/// and upload date, typo-tolerant.
void main() {
  final now = DateTime(2026, 10, 4, 12); // a Sunday

  FeedVideo video(String id, String title, String channel, DateTime published) =>
      FeedVideo(
        videoId: id,
        title: title,
        channelId: 'UC$id',
        channelName: channel,
        published: published,
      );

  final lofi = video('a', 'Lofi beats to study to', 'Chillhop Music',
      DateTime(2026, 10, 3, 9)); // Saturday, yesterday
  final jazz = video('b', 'Late night jazz session', 'Jazz Cafe',
      DateTime(2026, 9, 30, 18)); // Wednesday
  final talk = video('c', 'Top 3 podcasts of 2025', 'Talk Show',
      DateTime(2026, 8, 13, 10));
  final feed = [lofi, jazz, talk];

  List<String> ids(String query, [FeedSearchField field = FeedSearchField.all]) =>
      [for (final v in searchFeed(feed, query, field: field, now: now)) v.videoId];

  test('an empty query keeps the whole feed in order', () {
    expect(ids('  '), ['a', 'b', 'c']);
  });

  test('matches title words, prefixes and typos', () {
    expect(ids('lofi'), ['a']);
    expect(ids('stu'), ['a']);
    expect(ids('jaz sesion'), ['b']);
    expect(ids('podcsats'), ['c']); // swapped letters
    expect(ids('nothing like this'), isEmpty);
  });

  test('matches the channel', () {
    expect(ids('chillhop'), ['a']);
    expect(ids('jazz cafe', FeedSearchField.channel), ['b']);
    expect(ids('lofi', FeedSearchField.channel), isEmpty);
  });

  test('matches the upload date in the usual spellings', () {
    expect(ids('yesterday'), ['a']);
    expect(ids('2026-09-30'), ['b']);
    expect(ids('30/9'), ['b']);
    expect(ids('9/30'), ['b']);
    expect(ids('wednesday'), ['b']);
    expect(ids('aug 13'), ['c']);
    expect(ids('october', FeedSearchField.date), ['a']);
    expect(ids('septmber'), ['b']); // typo in the month
  });

  test('numbers match whole numbers only', () {
    expect(ids('3', FeedSearchField.title), ['c']);
    expect(ids('30', FeedSearchField.date), ['b']);
    expect(ids('3', FeedSearchField.date), ['a']); // 3 Oct, not 30 Sep or 13 Aug
  });

  test('every word must match something; better matches come first', () {
    expect(ids('jazz october'), isEmpty);
    expect(ids('jazz september'), ['b']);
    final ranked = searchFeed([jazz, lofi], 'lofi', now: now);
    expect(ranked.first.videoId, 'a');
  });

  test('fuzzyWordScore ranks exact above fuzzy', () {
    expect(fuzzyWordScore('beats', 'Lofi beats'), 1);
    expect(fuzzyWordScore('eats', 'Lofi beats'), lessThan(1));
    expect(fuzzyWordScore('baets', 'Lofi beats'), greaterThan(0));
    expect(fuzzyWordScore('xyzzy', 'Lofi beats'), 0);
  });
}
