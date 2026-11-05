import 'dart:async';
import 'dart:ui' show DartPluginRegistrant, PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';

/// The update check while the app is closed (Android only).
///
/// [UpdateController.start] schedules it when the app's config has a
/// [UpdateConfig.backgroundCheck]: Android's JobScheduler runs that entry
/// point every [UpdateConfig.backgroundInterval] (one hour by default) when
/// a network is there, kept across reboots. The entry point builds the
/// app's controller exactly as the app does and hands it to [run], which
/// checks and downloads a newer build silently. Nothing is shown: the
/// downloaded APK waits, and Android's "Update this app?" opens the next
/// time the app is opened (the check at start finds it complete).
///
/// The job is skipped while the app is open (the app checks every few
/// minutes itself) and stopped when the app opens during it, so the two
/// never download at the same time.
///
/// ```dart
/// @pragma('vm:entry-point')
/// Future<void> updateCheckInBackground() =>
///     UpdateBackground.run(() async => buildMyUpdateController());
/// ```
abstract final class UpdateBackground {
  /// The background engine's own channel: it says when the run is over.
  static const doneChannel = MethodChannel('mfficiency_updates/background');

  /// Runs inside the background engine: builds the controller ([build],
  /// the same as the app's, including `init()`), checks and downloads.
  /// Always tells Android the run is over, also after an error.
  static Future<void> run(Future<UpdateController> Function() build) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    var outcome = 'ok';
    try {
      final controller = await build();
      final r = await controller.checkInBackground();
      // "incomplete": Android runs the job again soon (with back-off) and
      // the download continues where it stopped.
      outcome = controller.downloadIncomplete ? 'incomplete' : r.status.name;
    } catch (e) {
      outcome = 'error: $e';
    } finally {
      try {
        await doneChannel.invokeMethod<void>('done', {'outcome': outcome});
      } on Object {
        // No native side (tests): nothing to tell.
      }
    }
  }

  /// The handle Android stores to start [entryPoint] later; null when it
  /// isn't a top-level or static function.
  static int? handleOf(Future<void> Function() entryPoint) =>
      PluginUtilities.getCallbackHandle(entryPoint)?.toRawHandle();
}
