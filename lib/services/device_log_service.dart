import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Dart end of the `besttodo/diag` channel — the Android-side breadcrumb file
/// written by `DiagLog.kt` (App Logs → Device).
///
/// It matters for the widget black-screen bug because the Android half of the
/// story keeps being recorded when the Flutter half has stopped painting, and
/// it survives the force-close that is the only way out of that state.
class DeviceLogService {
  DeviceLogService._();

  static const MethodChannel _channel = MethodChannel('besttodo/diag');

  static bool get _available => !kIsWeb && Platform.isAndroid;

  /// Whole native breadcrumb file, or a message explaining why there is none.
  static Future<String> read() async {
    if (!_available) {
      return 'The device log is only recorded on Android.';
    }
    try {
      return await _channel.invokeMethod<String>('read') ?? '';
    } catch (e) {
      return 'Could not read the device log: $e';
    }
  }

  static Future<void> clear() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {}
  }

  /// Mirrors a Dart breadcrumb into the native file, so both sides of a
  /// re-front appear in one ordered timeline. Never throws: on a wedged
  /// engine this is exactly the call that fails, and the caller's own logging
  /// must still happen.
  static Future<void> note(String message) async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('note', {'message': message});
    } catch (_) {}
  }
}
