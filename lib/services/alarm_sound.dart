import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native alarm melody player (MainActivity).
///
/// The native side synthesizes the built-in melodies and plays them on the
/// ALARM audio stream at an absolute loudness: `volume` is a fraction of the
/// device's maximum, independent of whatever the media / ringer / alarm
/// volume happens to be set to. With `overrideDnd` the melody also plays
/// while Do Not Disturb is active; without it, playback is skipped under DND
/// so the phone stays quiet.
///
/// Everything is a silent no-op on non-Android platforms and in widget tests
/// (where the method channel has no host).
class AlarmSound {
  AlarmSound._();

  static const MethodChannel _channel = MethodChannel('besttodo/alarm_audio');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts playing [melody] at [volume] (0.0–1.0 of the device maximum).
  /// Returns true when playback actually started.
  static Future<bool> play({
    required String melody,
    required double volume,
    bool overrideDnd = false,
    bool loop = true,
  }) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('play', <String, dynamic>{
            'melody': melody,
            'volume': volume.clamp(0.0, 1.0),
            'overrideDnd': overrideDnd,
            'loop': loop,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Stops any playing melody and restores the previous alarm stream volume.
  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
