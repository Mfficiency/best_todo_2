import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/youtube_feed.dart';
import '../services/mp3_downloader_service.dart' show formatViewCount;
import '../services/music_player_service.dart';
import '../services/youtube_feed_service.dart';
import '../utils/linkified_text.dart';
import 'mp3_downloader_page.dart';
import 'estimated_progress_bar.dart';
import 'subpage_app_bar.dart';
import 'youtube_channels_page.dart';
import 'youtube_feed_settings_page.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open YouTube")));
  }
}

Future<void> _play(List<FeedVideo> list, int index) => MusicPlayerService
    .playQueue(YoutubeFeedService.instance.queueFrom(list, index));

/// Best Music → Subscriptions: the newest videos from the YouTube channels
/// the user follows (SPEC.md §10.6m). Tap a video for its description and
/// "Open in YouTube"/"Download"; the play button streams its audio through
/// the normal player (mini player, lock screen, sleep timer) and carries
/// on through the unplayed videos below it.
class YoutubeFeedPage extends StatefulWidget {
  const YoutubeFeedPage({super.key, this.service});

  final YoutubeFeedService? service;

  @override
  State<YoutubeFeedPage> createState() => _YoutubeFeedPageState();
}

class _YoutubeFeedPageState extends State<YoutubeFeedPage> {
  late final YoutubeFeedService _service =
      widget.service ?? YoutubeFeedService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAndRefresh());
  }

  Future<void> _loadAndRefresh() async {
    await _service.load();
    if (!mounted) return;
    setState(() {});
    if (_service.subscriptions.value.isNotEmpty) await _service.refresh();
  }

  void _openChannels() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => YoutubeChannelsPage(service: _service)));

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
          IconButton(
            tooltip: 'Feed settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => YoutubeFeedSettingsPage(service: _service))),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _service.subscriptions,
          _service.videos,
          _service.settings,
          _service.progress,
          _service.refreshing,
          _service.refreshProgress,
          _service.failedChannels,
        ]),
        builder: (context, _) {
          if (_service.subscriptions.value.isEmpty) {
            return _EmptyFeed(onFindChannels: _openChannels);
          }
          final list = _service.visibleVideos;
          final failed = _service.failedChannels.value;
          return RefreshIndicator(
            onRefresh: _service.refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length + 1,
              itemBuilder: (context, index) {
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
                      ),
                    if (list.isEmpty && !_service.refreshing.value)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No videos yet — pull down to refresh.',
                            textAlign: TextAlign.center),
                      ),
                  ]);
                }
                final i = index - 1;
                return FeedVideoTile(
                  video: list[i],
                  progress: _service.progressFor(list[i].videoId),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => YoutubeVideoPage(
                      video: list[i],
                      service: _service,
                      onPlay: () => _play(list, i),
                    ),
                  )),
                  onPlay: () => _play(list, i),
                );
              },
            ),
          );
        },
      ),
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
      formatFeedAge(v.published),
      if (v.viewCount != null) '${formatViewCount(v.viewCount)} views',
    ].where((s) => s.isNotEmpty).join(' · ');

/// One feed row: thumbnail, title, channel/age/views, play button. Played
/// videos are dimmed with a check mark.
class FeedVideoTile extends StatelessWidget {
  const FeedVideoTile({
    super.key,
    required this.video,
    required this.progress,
    required this.onTap,
    required this.onPlay,
  });

  final FeedVideo video;
  final WatchProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final played = progress?.completed ?? false;
    return Opacity(
      opacity: played ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
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
                          _metaLine(video),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Play',
                icon: const Icon(Icons.play_circle_outline),
                onPressed: onPlay,
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
                [
                  _metaLine(video),
                  if (video.duration != null)
                    formatVideoDuration(video.duration!),
                ].join(' · '),
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
                    onPressed: () =>
                        _service.setPlayed(video.videoId, !played),
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
