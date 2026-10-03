/// Data types behind Best Music's Subscriptions feed (SPEC.md §10.6m): the
/// YouTube channels the user follows, the videos fetched from them, how far
/// each one has been listened to, the feed's settings, and SponsorBlock
/// skip segments. All plain values with tolerant `toJson`/`fromJson`,
/// persisted together by `YoutubeFeedService` in `youtube_feed.json`.
library;

/// A YouTube channel the user is subscribed to.
class YoutubeChannel {
  const YoutubeChannel({
    required this.id,
    required this.name,
    this.avatarUrl,
  });

  /// The `UC...` channel id.
  final String id;
  final String name;
  final String? avatarUrl;

  String get url => 'https://www.youtube.com/channel/$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  factory YoutubeChannel.fromJson(Map<String, dynamic> json) => YoutubeChannel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
      );
}

/// One video in the feed.
class FeedVideo {
  const FeedVideo({
    required this.videoId,
    required this.title,
    required this.channelId,
    required this.channelName,
    this.published,
    this.description = '',
    this.duration,
    this.viewCount,
    this.isShort = false,
    this.isLivestream = false,
  });

  final String videoId;
  final String title;
  final String channelId;
  final String channelName;

  /// Upload time. Exact when it came from the channel's RSS feed; only
  /// approximate ("3 days ago") when the RSS feed failed and the channel's
  /// Videos tab was used instead.
  final DateTime? published;

  /// Full description from the RSS feed; empty when unknown (the video
  /// page then fetches it on demand).
  final String description;

  /// Known only when the channel's Videos tab listed the video.
  final Duration? duration;
  final int? viewCount;

  /// Linked as `youtube.com/shorts/<id>` in the RSS feed.
  final bool isShort;

  /// In the RSS feed but not on the channel's Videos tab (and not a Short):
  /// a live, upcoming or past livestream, listed under the Live tab.
  final bool isLivestream;

  String get watchUrl => 'https://www.youtube.com/watch?v=$videoId';

  /// 320x180, for list rows.
  String get thumbnailUrl => 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';

  /// 480x360, for the video page, Now Playing and the media notification.
  String get largeThumbnailUrl =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  FeedVideo copyWith({
    String? description,
    Duration? duration,
    int? viewCount,
  }) =>
      FeedVideo(
        videoId: videoId,
        title: title,
        channelId: channelId,
        channelName: channelName,
        published: published,
        description: description ?? this.description,
        duration: duration ?? this.duration,
        viewCount: viewCount ?? this.viewCount,
        isShort: isShort,
        isLivestream: isLivestream,
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelId': channelId,
        'channelName': channelName,
        if (published != null) 'published': published!.millisecondsSinceEpoch,
        if (description.isNotEmpty) 'description': description,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (viewCount != null) 'viewCount': viewCount,
        if (isShort) 'isShort': true,
        if (isLivestream) 'isLivestream': true,
      };

  factory FeedVideo.fromJson(Map<String, dynamic> json) {
    final published = json['published'];
    final durationMs = json['durationMs'];
    return FeedVideo(
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      channelId: json['channelId'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      published: published is num
          ? DateTime.fromMillisecondsSinceEpoch(published.round())
          : null,
      description: json['description'] as String? ?? '',
      duration: durationMs is num
          ? Duration(milliseconds: durationMs.round())
          : null,
      viewCount: (json['viewCount'] as num?)?.round(),
      isShort: json['isShort'] as bool? ?? false,
      isLivestream: json['isLivestream'] as bool? ?? false,
    );
  }
}

/// How far a video has been listened to — backs the feed's played markers
/// and resuming a long video where it was left.
class WatchProgress {
  const WatchProgress({
    required this.position,
    this.duration,
    this.completed = false,
    required this.updated,
  });

  final Duration position;
  final Duration? duration;
  final bool completed;
  final DateTime updated;

  /// 0..1 when the duration is known, else null.
  double? get fraction {
    final total = duration;
    if (completed) return 1;
    if (total == null || total.inMilliseconds <= 0) return null;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'p': position.inMilliseconds,
        if (duration != null) 'd': duration!.inMilliseconds,
        if (completed) 'done': true,
        't': updated.millisecondsSinceEpoch,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> json) => WatchProgress(
        position: Duration(milliseconds: (json['p'] as num?)?.round() ?? 0),
        duration: json['d'] is num
            ? Duration(milliseconds: (json['d'] as num).round())
            : null,
        completed: json['done'] as bool? ?? false,
        updated: DateTime.fromMillisecondsSinceEpoch(
            (json['t'] as num?)?.round() ?? 0),
      );
}

/// A SponsorBlock category (https://wiki.sponsor.ajay.app/w/Types), with
/// the label the settings page shows.
enum SponsorBlockCategory {
  sponsor('sponsor', 'Sponsor'),
  selfpromo('selfpromo', 'Unpaid/self promotion'),
  interaction('interaction', 'Interaction reminder (subscribe)'),
  intro('intro', 'Intermission/intro animation'),
  outro('outro', 'Endcards/credits'),
  preview('preview', 'Preview/recap'),
  musicOfftopic('music_offtopic', 'Non-music section (music videos)'),
  filler('filler', 'Filler tangent/jokes');

  const SponsorBlockCategory(this.key, this.label);

  /// The id SponsorBlock's API uses.
  final String key;
  final String label;

  static SponsorBlockCategory? fromKey(String key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// The feed's settings.
class YoutubeFeedSettings {
  const YoutubeFeedSettings({
    this.sponsorBlockEnabled = true,
    this.sponsorBlockCategories = defaultSponsorBlockCategories,
    this.hideShorts = true,
    this.hideLivestreams = true,
    this.playbackSpeed = 1.0,
    this.videoVolume = 1.0,
    this.videoBoostDb = 0.0,
  });

  /// Upper end of the boost slider. LoudnessEnhancer starts to clip
  /// audibly much past this on already-loud material.
  static const double maxBoostDb = 12.0;

  /// Speeds offered by the speed sheet; [playbackSpeed] can be anything in
  /// [minSpeed]..[maxSpeed] via its slider.
  static const List<double> speedPresets = [
    0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0,
  ];
  static const double minSpeed = 0.5;
  static const double maxSpeed = 3.0;

  static const Set<SponsorBlockCategory> defaultSponsorBlockCategories = {
    SponsorBlockCategory.sponsor,
    SponsorBlockCategory.selfpromo,
    SponsorBlockCategory.interaction,
    SponsorBlockCategory.musicOfftopic,
  };

  final bool sponsorBlockEnabled;
  final Set<SponsorBlockCategory> sponsorBlockCategories;
  final bool hideShorts;

  /// Hides live, upcoming and past livestreams — anything a channel lists
  /// under its Live tab rather than its Videos tab.
  final bool hideLivestreams;

  /// Default playback speed for feed videos (local songs always play at
  /// 1x). Changing the speed from Now Playing overrides it for the rest of
  /// that queue only.
  final double playbackSpeed;

  /// Player volume (0..1) for feed videos — separate from music's
  /// (`Config.musicVolume`), since videos are usually played louder.
  final double videoVolume;

  /// Extra loudness (0..[maxBoostDb] dB, Android's LoudnessEnhancer) for
  /// quietly mastered videos; applied to feed videos only, never to music.
  final double videoBoostDb;

  YoutubeFeedSettings copyWith({
    bool? sponsorBlockEnabled,
    Set<SponsorBlockCategory>? sponsorBlockCategories,
    bool? hideShorts,
    bool? hideLivestreams,
    double? playbackSpeed,
    double? videoVolume,
    double? videoBoostDb,
  }) =>
      YoutubeFeedSettings(
        sponsorBlockEnabled: sponsorBlockEnabled ?? this.sponsorBlockEnabled,
        sponsorBlockCategories:
            sponsorBlockCategories ?? this.sponsorBlockCategories,
        hideShorts: hideShorts ?? this.hideShorts,
        hideLivestreams: hideLivestreams ?? this.hideLivestreams,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        videoVolume: videoVolume ?? this.videoVolume,
        videoBoostDb: videoBoostDb ?? this.videoBoostDb,
      );

  Map<String, dynamic> toJson() => {
        'sponsorBlockEnabled': sponsorBlockEnabled,
        'sponsorBlockCategories': [
          for (final c in sponsorBlockCategories) c.key,
        ],
        'hideShorts': hideShorts,
        'hideLivestreams': hideLivestreams,
        'playbackSpeed': playbackSpeed,
        'videoVolume': videoVolume,
        'videoBoostDb': videoBoostDb,
      };

  factory YoutubeFeedSettings.fromJson(Map<String, dynamic> json) {
    final categories = json['sponsorBlockCategories'];
    return YoutubeFeedSettings(
      sponsorBlockEnabled: json['sponsorBlockEnabled'] as bool? ?? true,
      sponsorBlockCategories: categories is List
          ? {
              for (final key in categories)
                if (SponsorBlockCategory.fromKey(key.toString()) != null)
                  SponsorBlockCategory.fromKey(key.toString())!,
            }
          : defaultSponsorBlockCategories,
      hideShorts: json['hideShorts'] as bool? ?? true,
      hideLivestreams: json['hideLivestreams'] as bool? ?? true,
      playbackSpeed: ((json['playbackSpeed'] as num?)?.toDouble() ?? 1.0)
          .clamp(minSpeed, maxSpeed),
      videoVolume: ((json['videoVolume'] as num?)?.toDouble() ?? 1.0)
          .clamp(0.0, 1.0),
      videoBoostDb: ((json['videoBoostDb'] as num?)?.toDouble() ?? 0.0)
          .clamp(0.0, maxBoostDb),
    );
  }
}

/// A stretch of a video SponsorBlock says to skip.
class SkipSegment {
  const SkipSegment({
    required this.start,
    required this.end,
    required this.category,
  });

  final Duration start;
  final Duration end;
  final String category;
}
