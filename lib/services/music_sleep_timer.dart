import 'dart:async';

import 'package:flutter/foundation.dart';

import 'music_player_service.dart';

/// What the sleep timer is currently set to.
@immutable
class SleepTimerState {
  const SleepTimerState.off()
      : endsAt = null,
        endOfTrack = false;
  const SleepTimerState.at(DateTime this.endsAt) : endOfTrack = false;
  const SleepTimerState.endOfTrack()
      : endsAt = null,
        endOfTrack = true;

  /// When playback pauses, for a timed sleep timer.
  final DateTime? endsAt;

  /// Pause when the current song finishes instead of at a time.
  final bool endOfTrack;

  bool get isActive => endsAt != null || endOfTrack;
}

/// The Music Player's one sleep timer: pauses playback after a duration or
/// at the end of the current song. Every place that offers it (Now
/// Playing, the mini player, the Best Music drawer, Settings) drives this
/// same instance through `showSleepTimerSheet`, so they always agree.
class MusicSleepTimer {
  MusicSleepTimer._();

  static final MusicSleepTimer instance = MusicSleepTimer._();

  final ValueNotifier<SleepTimerState> state =
      ValueNotifier(const SleepTimerState.off());

  Timer? _timer;

  /// Pauses playback; overridable so tests needn't build a real player.
  @visibleForTesting
  Future<void> Function() pausePlayback = () async {
    if (MusicPlayerService.isReady) await MusicPlayerService.handler.pause();
  };

  /// Pause [duration] from now, replacing any running timer.
  void start(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, _fire);
    state.value = SleepTimerState.at(DateTime.now().add(duration));
  }

  /// Pause when the current song ends (see [MusicAudioHandler]).
  void startEndOfTrack() {
    _timer?.cancel();
    _timer = null;
    state.value = const SleepTimerState.endOfTrack();
  }

  /// Push a running timed timer back by [extra].
  void extend(Duration extra) {
    final endsAt = state.value.endsAt;
    if (endsAt == null) return;
    final remaining = endsAt.difference(DateTime.now());
    start((remaining.isNegative ? Duration.zero : remaining) + extra);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state.value = const SleepTimerState.off();
  }

  /// Called by the audio handler when a song plays to its end: true means
  /// "stop here" (the end-of-song timer was set, and is now used up).
  bool consumeEndOfTrack() {
    if (!state.value.endOfTrack) return false;
    cancel();
    return true;
  }

  Future<void> _fire() async {
    cancel();
    await pausePlayback();
  }

  /// "23 min", "1 h 5 min", "End of song" — for buttons and the mini
  /// player badge.
  static String describe(SleepTimerState s, {DateTime? now}) {
    if (s.endOfTrack) return 'End of song';
    final endsAt = s.endsAt;
    if (endsAt == null) return 'Off';
    final left = endsAt.difference(now ?? DateTime.now());
    final minutes = (left.inSeconds / 60).ceil().clamp(0, 100000);
    if (minutes >= 60) {
      final m = minutes % 60;
      return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $m min';
    }
    return '$minutes min';
  }
}
