import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/music_audio_handler.dart';
import '../services/music_player_service.dart';
import '../services/speaker_play_guard.dart';
import '../services/music_playlist_service.dart';
import 'estimated_progress_bar.dart';
import 'music_mini_player_bar.dart'
    show SwitchSessionButton, switchSessionAndShow;
import 'playback_speed_sheet.dart';
import 'volume_sheet.dart';
import 'queue_page.dart';
import 'sleep_timer_sheet.dart';
import 'subpage_app_bar.dart';
import 'track_metadata_page.dart';

/// Full-screen "now playing" view. Swipe up on the artwork/title area to
/// favorite the current track, swipe down to mark it disliked and skip —
/// the "Tinder for songs" gesture pair the user asked for, on top of the
/// regular transport controls.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  /// How many Now Playing pages are open — [MusicMiniPlayerBar] hides while
  /// this is above zero, since the page already shows the same controls.
  static final ValueNotifier<int> openCount = ValueNotifier(0);

  /// Route name, so "Back to music" can find an open Now Playing page
  /// instead of stacking a second one ([showSessionScreen]).
  static const routeName = '/now-playing';

  static Route<void> route() => MaterialPageRoute(
      settings: const RouteSettings(name: routeName),
      builder: (_) => const NowPlayingPage());

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  double _dragOffset = 0;
  String? _flashLabel;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    // Deferred: listeners (the mini player) can't rebuild mid-build/dispose.
    Future.microtask(() => NowPlayingPage.openCount.value++);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    Future.microtask(() => NowPlayingPage.openCount.value--);
    super.dispose();
  }

  void _flash(String label) {
    _flashTimer?.cancel();
    setState(() => _flashLabel = label);
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _flashLabel = null);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    const threshold = 250.0;
    if (velocity < -threshold || _dragOffset < -80) {
      MusicPlayerService.handler.favoriteCurrent();
      _flash('Added to Favorites');
    } else if (velocity > threshold || _dragOffset > 80) {
      MusicPlayerService.handler.dislikeCurrentAndSkip();
      _flash("Skipped, won't come up as much");
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final handler = MusicPlayerService.handler;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Now Playing',
        actions: [
          // Feed videos only: speed is a podcast/talk thing, not a
          // local-music one.
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, _) => PlaybackSpeedButton(
              visible: handler.currentTrack?.isFeedVideo ?? false,
            ),
          ),
          // Music and feed videos each remember their own volume.
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, _) {
              final video = handler.currentTrack?.isFeedVideo ?? false;
              return IconButton(
                icon: const Icon(Icons.volume_up_outlined),
                tooltip: video ? 'Video volume' : 'Music volume',
                onPressed: () => showVolumeSheet(context, video: video),
              );
            },
          ),
          const SleepTimerButton(),
          ValueListenableBuilder<bool>(
            valueListenable: handler.shuffleEnabled,
            builder: (context, shuffleOn, _) => IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle off',
              color: shuffleOn ? Theme.of(context).colorScheme.primary : null,
              onPressed: () => handler.toggleShuffle(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Queue',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QueuePage()),
            ),
          ),
          StreamBuilder<MediaItem?>(
            stream: handler.mediaItem,
            builder: (context, _) {
              final track = handler.currentTrack;
              return IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Track info',
                onPressed: track == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TrackMetadataPage(trackId: track.id),
                        )),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        builder: (context, itemSnapshot) {
          final item = itemSnapshot.data;
          if (item == null) {
            return const Center(child: Text('Nothing playing'));
          }
          final track = handler.currentTrack;
          final isFavorite = track != null &&
              MusicPlaylistService.instance.isFavorite(track.id);
          return GestureDetector(
            onVerticalDragUpdate: (d) =>
                setState(() => _dragOffset += d.delta.dy),
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Loading (resolving a video, buffering): a filling bar.
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    initialData: handler.playbackState.valueOrNull,
                    builder: (context, snapshot) {
                      final state = snapshot.data?.processingState;
                      return EstimatedProgressBar(
                        active: state == AudioProcessingState.loading ||
                            state == AudioProcessingState.buffering,
                        expected: const Duration(seconds: 5),
                      );
                    },
                  ),
                  // One tap back to the last song / last video.
                  ValueListenableBuilder<PlaybackSession?>(
                    valueListenable: handler.otherSession,
                    builder: (context, other, _) {
                      if (other == null) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: ActionChip(
                          key: const ValueKey('nowPlayingSwitchSession'),
                          avatar: Icon(other.isVideo
                              ? Icons.smart_display_outlined
                              : Icons.library_music_outlined),
                          label: Text(SwitchSessionButton.labelFor(other),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onPressed: () => switchSessionAndShow(
                              handler, Navigator.of(context)),
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          transform: Matrix4.translationValues(
                              0, _dragOffset.clamp(-120, 120), 0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (item.artUri != null)
                                // A Subscriptions-feed video's thumbnail.
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 220),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      item.artUri.toString(),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.music_note,
                                        size: 120,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  Icons.music_note,
                                  size: 120,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.5),
                                ),
                              const SizedBox(height: 24),
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              if ((item.artist ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    item.artist!,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              if (isFavorite)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Icon(Icons.favorite, color: Colors.pink),
                                ),
                            ],
                          ),
                        ),
                        if (_flashLabel != null)
                          Positioned(
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(_flashLabel!),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Text(
                    'Swipe up to favorite • swipe down to skip & dislike',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _ProgressBar(handler: handler),
                  const SizedBox(height: 8),
                  _Transport(handler: handler, isFavorite: isFavorite),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.handler});

  final MusicAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        final position = state?.position ?? Duration.zero;
        final item = handler.mediaItem.valueOrNull;
        final duration = item?.duration ?? Duration.zero;
        final max = duration.inMilliseconds > 0
            ? duration.inMilliseconds.toDouble()
            : 1.0;
        final value = position.inMilliseconds.clamp(0, max.round()).toDouble();
        return Column(
          children: [
            Slider(
              value: value,
              max: max,
              onChanged: duration.inMilliseconds > 0
                  ? (v) => handler.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_format(position)),
                Text(_format(duration)),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.handler, required this.isFavorite});

  final MusicAudioHandler handler;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              tooltip: 'Favorite',
              color: isFavorite ? Colors.pink : null,
              onPressed: () => handler.favoriteCurrent(),
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: 'Previous',
              iconSize: 36,
              onPressed: () => handler.skipToPrevious(),
            ),
            IconButton(
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
              tooltip: playing ? 'Pause' : 'Play',
              iconSize: 56,
              onPressed: () async {
                if (playing) {
                  await handler.pause();
                } else if (await SpeakerPlayGuard.confirmPlay(context)) {
                  await handler.play();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: 'Next',
              iconSize: 36,
              onPressed: () => handler.skipToNext(),
            ),
            IconButton(
              icon: const Icon(Icons.thumb_down_alt_outlined),
              tooltip: "Don't really like",
              onPressed: () => handler.dislikeCurrentAndSkip(),
            ),
          ],
        );
      },
    );
  }
}
