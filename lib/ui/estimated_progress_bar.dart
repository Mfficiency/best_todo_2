import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A thin progress bar for anything loading — a video, the feed, a search.
///
/// With a known [value] (e.g. 3 of 12 channels fetched) it shows that.
/// Without one it still shows a filling bar rather than an endless
/// shimmer: progress eases toward ~95% over roughly [expected]
/// (`1 - e^(-t/τ)`), so it's never accurate but always visibly moving, and
/// jumps to full once [active] turns false before disappearing.
class EstimatedProgressBar extends StatefulWidget {
  const EstimatedProgressBar({
    super.key,
    required this.active,
    this.value,
    this.expected = const Duration(seconds: 4),
    this.minHeight = 3,
  });

  final bool active;

  /// Real progress in `[0, 1]`, when known.
  final double? value;

  /// About how long the load usually takes; sets the estimate's pace.
  final Duration expected;

  final double minHeight;

  @override
  State<EstimatedProgressBar> createState() => _EstimatedProgressBarState();
}

class _EstimatedProgressBarState extends State<EstimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  /// Shown at 100% for a moment after loading ends.
  bool _finishing = false;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    // The estimate is a function of elapsed time; the controller just
    // supplies ticks for up to a minute (the curve is flat by then).
    _clock = AnimationController(
        vsync: this, duration: const Duration(minutes: 1));
    if (widget.active) _clock.forward(from: 0);
  }

  @override
  void didUpdateWidget(EstimatedProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _finishing = false;
      _clock.forward(from: 0);
    } else if (!widget.active && old.active) {
      _clock.stop();
      setState(() => _finishing = true);
      _finishTimer?.cancel();
      _finishTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && !widget.active) setState(() => _finishing = false);
      });
    }
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  double _estimate() {
    final elapsedMs = _clock.value * _clock.duration!.inMilliseconds;
    final tau = math.max(1, widget.expected.inMilliseconds) / 2.5;
    return 0.95 * (1 - math.exp(-elapsedMs / tau));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_finishing) {
      return SizedBox(height: widget.minHeight);
    }
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final value = _finishing
            ? 1.0
            : (widget.value?.clamp(0.0, 1.0) ?? _estimate());
        return LinearProgressIndicator(
          key: const ValueKey('estimatedProgressBar'),
          value: value,
          minHeight: widget.minHeight,
        );
      },
    );
  }
}
