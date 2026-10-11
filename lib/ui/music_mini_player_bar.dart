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
import 'youtube_feed_page.dart';

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
    navigator.push(NowPlayingPage.route());
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
                            SwitchSessionButton(
                                handler: audio, navigatorKey: navigatorKey),
                          _SleepTimerBadge(
                              onTap: () =>
                                  showSleepTimerSheet(_sheetContext(context))),
                          if (audio is MusicAudioHandler &&
                              (audio.currentTrack?.isFeedVideo ?? false))
                            IconButton(
                              icon: const Icon(Icons.replay_10),
                              tooltip: 'Back 10 seconds',
                              visualDensity: VisualDensity.compact,
                              onPressed: audio.rewind,
                            ),
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
                          if (audio is MusicAudioHandler &&
                              (audio.currentTrack?.isFeedVideo ?? false))
                            IconButton(
                              icon: const Icon(Icons.forward_10),
                              tooltip: 'Forward 10 seconds',
                              visualDensity: VisualDensity.compact,
                              onPressed: audio.fastForward,
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

/// Brings the screen along with the sound: the Subscriptions feed for a
/// video, Now Playing for a song. Pops back to an already open copy of
/// that page (or to the root) rather than stacking another one.
void showSessionScreen(NavigatorState navigator, {required bool video}) {
  final name = video ? YoutubeFeedPage.routeName : NowPlayingPage.routeName;
  var found = false;
  navigator.popUntil((route) {
    if (route.settings.name == name) return found = true;
    return route.isFirst;
  });
  if (!found) {
    navigator.push(video ? YoutubeFeedPage.route() : NowPlayingPage.route());
  }
}

/// "Back to video"/"Back to music": switches playback to the other session
/// ([MusicAudioHandler.switchToOtherSession]) and, when [navigator] is
/// given, opens that session's screen too ([showSessionScreen]).
Future<void> switchSessionAndShow(
    MusicAudioHandler handler, NavigatorState? navigator) async {
  final target = handler.switchTarget();
  if (target == null) return;
  // Switching starts the other session playing — ask first if that would
  // be out of the phone's speaker (a video still loading doesn't count as
  // already listening, see MusicAudioHandler.isAudible).
  final askContext = navigator?.context;
  if (askContext != null &&
      askContext.mounted &&
      !await SpeakerPlayGuard.confirmPlay(askContext)) {
    return;
  }
  final switching = handler.switchToOtherSession();
  if (navigator != null) showSessionScreen(navigator, video: target.isVideo);
  await switching;
}

/// One tap back into the other kind of listening — the last song while a
/// video plays, the last video while music plays — resuming where it was
/// stopped ([MusicAudioHandler.switchToOtherSession]). Hidden until there
/// is one. No tooltip: the mini player has no Overlay, so it's labelled
/// through [Semantics] instead.
class SwitchSessionButton extends StatelessWidget {
  const SwitchSessionButton(
      {super.key, required this.handler, this.navigatorKey});

  final MusicAudioHandler handler;

  /// Navigator the target's screen opens on; defaults to the nearest one.
  final GlobalKey<NavigatorState>? navigatorKey;

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
            onPressed: () => switchSessionAndShow(handler,
                navigatorKey?.currentState ?? Navigator.maybeOf(context)),
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

/// The bottom-left "Back to music" / "Back to videos" button — a small
/// translucent circle with just a music/video icon (0.3.15; it used to be
/// a labelled pill that hid snackbars behind it) — floating just
/// above the song bar on every Best Music screen (`main_music.dart`). One
/// tap opens the other kind's screen (the feed / Now Playing) and resumes
/// it where it was left
/// — the last song at the music volume and 1×, or the last video at the
/// video volume and speed ([MusicAudioHandler.switchToOtherSession]).
/// Hidden while there's nothing to switch to, and while Now Playing (which
/// has its own switch chip) is open. Outside the navigator, so no tooltip.
class SessionSwitchPill extends StatelessWidget {
  const SessionSwitchPill({super.key, this.handler, this.navigatorKey});

  /// Defaults to [MusicPlayerService.handler] once it's ready.
  final MusicAudioHandler? handler;

  /// Navigator the target's screen (feed / Now Playing) opens on.
  final GlobalKey<NavigatorState>? navigatorKey;

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
              // A small see-through circle rather than a labelled pill, so
              // a snackbar (an error message, an Undo) showing behind it
              // stays readable.
              return Semantics(
                button: true,
                label: '$label: ${target.current.title}',
                child: Material(
                  key: const ValueKey('sessionSwitchPill'),
                  color: scheme.secondaryContainer.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => switchSessionAndShow(audio,
                        navigatorKey?.currentState ??
                            Navigator.maybeOf(context)),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        target.isVideo
                            ? Icons.smart_display_outlined
                            : Icons.library_music_outlined,
                        size: 20,
                        color: scheme.onSecondaryContainer
                            .withValues(alpha: 0.85),
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
