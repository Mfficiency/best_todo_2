import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart' show RemainingTime;
import 'package:shared_preferences/shared_preferences.dart';

/// A small "00:01:23 remaining" line for anything that can take a while (a
/// Todoist sync, a calendar import, a Health Connect scan). Put it below the
/// spinner / progress bar and drive it with [active]: nothing shows for the
/// first 3 seconds and nothing for work that looks no longer than 30 seconds
/// in total, then a rough countdown refreshed every second.
///
/// The estimate comes from [done] (0..1) when the work knows how far it is,
/// else from [typical] (how long it took last time), else — with a
/// [durationKey] — from the duration this widget recorded for that key the
/// last time (SharedPreferences `eta.<key>`, written when [active] turns
/// false or the widget goes away while active). With nothing to go on it
/// shows nothing. Only an indication, never exact.
class RemainingTimeText extends StatefulWidget {
  final bool active;
  final double? done;
  final Duration? typical;
  final String? durationKey;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// Test seam: the clock the countdown reads.
  final DateTime Function()? clock;

  const RemainingTimeText({
    super.key,
    required this.active,
    this.done,
    this.typical,
    this.durationKey,
    this.style,
    this.textAlign,
    this.clock,
  });

  static String prefKey(String key) => 'eta.$key';

  /// The duration recorded for [key] last time, or null.
  static Future<Duration?> lastDuration(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(prefKey(key));
      return ms == null || ms <= 0 ? null : Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordDuration(String key, Duration d) async {
    if (d <= Duration.zero) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey(key), d.inMilliseconds);
    } catch (_) {}
  }

  @override
  State<RemainingTimeText> createState() => _RemainingTimeTextState();
}

class _RemainingTimeTextState extends State<RemainingTimeText> {
  late final RemainingTime _eta = RemainingTime(clock: widget.clock);
  Timer? _ticker;
  Duration? _stored;

  @override
  void initState() {
    super.initState();
    if (widget.active) _begin();
  }

  @override
  void didUpdateWidget(RemainingTimeText old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _begin();
    if (!widget.active && old.active) _end();
  }

  @override
  void dispose() {
    if (widget.active) _end();
    super.dispose();
  }

  void _begin() {
    _eta.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    final key = widget.durationKey;
    if (key != null && widget.typical == null) {
      RemainingTimeText.lastDuration(key).then((d) {
        if (mounted) setState(() => _stored = d);
      });
    }
  }

  void _end() {
    _ticker?.cancel();
    _ticker = null;
    final key = widget.durationKey;
    if (key != null && _eta.running) {
      RemainingTimeText.recordDuration(key, _eta.elapsed);
    }
    _eta.stop();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final label =
        _eta.label(widget.done, typical: widget.typical ?? _stored);
    if (label == null) return const SizedBox.shrink();
    return Text(
      label,
      key: const Key('remaining-time'),
      textAlign: widget.textAlign,
      style: widget.style ?? Theme.of(context).textTheme.bodySmall,
    );
  }
}
