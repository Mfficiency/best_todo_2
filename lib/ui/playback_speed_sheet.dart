import 'package:flutter/material.dart';

import '../models/youtube_feed.dart';
import '../services/music_player_service.dart';
import '../services/youtube_feed_service.dart';

/// `1×`, `1.25×`, `1.5×`.
String formatSpeed(double speed) {
  var text = speed.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '$text×';
}

/// Picks a playback speed for Subscriptions-feed videos: preset chips plus
/// a fine slider. The speed is remembered for the next videos either way;
/// from Now Playing ([forDefault] false) it also applies to the playing
/// video right away.
Future<void> showPlaybackSpeedSheet(
  BuildContext context, {
  bool forDefault = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _PlaybackSpeedSheet(forDefault: forDefault),
  );
}

class _PlaybackSpeedSheet extends StatefulWidget {
  const _PlaybackSpeedSheet({required this.forDefault});

  final bool forDefault;

  @override
  State<_PlaybackSpeedSheet> createState() => _PlaybackSpeedSheetState();
}

class _PlaybackSpeedSheetState extends State<_PlaybackSpeedSheet> {
  final YoutubeFeedService _feed = YoutubeFeedService.instance;
  late double _speed = widget.forDefault || !MusicPlayerService.isReady
      ? _feed.settings.value.playbackSpeed
      : MusicPlayerService.handler.videoSpeed.value;

  Future<void> _set(double speed) async {
    final value = (speed * 20).round() / 20; // 0.05 steps
    setState(() => _speed = value);
    if (widget.forDefault) {
      await _feed.updateSettings(
          _feed.settings.value.copyWith(playbackSpeed: value));
    } else if (MusicPlayerService.isReady) {
      await MusicPlayerService.handler.setVideoSpeed(value);
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
              widget.forDefault
                  ? 'Video speed'
                  : 'Playback speed  ${formatSpeed(_speed)}',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (widget.forDefault)
              Text(formatSpeed(_speed),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in YoutubeFeedSettings.speedPresets)
                  ChoiceChip(
                    label: Text(formatSpeed(preset)),
                    selected: (preset - _speed).abs() < 0.001,
                    onSelected: (_) => _set(preset),
                  ),
              ],
            ),
            Row(children: [
              IconButton(
                tooltip: 'Slower',
                icon: const Icon(Icons.remove),
                onPressed: _speed <= YoutubeFeedSettings.minSpeed
                    ? null
                    : () => _set(_speed - 0.05),
              ),
              Expanded(
                child: Slider(
                  min: YoutubeFeedSettings.minSpeed,
                  max: YoutubeFeedSettings.maxSpeed,
                  divisions: 50,
                  value: _speed.clamp(
                      YoutubeFeedSettings.minSpeed, YoutubeFeedSettings.maxSpeed),
                  label: formatSpeed(_speed),
                  onChanged: _set,
                ),
              ),
              IconButton(
                tooltip: 'Faster',
                icon: const Icon(Icons.add),
                onPressed: _speed >= YoutubeFeedSettings.maxSpeed
                    ? null
                    : () => _set(_speed + 0.05),
              ),
            ]),
            Text(
              'Remembered for your next videos — songs always play at 1×',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Now Playing's app-bar speed button: shows the current speed (e.g.
/// `1.5×`) while a Subscriptions-feed video plays, hidden otherwise.
class PlaybackSpeedButton extends StatelessWidget {
  const PlaybackSpeedButton({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || !MusicPlayerService.isReady) return const SizedBox.shrink();
    return ValueListenableBuilder<double>(
      valueListenable: MusicPlayerService.handler.videoSpeed,
      builder: (context, speed, _) => Tooltip(
        message: 'Playback speed',
        child: TextButton(
          onPressed: () => showPlaybackSpeedSheet(context),
          child: Text(formatSpeed(speed)),
        ),
      ),
    );
  }
}
