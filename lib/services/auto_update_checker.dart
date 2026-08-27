import 'dart:async';

import 'update_service.dart';

typedef UpdateFoundCallback = void Function(UpdateInfo info);

/// Polls GitHub for a newer build while the app is open, on top of the
/// on-demand check the About page offers. Reports a build via
/// [UpdateFoundCallback] the first time it appears — not again for the same
/// version once the user has declined it, until a newer one is published.
/// Only ever reports a build [UpdateService] can install in place (an APK
/// asset present); a release with no APK asset is skipped, since there is
/// nothing to auto-install.

class AutoUpdateChecker {
  AutoUpdateChecker._();

  static AutoUpdateChecker instance = AutoUpdateChecker._();

  /// Fresh instance per test, dropping any timer/dismissal state.
  static void resetForTest() {
    instance.stop();
    instance = AutoUpdateChecker._();
  }

  static const Duration interval = Duration(minutes: 1);

  Timer? _timer;
  bool _checking = false;
  String? _dismissedVersion;

  bool get isRunning => _timer != null;

  /// Starts polling every [interval] (overridable for tests via
  /// [testInterval]). Calling this again while already running restarts the
  /// timer with the (possibly new) callback.
  void start(UpdateFoundCallback onUpdateFound, {Duration? testInterval}) {
    stop();
    _timer = Timer.periodic(
      testInterval ?? interval,
      (_) => checkOnce(onUpdateFound),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Records that [version] was declined, so it is not offered again until a
  /// newer one is published.
  void dismiss(String version) {
    _dismissedVersion = version;
  }

  /// Runs one check; calls [onUpdateFound] when a newer, installable build
  /// exists that has not already been dismissed. Swallows network/parse
  /// errors — this is a silent background poll, retried on the next tick.
  Future<void> checkOnce(UpdateFoundCallback onUpdateFound) async {
    if (_checking) return;
    _checking = true;
    try {
      final update = await UpdateService.instance.checkForUpdate();
      if (update != null &&
          update.apkUrl != null &&
          update.version != _dismissedVersion) {
        onUpdateFound(update);
      }
    } catch (_) {
      // Offline or GitHub unreachable — retried on the next tick.
    } finally {
      _checking = false;
    }
  }
}
