import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/music_audio_handler.dart';
import '../services/music_player_service.dart';
import '../services/speaker_play_guard.dart';
import '../services/youtube_feed_service.dart';
import '../services/music_sleep_timer.dart';
import 'estimated_progress_bar.dart';
import 'now_playing_page.dart';
import 'sleep_timer_sheet.dart';

/// Small persistent bar showing the current song — or, when nothing is
/// playing, the last-played one restored at startup
/// ([MusicPlayerService.restoreLastSession]) — with play/pause and a
/// tap-through to [NowPlayingPage].
///
/// Best Music mounts it once below its navigator (`main_music.dart`), so it
/// sits at the bottom of every screen; that spot has no Overlay, so it uses
/// no tooltips and opens Now Playing through [navigatorKey]. It hides while
/// Now Playing itself is open ([NowPlayingPage.openCount]).
class MusicMiniPlayerBar extends StatelessWidget {
  const MusicMiniPlayerBar({super.key, this.navigatorKey, this.handler});

  /// Navigator to push [NowPlayingPage] on; defaults to the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Defaults to [MusicPlayerService.handler]; tests pass a fake.
  final BaseAudioHandler? handler;

  void _openNowPlaying(BuildContext context) {
    final navigator = navigatorKey?.currentState ?? Navigator.of(context);
    navigator.push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
  }

  /// Context under the navigator (the bar itself sits outside it, so it
  /// can't host a bottom sheet).
  BuildContext _sheetContext(BuildContext context) =>
      navigatorKey?.currentContext ?? context;

  @override
  Widget build(BuildContext context) {
    final BaseAudioHandler? audio = handler ??
        (MusicPlayerService.isReady ? MusicPlayerService.handler : null);
    if (audio == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: NowPlayingPage.openCount,
      builder: (context, nowPlayingOpen, _) {
        if (nowPlayingOpen > 0) return const SizedBox.shrink();
        return StreamBuilder<MediaItem?>(
          stream: audio.mediaItem,
          initialData: audio.mediaItem.valueOrNull,
          builder: (context, snapshot) {
            final item = snapshot.data;
            if (item == null) return const SizedBox.shrink();
            return Material(
              key: const ValueKey('musicMiniPlayer'),
              elevation: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Loading a track (resolving a video, buffering): a bar
                  // that visibly fills instead of a silent wait.
                  StreamBuilder<PlaybackState>(
                    stream: audio.playbackState,
                    initialData: audio.playbackState.valueOrNull,
                    builder: (context, stateSnapshot) {
                      final state = stateSnapshot.data?.processingState;
                      return EstimatedProgressBar(
                        active: state == AudioProcessingState.loading ||
                            state == AudioProcessingState.buffering,
                        expected: const Duration(seconds: 5),
                        minHeight: 2,
                      );
                    },
                  ),
                  InkWell(
                    onTap: () => _openNowPlaying(context),
                    // Long-press: the sleep timer, from anywhere in the app.
                    onLongPress: () =>
                        showSleepTimerSheet(_sheetContext(context)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if ((item.artist ?? '').isNotEmpty)
                                  Text(item.artist!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ],
                            ),
                          ),
                          if (audio is MusicAudioHandler)
                            SwitchSessionButton(handler: audio),
                          _SleepTimerBadge(
                              onTap: () =>
                                  showSleepTimerSheet(_sheetContext(context))),
                          StreamBuilder<PlaybackState>(
                            stream: audio.playbackState,
                            initialData: audio.playbackState.valueOrNull,
                            builder: (context, stateSnapshot) {
                              final playing =
                                  stateSnapshot.data?.playing ?? false;
                              return Semantics(
                                label: playing ? 'Pause' : 'Play',
                                button: true,
                                child: IconButton(
                                  key: const ValueKey(
                                      'musicMiniPlayerPlayPause'),
                                  icon: Icon(
                                      playing ? Icons.pause : Icons.play_arrow),
                                  onPressed: () async {
                                    if (playing) {
                                      await audio.pause();
                                    } else if (await SpeakerPlayGuard
                                        .confirmPlay(_sheetContext(context))) {
                                      await audio.play();
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// One tap back into the other kind of listening — the last song while a
/// video plays, the last video while music plays — resuming where it was
/// stopped ([MusicAudioHandler.switchToOtherSession]). Hidden until there
/// is one. No tooltip: the mini player has no Overlay, so it's labelled
/// through [Semantics] instead.
class SwitchSessionButton extends StatelessWidget {
  const SwitchSessionButton({super.key, required this.handler});

  final MusicAudioHandler handler;

  static String labelFor(PlaybackSession session) =>
      '${session.isVideo ? 'Back to video' : 'Back to music'}: '
      '${session.current.title}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackSession?>(
      valueListenable: handler.otherSession,
      builder: (context, other, _) {
        if (other == null) return const SizedBox.shrink();
        return Semantics(
          label: labelFor(other),
          button: true,
          child: IconButton(
            key: const ValueKey('switchSessionButton'),
            icon: Icon(other.isVideo
                ? Icons.smart_display_outlined
                : Icons.library_music_outlined),
            onPressed: handler.switchToOtherSession,
          ),
        );
      },
    );
  }
}

/// Bedtime icon + time left, shown in the mini player only while a sleep
/// timer runs; refreshes every 15 s so the minutes count down.
class _SleepTimerBadge extends StatelessWidget {
  const _SleepTimerBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SleepTimerState>(
      valueListenable: MusicSleepTimer.instance.state,
      builder: (context, state, _) {
        if (!state.isActive) return const SizedBox.shrink();
        final color = Theme.of(context).colorScheme.primary;
        return StreamBuilder<void>(
          stream: Stream<void>.periodic(const Duration(seconds: 15)),
          builder: (context, _) => InkWell(
            key: const ValueKey('musicMiniPlayerSleepTimer'),
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bedtime, size: 18, color: color),
                  const SizedBox(width: 4),
                  Text(MusicSleepTimer.describe(state),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: color)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The bottom-left "Back to music" / "Back to videos" button floating just
/// above the song bar on every Best Music screen (`main_music.dart`). One
/// tap stops what's playing and resumes the other kind where it was left
/// — the last song at the music volume and 1×, or the last video at the
/// video volume and speed ([MusicAudioHandler.switchToOtherSession]).
/// Hidden while there's nothing to switch to, and while Now Playing (which
/// has its own switch chip) is open. Outside the navigator, so no tooltip.
class SessionSwitchPill extends StatelessWidget {
  const SessionSwitchPill({super.key, this.handler});

  /// Defaults to [MusicPlayerService.handler] once it's ready.
  final MusicAudioHandler? handler;

  @override
  Widget build(BuildContext context) {
    final audio = handler ??
        (MusicPlayerService.isReady ? MusicPlayerService.handler : null);
    if (audio == null) return const SizedBox.shrink();
    final feed = YoutubeFeedService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: NowPlayingPage.openCount,
      builder: (context, nowPlayingOpen, _) {
        if (nowPlayingOpen > 0) return const SizedBox.shrink();
        return StreamBuilder<MediaItem?>(
          stream: audio.mediaItem,
          initialData: audio.mediaItem.valueOrNull,
          builder: (context, _) => ListenableBuilder(
            listenable: Listenable.merge(
                [audio.otherSession, feed.progress, feed.videos]),
            builder: (context, _) {
              final target = audio.switchTarget();
              if (target == null) return const SizedBox.shrink();
              final scheme = Theme.of(context).colorScheme;
              final label = target.isVideo ? 'Back to videos' : 'Back to music';
              return Semantics(
                button: true,
                label: '$label: ${target.current.title}',
                child: Material(
                  key: const ValueKey('sessionSwitchPill'),
                  color: scheme.secondaryContainer,
                  elevation: 3,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: audio.switchToOtherSession,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            target.isVideo
                                ? Icons.smart_display_outlined
                                : Icons.library_music_outlined,
                            size: 18,
                            color: scheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
