import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:just_audio/just_audio.dart' as ja;

import '../models/track.dart';
import '../models/youtube_feed.dart';
import 'media_volume.dart';
import 'music_library_service.dart';
import 'music_playlist_service.dart';
import 'music_resume_service.dart';
import 'music_sleep_timer.dart';
import 'sponsorblock_service.dart';
import 'video_audio_cache.dart';
import 'subsonic_client.dart';
import 'youtube_audio_source.dart';
import 'youtube_feed_service.dart';

/// A paused queue kept aside for [MusicAudioHandler.switchToOtherSession]:
/// the last music queue while a Subscriptions video plays, or the last
/// video queue while music plays, with where it was stopped.
class PlaybackSession {
  const PlaybackSession({
    required this.queue,
    required this.index,
    required this.position,
  });

  final List<Track> queue;
  final int index;
  final Duration position;

  Track get current => queue[index.clamp(0, queue.length - 1)];

  /// Whether this is a Subscriptions-video session (else music).
  bool get isVideo => current.isFeedVideo;
}

/// The app's single [BaseAudioHandler]: everything the system media
/// notification, lock screen, headset buttons and (when registered through
/// [AudioService.init]) Android Auto talk to. Wraps a [ja.AudioPlayer] and
/// owns the play queue (built by [MusicPlaylistService.weightedShuffle] or
/// handed a specific playlist/track list), advancing automatically when a
/// track finishes and reshuffling once the queue runs out so playback keeps
/// going indefinitely, "radio" style.
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  /// Android only: lifts quiet feed videos past 100% volume
  /// ([YoutubeFeedSettings.videoBoostDb]). Off for music.
  final ja.AndroidLoudnessEnhancer? _boost =
      _isAndroid ? ja.AndroidLoudnessEnhancer() : null;

  late final ja.AudioPlayer _player = ja.AudioPlayer(
    audioPipeline: _boost == null
        ? null
        : ja.AudioPipeline(androidAudioEffects: [_boost!]),
  );

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Whether volume boost is available on this device (Android only).
  bool get boostSupported => _boost != null;

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
  int _ticksSinceSave = 0;

  /// False after [restore]: the remembered track is shown (mini player,
  /// notification) but its audio isn't loaded until [play] is pressed, so
  /// app start does no audio work.
  bool _sourceLoaded = false;

  /// Where to start the remembered track once [play] loads it.
  Duration? _resumePosition;

  /// SponsorBlock segments to jump over in the current YouTube track, and
  /// which track they belong to (the lookup is async, so a late answer for
  /// a track already skipped past must not apply to the next one).
  List<SkipSegment> _skipSegments = const [];

  /// The speed feed videos play at right now — what Now Playing's speed
  /// button shows.
  final ValueNotifier<double> videoSpeed = ValueNotifier(1.0);

  /// The other kind's paused session (see [PlaybackSession]) — what the
  /// "Back to music"/"Back to video" buttons resume. Set whenever playback
  /// switches between music and Subscriptions videos.
  final ValueNotifier<PlaybackSession?> otherSession = ValueNotifier(null);

  /// The track whose audio the player currently holds.
  String? _loadedTrackId;
  String? _skipSegmentsTrackId;

  /// Whether sound is actually coming out: playing, *and* the current
  /// track's audio has been ready (so not a video still being looked up /
  /// buffered for the first time). The "Play out loud?" guard only trusts
  /// this — `playbackState.playing` is already true while a video loads,
  /// which let a switch to music skip the question.
  bool get isAudible => _player.playing && _audibleSinceLoad;
  bool _audibleSinceLoad = false;

  MusicAudioHandler() {
    // A volume/boost change in Feed settings (or the Now Playing volume
    // sheet) applies to the playing video right away.
    YoutubeFeedService.instance.settings.addListener(applyCurrentVolume);
    _player.playbackEventStream.listen(_broadcastState, onError: (Object e, StackTrace st) {
      _broadcastState(_player.playbackEvent);
    });
    _player.playerStateStream.listen((state) {
      if (state.playing && state.processingState == ja.ProcessingState.ready) {
        _audibleSinceLoad = true;
      }
    });
    _player.processingStateStream.listen((state) {
      if (state == ja.ProcessingState.completed) {
        // Only a track that actually played to the end counts as "played"
        // for the Most Played smart playlists — a manual skip goes through
        // skipToNext/skipToPrevious instead, which never reach this stream
        // state.
        final finished = currentTrack;
        if (finished != null) {
          unawaited(MusicLibraryService.instance.incrementPlayCount(finished.id));
          if (finished.isFeedVideo) {
            unawaited(YoutubeFeedService.instance
                .setPlayed(finished.remoteId!, true));
          }
        }
        // Sleep timer set to "end of song": stop here, rewound so play
        // starts this song again rather than sitting at its end.
        if (MusicSleepTimer.instance.consumeEndOfTrack()) {
          unawaited(_player.pause().then((_) async {
            await _player.seek(Duration.zero);
            _persist();
          }));
          return;
        }
        _advance(1, wrapWithReshuffle: true);
      }
    });
    _player.positionStream.listen(_skipSponsorSegment);
    _player.playingStream.listen((playing) {
      _positionTicker?.cancel();
      _positionTicker = playing
          ? Timer.periodic(const Duration(seconds: 1), (_) {
              _broadcastState(_player.playbackEvent);
              // Remember the position now and then, so a reboot or a killed
              // app resumes close to where it was.
              if (++_ticksSinceSave >= 15) _persist();
            })
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

  /// How far the back/forward buttons jump in a feed video.
  static const Duration seekStep = Duration(seconds: 10);

  /// "Back 10 seconds" / "Forward 10 seconds" in the notification, the
  /// lock screen and Android's media controls — feed videos only.
  static const MediaControl replay10Control = MediaControl(
    androidIcon: 'drawable/ic_replay_10',
    label: 'Back 10 seconds',
    action: MediaAction.rewind,
  );
  static const MediaControl forward10Control = MediaControl(
    androidIcon: 'drawable/ic_forward_10',
    label: 'Forward 10 seconds',
    action: MediaAction.fastForward,
  );

  /// The notification's buttons: a feed video also gets back/forward 10
  /// seconds around play/pause, and those three are what the collapsed
  /// notification shows.
  List<MediaControl> notificationControls(bool playing) {
    final video = currentTrack?.isFeedVideo ?? false;
    return [
      MediaControl.skipToPrevious,
      if (video) replay10Control,
      if (playing) MediaControl.pause else MediaControl.play,
      if (video) forward10Control,
      MediaControl.skipToNext,
    ];
  }

  List<int> _compactIndices() =>
      (currentTrack?.isFeedVideo ?? false) ? const [1, 2, 3] : const [0, 1, 2];

  void _broadcastState(ja.PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: notificationControls(playing),
      systemActions: const {
        MediaAction.seek,
        MediaAction.rewind,
        MediaAction.fastForward,
      },
      androidCompactActionIndices: _compactIndices(),
      processingState: const {
        ja.ProcessingState.idle: AudioProcessingState.idle,
        ja.ProcessingState.loading: AudioProcessingState.loading,
        ja.ProcessingState.buffering: AudioProcessingState.buffering,
        ja.ProcessingState.ready: AudioProcessingState.ready,
        ja.ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      // A restored track isn't loaded yet: report where it will resume.
      updatePosition: _sourceLoaded
          ? _player.position
          : (_resumePosition ?? Duration.zero),
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _queueIndex >= 0 ? _queueIndex : null,
    ));
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        artUri: t.artUrl != null ? Uri.tryParse(t.artUrl!) : null,
        title: t.title.isNotEmpty ? t.title : t.fileBaseName,
        artist: t.artist.isNotEmpty ? t.artist : null,
        album: t.album.isNotEmpty ? t.album : null,
        duration: t.durationMs != null ? Duration(milliseconds: t.durationMs!) : null,
      );

  Future<ja.AudioSource> _audioSourceFor(Track track) async {
    switch (track.source) {
      case TrackSource.local:
        return ja.AudioSource.uri(Uri.file(track.filePath!));
      case TrackSource.subsonic:
        return ja.AudioSource.uri(
            SubsonicClient.instance.streamUri(track.remoteId!));
      case TrackSource.youtube:
        // A feed video played in the last week is on disk already.
        if (track.isFeedVideo) {
          final cached =
              await VideoAudioCache.instance.cachedFile(track.remoteId!);
          if (cached != null) {
            unawaited(VideoAudioCache.instance.touch(cached));
            return ja.AudioSource.uri(Uri.file(cached.path));
          }
        }
        return YoutubeAudioSource(
          track.remoteId!,
          duration: track.durationMs != null
              ? Duration(milliseconds: track.durationMs!)
              : null,
        );
    }
  }

  /// Looks up SponsorBlock segments for a YouTube [track], if enabled.
  void _loadSkipSegments(Track track) {
    _skipSegments = const [];
    _skipSegmentsTrackId = track.id;
    final settings = YoutubeFeedService.instance.settings.value;
    if (!track.isFeedVideo || !settings.sponsorBlockEnabled) {
      return;
    }
    unawaited(SponsorBlockService.instance
        .segmentsFor(track.remoteId!, settings.sponsorBlockCategories)
        .then((segments) {
      if (_skipSegmentsTrackId == track.id) _skipSegments = segments;
    }));
  }

  /// Seeks past a SponsorBlock segment the playhead has entered. Only near
  /// a segment's start (the first 2 s), so dragging the seek bar into the
  /// middle of one deliberately still plays it.
  void _skipSponsorSegment(Duration position) {
    if (_skipSegments.isEmpty || !_player.playing) return;
    if (_skipSegmentsTrackId != currentTrack?.id) return;
    for (final segment in _skipSegments) {
      if (position >= segment.start &&
          position < segment.start + const Duration(seconds: 2) &&
          position < segment.end) {
        unawaited(_player.seek(segment.end));
        return;
      }
    }
  }

  /// The current queue and where it is, for [otherSession].
  PlaybackSession? _snapshotCurrent() {
    final track = currentTrack;
    if (track == null) return null;
    final position = _sourceLoaded && _loadedTrackId == track.id
        ? _player.position
        : (_resumePosition ?? Duration.zero);
    return PlaybackSession(
        queue: List.of(_queue), index: _queueIndex, position: position);
  }

  static MusicResumeState _resumeStateOf(
    List<Track> queue,
    int index,
    Duration position,
  ) {
    final current = queue[index.clamp(0, queue.length - 1)];
    return MusicResumeState(
      queueIds: [for (final t in queue) t.id],
      index: index,
      position: position,
      current: current,
      // Feed videos aren't in the library to be looked up by id later.
      tracks: current.isFeedVideo ? queue : null,
    );
  }

  /// Puts back the other kind's session saved before a restart.
  void restoreOtherSession(PlaybackSession? session) {
    otherSession.value =
        session == null || session.queue.isEmpty ? null : session;
  }

  /// What [switchToOtherSession] would resume: the remembered other
  /// session, or — before there is one — the last played Subscriptions
  /// video while music plays (or nothing does), or a fresh shuffle of the
  /// library while a video plays. Null when there's nothing to switch to.
  PlaybackSession? switchTarget() {
    final other = otherSession.value;
    if (other != null && other.queue.isNotEmpty) return other;
    final current = currentTrack;
    if (current == null || !current.isFeedVideo) {
      final video = YoutubeFeedService.instance.lastPlayedVideo();
      if (video == null) return null;
      return PlaybackSession(
        queue: [YoutubeFeedService.trackFor(video)],
        index: 0,
        position: Duration.zero, // the feed's own resume point applies
      );
    }
    final library = MusicLibraryService.instance.tracks.value;
    if (library.isEmpty) return null;
    return PlaybackSession(
      queue: MusicPlaylistService.instance.weightedShuffle(library),
      index: 0,
      position: Duration.zero,
    );
  }

  /// One tap back into the other kind of listening: stops what's playing
  /// now (remembering where, so the same button flips straight back) and
  /// resumes the last music queue or the last video queue where it
  /// stopped — each with its own remembered volume and speed (applied by
  /// [_playCurrent] from the track's kind).
  Future<void> switchToOtherSession() async {
    final other = switchTarget();
    if (other == null || other.queue.isEmpty) return;
    _persist(); // a feed video records its resume point here
    otherSession.value = _snapshotCurrent();
    _queue = other.queue;
    _queueIndex = other.index.clamp(0, other.queue.length - 1);
    _preShuffleOrder = null;
    shuffleEnabled.value = false;
    _resumePosition = other.position > Duration.zero ? other.position : null;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playCurrent();
  }

  /// Swipe-to-queue on a Subscriptions video: appends [track] to the
  /// *video* queue without interrupting anything — the playing queue when
  /// a video is playing (or paused), else the remembered video session
  /// ("Back to videos" then resumes into it), else a new paused one. A
  /// video already in that queue isn't added twice. Either way it starts
  /// downloading for offline play (VideoAudioCache). Returns false when it
  /// was already queued.
  Future<bool> addToVideoQueue(Track track) async {
    unawaited(VideoAudioCache.instance.cacheInBackground(track));
    final current = currentTrack;
    if (current == null) {
      restore([track]);
      _persist();
      return true;
    }
    if (current.isFeedVideo) {
      if (_queue.any((t) => t.id == track.id)) return false;
      _queue = [..._queue, track];
      if (_preShuffleOrder != null) {
        _preShuffleOrder = [..._preShuffleOrder!, track];
      }
      queue.add(_queue.map(_toMediaItem).toList());
      _persist();
      return true;
    }
    final other = otherSession.value;
    if (other != null && other.isVideo) {
      if (other.queue.any((t) => t.id == track.id)) return false;
      otherSession.value = PlaybackSession(
        queue: [...other.queue, track],
        index: other.index,
        position: other.position,
      );
    } else {
      otherSession.value = PlaybackSession(
          queue: [track], index: 0, position: Duration.zero);
    }
    _persist();
    return true;
  }

  /// How many videos after the playing one are downloaded ahead, so a
  /// queue keeps playing offline.
  static const int _videosAhead = 2;

  /// Saves queue/track/position for [restore] after a restart.
  void _persist() {
    _ticksSinceSave = 0;
    final track = currentTrack;
    if (track == null) return;
    // Only once this track's own audio is loaded — until then the player
    // still reports the previous track's position.
    if (track.isFeedVideo && _loadedTrackId == track.id) {
      unawaited(YoutubeFeedService.instance.recordProgress(
        track.remoteId!,
        _player.position,
        duration: _player.duration,
      ));
    }
    final other = otherSession.value;
    unawaited(MusicResumeService.save(
      _resumeStateOf(
        _queue,
        _queueIndex,
        _sourceLoaded ? _player.position : (_resumePosition ?? Duration.zero),
      ),
      other: other == null
          ? null
          : _resumeStateOf(other.queue, other.index, other.position),
    ));
  }

  /// Shows [tracks]/[index] as the current, paused queue without loading
  /// any audio — the app-start "last played" state. [play] then loads the
  /// track and starts at [position].
  void restore(List<Track> tracks, {int index = 0, Duration position = Duration.zero}) {
    if (tracks.isEmpty) return;
    _queue = tracks;
    _queueIndex = index.clamp(0, tracks.length - 1);
    _sourceLoaded = false;
    _resumePosition = position;
    queue.add(_queue.map(_toMediaItem).toList());
    mediaItem.add(_toMediaItem(currentTrack!));
    playbackState.add(playbackState.value.copyWith(
      controls: notificationControls(false),
      androidCompactActionIndices: _compactIndices(),
      processingState: AudioProcessingState.ready,
      playing: false,
      updatePosition: position,
      queueIndex: _queueIndex,
    ));
  }

  /// Replaces the play queue and starts playing at [startIndex] (default:
  /// the first track).
  Future<void> setQueueAndPlay(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    // Switching between music and Subscriptions videos: keep the queue
    // being left so it's one tap to get back into it.
    final current = currentTrack;
    final next = tracks[startIndex.clamp(0, tracks.length - 1)];
    if (current != null && current.isFeedVideo != next.isFeedVideo) {
      _persist();
      otherSession.value = _snapshotCurrent();
    }
    _queue = tracks;
    _queueIndex = startIndex.clamp(0, tracks.length - 1);
    _preShuffleOrder = null;
    _resumePosition = null;
    shuffleEnabled.value = false;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    mediaItem.add(_toMediaItem(track));
    var startAt = _resumePosition;
    _resumePosition = null;
    // A feed video picks up where it was left (podcasts, long mixes).
    if (startAt == null && track.isFeedVideo) {
      startAt = YoutubeFeedService.instance.resumePosition(track.remoteId!);
    }
    _loadedTrackId = null;
    _audibleSinceLoad = false;
    _persist();
    _loadSkipSegments(track);
    try {
      final source = await _audioSourceFor(track);
      await _player.setAudioSource(source, initialPosition: startAt);
      _sourceLoaded = true;
      _loadedTrackId = track.id;
      await _applySpeed(track);
      await _applyVolume(track);
      // Keep a full copy of a video you start, so stopping halfway and
      // coming back later (even offline) is instant.
      if (track.isFeedVideo) {
        unawaited(VideoAudioCache.instance.cacheInBackground(track));
        // …and the next few in the queue, so it keeps going offline.
        for (final next in _queue.skip(_queueIndex + 1).take(_videosAhead)) {
          if (next.isFeedVideo) {
            unawaited(VideoAudioCache.instance.cacheInBackground(next));
          }
        }
      }
      await _player.play();
    } catch (_) {
      // Unplayable track (missing file, unreachable server): skip it rather
      // than getting stuck silently.
      await _advance(1, wrapWithReshuffle: true);
    }
  }

  /// The last video speed picked — remembered in the feed settings.
  double get _videoSpeedNow =>
      YoutubeFeedService.instance.settings.value.playbackSpeed;

  /// Feed videos play at the chosen speed; music (including songs
  /// streamed from YouTube) always at 1x.
  Future<void> _applySpeed(Track track) async {
    final speed = track.isFeedVideo ? _videoSpeedNow : 1.0;
    videoSpeed.value = _videoSpeedNow;
    if (_player.speed != speed) await _player.setSpeed(speed);
  }

  /// Now Playing's speed sheet: [speed] for feed videos, applied to the
  /// current one right away and remembered for the next ones (the
  /// settings listener applies it).
  Future<void> setVideoSpeed(double speed) async {
    final feed = YoutubeFeedService.instance;
    await feed.updateSettings(feed.settings.value.copyWith(
        playbackSpeed: speed.clamp(
            YoutubeFeedSettings.minSpeed, YoutubeFeedSettings.maxSpeed)));
  }

  /// No app-specific volume: the player always runs at full volume and
  /// the phone's own media volume is switched between music's and
  /// videos' remembered levels ([MediaVolume.onPlaying]). Feed videos
  /// also get their boost; music never does.
  Future<void> _applyVolume(Track track) async {
    final settings = YoutubeFeedService.instance.settings.value;
    final video = track.isFeedVideo;
    if (_player.volume != 1.0) await _player.setVolume(1.0);
    await MediaVolume.onPlaying(video ? VolumeKind.video : VolumeKind.music);
    final boost = _boost;
    if (boost == null) return;
    final gain = video ? settings.videoBoostDb : 0.0;
    try {
      await boost.setTargetGain(gain);
      await boost.setEnabled(gain > 0);
    } catch (_) {
      // Audio effects can be unavailable on some devices/sessions; the
      // phone volume still applies.
    }
  }

  /// Re-applies the boost and speed for the playing track — feed-settings
  /// changes trigger this on their own.
  void applyCurrentVolume() {
    final track = currentTrack;
    if (track == null) return;
    if (_sourceLoaded) {
      unawaited(_applyVolume(track));
      unawaited(_applySpeed(track));
    } else {
      videoSpeed.value = _videoSpeedNow;
    }
  }

  @override
  Future<void> play() {
    // A restored "last played" track has no audio loaded yet.
    if (!_sourceLoaded && currentTrack != null) return _playCurrent();
    return _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _persist();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// Back 10 seconds (notification, lock screen, headset, Now Playing).
  @override
  Future<void> rewind() => seekBy(-seekStep);

  /// Forward 10 seconds.
  @override
  Future<void> fastForward() => seekBy(seekStep);

  /// Jumps [delta] from where playback is, kept within the track. A
  /// restored track that isn't loaded yet moves its resume point instead.
  Future<void> seekBy(Duration delta) async {
    if (!_sourceLoaded) {
      if (currentTrack == null) return;
      var target = (_resumePosition ?? Duration.zero) + delta;
      if (target < Duration.zero) target = Duration.zero;
      _resumePosition = target;
      playbackState.add(playbackState.value.copyWith(updatePosition: target));
      return;
    }
    var target = _player.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    final duration = _player.duration;
    if (duration != null && target > duration) target = duration;
    await _player.seek(target);
  }

  @override
  Future<void> skipToNext() => _advance(1, wrapWithReshuffle: true);

  @override
  Future<void> skipToPrevious() => _advance(-1, wrapWithReshuffle: false);

  Future<void> _advance(int delta, {required bool wrapWithReshuffle}) async {
    if (_queue.isEmpty) return;
    var next = _queueIndex + delta;
    if (next >= _queue.length) {
      if (!wrapWithReshuffle) return;
      // The end of a Subscriptions-feed queue is the end, not a cue to
      // start shuffling the local library.
      if (currentTrack?.isFeedVideo ?? false) {
        await _player.pause();
        return;
      }
      final library = MusicLibraryService.instance.tracks.value;
      if (library.isEmpty) return;
      _queue = MusicPlaylistService.instance.weightedShuffle(library);
      queue.add(_queue.map(_toMediaItem).toList());
      next = 0;
    }
    if (next < 0) next = 0;
    // A remembered position belongs to the restored track only.
    if (next != _queueIndex) _resumePosition = null;
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
    _persist();
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
    _persist();
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
    YoutubeFeedService.instance.settings.removeListener(applyCurrentVolume);
    shuffleEnabled.dispose();
    videoSpeed.dispose();
    otherSession.dispose();
    await _player.dispose();
  }
}
