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

  /// GitHub's anonymous API allows 60 requests/hour/IP, shared by every
  /// installed app on the phone's network — so no faster than this.
  static const Duration interval = Duration(minutes: 15);

  Timer? _timer;
  bool _checking = false;
  String? _dismissedVersion;

  /// When the last check started (null = none yet this session).
  DateTime? _lastCheck;

  bool get isRunning => _timer != null;

  /// Starts polling every [interval] (overridable for tests via
  /// [testInterval]). Calling this again while already running restarts the
  /// timer with the (possibly new) callback. Also runs one check right away
  /// — `Timer.periodic` only fires after the first full interval elapses, so
  /// without this, opening the app would never check until a minute later.
  ///
  /// [service] defaults to [UpdateService.instance] (BestToDo's own build);
  /// Best Music passes its [UpdateService.forApp] instance instead, so the
  /// two apps' background polls never cross-report each other's builds.
  void start(UpdateFoundCallback onUpdateFound,
      {Duration? testInterval, UpdateService? service}) {
    stop();
    unawaited(checkOnce(onUpdateFound, service: service));
    _timer = Timer.periodic(
      testInterval ?? interval,
      (_) => checkOnce(onUpdateFound, service: service),
    );
  }

  /// Like [checkOnce], but skipped when the last check started less than
  /// [minGap] (default [interval]) ago — used when the app comes back to the
  /// foreground, so frequent app switching can't burn the API rate limit.
  Future<void> checkIfDue(UpdateFoundCallback onUpdateFound,
      {UpdateService? service, Duration? minGap, DateTime? now}) async {
    final last = _lastCheck;
    final t = now ?? DateTime.now();
    if (last != null && t.difference(last) < (minGap ?? interval)) return;
    await checkOnce(onUpdateFound, service: service);
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
  Future<void> checkOnce(UpdateFoundCallback onUpdateFound,
      {UpdateService? service}) async {
    if (_checking) return;
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final update = await (service ?? UpdateService.instance).checkForUpdate();
      if (update != null &&
          update.apkUrl != null &&
          update.version != _dismissedVersion) {
        onUpdateFound(update);
      }
    } catch (_) {
      // Offline, GitHub unreachable or rate limited (UpdateRateLimitedException,
      // which also makes UpdateService skip requests until the limit resets)
      // — retried on the next tick.
    } finally {
      _checking = false;
    }
  }
}
