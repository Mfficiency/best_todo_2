import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../config.dart';

/// Which kind of listening a remembered phone volume belongs to.
enum VolumeKind {
  music('music'),
  video('video');

  const VolumeKind(this.key);
  final String key;

  static VolumeKind? fromKey(String key) {
    for (final k in values) {
      if (k.key == key) return k;
    }
    return null;
  }
}

/// The phone's own media volume (Android's music stream, the one the
/// volume buttons change while something plays), as 0..1.
///
/// There is no app-specific volume in Best Music: instead the phone's
/// media volume is remembered separately for music and for Subscriptions
/// videos ([Config.musicPhoneVolume]/[Config.videoPhoneVolume]). When
/// playback switches from one kind to the other, the level the phone is
/// at is saved for the kind that was playing and the other kind's level
/// is put back ([onPlaying]). Only the video boost stays inside the app.
class MediaVolume {
  MediaVolume._();

  static const MethodChannel _channel = MethodChannel('besttodo/media_volume');

  /// Tests stand in for the phone here.
  @visibleForTesting
  static Future<double?> Function()? getOverride;
  @visibleForTesting
  static Future<void> Function(double volume, {bool showUi})? setOverride;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// The phone's media volume now; null where it can't be read.
  static Future<double?> get() async {
    if (getOverride != null) return getOverride!();
    if (!_supported) return null;
    try {
      final v = await _channel.invokeMethod<double>('get');
      return v?.clamp(0.0, 1.0).toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Sets the phone's media volume; [showUi] shows the phone's own volume
  /// bar so the change doesn't come as a surprise.
  static Future<void> set(double volume, {bool showUi = false}) async {
    final v = volume.clamp(0.0, 1.0).toDouble();
    if (setOverride != null) return setOverride!(v, showUi: showUi);
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('set', {'volume': v, 'showUi': showUi});
    } catch (_) {
      // No volume control (fixed-volume device, Do Not Disturb): leave it.
    }
  }

  /// The level remembered for [kind]; null until there is one.
  static double? remembered(VolumeKind kind) => kind == VolumeKind.video
      ? Config.videoPhoneVolume
      : Config.musicPhoneVolume;

  static void _remember(VolumeKind kind, double volume) {
    if (kind == VolumeKind.video) {
      Config.videoPhoneVolume = volume;
    } else {
      Config.musicPhoneVolume = volume;
    }
  }

  /// The kind playing last (survives restarts); null before anything played.
  static VolumeKind? get playingKind =>
      VolumeKind.fromKey(Config.phoneVolumeKind);

  /// A [kind] track is starting. When the other kind was playing before,
  /// remember the phone's volume for that one and put back [kind]'s.
  static Future<void> onPlaying(VolumeKind kind) async {
    final previous = playingKind;
    if (previous == kind) return;
    Config.phoneVolumeKind = kind.key;
    if (previous != null) {
      final now = await get();
      if (now != null) _remember(previous, now);
      final target = remembered(kind);
      if (target != null && (now == null || (target - now).abs() > 0.001)) {
        await set(target, showUi: true);
      }
    }
    unawaited(Config.save());
  }

  /// The volume sheet picked [volume] for [kind]: remembered, and applied
  /// to the phone right away when [kind] is what's playing. [persist]
  /// false while a slider is still being dragged.
  static Future<void> choose(VolumeKind kind, double volume,
      {bool persist = true}) async {
    _remember(kind, volume);
    if (playingKind == kind || playingKind == null) await set(volume);
    if (persist) unawaited(Config.save());
  }

  /// What the volume sheet shows for [kind]: the phone's level while
  /// [kind] is playing, otherwise the remembered one.
  static Future<double?> current(VolumeKind kind) async {
    if (playingKind == kind || playingKind == null) {
      return await get() ?? remembered(kind);
    }
    return remembered(kind) ?? await get();
  }
}
