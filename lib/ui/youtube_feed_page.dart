import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/track.dart';
import '../models/youtube_feed.dart';
import '../services/feed_search.dart';
import '../services/mp3_downloader_service.dart'
    show Mp3SearchResult, formatViewCount;
import '../services/music_player_service.dart';
import '../services/youtube_search_api.dart';
import '../services/youtube_feed_service.dart';
import '../utils/linkified_text.dart';
import 'mp3_downloader_page.dart';
import 'estimated_progress_bar.dart';
import 'subpage_app_bar.dart';
import 'video_transcript_page.dart';
import 'youtube_channels_page.dart';

/// "3h ago" / "2d ago" / "5w ago" — compact enough for a phone row.
String formatFeedAge(DateTime? published, {DateTime? now}) {
  if (published == null) return '';
  final age = (now ?? DateTime.now()).difference(published);
  if (age.inMinutes < 60) return '${age.inMinutes.clamp(0, 59)}m ago';
  if (age.inHours < 24) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  if (age.inDays < 30) return '${age.inDays ~/ 7}w ago';
  if (age.inDays < 365) return '${age.inDays ~/ 30}mo ago';
  return '${age.inDays ~/ 365}y ago';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// When a video went up, in local time: "Today 14:05", "Yesterday 09:12",
/// "Mon 18:30" within the week, "3 Oct, 14:05" this year, "3 Oct 2025"
/// before that. Empty when unknown. [approx] (a date read off "3 days
/// ago") leaves the clock time out: "Today", "Mon", "3 Oct".
String formatFeedUploadTime(DateTime? published,
    {DateTime? now, bool approx = false}) {
  if (published == null) return '';
  final at = published.toLocal();
  final today = now ?? DateTime.now();
  final hhmm = approx
      ? ''
      : ' ${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'Today$hhmm';
  if (days == 1) return 'Yesterday$hhmm';
  if (days < 7) return '${_weekdays[at.weekday - 1]}$hhmm';
  final date = '${at.day} ${_months[at.month - 1]}';
  if (at.year == today.year) return approx ? date : '$date,$hhmm';
  return '$date ${at.year}';
}

/// `4:05` / `1:02:03`.
String formatVideoDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

Future<void> _openOnYoutube(BuildContext context, FeedVideo video) async {
  final ok = await launchUrl(Uri.parse(video.watchUrl),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Couldn't open YouTube")));
  }
}

VideoRef _videoRef(FeedVideo video) => VideoRef(
      videoId: video.videoId,
      title: video.title,
      channel: video.channelName,
      published: video.published,
    );

/// A YouTube search result shown in the feed (the online fallback of the
/// feed search) as a feed row.
FeedVideo feedVideoFromSearch(Mp3SearchResult r) => FeedVideo(
      videoId: r.videoId,
      title: r.title,
      channelId: '',
      channelName: r.channel,
      published: r.uploadDate,
      publishedApprox: r.uploadDate != null,
      duration: r.duration,
      viewCount: r.viewCount,
    );

/// Best Music → Subscriptions: the newest videos from the YouTube channels
/// the user follows (SPEC.md §10.6m), newest first. Opens on the last two
/// days, widens to a week once the refresh is done, and shows older weeks
/// only when scrolled to the end. Tapping a video plays its audio through
/// the normal player (mini player, lock screen, sleep timer); the info
/// button opens its description and "Open in YouTube"/"Download". The
/// search button fuzzy-searches every fetched video by title, channel and
/// upload date.
class YoutubeFeedPage extends StatefulWidget {
  const YoutubeFeedPage({
    super.key,
    this.service,
    this.playQueue,
    this.addToQueue,
    this.onlineSearch,
  });

  final YoutubeFeedService? service;

  /// Starts a queue; defaults to [MusicPlayerService.playQueue]. Tests
  /// pass a recorder.
  final Future<void> Function(List<Track> queue)? playQueue;

  /// Appends a video to the video queue (swipe / "Add to queue"); defaults
  /// to the player's `addToVideoQueue`. True when added, false when it was
  /// already queued.
  final Future<bool> Function(Track track)? addToQueue;

  /// YouTube search used when the feed search finds nothing; defaults to
  /// [YoutubeSearchApi.search].
  final Future<List<Mp3SearchResult>> Function(String query)? onlineSearch;

  /// Route name, so "Back to videos" can find an open feed instead of
  /// stacking a second one ([showSessionScreen]).
  static const routeName = '/subscriptions';

  static Route<void> route() => MaterialPageRoute(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const YoutubeFeedPage());

  @override
  State<YoutubeFeedPage> createState() => _YoutubeFeedPageState();
}

class _YoutubeFeedPageState extends State<YoutubeFeedPage> {
  late final YoutubeFeedService _service =
      widget.service ?? YoutubeFeedService.instance;

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  FeedSearchField _searchField = FeedSearchField.all;

  bool get _searching => _searchActive && _searchQuery.trim().isNotEmpty;

  // The feed search's online fallback: when nothing in the feed matches,
  // YouTube itself is searched (debounced; a newer query wins).
  Timer? _onlineTimer;
  int _onlineSeq = 0;
  String _onlineQuery = '';
  bool _onlineLoading = false;
  bool _onlineFailed = false;
  List<FeedVideo> _onlineResults = const [];

  static const Duration onlineSearchDelay = Duration(milliseconds: 600);

  @override
  void dispose() {
    _onlineTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() => setState(() {
        _searchActive = false;
        _searchQuery = '';
        _searchController.clear();
        _searchField = FeedSearchField.all;
        _clearOnline();
      });

  void _clearOnline() {
    _onlineTimer?.cancel();
    _onlineSeq++;
    _onlineQuery = '';
    _onlineLoading = false;
    _onlineFailed = false;
    _onlineResults = const [];
  }

  List<FeedVideo> _localMatches() => searchFeed(
      filterFeed(_service.videos.value, _service.settings.value),
      _searchQuery,
      field: _searchField);

  /// After each edit: if the feed has no match, ask YouTube.
  void _onSearchChanged() {
    final query = _searchQuery.trim();
    if (query.length < 2 || _localMatches().isNotEmpty) {
      setState(_clearOnline);
      return;
    }
    if (query == _onlineQuery && (_onlineLoading || _onlineResults.isNotEmpty)) {
      return;
    }
    _onlineTimer?.cancel();
    setState(() {
      _onlineLoading = true;
      _onlineFailed = false;
    });
    _onlineTimer = Timer(onlineSearchDelay, () => _searchOnline(query));
  }

  Future<void> _searchOnline(String query) async {
    final seq = ++_onlineSeq;
    _onlineQuery = query;
    List<FeedVideo> results = const [];
    var failed = false;
    try {
      final found = await (widget.onlineSearch ??
          (q) => YoutubeSearchApi.search(q, limit: 15))(query);
      results = [for (final r in found) feedVideoFromSearch(r)];
    } catch (_) {
      failed = true;
    }
    if (!mounted || seq != _onlineSeq) return; // a newer query took over
    setState(() {
      _onlineLoading = false;
      _onlineFailed = failed;
      _onlineResults = results;
    });
  }

  // ---------------------------------------------------------------------
  // Swipes, long-press and the options sheet

  Future<void> _addToQueue(FeedVideo video) async {
    final messenger = ScaffoldMessenger.of(context);
    final track = YoutubeFeedService.trackFor(video);
    final add = widget.addToQueue ??
        (MusicPlayerService.isReady
            ? MusicPlayerService.handler.addToVideoQueue
            : null);
    if (add == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text("The player isn't ready yet — try again")));
      return;
    }
    final added = await add(track);
    if (!mounted) return;
    final days = _service.settings.value.offlineDays;
    messenger.showSnackBar(SnackBar(
      content: Text(added
          ? (days > 0
              ? 'Added to the queue — downloading it for offline play'
              : 'Added to the queue')
          : 'Already in the queue'),
    ));
  }

  Future<void> _togglePlayed(FeedVideo video) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasPlayed = _service.isPlayed(video.videoId);
    await _service.setPlayed(video.videoId, !wasPlayed);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(wasPlayed ? 'Marked unwatched' : 'Marked watched'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _service.setPlayed(video.videoId, wasPlayed),
      ),
    ));
  }

  void _openTranscript(FeedVideo video) => Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => VideoTranscriptPage(video: _videoRef(video))));

  void _openSummary(FeedVideo video) => Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => VideoSummaryPage(video: _videoRef(video))));

  /// Runs what Settings says a swipe / long-press on [list]`[i]` does.
  Future<void> _runGesture(
      FeedGestureAction action, List<FeedVideo> list, int i) async {
    final video = list[i];
    switch (action) {
      case FeedGestureAction.nothing:
        return;
      case FeedGestureAction.addToQueue:
        return _addToQueue(video);
      case FeedGestureAction.togglePlayed:
        return _togglePlayed(video);
      case FeedGestureAction.options:
        return _showOptions(list, i);
      case FeedGestureAction.play:
        return _play(list, i);
      case FeedGestureAction.transcript:
        return _openTranscript(video);
      case FeedGestureAction.summary:
        return _openSummary(video);
      case FeedGestureAction.info:
        return _openInfo(list, i);
    }
  }

  /// Long-press (by default): everything a video can do.
  Future<void> _showOptions(List<FeedVideo> list, int i) async {
    final video = list[i];
    final played = _service.isPlayed(video.videoId);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget option(String key, IconData icon, String label) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(sheetContext).pop(key),
            );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(sheetContext).textTheme.titleSmall),
                ),
                option('play', Icons.play_arrow, 'Play'),
                option('queue', Icons.playlist_add, 'Add to queue'),
                option(
                    'played',
                    played ? Icons.remove_done : Icons.check_circle_outline,
                    played ? 'Mark unwatched' : 'Mark watched'),
                option('transcript', Icons.subtitles_outlined, 'Transcript'),
                option('summary', Icons.summarize_outlined, 'Quick summary'),
                option('download', Icons.download_outlined, 'Download as MP3'),
                option('youtube', Icons.open_in_new, 'Open in YouTube'),
                option('info', Icons.info_outline, 'Video info'),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'play':
        return _play(list, i);
      case 'queue':
        return _addToQueue(video);
      case 'played':
        return _togglePlayed(video);
      case 'transcript':
        return _openTranscript(video);
      case 'summary':
        return _openSummary(video);
      case 'download':
        unawaited(Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Mp3DownloaderPage(initialQuery: video.watchUrl))));
        return;
      case 'youtube':
        return _openOnYoutube(context, video);
      case 'info':
        return _openInfo(list, i);
    }
  }

  /// One feed row with the swipe gestures and long-press from Settings.
  Widget _videoRow(List<FeedVideo> list, int i) {
    final settings = _service.settings.value;
    final video = list[i];
    return _SwipeableVideo(
      key: ValueKey('feedRow-${video.videoId}'),
      right: settings.swipeRight,
      left: settings.swipeLeft,
      played: _service.isPlayed(video.videoId),
      onSwipe: (action) => _runGesture(action, list, i),
      child: FeedVideoTile(
        video: video,
        progress: _service.progressFor(video.videoId),
        onTap: () => _play(list, i),
        onInfo: () => _openInfo(list, i),
        onLongPress: settings.longPress == FeedGestureAction.nothing
            ? null
            : () => _runGesture(settings.longPress, list, i),
      ),
    );
  }

  Future<void> _play(List<FeedVideo> list, int index) {
    final queue = _service.queueFrom(list, index);
    return (widget.playQueue ?? MusicPlayerService.playQueue)(queue);
  }

  @override
  void initState() {
    super.initState();
    _service.startSession();
    unawaited(_loadAndRefresh());
  }

  /// Saved videos of the last two days show at once and new ones join as
  /// each channel arrives (a refresh only adds — see
  /// YoutubeFeedService._merged; skipped when the feed was refreshed in the
  /// last few minutes); once it's done the rest of the week fills in below.
  Future<void> _loadAndRefresh() async {
    await _service.load();
    if (!mounted) return;
    setState(() {});
    try {
      if (_service.subscriptions.value.isNotEmpty) {
        await _service.refreshIfStale();
      }
    } finally {
      _service.widenToBackgroundWindow();
    }
  }

  /// Older videos only once the week is shown and the list is scrolled
  /// near its end.
  bool _onScroll(ScrollNotification n) {
    if (!_searching &&
        n.metrics.extentAfter < 400 &&
        _service.window.value >= YoutubeFeedService.backgroundWindow &&
        _service.hasOlderVideos) {
      _service.showOlder();
    }
    return false;
  }

  void _openInfo(List<FeedVideo> list, int i) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => YoutubeVideoPage(
          video: list[i],
          service: _service,
          onPlay: () => _play(list, i),
        ),
      ));

  /// The "Couldn't refresh" line's Retry: force-checks just the failed
  /// channels (each tried up to three times).
  Future<void> _retryFailed() async {
    final messenger = ScaffoldMessenger.of(context);
    final total = _service.failedChannels.value.length;
    final loaded = await _service.retryFailedChannels();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(loaded == total
          ? 'All $total channel${total == 1 ? '' : 's'} loaded'
          : 'Loaded $loaded of $total — the rest still don\'t answer'),
    ));
  }

  void _openChannels() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => YoutubeChannelsPage(service: _service)));

  /// The search field plus chips limiting it to the title, channel or date.
  PreferredSizeWidget _buildSearchBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(104),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: _searchField == FeedSearchField.date
                    ? 'e.g. yesterday, oct 3, 2026-10-03, friday'
                    : 'Search title, channel or date',
                border: const OutlineInputBorder(),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                          _clearOnline();
                        }),
                      ),
              ),
              onChanged: (v) {
                _searchQuery = v;
                _onSearchChanged();
              },
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final field in FeedSearchField.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(field.label),
                        selected: _searchField == field,
                        onSelected: (_) {
                          _searchField = field;
                          _onSearchChanged();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Subscriptions',
        actions: [
          IconButton(
            tooltip: 'Channels',
            icon: const Icon(Icons.subscriptions_outlined),
            onPressed: _openChannels,
          ),
          _searchActive
              ? IconButton(
                  tooltip: 'Close search',
                  icon: const Icon(Icons.close),
                  onPressed: _closeSearch,
                )
              : IconButton(
                  tooltip: 'Search feed',
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _searchActive = true),
                ),
        ],
        bottom: _searchActive ? _buildSearchBar() : null,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _service.subscriptions,
          _service.videos,
          _service.settings,
          _service.progress,
          _service.refreshing,
          _service.refreshProgress,
          _service.window,
          _service.failedChannels,
        ]),
        builder: (context, _) {
          if (_service.subscriptions.value.isEmpty) {
            return _EmptyFeed(onFindChannels: _openChannels);
          }
          final searching = _searching;
          final local = searching ? _localMatches() : _service.visibleVideos;
          // Nothing in the feed matched: YouTube's own results instead.
          final online = searching && local.isEmpty;
          final list = online ? _onlineResults : local;
          final failed = _service.failedChannels.value;
          final hasOlder = !searching && _service.hasOlderVideos;
          return RefreshIndicator(
            onRefresh: _service.refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.length + 2,
                itemBuilder: (context, index) {
                  if (index == list.length + 1) {
                    if (searching) return const SizedBox.shrink();
                    return _FeedFooter(
                      loadingWeek: _service.window.value <
                          YoutubeFeedService.backgroundWindow,
                      hasOlder: hasOlder,
                      empty: list.isEmpty,
                      onShowOlder: _service.showOlder,
                    );
                  }
                  if (index == 0) {
                    return Column(children: [
                      EstimatedProgressBar(
                        active: _service.refreshing.value,
                        value: _service.refreshProgress.value > 0
                            ? _service.refreshProgress.value
                            : null,
                      ),
                      if (failed.isNotEmpty)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.error_outline),
                          title: Text("Couldn't refresh ${failed.length} "
                              "channel${failed.length == 1 ? '' : 's'}: "
                              '${failed.take(3).join(', ')}'
                              '${failed.length > 3 ? ', ...' : ''}'),
                          trailing: ValueListenableBuilder<Set<String>>(
                            valueListenable: _service.forceRefreshing,
                            builder: (context, busy, _) => busy.isNotEmpty
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : TextButton(
                                    onPressed: _retryFailed,
                                    child: const Text('Retry'),
                                  ),
                          ),
                        ),
                      if (online)
                        _OnlineSearchHeader(
                          loading: _onlineLoading,
                          failed: _onlineFailed,
                          empty: _onlineResults.isEmpty,
                          tooShort: _searchQuery.trim().length < 2,
                        )
                      else if (list.isEmpty &&
                          !hasOlder &&
                          !_service.refreshing.value)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No videos yet — pull down to refresh.',
                              textAlign: TextAlign.center),
                        ),
                    ]);
                  }
                  return _videoRow(list, index - 1);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Below the last video: the week still loading, a way to older videos
/// (they also load by themselves when scrolled to), or the end.
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.loadingWeek,
    required this.hasOlder,
    required this.empty,
    required this.onShowOlder,
  });

  final bool loadingWeek;
  final bool hasOlder;
  final bool empty;
  final VoidCallback onShowOlder;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    if (loadingWeek) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Loading the rest of the week...',
            textAlign: TextAlign.center, style: small),
      );
    }
    if (hasOlder) {
      return Center(
        child: TextButton.icon(
          onPressed: onShowOlder,
          icon: const Icon(Icons.expand_more),
          label: const Text('Show older videos'),
        ),
      );
    }
    if (empty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('No older videos', textAlign: TextAlign.center, style: small),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.onFindChannels});

  final VoidCallback onFindChannels;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.subscriptions_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No subscriptions yet. Find YouTube channels by name, or import '
              'your subscriptions from Tubular/NewPipe.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onFindChannels,
              child: const Text('Add channels'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A video thumbnail with the duration and listening progress drawn on it.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.url,
    required this.video,
    required this.progress,
    this.width,
  });

  final String url;
  final FeedVideo video;
  final WatchProgress? progress;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: const Icon(Icons.smart_display_outlined),
                ),
              ),
              if (video.duration != null)
                Positioned(
                  right: 4,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    color: Colors.black87,
                    child: Text(
                      formatVideoDuration(video.duration!),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              if (fraction != null && fraction > 0)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(height: 3, color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _metaLine(FeedVideo v) => [
      v.channelName,
      _statsLine(v),
      _uploadLine(v),
    ].where((s) => s.isNotEmpty).join(' · ');

/// "12:34 · 1.2K views" — duration first, then views.
String _statsLine(FeedVideo v) => [
      if (v.duration != null) formatVideoDuration(v.duration!),
      if (v.viewCount != null) '${formatViewCount(v.viewCount)} views',
    ].join(' · ');

/// "Today 14:05 (3h ago)" — when it went up.
String _uploadLine(FeedVideo v) {
  if (v.published == null) return '';
  final when = formatFeedUploadTime(v.published, approx: v.publishedApprox);
  return '$when (${formatFeedAge(v.published)})';
}

/// A small icon + one line of [FeedVideoTile] details.
class _MetaRow extends StatelessWidget {
  const _MetaRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: style?.color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ]),
    );
  }
}

/// One feed row: thumbnail, title, channel, duration/views, upload time
/// and an info button.
/// Tapping the row plays the video; the info button opens its page.
/// Played videos are dimmed with a check mark.
class FeedVideoTile extends StatelessWidget {
  const FeedVideoTile({
    super.key,
    required this.video,
    required this.progress,
    required this.onTap,
    required this.onInfo,
    this.onLongPress,
  });

  final FeedVideo video;
  final WatchProgress? progress;

  /// The long-press action from Settings (the options sheet by default).
  final VoidCallback? onLongPress;

  /// Plays the video.
  final VoidCallback onTap;

  /// Opens the video's page (description, Open in YouTube, Download).
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final played = progress?.completed ?? false;
    return Opacity(
      opacity: played ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(
                url: video.thumbnailUrl,
                video: video,
                progress: progress,
                width: 140,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      if (played)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.check_circle, size: 14),
                        ),
                      Expanded(
                        child: Text(
                          video.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ]),
                    // Duration, views and upload time: each on a line of
                    // its own so none is ever cut off on a narrow phone.
                    if (_statsLine(video).isNotEmpty)
                      _MetaRow(
                        key: const ValueKey('feedVideoStats'),
                        icon: Icons.play_circle_outline,
                        text: _statsLine(video),
                      ),
                    if (video.published != null)
                      _MetaRow(
                        key: const ValueKey('feedVideoUploadTime'),
                        icon: Icons.schedule,
                        text: _uploadLine(video),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Video info',
                icon: const Icon(Icons.info_outline),
                onPressed: onInfo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A feed video's page: big thumbnail, play/resume, Open in YouTube,
/// Download, mark played, and the full description.
class YoutubeVideoPage extends StatefulWidget {
  const YoutubeVideoPage({
    super.key,
    required this.video,
    required this.onPlay,
    this.service,
  });

  final FeedVideo video;
  final VoidCallback onPlay;
  final YoutubeFeedService? service;

  @override
  State<YoutubeVideoPage> createState() => _YoutubeVideoPageState();
}

class _YoutubeVideoPageState extends State<YoutubeVideoPage> {
  late final YoutubeFeedService _service =
      widget.service ?? YoutubeFeedService.instance;
  late String _description = widget.video.description;
  late bool _loadingDescription = _description.isEmpty;

  @override
  void initState() {
    super.initState();
    if (_description.isEmpty) unawaited(_loadDescription());
  }

  Future<void> _loadDescription() async {
    try {
      final text = await _service.fetchDescription(widget.video.videoId);
      if (mounted) setState(() => _description = text);
    } catch (_) {
      // Leave the "no description" text.
    } finally {
      if (mounted) setState(() => _loadingDescription = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: video.channelName),
      body: ValueListenableBuilder<Map<String, WatchProgress>>(
        valueListenable: _service.progress,
        builder: (context, progressMap, _) {
          final progress = progressMap[video.videoId];
          final played = progress?.completed ?? false;
          final resume = _service.resumePosition(video.videoId);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Thumbnail(
                url: video.largeThumbnailUrl,
                video: video,
                progress: progress,
              ),
              const SizedBox(height: 12),
              SelectableText(video.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                _metaLine(video),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onPlay,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(resume != null
                        ? 'Resume at ${formatVideoDuration(resume)}'
                        : 'Play'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openOnYoutube(context, video),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in YouTube'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => Mp3DownloaderPage(
                                initialQuery: video.watchUrl))),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                VideoTranscriptPage(video: _videoRef(video)))),
                    icon: const Icon(Icons.subtitles_outlined),
                    label: const Text('Transcript'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                VideoSummaryPage(video: _videoRef(video)))),
                    icon: const Icon(Icons.summarize_outlined),
                    label: const Text('Quick summary'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _service.setPlayed(video.videoId, !played),
                    icon: Icon(played
                        ? Icons.remove_done
                        : Icons.check_circle_outline),
                    label: Text(played ? 'Mark unplayed' : 'Mark played'),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (_loadingDescription)
                const EstimatedProgressBar(
                    active: true, expected: Duration(seconds: 3))
              else if (_description.isEmpty)
                Text('No description.', style: theme.textTheme.bodySmall)
              else
                LinkifiedText(_description),
            ],
          );
        },
      ),
    );
  }
}

/// A feed row that swipes: right and left run the actions picked in
/// Settings (add to queue / mark watched by default). The row springs back
/// — a swipe never removes it from the list. A direction set to
/// "Nothing" doesn't swipe at all.
class _SwipeableVideo extends StatelessWidget {
  const _SwipeableVideo({
    super.key,
    required this.right,
    required this.left,
    required this.played,
    required this.onSwipe,
    required this.child,
  });

  final FeedGestureAction right;
  final FeedGestureAction left;
  final bool played;
  final Future<void> Function(FeedGestureAction action) onSwipe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canRight = right != FeedGestureAction.nothing;
    final canLeft = left != FeedGestureAction.nothing;
    if (!canRight && !canLeft) return child;
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: canRight && canLeft
          ? DismissDirection.horizontal
          : canRight
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      background: _SwipeBackground(
          action: right, played: played, alignLeft: true),
      secondaryBackground: _SwipeBackground(
          action: left, played: played, alignLeft: false),
      confirmDismiss: (direction) async {
        unawaited(onSwipe(
            direction == DismissDirection.startToEnd ? right : left));
        return false; // the video stays in the list
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.action,
    required this.played,
    required this.alignLeft,
  });

  final FeedGestureAction action;
  final bool played;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label) = switch (action) {
      FeedGestureAction.addToQueue => (Icons.playlist_add, 'Add to queue'),
      FeedGestureAction.togglePlayed => played
          ? (Icons.remove_done, 'Mark unwatched')
          : (Icons.check_circle_outline, 'Mark watched'),
      FeedGestureAction.options => (Icons.more_horiz, 'Options'),
      FeedGestureAction.play => (Icons.play_arrow, 'Play'),
      FeedGestureAction.transcript => (Icons.subtitles_outlined, 'Transcript'),
      FeedGestureAction.summary => (Icons.summarize_outlined, 'Summary'),
      FeedGestureAction.info => (Icons.info_outline, 'Info'),
      FeedGestureAction.nothing => (Icons.block, ''),
    };
    final color = alignLeft ? scheme.primaryContainer : scheme.tertiaryContainer;
    final onColor =
        alignLeft ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
    return Container(
      color: color,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onColor),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Above the online fallback's results: what's going on.
class _OnlineSearchHeader extends StatelessWidget {
  const _OnlineSearchHeader({
    required this.loading,
    required this.failed,
    required this.empty,
    required this.tooShort,
  });

  final bool loading;
  final bool failed;
  final bool empty;
  final bool tooShort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tooShort) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('No videos in your feed match.',
            textAlign: TextAlign.center),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            loading
                ? 'Nothing in your feed — searching YouTube…'
                : failed
                    ? "Nothing in your feed, and YouTube couldn't be "
                        'searched (offline?)'
                    : empty
                        ? 'Nothing in your feed or on YouTube'
                        : 'Nothing in your feed — results from YouTube',
            style: theme.textTheme.labelLarge,
          ),
        ),
        if (loading) const LinearProgressIndicator(),
      ],
    );
  }
}
