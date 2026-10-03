import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import 'music_player_service.dart';

/// "Play out loud?" — guards every Play/Shuffle/tap-a-song entry point of the
/// Music Player so a stray tap with nothing connected doesn't suddenly blast
/// music out of the phone's own speaker.
///
/// Asks only when all of these hold:
/// - [Config.musicConfirmSpeakerPlay] is on (Music settings),
/// - nothing is playing right now (switching songs mid-playback, or pausing,
///   never asks — the user is clearly already listening),
/// - the platform reports no output besides the built-in speaker/earpiece
///   (no Bluetooth speaker/headphones, wired/USB headset, car, ...) —
///   `besttodo/audio_output` → `MainActivity.isExternalAudioOutputConnected`.
///
/// Off Android, or if that check fails, it never asks: a false "are you
/// sure?" on every play would be worse than the occasional missing one.
class SpeakerPlayGuard {
  SpeakerPlayGuard._();

  static const MethodChannel _channel = MethodChannel('besttodo/audio_output');

  /// Overrides the platform check in tests: return true for "headphones or
  /// a speaker are connected", false for "phone speaker only".
  @visibleForTesting
  static Future<bool> Function()? externalOutputOverride;

  /// Overrides "is music playing right now" in tests.
  @visibleForTesting
  static bool Function()? isPlayingOverride;

  static bool _isPlaying() {
    final override = isPlayingOverride;
    if (override != null) return override();
    if (!MusicPlayerService.isReady) return false;
    return MusicPlayerService.handler.playbackState.valueOrNull?.playing ??
        false;
  }

  static Future<bool> _externalOutputConnected() async {
    final override = externalOutputOverride;
    if (override != null) return override();
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isExternalOutputConnected') ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// True when playback may start: no confirmation was needed, or the user
  /// confirmed. [context] must be under a [Navigator].
  static Future<bool> confirmPlay(BuildContext context) async {
    if (!Config.musicConfirmSpeakerPlay) return true;
    if (_isPlaying()) return true;
    if (await _externalOutputConnected()) return true;
    if (!context.mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.volume_up),
        title: const Text('Play out loud?'),
        content: const Text(
          'No Bluetooth speaker or headphones are connected, so music will '
          "play from the phone's speaker.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }
}
