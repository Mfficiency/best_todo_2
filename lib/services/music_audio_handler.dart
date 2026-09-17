import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:just_audio/just_audio.dart' as ja;

import '../models/track.dart';
import 'music_library_service.dart';
import 'music_playlist_service.dart';
import 'subsonic_client.dart';

/// The app's single [BaseAudioHandler]: everything the system media
/// notification, lock screen, headset buttons and (when registered through
/// [AudioService.init]) Android Auto talk to. Wraps a [ja.AudioPlayer] and
/// owns the play queue (built by [MusicPlaylistService.weightedShuffle] or
/// handed a specific playlist/track list), advancing automatically when a
/// track finishes and reshuffling once the queue runs out so playback keeps
/// going indefinitely, "radio" style.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  final ja.AudioPlayer _player = ja.AudioPlayer();

  List<Track> _queue = [];
  int _queueIndex = -1;

  /// Whether the upcoming queue is in shuffled order. Toggled by
  /// [toggleShuffle]; the Now Playing shuffle button listens to this.
  final ValueNotifier<bool> shuffleEnabled = ValueNotifier(false);

  /// Queue order captured just before [toggleShuffle] shuffled it, so
  /// turning shuffle back off can restore it. Cleared by a manual
  /// [reorderQueue] so a drag edit isn't silently discarded later.
  List<Track>? _preShuffleOrder;

  // just_audio's playbackEventStream only fires on discrete state changes
  // (buffering, track load, pause/play), not once a second — without this,
  // the Now Playing progress line/position text never advances while a
  // track is actually playing.
  Timer? _positionTicker;

  MusicAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState, onError: (Object e, StackTrace st) {
      _broadcastState(_player.playbackEvent);
    });
    _player.processingStateStream.listen((state) {
      if (state == ja.ProcessingState.completed) {
        _advance(1, wrapWithReshuffle: true);
      }
    });
    _player.playingStream.listen((playing) {
      _positionTicker?.cancel();
      _positionTicker = playing
          ? Timer.periodic(const Duration(seconds: 1),
              (_) => _broadcastState(_player.playbackEvent))
          : null;
    });
    // Track duration isn't reliably known from file tags at scan time; take
    // it from the player once the audio source actually reports it, so the
    // progress bar's total time (and seek range) are correct for every
    // format, not just tagged mp3s.
    _player.durationStream.listen((duration) {
      final current = mediaItem.valueOrNull;
      if (current != null && duration != null && current.duration != duration) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  Track? get currentTrack =>
      (_queueIndex >= 0 && _queueIndex < _queue.length) ? _queue[_queueIndex] : null;

  List<Track> get currentQueueTracks => _queue;

  void _broadcastState(ja.PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ja.ProcessingState.idle: AudioProcessingState.idle,
        ja.ProcessingState.loading: AudioProcessingState.loading,
        ja.ProcessingState.buffering: AudioProcessingState.buffering,
        ja.ProcessingState.ready: AudioProcessingState.ready,
        ja.ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _queueIndex >= 0 ? _queueIndex : null,
    ));
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        title: t.title.isNotEmpty ? t.title : t.fileBaseName,
        artist: t.artist.isNotEmpty ? t.artist : null,
        album: t.album.isNotEmpty ? t.album : null,
        duration: t.durationMs != null ? Duration(milliseconds: t.durationMs!) : null,
      );

  Future<Uri> _resolveUri(Track track) async {
    switch (track.source) {
      case TrackSource.local:
        return Uri.file(track.filePath!);
      case TrackSource.subsonic:
        return SubsonicClient.instance.streamUri(track.remoteId!);
    }
  }

  /// Replaces the play queue and starts playing at [startIndex] (default:
  /// the first track).
  Future<void> setQueueAndPlay(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue = tracks;
    _queueIndex = startIndex.clamp(0, tracks.length - 1);
    _preShuffleOrder = null;
    shuffleEnabled.value = false;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    mediaItem.add(_toMediaItem(track));
    try {
      final uri = await _resolveUri(track);
      await _player.setAudioSource(ja.AudioSource.uri(uri));
      await _player.play();
    } catch (_) {
      // Unplayable track (missing file, unreachable server): skip it rather
      // than getting stuck silently.
      await _advance(1, wrapWithReshuffle: true);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _advance(1, wrapWithReshuffle: true);

  @override
  Future<void> skipToPrevious() => _advance(-1, wrapWithReshuffle: false);

  Future<void> _advance(int delta, {required bool wrapWithReshuffle}) async {
    if (_queue.isEmpty) return;
    var next = _queueIndex + delta;
    if (next >= _queue.length) {
      if (!wrapWithReshuffle) return;
      final library = MusicLibraryService.instance.tracks.value;
      if (library.isEmpty) return;
      _queue = MusicPlaylistService.instance.weightedShuffle(library);
      queue.add(_queue.map(_toMediaItem).toList());
      next = 0;
    }
    if (next < 0) next = 0;
    _queueIndex = next;
    await _playCurrent();
  }

  /// Toggles shuffle. Turning it on shuffles the not-yet-played tail of the
  /// queue (leaving playback history and the current track in place);
  /// turning it off restores the order the tail had before shuffling.
  Future<void> toggleShuffle() async {
    if (shuffleEnabled.value) {
      shuffleEnabled.value = false;
      final original = _preShuffleOrder;
      _preShuffleOrder = null;
      if (original == null) return;
      final current = currentTrack;
      _queue = original;
      _queueIndex =
          current == null ? 0 : _queue.indexWhere((t) => t.id == current.id);
      if (_queueIndex < 0) _queueIndex = 0;
      queue.add(_queue.map(_toMediaItem).toList());
      return;
    }
    shuffleEnabled.value = true;
    if (_queueIndex < 0 || _queueIndex >= _queue.length - 1) return;
    _preShuffleOrder = List.of(_queue);
    final upcoming = _queue.sublist(_queueIndex + 1)..shuffle();
    _queue = [..._queue.sublist(0, _queueIndex + 1), ...upcoming];
    queue.add(_queue.map(_toMediaItem).toList());
  }

  /// Moves the track at [oldIndex] to [newIndex] (Flutter
  /// `ReorderableListView` index convention), keeping the currently playing
  /// track's identity intact even if its position shifts.
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;
    _queue = List.of(_queue);
    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    if (oldIndex == _queueIndex) {
      _queueIndex = newIndex;
    } else if (oldIndex < _queueIndex && newIndex >= _queueIndex) {
      _queueIndex -= 1;
    } else if (oldIndex > _queueIndex && newIndex <= _queueIndex) {
      _queueIndex += 1;
    }
    _preShuffleOrder = null;
    queue.add(_queue.map(_toMediaItem).toList());
  }

  /// Swipe-up on Now Playing: favorites the current track without
  /// interrupting playback.
  Future<void> favoriteCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    await MusicPlaylistService.instance.toggleFavorite(track.id);
  }

  /// Swipe-down on Now Playing: marks the current track disliked (so it
  /// comes up far less in future shuffles) and skips it right away.
  Future<void> dislikeCurrentAndSkip() async {
    final track = currentTrack;
    if (track == null) return;
    await MusicPlaylistService.instance.markDisliked(track.id);
    await skipToNext();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    await super.stop();
  }

  Future<void> dispose() async {
    _positionTicker?.cancel();
    shuffleEnabled.dispose();
    await _player.dispose();
  }
}
