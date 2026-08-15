import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import 'device_log_service.dart';
import 'log_service.dart';

/// Breadcrumbs for the "widget tap opens a black screen while the app is in
/// the background" bug.
///
/// The failure is invisible from inside the app: everything keeps running —
/// timers, taps, saves — while the window never repaints, so no ordinary log
/// line says anything is wrong. What distinguishes it is *frames*, so this
/// class counts them (`addTimingsCallback` fires once per rasterized frame)
/// and, on every resume, watches whether any arrive.
///
/// Each line goes to the App Logs page (persisted in `app_log.txt`) and is
/// mirrored into the Android breadcrumb file, so one shared timeline shows
/// the Android callbacks and the Dart verdicts interleaved.
///
/// Reading the resume block:
///   * `first frame after resume +Nms` — healthy re-front, nothing to see.
///   * `NO FRAME …` — the black window. The snapshot on the same line says
///     which of the two known causes it is: `hasScheduledFrame=true` means a
///     frame was requested and never serviced (the scheduler is wedged —
///     0.1.143's forced frame did this), while `hasScheduledFrame=false` with
///     `framesEnabled=false` means the engine still considers the app
///     invisible and is dropping frame requests on the floor.
class RenderDiagnostics {
  RenderDiagnostics._();

  static int _frames = 0;
  static int _framesAtResume = 0;
  static DateTime _resumedAt = DateTime.now();
  static Timer? _watchdog;
  static bool _installed = false;

  /// The watchdog runs on Android only: it is the only platform with the bug,
  /// and its timers would otherwise outlive widget tests.
  static bool get _watchEnabled => !kIsWeb && Platform.isAndroid;

  /// Number of frames rasterized since the app started.
  static int get frameCount => _frames;

  /// Starts frame counting and writes the launch banner. Called from `main`
  /// right after the first frame.
  static void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addTimingsCallback((timings) {
      _frames += timings.length;
    });
    unawaited(_logStartBanner());
  }

  /// The build number is the first thing to check in a shared log, and it
  /// comes from the platform — so the banner waits for it, briefly.
  static Future<void> _logStartBanner() async {
    try {
      await Config.ensureVersionLoaded().timeout(const Duration(seconds: 2));
    } catch (_) {}
    log('app start — BestToDo ${Config.versionWithBuild} | ${snapshot()}');
  }

  /// One line describing everything that decides whether a frame happens.
  static String snapshot() {
    final scheduler = SchedulerBinding.instance;
    final view = PlatformDispatcher.instance.implicitView;
    final size = view?.physicalSize;
    final geometry = size == null
        ? 'none'
        : '${size.width.round()}x${size.height.round()}';
    return 'frames=$_frames '
        'hasScheduledFrame=${scheduler.hasScheduledFrame} '
        'framesEnabled=${scheduler.framesEnabled} '
        'lifecycle=${scheduler.lifecycleState?.name ?? '-'} '
        'view=$geometry';
  }

  /// Logs to the App Logs page and mirrors into the Android breadcrumb file.
  static void log(String message) {
    LogService.add('render', message);
    unawaited(DeviceLogService.note(message));
  }

  /// Called from the app's lifecycle observer for every state change.
  static void onLifecycleChanged(AppLifecycleState state) {
    log('lifecycle -> ${state.name} | ${snapshot()}');
    if (state == AppLifecycleState.resumed) {
      _startResumeWatch();
    } else {
      _watchdog?.cancel();
      _watchdog = null;
    }
  }

  /// Called when the window metrics change. A resume that ends black often
  /// shows the surface coming back here (a size change) with no frame
  /// following it.
  static void onMetricsChanged() {
    log('metrics changed | ${snapshot()}');
  }

  /// Watches the seconds after a resume for the frames that make the app
  /// visible again, and reports when none arrive.
  static void _startResumeWatch() {
    _watchdog?.cancel();
    _watchdog = null;
    if (!_watchEnabled) return;
    _framesAtResume = _frames;
    _resumedAt = DateTime.now();
    // If frames are dead this callback never runs at all — its absence from
    // the log is itself part of the evidence.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      log('post-frame callback after resume ran (+${_sinceResumeMs()}ms)');
    });

    var ticks = 0;
    _watchdog = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      ticks++;
      final rendered = _frames - _framesAtResume;
      if (rendered > 0) {
        timer.cancel();
        _watchdog = null;
        log('first frame after resume +${_sinceResumeMs()}ms '
            '(frames=$rendered) | ${snapshot()}');
        return;
      }
      // 1 s, 3 s, 5 s, 10 s: enough detail to see whether the window ever
      // recovers, without filling the log while it stays black.
      if (ticks == 2 || ticks == 6 || ticks == 10 || ticks == 20) {
        log('NO FRAME ${_sinceResumeMs()}ms after resume — window is black '
            '| ${snapshot()}');
      }
      // A plain frame request at 2 s, always announced, so a frame appearing
      // right after it is never mistaken for the app recovering on its own.
      // Deliberately scheduleFrame() and never scheduleForcedFrame(): the
      // forced variant on resume is what caused this bug in 0.1.143 (SPEC §8).
      if (ticks == 4) {
        log('probe: no frame yet, requesting one with scheduleFrame()');
        WidgetsBinding.instance.scheduleFrame();
      }
      if (ticks == 8) {
        log('probe result: scheduleFrame() produced no frame | ${snapshot()}');
      }
      if (ticks >= 20) {
        timer.cancel();
        _watchdog = null;
      }
    });
  }

  static int _sinceResumeMs() =>
      DateTime.now().difference(_resumedAt).inMilliseconds;

  /// Test hook: stops the watchdog and forgets the installed state.
  @visibleForTesting
  static void resetForTest() {
    _watchdog?.cancel();
    _watchdog = null;
    _installed = false;
    _frames = 0;
  }
}
