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
import 'youtube_channel_videos_api.dart';

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

  /// How far the running refresh is, `[0, 1]` by channels fetched.
  final ValueNotifier<double> refreshProgress = ValueNotifier(0);

  DateTime? lastRefresh;

  /// How far back the feed shows: [initialWindow] when the feed opens (so
  /// the newest videos are up at once), widened to [backgroundWindow] once
  /// the refresh finishes, then by [windowStep] each time the list is
  /// scrolled to its end ([showOlder]).
  final ValueNotifier<Duration> window = ValueNotifier(backgroundWindow);
  static const Duration initialWindow = Duration(days: 2);
  static const Duration backgroundWindow = Duration(days: 7);
  static const Duration windowStep = Duration(days: 7);

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

  /// Stands in for one video's own page in [fillMissingDetails].
  @visibleForTesting
  Future<VideoDetails?> Function(String videoId)? detailsOverride;

  /// Videos [fillMissingDetails] already looked up this run of the app, so
  /// a video whose page has no duration (a premiere) isn't asked again.
  final Set<String> _detailsTried = {};
  Future<void>? _detailsInFlight;

  /// How many videos one [fillMissingDetails] pass looks up at most.
  static const int maxDetailLookups = 15;

  @visibleForTesting
  void resetForTest() {
    subscriptions.value = const [];
    videos.value = const [];
    settings.value = const YoutubeFeedSettings();
    progress.value = const {};
    refreshing.value = false;
    window.value = backgroundWindow;
    failedChannels.value = const [];
    lastRefresh = null;
    _loaded = false;
    _refreshInFlight = null;
    fetchOverride = null;
    searchOverride = null;
    resolveChannelOverride = null;
    descriptionOverride = null;
    detailsOverride = null;
    _detailsTried.clear();
    _detailsInFlight = null;
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

  /// The feed as shown: Shorts/livestreams dropped per [settings], newest
  /// first, limited to [window].
  List<FeedVideo> get visibleVideos =>
      windowFeed(filterFeed(videos.value, settings.value), window.value);

  /// Whether there are (filtered) videos older than [window] to show.
  bool get hasOlderVideos {
    final all = filterFeed(videos.value, settings.value);
    return windowFeed(all, window.value).length < all.length;
  }

  /// Opening the feed: start with just the last [initialWindow].
  void startSession() => window.value = initialWindow;

  /// The background step after the first screenful: up to
  /// [backgroundWindow].
  void widenToBackgroundWindow() {
    if (window.value < backgroundWindow) window.value = backgroundWindow;
  }

  /// Scrolled to the end: show another [windowStep] of older videos — or,
  /// across a quiet stretch, at least as far back as the next older video,
  /// so each step always shows something new.
  void showOlder() {
    final cutoff = DateTime.now().subtract(window.value);
    DateTime? nextOlder;
    for (final v in filterFeed(videos.value, settings.value)) {
      final p = v.published;
      if (p != null && p.isBefore(cutoff) &&
          (nextOlder == null || p.isAfter(nextOlder))) {
        nextOlder = p;
      }
    }
    if (nextOlder == null) {
      if (hasOlderVideos) window.value += windowStep; // undated only
      return;
    }
    final reach = DateTime.now().difference(nextOlder) +
        const Duration(minutes: 1);
    final stepped = window.value + windowStep;
    window.value = reach > stepped ? reach : stepped;
  }

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

  /// Channels matching [query]. A pasted channel URL or `@handle` resolves
  /// to that one channel instead of searching.
  ///
  /// Doesn't use `youtube_explode_dart`'s `searchContent`: its 3.1.0 channel
  /// parser calls the `getT` extension on a `dynamic` value
  /// (`videoCountText/runs.first`), which throws `NoSuchMethodError: ...
  /// '_Map<String, dynamic>' has no instance method 'getT'` for every
  /// channel YouTube now returns with a video count — i.e. all of them.
  /// Instead this posts to InnerTube's `search` endpoint with the
  /// channels-only filter and reads the results with
  /// [parseChannelSearchResults].
  Future<List<YoutubeChannel>> searchChannels(String query) async {
    final override = searchOverride;
    if (override != null) return override(query);
    final trimmed = query.trim();
    final directId = channelIdFromUrl(trimmed);
    if (directId != null) {
      final client = yt.YoutubeExplode();
      try {
        final channel = await client.channels.get(directId);
        return [
          YoutubeChannel(
              id: directId, name: channel.title, avatarUrl: channel.logoUrl),
        ];
      } finally {
        client.close();
      }
    }
    if (RegExp(r'^@[\w.-]+$').hasMatch(trimmed) ||
        RegExp(r'youtube\.com/(@|user/)').hasMatch(trimmed)) {
      final url = trimmed.startsWith('@')
          ? 'https://www.youtube.com/$trimmed'
          : trimmed;
      final channel = await _resolveChannelUrl(url);
      return channel == null ? const [] : [channel];
    }
    final http = yt.YoutubeHttpClient();
    try {
      final response = await http.sendPost('search', {
        'query': trimmed,
        // TypeFilters.channel's `sp` value, base64-decoded for a JSON body.
        'params': 'EgIQAg==',
      });
      final channels = parseChannelSearchResults(response);
      _log('Channel search "$trimmed": ${channels.length} result(s)');
      return channels;
    } catch (e) {
      _log('Channel search "$trimmed" failed: $e');
      rethrow;
    } finally {
      http.close();
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
    refreshProgress.value = 0;
    final fetched = <String, List<FeedVideo>>{};
    final failed = <String>[];
    try {
      var next = 0;
      var done = 0;
      Future<void> worker() async {
        while (next < channels.length) {
          final channel = channels[next++];
          try {
            fetched[channel.id] = (await fetchChannel(channel)).videos;
            // Show each channel's videos as soon as they arrive rather
            // than after the slowest channel.
            videos.value = _merged(fetched);
          } catch (e) {
            failed.add(channel.name);
            _log('Refreshing ${channel.name} failed: $e');
          }
          refreshProgress.value = ++done / channels.length;
        }
      }

      await Future.wait([
        for (var i = 0; i < _parallelFetches && i < channels.length; i++)
          worker(),
      ]);
      final merged = _merged(fetched);
      videos.value = merged;
      if (all) {
        lastRefresh = DateTime.now();
        failedChannels.value = failed;
      }
      _log('Refreshed ${fetched.length}/${channels.length} channel(s), '
          '${merged.length} video(s) in the feed');
      await _save();
      // Whatever the channel pages left out (duration, views, an exact
      // upload time) comes from each video's own page, newest first.
      unawaited(fillMissingDetails());
    } finally {
      refreshing.value = false;
    }
  }

  /// [videos] with each channel in [fetched] replaced by its fresh list,
  /// newest first. Keeps what was cached for a channel not (yet) fetched or
  /// that failed, and anything already known about a video (a description
  /// fetched on demand) that this fetch didn't include.
  List<FeedVideo> _merged(Map<String, List<FeedVideo>> fetched) {
    final previous = {for (final v in videos.value) v.videoId: v};
    return <FeedVideo>[
      for (final v in videos.value)
        if (!fetched.containsKey(v.channelId) && isSubscribed(v.channelId)) v,
      for (final list in fetched.values)
        for (final v in list) keepKnownDetails(v, previous[v.videoId]),
    ]..sort(_newestFirst);
  }

  /// One video's details fetched or looked up again ([fresh]) on top of
  /// what was already known ([known]): a fetch that missed the duration,
  /// views, description or exact upload time never erases them.
  @visibleForTesting
  static FeedVideo keepKnownDetails(FeedVideo fresh, FeedVideo? known) {
    if (known == null) return fresh;
    final keepDate = known.published != null &&
        (fresh.published == null ||
            (fresh.publishedApprox && !known.publishedApprox));
    return fresh.copyWith(
      description: fresh.description.isEmpty ? known.description : null,
      duration: fresh.duration ?? known.duration,
      viewCount: fresh.viewCount ?? known.viewCount,
      published: keepDate ? known.published : null,
      publishedApprox: keepDate ? known.publishedApprox : null,
      // Once a video's own page showed its length it isn't a livestream.
      isLivestream: fresh.isLivestream && fresh.duration == null &&
          known.duration != null && !known.isLivestream
          ? false
          : null,
    );
  }

  /// Looks up, on each video's own page, what the channel pages didn't
  /// give for the newest feed videos: duration, views, an exact upload
  /// time. At most [maxDetailLookups] per pass, each video once per app
  /// run; concurrent calls share one pass.
  Future<void> fillMissingDetails() =>
      _detailsInFlight ??= _fillMissingDetails()
          .whenComplete(() => _detailsInFlight = null);

  Future<void> _fillMissingDetails() async {
    // Tests that fake the channel fetch never reach the network here.
    if (fetchOverride != null && detailsOverride == null) return;
    final todo = [
      for (final v in filterFeed(videos.value, settings.value))
        if (!v.isShort &&
            !_detailsTried.contains(v.videoId) &&
            (v.duration == null ||
                v.viewCount == null ||
                v.published == null ||
                v.publishedApprox))
          v,
    ].take(maxDetailLookups).toList();
    if (todo.isEmpty) return;
    var next = 0;
    var filled = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final id = todo[next++].videoId;
        _detailsTried.add(id);
        try {
          final d = await (detailsOverride ?? _fetchDetails)(id);
          if (d == null) continue;
          filled++;
          videos.value = [
            for (final v in videos.value)
              v.videoId == id
                  ? v.copyWith(
                      duration: d.duration,
                      viewCount: d.views,
                      published: d.published,
                      publishedApprox: d.published != null ? false : null,
                      isLivestream:
                          d.duration != null ? false : null,
                    )
                  : v,
          ];
        } catch (e) {
          _log('Looking up video $id failed: $e');
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    if (filled > 0) {
      _log('Filled in details for $filled video(s)');
      await _save();
    }
  }

  static Future<VideoDetails?> _fetchDetails(String videoId) async {
    final client = yt.YoutubeExplode();
    try {
      final v = await client.videos
          .get(videoId)
          .timeout(const Duration(seconds: 20));
      final duration = v.duration;
      final views = v.engagement.viewCount;
      return VideoDetails(
        duration:
            duration == null || duration == Duration.zero ? null : duration,
        views: views > 0 ? views : null,
        published: v.uploadDate ?? v.publishDate,
      );
    } finally {
      client.close();
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

    // The Videos tab: YouTube's JSON API first; youtube_explode's page
    // scraper only as a fallback (its parser misses the duration and views
    // on YouTube's newer video cards, so its zeros count as "unknown").
    List<ChannelTabVideo>? tab;
    Map<String, String>? tabTitles;
    Object? tabError;
    try {
      tab = await YoutubeChannelVideosApi.fetch(channel.id);
      if (tab.isEmpty) tab = null; // unreadable page, not an empty channel
    } catch (e) {
      tabError = e;
    }
    if (tab == null) {
      final client = yt.YoutubeExplode();
      try {
        final page = (await client.channels
                .getUploadsFromPage(channel.id)
                .timeout(const Duration(seconds: 30)))
            .toList();
        if (page.isNotEmpty) {
          tab = [
            for (final v in page)
              ChannelTabVideo(
                videoId: v.id.value,
                duration: v.duration == null || v.duration == Duration.zero
                    ? null
                    : v.duration,
                views: v.engagement.viewCount > 0
                    ? v.engagement.viewCount
                    : null,
                published: v.uploadDate,
              ),
          ];
          tabTitles = {for (final v in page) v.id.value: v.title};
        }
      } catch (e) {
        tabError = '$tabError; $e';
      } finally {
        client.close();
      }
    }
    if (rss == null && tab == null) {
      throw Exception('RSS: $rssError; Videos tab: $tabError');
    }

    if (rss == null) {
      // Titles only come with youtube_explode's page; without RSS or that,
      // the JSON tab alone isn't enough to list videos.
      if (tabTitles == null) {
        throw Exception('RSS: $rssError; Videos tab has no titles');
      }
      return ChannelFetchResult([
        for (final v in tab!)
          FeedVideo(
            videoId: v.videoId,
            title: tabTitles[v.videoId] ?? '',
            channelId: channel.id,
            channelName: channel.name,
            published: v.published,
            publishedApprox: v.published != null,
            duration: v.duration,
            viewCount: v.views,
          ),
      ]);
    }
    return ChannelFetchResult(mergeVideosTab(rss, tab == null
        ? null
        : {
            for (final v in tab)
              v.videoId: (duration: v.duration, views: v.views),
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

  /// The play queue for tapping [videos]`[index]`: just that video —
  /// unless [YoutubeFeedSettings.autoplayNext] is on, then also the rest of
  /// the list below it that hasn't been played yet, to keep going through
  /// the backlog.
  List<Track> queueFrom(List<FeedVideo> videos, int index) => [
        trackFor(videos[index]),
        if (settings.value.autoplayNext)
          for (final v in videos.skip(index + 1).take(50))
            if (!isPlayed(v.videoId)) trackFor(v),
      ];

  /// The most recently played feed video still in the feed, for switching
  /// to videos when no video session is remembered yet.
  FeedVideo? lastPlayedVideo() {
    final byId = {for (final v in videos.value) v.videoId: v};
    final entries = progress.value.entries
        .where((e) => byId.containsKey(e.key))
        .toList()
      ..sort((a, b) => b.value.updated.compareTo(a.value.updated));
    return entries.isEmpty ? null : byId[entries.first.key];
  }

  static Track trackFor(FeedVideo v) => Track.youtube(
        videoId: v.videoId,
        title: v.title,
        artist: v.channelName,
        durationMs: v.duration?.inMilliseconds,
        artUrl: v.largeThumbnailUrl,
      );
}

String _absoluteUrl(String url) => url.startsWith('//') ? 'https:$url' : url;

/// Every `channelRenderer` anywhere in an InnerTube `search` response, in
/// order, deduplicated. Walks the whole tree rather than one fixed path
/// (`contents/twoColumnSearchResultsRenderer/.../itemSectionRenderer`)
/// so a reshuffled layout still yields results; every field is read
/// defensively and a renderer without an id or name is skipped.
List<YoutubeChannel> parseChannelSearchResults(Object? response) {
  final channels = <YoutubeChannel>[];
  final seen = <String>{};

  String? text(Object? node) {
    if (node is! Map) return null;
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .whereType<Map>()
          .map((r) => r['text'])
          .whereType<String>()
          .join();
    }
    return null;
  }

  void visit(Object? node) {
    if (node is List) {
      for (final child in node) {
        visit(child);
      }
      return;
    }
    if (node is! Map) return;
    final renderer = node['channelRenderer'];
    if (renderer is Map) {
      final id = renderer['channelId'];
      final name = text(renderer['title'])?.trim();
      if (id is String &&
          id.startsWith('UC') &&
          name != null &&
          name.isNotEmpty &&
          seen.add(id)) {
        final thumbs = (renderer['thumbnail'] is Map
                ? (renderer['thumbnail'] as Map)['thumbnails']
                : null) ??
            const [];
        String? avatar;
        if (thumbs is List && thumbs.isNotEmpty && thumbs.last is Map) {
          final url = (thumbs.last as Map)['url'];
          if (url is String && url.isNotEmpty) avatar = _absoluteUrl(url);
        }
        channels.add(YoutubeChannel(id: id, name: name, avatarUrl: avatar));
      }
    }
    for (final value in node.values) {
      visit(value);
    }
  }

  visit(response);
  return channels;
}

/// Drops Shorts/livestreams per [settings].
/// The part of [all] (newest first) published within [window] of [now].
/// Undated videos sort last and only show once nothing dated is hidden.
List<FeedVideo> windowFeed(List<FeedVideo> all, Duration window,
    {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(window);
  final dated = [
    for (final v in all)
      if (v.published != null && !v.published!.isBefore(cutoff)) v,
  ];
  final olderDated =
      all.any((v) => v.published != null && v.published!.isBefore(cutoff));
  return [
    ...dated,
    if (!olderDated)
      for (final v in all)
        if (v.published == null) v,
  ];
}

List<FeedVideo> filterFeed(List<FeedVideo> all, YoutubeFeedSettings settings) =>
    [
      for (final v in all)
        if (!(settings.hideShorts && v.isShort) &&
            !(settings.hideLivestreams && v.isLivestream))
          v,
    ];

/// Annotates RSS entries with what the channel's Videos tab knows
/// ([tab]: video id → duration/views; null when the tab couldn't be read).
/// A non-Short entry missing from a readable tab is a livestream. Views:
/// the higher of the two — RSS counts are exact but can lag, the tab's
/// are rounded ("1.2K"); a missing count never erases the other.
List<FeedVideo> mergeVideosTab(
  List<FeedVideo> rss,
  Map<String, ({Duration? duration, int? views})>? tab,
) {
  if (tab == null) return rss;
  return [
    for (final v in rss)
      if (tab[v.videoId] case final info?)
        v.copyWith(
          duration: info.duration == Duration.zero ? null : info.duration,
          viewCount: switch ((v.viewCount, info.views)) {
            (final a?, final b?) => a > b ? a : b,
            (final a, final b) => a ?? b,
          },
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

/// What a video's own page says ([YoutubeFeedService.fillMissingDetails]).
class VideoDetails {
  const VideoDetails({this.duration, this.views, this.published});

  final Duration? duration;
  final int? views;

  /// Exact upload time.
  final DateTime? published;
}
