import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native vibrator (MainActivity), sharing the alarm audio
/// channel. [start] buzzes in a repeating alarm pattern until [stop] is
/// called, so a vibration-only alert is as insistent as a melody.
///
/// Everything is a silent no-op on non-Android platforms and in widget tests
/// (where the method channel has no host).
class AlarmVibration {
  AlarmVibration._();

  static const MethodChannel _channel = MethodChannel('besttodo/alarm_audio');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts the repeating vibration pattern. Returns true when the device
  /// actually has a vibrator and started buzzing.
  static Future<bool> start() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('vibrate') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stops any vibration started by [start].
  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopVibrate');
    } catch (_) {}
  }
}
