import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/youtube_feed.dart';
import '../services/music_player_service.dart';
import '../services/youtube_feed_service.dart';

/// Volume for music ([video] false: [Config.musicVolume]) or for
/// Subscriptions-feed videos ([video] true: [YoutubeFeedSettings.videoVolume]
/// plus a boost slider for quiet videos). The two are remembered
/// separately — music usually wants to be softer than videos — and a
/// change applies to what's playing right away.
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
  late double _volume = widget.video
      ? _feed.settings.value.videoVolume
      : Config.musicVolume;
  late double _boost = _feed.settings.value.videoBoostDb;

  void _applyNow() {
    if (MusicPlayerService.isReady) {
      MusicPlayerService.handler.applyCurrentVolume();
    }
  }

  /// Live while dragging: applied to the player, not yet written to disk.
  void _setVolume(double value) {
    setState(() => _volume = value);
    if (widget.video) {
      _feed.settings.value = _feed.settings.value.copyWith(videoVolume: value);
    } else {
      Config.musicVolume = value;
      _applyNow();
    }
  }

  void _setBoost(double value) {
    setState(() => _boost = value);
    _feed.settings.value = _feed.settings.value.copyWith(videoBoostDb: value);
  }

  /// Drag finished: remember it.
  void _persist([double _ = 0]) {
    if (widget.video) {
      unawaited(_feed.updateSettings(_feed.settings.value));
    } else {
      unawaited(Config.save());
    }
  }

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
                  ? 'Subscriptions videos only — music keeps its own volume'
                  : 'Songs only — Subscriptions videos keep their own volume',
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
                  onChangeEnd: _persist,
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
                    onChangeEnd: _persist,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(formatBoost(_boost), textAlign: TextAlign.end),
                ),
              ]),
              Text(
                'Lifts videos past 100% — high boosts can distort loud ones',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
