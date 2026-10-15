/// A rough "hh:mm:ss remaining" for anything that takes a while (a
/// download, an upload, a sync). Only for long work: nothing unless the
/// whole job looks like it takes more than [longerThan] (30 s), and nothing
/// for the first [after] (3 s) while the estimate settles. Not meant to be
/// exact, only an indication.
///
///   final eta = RemainingTime()..start();
///   // on each progress update, done = 0..1:
///   final text = eta.label(done); // "00:01:23 remaining" or null
///
/// Without a fraction (the work can't say how far it is), [estimate] with
/// `typical` (e.g. how long it took last time) counts that down instead.
class RemainingTime {
  RemainingTime({
    DateTime Function()? clock,
    this.after = const Duration(seconds: 3),
    this.longerThan = const Duration(seconds: 30),
  }) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  /// No estimate before the work has run this long.
  final Duration after;

  /// No estimate for work that looks shorter than this in total (time so
  /// far plus time left).
  final Duration longerThan;
  DateTime? _start;

  /// Starts (or restarts) the clock.
  void start() => _start = _now();

  /// Stops it: no estimate until [start] again.
  void stop() => _start = null;

  bool get running => _start != null;

  /// How long since [start].
  Duration get elapsed =>
      _start == null ? Duration.zero : _now().difference(_start!);

  /// Time left, extrapolated from [done] (0..1) and the time so far; with
  /// [done] null, [typical] minus the time so far. Null before [after],
  /// when not running, when the whole job looks no longer than
  /// [longerThan], or when there is nothing to go on.
  Duration? estimate(double? done, {Duration? typical}) {
    if (_start == null) return null;
    final spent = elapsed;
    if (spent < after) return null;
    Duration left;
    if (done != null && done > 0) {
      left = done >= 1
          ? Duration.zero
          : Duration(
              milliseconds: (spent.inMilliseconds * (1 - done) / done).round(),
            );
    } else if (typical != null) {
      left = typical - spent;
      if (left.isNegative) left = Duration.zero;
    } else {
      return null;
    }
    return spent + left > longerThan ? left : null;
  }

  /// "00:01:23 remaining" (or [text] around the time), else null.
  String? label(
    double? done, {
    Duration? typical,
    String Function(String hms) text = _remaining,
  }) {
    final left = estimate(done, typical: typical);
    return left == null ? null : text(formatHms(left));
  }
}

String _remaining(String hms) => '$hms remaining';

/// "hh:mm:ss", rounded up to the next second; hours past 99 keep going.
String formatHms(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil().clamp(0, 1 << 31);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(s ~/ 3600)}:${two(s ~/ 60 % 60)}:${two(s % 60)}';
}
