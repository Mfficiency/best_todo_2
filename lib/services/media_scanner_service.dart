import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tells the platform media database (`MediaStore` — what Samsung's own
/// Gallery/My Files/Music apps, and every other media-aware app, read from)
/// about a file this app just wrote directly to shared storage with
/// `dart:io`. Writing through `File` bypasses `MediaStore` entirely, so
/// without this a freshly downloaded track sits invisible to those apps
/// until the next full device media scan — which on some OEMs (Samsung
/// included) doesn't happen again until a reboot.
class MediaScannerService {
  MediaScannerService._();

  static const MethodChannel _channel =
      MethodChannel('besttodo/media_scanner');

  /// Lets tests observe/substitute the call instead of hitting a platform
  /// channel with no Android host behind it.
  @visibleForTesting
  static Future<void> Function(String path)? scanOverride;

  /// Best-effort: failures are swallowed since the file itself is already
  /// saved successfully at this point — this only affects how soon other
  /// apps see it, not whether the download succeeded.
  static Future<void> scanFile(String path) async {
    if (scanOverride != null) return scanOverride!(path);
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    } catch (_) {}
  }
}
