import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps long background work (Best Music's song-info search) alive while
/// other apps are in front: on Android it runs `BackgroundWorkService.kt`,
/// a foreground service with an ongoing notification showing [update]'s
/// text and a partial wake lock. Everywhere else — and if Android refuses
/// (starting one from the background on Android 12+) — it's a no-op and
/// the work simply runs while the app is open.
class BackgroundWork {
  const BackgroundWork();

  static const MethodChannel _channel = MethodChannel('besttodo/background_work');

  bool get _supported {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Shows the notification (starting the service if needed).
  Future<void> start(String title, String text) =>
      _call('start', {'title': title, 'text': text});

  /// Replaces the notification's text; no-op when not started.
  Future<void> update(String text) => _call('update', {'text': text});

  Future<void> stop() => _call('stop', const {});

  Future<void> _call(String method, Map<String, Object?> args) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } catch (_) {
      // No plugin (tests), or Android said no — run without it.
    }
  }
}
