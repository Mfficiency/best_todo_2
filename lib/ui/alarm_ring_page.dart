import 'dart:async';

import 'package:flutter/material.dart';

import '../services/alarm_fullscreen.dart';
import '../services/notification_service.dart';

/// Full-screen alarm screen shown while an alarm is ringing — the same idea
/// as the Google/Samsung clock apps: it covers the whole screen (over the
/// lock screen when launched by the alarm's full-screen intent), shows a live
/// clock and the alarm's name, and offers big Snooze / Stop actions. The
/// sound and vibration come from the insistent alarm notification, so they
/// keep going until one of the actions here (or on the notification) is used.
class AlarmRingPage extends StatefulWidget {
  /// Decoded alarm notification payload (uid, name, body, snooze settings,
  /// color) — the same JSON the notification actions receive.
  final Map<String, dynamic> payload;

  /// Overridable action handlers (for tests); default to the notification
  /// service, which stops the ringing notification and keeps the OS
  /// schedules + watchdog consistent.
  final Future<void> Function(Map<String, dynamic> payload)? onDismiss;
  final Future<void> Function(Map<String, dynamic> payload)? onSnooze;

  const AlarmRingPage({
    Key? key,
    required this.payload,
    this.onDismiss,
    this.onSnooze,
  }) : super(key: key);

  @override
  State<AlarmRingPage> createState() => _AlarmRingPageState();
}

class _AlarmRingPageState extends State<AlarmRingPage>
    with SingleTickerProviderStateMixin {
  late final Timer _clockTimer;
  late final AnimationController _pulse;
  DateTime _now = DateTime.now();
  bool _busy = false;

  String get _name {
    final name = (widget.payload['name'] as String?)?.trim() ?? '';
    return name.isEmpty ? 'Alarm' : name;
  }

  String get _body => (widget.payload['body'] as String?)?.trim() ?? '';

  bool get _snoozeEnabled => widget.payload['snoozeEnabled'] as bool? ?? false;

  int get _snoozeMinutes => widget.payload['snoozeMinutes'] as int? ?? 9;

  Color get _accent => Color(widget.payload['color'] as int? ?? 0xFF005FDD);

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.9,
      upperBound: 1.1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _pulse.dispose();
    // The activity may be showing over the lock screen because the alarm's
    // full-screen intent launched it; drop that as soon as the ring UI goes
    // away so the rest of the app stays behind the keyguard.
    AlarmFullScreen.clearLockScreenFlags();
    super.dispose();
  }

  Future<void> _run(
      Future<void> Function(Map<String, dynamic> payload) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(widget.payload);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _dismiss() =>
      _run(widget.onDismiss ?? NotificationService.dismissAlarmFromRing);

  Future<void> _snooze() =>
      _run(widget.onSnooze ?? NotificationService.snoozeAlarmFromRing);

  String get _timeLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_now.hour)}:${two(_now.minute)}';
  }

  String get _dateLabel {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    // The alarm must be answered with Stop or Snooze (like a clock app);
    // back would leave it ringing behind an app screen.
    return PopScope(
      canPop: false,
      child: Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        child: Scaffold(
          body: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(accent, Colors.black, 0.55)!,
                  Colors.black,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    ScaleTransition(
                      scale: _pulse,
                      child: Icon(
                        Icons.alarm,
                        size: 72,
                        color: accent.computeLuminance() > 0.4
                            ? accent
                            : Color.lerp(accent, Colors.white, 0.5),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    if (_body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      _timeLabel,
                      style: const TextStyle(
                        fontSize: 88,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _dateLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const Spacer(flex: 3),
                    if (_snoozeEnabled) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: _busy ? null : _snooze,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            'Snooze  ·  $_snoozeMinutes min',
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    SizedBox(
                      width: 112,
                      height: 112,
                      child: FilledButton(
                        onPressed: _busy ? null : _dismiss,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Stop',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
