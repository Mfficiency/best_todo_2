import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native side of the full-screen alarm UI (MainActivity):
/// querying the Android 14+ "full screen intents" special access and clearing
/// the show-over-lock-screen window flags once the ring page closes.
class AlarmFullScreen {
  AlarmFullScreen._();

  static const MethodChannel _channel = MethodChannel('besttodo/alarm_ring');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether the app may use full-screen intents (the full-screen alarm UI
  /// over the lock screen). Always true below Android 14; null when the state
  /// cannot be read (non-Android, or the activity is not attached).
  static Future<bool?> canUseFullScreenIntent() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent');
    } catch (_) {
      return null;
    }
  }

  /// Drops the show-when-locked / turn-screen-on window flags that were set
  /// for the alarm launch, so the rest of the app does not stay visible over
  /// the lock screen after the alarm is handled.
  static Future<void> clearLockScreenFlags() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('clearLockScreenFlags');
    } catch (_) {}
  }
}
