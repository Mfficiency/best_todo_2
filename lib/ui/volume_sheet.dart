import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/youtube_feed.dart';
import '../services/media_volume.dart';
import '../services/youtube_feed_service.dart';

/// The phone's media volume for music ([video] false) or for
/// Subscriptions-feed videos ([video] true, plus a boost slider for quiet
/// videos). Not an app volume: it is the phone's own volume, remembered
/// separately for music and videos and switched automatically when
/// playback goes from one to the other ([MediaVolume]). Moving the slider
/// for what's playing changes the phone's volume right away; for the
/// other kind it sets the level it will get next time.
Future<void> showVolumeSheet(BuildContext context, {required bool video}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => VolumeSheet(video: video),
  );
}

/// Boost needs Android's LoudnessEnhancer.
bool get volumeBoostSupported => !kIsWeb && Platform.isAndroid;

String formatVolume(double volume) => '${(volume * 100).round()}%';

String formatBoost(double db) => db <= 0 ? 'Off' : '+${db.round()} dB';

/// "40%" for a remembered level, or that there isn't one yet.
String describeRememberedVolume(VolumeKind kind) {
  final v = MediaVolume.remembered(kind);
  return v == null ? 'Not remembered yet' : formatVolume(v);
}

class VolumeSheet extends StatefulWidget {
  const VolumeSheet({super.key, required this.video, this.feed});

  final bool video;
  final YoutubeFeedService? feed;

  @override
  State<VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<VolumeSheet> {
  late final YoutubeFeedService _feed =
      widget.feed ?? YoutubeFeedService.instance;
  late final VolumeKind _kind =
      widget.video ? VolumeKind.video : VolumeKind.music;
  late double _volume = MediaVolume.remembered(_kind) ?? 0.5;
  late double _boost = _feed.settings.value.videoBoostDb;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final v = await MediaVolume.current(_kind);
    if (v != null && mounted) setState(() => _volume = v);
  }

  /// Live while dragging; remembered once the drag ends.
  void _setVolume(double value) {
    setState(() => _volume = value);
    unawaited(MediaVolume.choose(_kind, value, persist: false));
  }

  void _persistVolume(double value) =>
      unawaited(MediaVolume.choose(_kind, value));

  void _setBoost(double value) {
    setState(() => _boost = value);
    _feed.settings.value = _feed.settings.value.copyWith(videoBoostDb: value);
  }

  void _persistBoost(double _) =>
      unawaited(_feed.updateSettings(_feed.settings.value));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.video ? 'Video volume' : 'Music volume',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Text(
              widget.video
                  ? "Your phone's volume while videos play. It's remembered, "
                      'and switches back by itself when you go between '
                      'videos and music'
                  : "Your phone's volume while music plays. It's remembered, "
                      'and switches back by itself when you go between '
                      'music and videos',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  key: const ValueKey('volumeSlider'),
                  value: _volume.clamp(0.0, 1.0),
                  divisions: 20,
                  label: formatVolume(_volume),
                  onChanged: _setVolume,
                  onChangeEnd: _persistVolume,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(formatVolume(_volume), textAlign: TextAlign.end),
              ),
            ]),
            if (widget.video && volumeBoostSupported) ...[
              const SizedBox(height: 8),
              Text('Boost for quiet videos',
                  style: theme.textTheme.titleSmall),
              Row(children: [
                const Icon(Icons.volume_up),
                Expanded(
                  child: Slider(
                    key: const ValueKey('boostSlider'),
                    value: _boost.clamp(0.0, YoutubeFeedSettings.maxBoostDb),
                    max: YoutubeFeedSettings.maxBoostDb,
                    divisions: YoutubeFeedSettings.maxBoostDb.round(),
                    label: formatBoost(_boost),
                    onChanged: _setBoost,
                    onChangeEnd: _persistBoost,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(formatBoost(_boost), textAlign: TextAlign.end),
                ),
              ]),
              Text(
                'Only in this app: lifts videos past the phone\'s 100% — high '
                    'boosts can distort loud ones',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
