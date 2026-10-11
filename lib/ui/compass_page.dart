import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'subpage_app_bar.dart';

/// The phone's heading in degrees (clockwise from magnetic north, 0..360),
/// streamed by the native `CompassSensor` (Android). Errors on devices or
/// platforms without a compass.
Stream<double> compassHeadings() =>
    const EventChannel('besttodo/compass')
        .receiveBroadcastStream()
        .map((e) => (e as num).toDouble());

/// Cardinal/intercardinal label for [degrees]: N, NE, E, SE, S, SW, W, NW.
String compassDirection(double degrees) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final index = (((degrees % 360) + 360) % 360 / 45).round() % 8;
  return names[index];
}

/// Compass tool: a dial that turns with the phone, plus a Hold button that
/// freezes the reading (e.g. to take a bearing, then look at the number).
class CompassPage extends StatefulWidget {
  /// Heading source; defaults to the native sensor. Tests pass their own.
  final Stream<double>? headings;

  const CompassPage({super.key, this.headings});

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> {
  StreamSubscription<double>? _sub;
  double? _heading;
  bool _held = false;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _sub = (widget.headings ?? compassHeadings()).listen(
      (h) {
        if (_held || !mounted) return;
        setState(() => _heading = h);
      },
      onError: (_) {
        if (mounted) setState(() => _unavailable = true);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heading = _heading;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Compass'),
      body: Center(
        child: _unavailable
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No compass sensor on this device',
                    textAlign: TextAlign.center),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    heading == null
                        ? '--°'
                        : '${heading.round() % 360}° ${compassDirection(heading)}',
                    key: const Key('compass-reading'),
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 24),
                  SizedBox.square(
                    dimension: 260,
                    child: CustomPaint(
                      painter: _DialPainter(
                        heading: heading ?? 0,
                        color: scheme.onSurface,
                        accent: scheme.error,
                        held: _held,
                        heldColor: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed:
                        heading == null ? null : () => setState(() => _held = !_held),
                    icon: Icon(_held ? Icons.lock_open : Icons.lock),
                    label: Text(_held ? 'Release' : 'Hold'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Dial whose card rotates opposite to [heading] so N always points north;
/// a fixed triangle at the top marks where the phone points.
class _DialPainter extends CustomPainter {
  final double heading;
  final Color color;
  final Color accent;
  final bool held;
  final Color heldColor;

  _DialPainter({
    required this.heading,
    required this.color,
    required this.accent,
    required this.held,
    required this.heldColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final ring = held ? heldColor : color;
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = held ? 4 : 2
          ..color = ring);

    // Fixed pointer: where the top of the phone faces.
    final pointer = Path()
      ..moveTo(center.dx, center.dy - radius - 6)
      ..lineTo(center.dx - 9, center.dy - radius + 12)
      ..lineTo(center.dx + 9, center.dy - radius + 12)
      ..close();
    canvas.drawPath(pointer, Paint()..color = ring);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);
    final tick = Paint()..color = color;
    for (var d = 0; d < 360; d += 15) {
      final major = d % 90 == 0;
      final a = d * math.pi / 180;
      final outer = radius - 4;
      final inner = radius - (major ? 20 : 12);
      tick.strokeWidth = major ? 3 : 1.5;
      canvas.drawLine(Offset(math.sin(a) * inner, -math.cos(a) * inner),
          Offset(math.sin(a) * outer, -math.cos(a) * outer), tick);
    }
    const labels = {'N': 0, 'E': 90, 'S': 180, 'W': 270};
    labels.forEach((label, d) {
      final a = d * math.pi / 180;
      final r = radius - 42;
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: label == 'N' ? accent : color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(math.sin(a) * r - tp.width / 2,
              -math.cos(a) * r - tp.height / 2));
    });
    // Needle: red half points north.
    final needle = Paint()..color = accent;
    canvas.drawPath(
        Path()
          ..moveTo(0, -radius + 60)
          ..lineTo(-8, 0)
          ..lineTo(8, 0)
          ..close(),
        needle);
    canvas.drawPath(
        Path()
          ..moveTo(0, radius - 60)
          ..lineTo(-8, 0)
          ..lineTo(8, 0)
          ..close(),
        Paint()..color = color.withValues(alpha: 0.5));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.heading != heading ||
      old.held != held ||
      old.color != color ||
      old.accent != accent;
}
