import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../models/track.dart';
import '../models/youtube_feed.dart';
import 'log_service.dart';

/// What [YoutubeFeedService.fetchChannel] got for one channel.
class ChannelFetchResult {
  const ChannelFetchResult(this.videos);
  final List<FeedVideo> videos;
}

/// Outcome of [YoutubeFeedService.importNewPipe].
class SubscriptionImportResult {
  const SubscriptionImportResult({
    required this.added,
    required this.alreadySubscribed,
    required this.skipped,
  });

  final int added;
  final int alreadySubscribed;

  /// Entries that weren't YouTube channels or couldn't be resolved.
  final int skipped;
}

/// Best Music's Subscriptions feed (SPEC.md §10.6m): the YouTube channels
/// the user follows, their latest videos, listening progress, and the
/// feed's settings — all persisted to `youtube_feed.json` in the app
/// documents dir.
///
/// Per channel, a refresh reads two things:
/// - the channel's **RSS feed** (`youtube.com/feeds/videos.xml`): the 15
///   newest uploads of every kind with exact publish times and full
///   descriptions; Shorts are linked as `/shorts/<id>`;
/// - the channel's **Videos tab** (via `youtube_explode_dart`): durations
///   and view counts, and — since livestreams live on the separate Live tab
///   — a way to tell them apart: a non-Short RSS entry missing from a
///   successfully read Videos tab is flagged [FeedVideo.isLivestream].
/// Either one failing still yields a feed: without the Videos tab nothing
/// is flagged as a livestream; without RSS the Videos tab is used alone
/// (approximate dates, descriptions fetched when a video is opened).
class YoutubeFeedService {
  YoutubeFeedService._();

  static final YoutubeFeedService instance = YoutubeFeedService._();

  final ValueNotifier<List<YoutubeChannel>> subscriptions =
      ValueNotifier(const []);

  /// Every fetched video, newest first, unfiltered — see [visibleVideos].
  final ValueNotifier<List<FeedVideo>> videos = ValueNotifier(const []);

  final ValueNotifier<YoutubeFeedSettings> settings =
      ValueNotifier(const YoutubeFeedSettings());

  final ValueNotifier<Map<String, WatchProgress>> progress =
      ValueNotifier(const {});

  final ValueNotifier<bool> refreshing = ValueNotifier(false);

  DateTime? lastRefresh;

  /// Channels whose last refresh failed, for the feed's error banner.
  final ValueNotifier<List<String>> failedChannels = ValueNotifier(const []);

  static const int _maxProgressEntries = 2000;
  static const int _parallelFetches = 6;

  bool _loaded = false;
  Future<void>? _refreshInFlight;

  @visibleForTesting
  Future<ChannelFetchResult> Function(YoutubeChannel channel)? fetchOverride;
  @visibleForTesting
  Future<List<YoutubeChannel>> Function(String query)? searchOverride;
  @visibleForTesting
  Future<YoutubeChannel?> Function(String url)? resolveChannelOverride;
  @visibleForTesting
  Future<String> Function(String videoId)? descriptionOverride;

  @visibleForTesting
  void resetForTest() {
    subscriptions.value = const [];
    videos.value = const [];
    settings.value = const YoutubeFeedSettings();
    progress.value = const {};
    refreshing.value = false;
    failedChannels.value = const [];
    lastRefresh = null;
    _loaded = false;
    _refreshInFlight = null;
    fetchOverride = null;
    searchOverride = null;
    resolveChannelOverride = null;
    descriptionOverride = null;
  }

  void _log(String message) => LogService.add('Feed', message);

  // ---------------------------------------------------------------------
  // Persistence

  Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}youtube_feed.json');
    } catch (_) {
      return null; // web / tests without a path provider
    }
  }

  /// Reads the saved state. Safe to call repeatedly; only the first call
  /// does any work.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      subscriptions.value = [
        for (final c in (json['subscriptions'] as List? ?? const []))
          if (c is Map) YoutubeChannel.fromJson(Map<String, dynamic>.from(c)),
      ];
      videos.value = [
        for (final v in (json['videos'] as List? ?? const []))
          if (v is Map) FeedVideo.fromJson(Map<String, dynamic>.from(v)),
      ];
      final s = json['settings'];
      if (s is Map) {
        settings.value =
            YoutubeFeedSettings.fromJson(Map<String, dynamic>.from(s));
      }
      final p = json['progress'];
      if (p is Map) {
        progress.value = {
          for (final e in p.entries)
            if (e.value is Map)
              e.key.toString():
                  WatchProgress.fromJson(Map<String, dynamic>.from(e.value)),
        };
      }
      final refreshed = json['lastRefresh'];
      if (refreshed is num) {
        lastRefresh = DateTime.fromMillisecondsSinceEpoch(refreshed.round());
      }
    } catch (e) {
      _log('Could not read youtube_feed.json: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      if (file == null) return;
      await file.writeAsString(
        jsonEncode({
          'subscriptions': [for (final c in subscriptions.value) c.toJson()],
          'videos': [for (final v in videos.value) v.toJson()],
          'settings': settings.value.toJson(),
          'progress': {
            for (final e in progress.value.entries) e.key: e.value.toJson(),
          },
          if (lastRefresh != null)
            'lastRefresh': lastRefresh!.millisecondsSinceEpoch,
        }),
        flush: true,
      );
    } catch (e) {
      _log('Could not save youtube_feed.json: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Settings

  Future<void> updateSettings(YoutubeFeedSettings value) async {
    settings.value = value;
    await _save();
  }

  /// The feed as shown: Shorts/livestreams dropped per [settings].
  List<FeedVideo> get visibleVideos => filterFeed(videos.value, settings.value);

  // ---------------------------------------------------------------------
  // Subscriptions

  bool isSubscribed(String channelId) =>
      subscriptions.value.any((c) => c.id == channelId);

  Future<void> subscribe(YoutubeChannel channel) async {
    if (isSubscribed(channel.id)) return;
    subscriptions.value = [...subscriptions.value, channel]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _log('Subscribed to ${channel.name} (${channel.id})');
    await _save();
    // Pull the new channel's videos in right away.
    unawaited(_refreshChannels([channel]));
  }

  Future<void> unsubscribe(String channelId) async {
    subscriptions.value =
        subscriptions.value.where((c) => c.id != channelId).toList();
    videos.value = videos.value.where((v) => v.channelId != channelId).toList();
    _log('Unsubscribed from $channelId');
    await _save();
  }

  Future<List<YoutubeChannel>> searchChannels(String query) async {
    final override = searchOverride;
    if (override != null) return override(query);
    final client = yt.YoutubeExplode();
    try {
      final results = await client.search
          .searchContent(query, filter: yt.TypeFilters.channel);
      return [
        for (final r in results)
          if (r is yt.SearchChannel)
            YoutubeChannel(
              id: r.id.value,
              name: r.name,
              avatarUrl: r.thumbnails.isEmpty
                  ? null
                  : _absoluteUrl(r.thumbnails.last.url.toString()),
            ),
      ];
    } finally {
      client.close();
    }
  }

  /// Imports a Tubular/NewPipe subscriptions export (Settings → Content →
  /// Export subscriptions — a JSON file).
  Future<SubscriptionImportResult> importNewPipe(String json) async {
    final entries = parseNewPipeSubscriptions(json);
    var added = 0, already = 0, skipped = 0;
    final current = {for (final c in subscriptions.value) c.id: c};
    for (final entry in entries) {
      YoutubeChannel? channel;
      final id = channelIdFromUrl(entry.url);
      if (id != null) {
        channel = YoutubeChannel(id: id, name: entry.name);
      } else {
        try {
          channel = await _resolveChannelUrl(entry.url);
        } catch (e) {
          _log('Import: could not resolve ${entry.url}: $e');
        }
      }
      if (channel == null) {
        skipped++;
      } else if (current.containsKey(channel.id)) {
        already++;
      } else {
        current[channel.id] = channel;
        added++;
      }
    }
    subscriptions.value = current.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _log('Imported subscriptions: $added added, $already already there, '
        '$skipped skipped');
    await _save();
    return SubscriptionImportResult(
        added: added, alreadySubscribed: already, skipped: skipped);
  }

  /// Resolves an `@handle` or `/user/` channel URL to its `UC...` id.
  Future<YoutubeChannel?> _resolveChannelUrl(String url) async {
    final override = resolveChannelOverride;
    if (override != null) return override(url);
    final handle = RegExp(r'youtube\.com/(@[^/?#]+)').firstMatch(url);
    final user = RegExp(r'youtube\.com/user/([^/?#]+)').firstMatch(url);
    if (handle == null && user == null) return null;
    final client = yt.YoutubeExplode();
    try {
      final channel = handle != null
          ? await client.channels.getByHandle(handle.group(1)!)
          : await client.channels.getByUsername(user!.group(1)!);
      return YoutubeChannel(
        id: channel.id.value,
        name: channel.title,
        avatarUrl: channel.logoUrl,
      );
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------
  // Refreshing

  /// Re-fetches every subscribed channel. Concurrent calls share one run.
  Future<void> refresh() =>
      _refreshInFlight ??= _refreshChannels(subscriptions.value, all: true)
          .whenComplete(() => _refreshInFlight = null);

  Future<void> _refreshChannels(
    List<YoutubeChannel> channels, {
    bool all = false,
  }) async {
    if (channels.isEmpty) return;
    refreshing.value = true;
    final fetched = <String, List<FeedVideo>>{};
    final failed = <String>[];
    try {
      var next = 0;
      Future<void> worker() async {
        while (next < channels.length) {
          final channel = channels[next++];
          try {
            fetched[channel.id] = (await fetchChannel(channel)).videos;
          } catch (e) {
            failed.add(channel.name);
            _log('Refreshing ${channel.name} failed: $e');
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < _parallelFetches && i < channels.length; i++)
          worker(),
      ]);
      // Keep what was cached for a channel that failed this time, and
      // anything already known about a video (a description fetched on
      // demand) that this fetch didn't include.
      final previous = {for (final v in videos.value) v.videoId: v};
      final merged = <FeedVideo>[
        for (final v in videos.value)
          if (!fetched.containsKey(v.channelId) &&
              isSubscribed(v.channelId))
            v,
        for (final list in fetched.values)
          for (final v in list)
            v.description.isEmpty && previous[v.videoId] != null
                ? v.copyWith(description: previous[v.videoId]!.description)
                : v,
      ]..sort(_newestFirst);
      videos.value = merged;
      if (all) {
        lastRefresh = DateTime.now();
        failedChannels.value = failed;
      }
      _log('Refreshed ${fetched.length}/${channels.length} channel(s), '
          '${merged.length} video(s) in the feed');
      await _save();
    } finally {
      refreshing.value = false;
    }
  }

  static int _newestFirst(FeedVideo a, FeedVideo b) {
    final pa = a.published, pb = b.published;
    if (pa == null && pb == null) return 0;
    if (pa == null) return 1;
    if (pb == null) return -1;
    return pb.compareTo(pa);
  }

  /// Fetches one channel's latest videos (RSS + Videos tab, see the class
  /// doc). Throws only when both sources fail.
  Future<ChannelFetchResult> fetchChannel(YoutubeChannel channel) async {
    final override = fetchOverride;
    if (override != null) return override(channel);

    List<FeedVideo>? rss;
    Object? rssError;
    try {
      final response = await http
          .get(Uri.parse(
              'https://www.youtube.com/feeds/videos.xml?channel_id=${channel.id}'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('RSS feed answered HTTP ${response.statusCode}');
      }
      rss = parseYoutubeRss(utf8.decode(response.bodyBytes),
          channelId: channel.id, channelName: channel.name);
    } catch (e) {
      rssError = e;
    }

    List<yt.Video>? tab;
    final client = yt.YoutubeExplode();
    try {
      tab = (await client.channels.getUploadsFromPage(channel.id)
              .timeout(const Duration(seconds: 30)))
          .toList();
      if (tab.isEmpty) tab = null; // unreadable page, not an empty channel
    } catch (e) {
      if (rss == null) {
        throw Exception('RSS: $rssError; Videos tab: $e');
      }
    } finally {
      client.close();
    }

    if (rss == null) {
      return ChannelFetchResult([
        for (final v in tab!)
          FeedVideo(
            videoId: v.id.value,
            title: v.title,
            channelId: channel.id,
            channelName: channel.name,
            published: v.uploadDate,
            duration: v.duration,
            viewCount: v.engagement.viewCount,
          ),
      ]);
    }
    return ChannelFetchResult(mergeVideosTab(rss, tab == null
        ? null
        : {
            for (final v in tab)
              v.id.value: (duration: v.duration, views: v.engagement.viewCount),
          }));
  }

  /// The full description of a video the feed only has a stub for.
  Future<String> fetchDescription(String videoId) async {
    final override = descriptionOverride;
    final description = override != null
        ? await override(videoId)
        : await () async {
            final client = yt.YoutubeExplode();
            try {
              return (await client.videos.get(videoId)).description;
            } finally {
              client.close();
            }
          }();
    videos.value = [
      for (final v in videos.value)
        v.videoId == videoId ? v.copyWith(description: description) : v,
    ];
    unawaited(_save());
    return description;
  }

  // ---------------------------------------------------------------------
  // Listening progress

  WatchProgress? progressFor(String videoId) => progress.value[videoId];

  bool isPlayed(String videoId) => progress.value[videoId]?.completed ?? false;

  /// Where to resume [videoId]: null to start from the top (never played,
  /// played to the end, or only the first few seconds heard).
  Duration? resumePosition(String videoId) {
    final p = progress.value[videoId];
    if (p == null || p.completed || p.position.inSeconds < 10) return null;
    return p.position - const Duration(seconds: 3);
  }

  /// Called by `MusicAudioHandler` while a feed video plays. Within the
  /// last 30 s (or 5 %) counts as played, like podcast apps do, so an
  /// outro/end screen nobody waits for doesn't leave it "in progress".
  Future<void> recordProgress(
    String videoId,
    Duration position, {
    Duration? duration,
  }) async {
    final previous = progress.value[videoId];
    final total = duration ?? previous?.duration;
    var completed = previous?.completed ?? false;
    if (total != null && total > Duration.zero) {
      final remaining = total - position;
      if (remaining <= const Duration(seconds: 30) ||
          position.inMilliseconds >= total.inMilliseconds * 0.95) {
        completed = true;
      }
    }
    _setProgress(videoId, WatchProgress(
      position: position,
      duration: total,
      completed: completed,
      updated: DateTime.now(),
    ));
    await _save();
  }

  /// Marks [videoId] played (or back to unplayed, which also forgets the
  /// resume position).
  Future<void> setPlayed(String videoId, bool played) async {
    if (played) {
      final previous = progress.value[videoId];
      _setProgress(videoId, WatchProgress(
        position: previous?.duration ?? previous?.position ?? Duration.zero,
        duration: previous?.duration,
        completed: true,
        updated: DateTime.now(),
      ));
    } else {
      progress.value = Map.of(progress.value)..remove(videoId);
    }
    await _save();
  }

  void _setProgress(String videoId, WatchProgress value) {
    final updated = Map.of(progress.value)..[videoId] = value;
    if (updated.length > _maxProgressEntries) {
      final oldest = updated.entries.toList()
        ..sort((a, b) => a.value.updated.compareTo(b.value.updated));
      for (final e in oldest.take(updated.length - _maxProgressEntries)) {
        updated.remove(e.key);
      }
    }
    progress.value = updated;
  }

  // ---------------------------------------------------------------------
  // Playback

  /// The play queue for tapping [videos]`[index]`: that video, then the
  /// rest of the list below it that hasn't been played yet — so tapping
  /// the newest unheard upload keeps going through the backlog.
  List<Track> queueFrom(List<FeedVideo> videos, int index) => [
        trackFor(videos[index]),
        for (final v in videos.skip(index + 1).take(50))
          if (!isPlayed(v.videoId)) trackFor(v),
      ];

  static Track trackFor(FeedVideo v) => Track.youtube(
        videoId: v.videoId,
        title: v.title,
        artist: v.channelName,
        durationMs: v.duration?.inMilliseconds,
        artUrl: v.largeThumbnailUrl,
      );
}

String _absoluteUrl(String url) => url.startsWith('//') ? 'https:$url' : url;

/// Drops Shorts/livestreams per [settings].
List<FeedVideo> filterFeed(List<FeedVideo> all, YoutubeFeedSettings settings) =>
    [
      for (final v in all)
        if (!(settings.hideShorts && v.isShort) &&
            !(settings.hideLivestreams && v.isLivestream))
          v,
    ];

/// Annotates RSS entries with what the channel's Videos tab knows
/// ([tab]: video id → duration/views; null when the tab couldn't be read).
/// A non-Short entry missing from a readable tab is a livestream.
List<FeedVideo> mergeVideosTab(
  List<FeedVideo> rss,
  Map<String, ({Duration? duration, int views})>? tab,
) {
  if (tab == null) return rss;
  return [
    for (final v in rss)
      if (tab[v.videoId] case final info?)
        v.copyWith(
          duration: info.duration == Duration.zero ? null : info.duration,
          viewCount: info.views,
        )
      else
        FeedVideo(
          videoId: v.videoId,
          title: v.title,
          channelId: v.channelId,
          channelName: v.channelName,
          published: v.published,
          description: v.description,
          duration: v.duration,
          viewCount: v.viewCount,
          isShort: v.isShort,
          isLivestream: !v.isShort,
        ),
  ];
}

/// Parses a channel's `youtube.com/feeds/videos.xml` Atom feed.
List<FeedVideo> parseYoutubeRss(
  String body, {
  required String channelId,
  required String channelName,
}) {
  final doc = XmlDocument.parse(body);
  XmlElement? child(XmlElement parent, String local) {
    for (final e in parent.childElements) {
      if (e.name.local == local) return e;
    }
    return null;
  }

  final feedTitle = child(doc.rootElement, 'title')?.innerText.trim();
  final result = <FeedVideo>[];
  for (final entry
      in doc.rootElement.childElements.where((e) => e.name.local == 'entry')) {
    final id = child(entry, 'videoId')?.innerText.trim() ?? '';
    if (id.isEmpty) continue;
    final link = child(entry, 'link')?.getAttribute('href') ?? '';
    final group = child(entry, 'group');
    final community = group == null ? null : child(group, 'community');
    final stats = community == null ? null : child(community, 'statistics');
    result.add(FeedVideo(
      videoId: id,
      title: child(entry, 'title')?.innerText.trim() ?? '',
      channelId: channelId,
      channelName: (feedTitle?.isNotEmpty ?? false) ? feedTitle! : channelName,
      published: DateTime.tryParse(
          child(entry, 'published')?.innerText.trim() ?? ''),
      description: group == null
          ? ''
          : child(group, 'description')?.innerText.trim() ?? '',
      viewCount: int.tryParse(stats?.getAttribute('views') ?? ''),
      isShort: link.contains('/shorts/'),
    ));
  }
  return result;
}

/// The `UC...` id in a `youtube.com/channel/UC...` URL, else null.
String? channelIdFromUrl(String url) =>
    RegExp(r'youtube\.com/channel/(UC[A-Za-z0-9_-]{22})')
        .firstMatch(url)
        ?.group(1);

/// Reads a Tubular/NewPipe subscriptions export:
/// `{"subscriptions": [{"service_id": 0, "url": ..., "name": ...}]}`.
/// Only YouTube entries (service 0) are returned.
List<({String url, String name})> parseNewPipeSubscriptions(String body) {
  final json = jsonDecode(body);
  final list = json is Map ? json['subscriptions'] : null;
  if (list is! List) {
    throw const FormatException(
        'Not a Tubular/NewPipe subscriptions export (no "subscriptions" list)');
  }
  return [
    for (final e in list.whereType<Map>())
      if ((e['service_id'] ?? 0) == 0 && e['url'] is String)
        (url: e['url'] as String, name: (e['name'] ?? '').toString()),
  ];
}
