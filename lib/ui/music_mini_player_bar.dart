import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/music_player_service.dart';
import 'now_playing_page.dart';

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
              child: InkWell(
                onTap: () => _openNowPlaying(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            if ((item.artist ?? '').isNotEmpty)
                              Text(item.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      StreamBuilder<PlaybackState>(
                        stream: audio.playbackState,
                        initialData: audio.playbackState.valueOrNull,
                        builder: (context, stateSnapshot) {
                          final playing = stateSnapshot.data?.playing ?? false;
                          return Semantics(
                            label: playing ? 'Pause' : 'Play',
                            button: true,
                            child: IconButton(
                              key: const ValueKey('musicMiniPlayerPlayPause'),
                              icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow),
                              onPressed: () =>
                                  playing ? audio.pause() : audio.play(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
