import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/f1_reminder.dart';

/// Fixed alarm id so re-scheduling replaces the previous registration.
const int kF1ReminderAlarmId = 0xF1F1;

bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// A race whose reminder is still to be sent, and when.
class F1PendingReminder {
  final F1Race race;
  final DateTime sendAt;
  const F1PendingReminder(this.race, this.sendAt);
}

/// Top-level entry point run in a background isolate when the reminder
/// alarm fires. Marks the due race handled and re-arms the chain for the
/// next race BEFORE sending, so neither a crash in the send nor the re-arm
/// itself can make the same text go out twice or break the chain.
@pragma('vm:entry-point')
Future<void> f1ReminderAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await F1ReminderService.runDue();
  } catch (_) {}
}

class F1ReminderService {
  static const _fileName = 'f1_reminder.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<F1ReminderConfig> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return F1ReminderConfig();
      final data = jsonDecode(await file.readAsString());
      return F1ReminderConfig.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (_) {
      return F1ReminderConfig();
    }
  }

  static Future<void> save(F1ReminderConfig config) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(config.toJson()), flush: true);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- timing

  static DateTime sendTimeFor(F1Race race) =>
      race.start.subtract(kF1ReminderLead);

  /// The next reminder still to go out: the earliest race not yet handled
  /// that is still more than [kF1LateSendCutoff] away. Its send time may be
  /// in the past (a missed alarm) — it is then sent as soon as possible.
  static F1PendingReminder? nextPending(
    F1ReminderConfig config, {
    DateTime? now,
    List<F1Race>? races,
  }) {
    final t = now ?? DateTime.now();
    final sorted = [...(races ?? kF1Races)]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final race in sorted) {
      if (config.handledRaces.contains(race.key)) continue;
      if (!race.start.subtract(kF1LateSendCutoff).isAfter(t)) continue;
      return F1PendingReminder(race, sendTimeFor(race));
    }
    return null;
  }

  /// The first race that hasn't started yet (used for the welcome text).
  static F1Race? nextRace({DateTime? now, List<F1Race>? races}) {
    final t = now ?? DateTime.now();
    final sorted = [...(races ?? kF1Races)]
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final race in sorted) {
      if (race.start.isAfter(t)) return race;
    }
    return null;
  }

  // ------------------------------------------------------------- rendering

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "18:00"
  static String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// "Sunday 8 November"
  static String formatDate(DateTime d) =>
      '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  /// "Sunday 8 November, 18:00"
  static String formatDateTime(DateTime d) =>
      '${formatDate(d)}, ${formatTime(d)}';

  /// "4 hours", "3 hours 20 minutes", "45 minutes" — rounded to minutes.
  static String formatCountdown(Duration d) {
    final totalMinutes = (d.inSeconds / 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final hours = h == 1 ? '1 hour' : '$h hours';
    final minutes = m == 1 ? '1 minute' : '$m minutes';
    if (h == 0) return minutes;
    if (m == 0) return hours;
    return '$hours $minutes';
  }

  /// Fills a template's tokens for [race]. The countdown is measured from
  /// [now] (defaults to the race's regular send time, i.e. "4 hours").
  static String render(String template, F1Race race, {DateTime? now}) {
    final from = now ?? sendTimeFor(race);
    var left = race.start.difference(from);
    if (left.isNegative) left = Duration.zero;
    return template
        .replaceAll('{race}', race.name)
        .replaceAll('{time}', formatTime(race.start))
        .replaceAll('{date}', formatDate(race.start))
        .replaceAll('{countdown}', formatCountdown(left));
  }

  // --------------------------------------------------------------- sending

  /// Test seam: replaces the real SMS send.
  @visibleForTesting
  static Future<String?> Function(String phone, String message)? sendOverride;

  /// Sends one text. Returns null on success, else an error description.
  static Future<String?> sendSms(String phone, String message) async {
    final override = sendOverride;
    if (override != null) return override(phone, message);
    if (!_isAndroidNative) return 'SMS sending only works on Android';
    try {
      var perm = await Permission.sms.status;
      if (!perm.isGranted) perm = await Permission.sms.request();
      if (!perm.isGranted) return 'SMS permission not granted';
    } catch (e) {
      return 'Permission check failed: $e';
    }

    final isNonAscii = message.runes.any((r) => r > 127);
    final isMultipart = message.length > (isNonAscii ? 70 : 160);
    final status = Completer<String>();
    final timeout = Timer(const Duration(seconds: 20), () {
      if (!status.isCompleted) status.complete('TIMEOUT');
    });
    try {
      await Telephony.instance.sendSms(
        to: phone,
        message: message,
        isMultipart: isMultipart,
        statusListener: (SendStatus s) {
          if (!status.isCompleted) status.complete(s.toString());
        },
      );
    } catch (e) {
      timeout.cancel();
      return 'Send failed: $e';
    }
    final result = await status.future;
    timeout.cancel();
    return result == 'TIMEOUT' ? 'No delivery status within 20 s' : null;
  }

  static Future<String?> _sendAndRecord(
      F1ReminderConfig config, String message) async {
    final phone = config.phoneNumber.trim();
    final error = phone.isEmpty
        ? 'No phone number set'
        : await sendSms(phone, message);
    config.addHistory(F1SendRecord(
      at: DateTime.now(),
      message: message,
      success: error == null,
      error: error,
    ));
    return error;
  }

  /// Sends the welcome text for the next race, records it and saves
  /// [config]. Returns null on success, else an error description.
  static Future<String?> sendWelcome(F1ReminderConfig config,
      {DateTime? now}) async {
    final race = nextRace(now: now);
    final message = race == null
        ? 'Welcome to F1 race reminders! 🏎️ The season is over for now — '
            'you\'ll hear from me when the next one starts.'
        : render(kDefaultF1WelcomeTemplate, race, now: now);
    final error = await _sendAndRecord(config, message);
    await save(config);
    return error;
  }

  /// Sends the reminder that is due now, if any. Called from the alarm.
  /// Returns true if a text was attempted.
  static Future<bool> runDue({DateTime? now}) async {
    final t = now ?? DateTime.now();
    final config = await load();
    if (!config.enabled || config.phoneNumber.trim().isEmpty) {
      await applyFromConfig(config);
      return false;
    }
    final pending = nextPending(config, now: t);
    // A little slack: an alarm can be delivered a moment early.
    if (pending == null ||
        pending.sendAt.isAfter(t.add(const Duration(minutes: 1)))) {
      await applyFromConfig(config);
      return false;
    }
    config.handledRaces.add(pending.race.key);
    await save(config);
    try {
      await applyFromConfig(config);
    } catch (_) {}
    await _sendAndRecord(
        config, render(config.template, pending.race, now: t));
    await save(config);
    return true;
  }

  // ------------------------------------------------------------ scheduling

  static bool _alarmInitialized = false;

  /// Schedules (or cancels) the one-shot alarm for the next reminder. Runs
  /// on every launch too, so a chain lost to a force-stop is restored.
  static Future<void> applyFromConfig([F1ReminderConfig? config]) async {
    if (!_isAndroidNative) return;
    final cfg = config ?? await load();
    if (!_alarmInitialized) {
      await AndroidAlarmManager.initialize();
      _alarmInitialized = true;
    }
    await AndroidAlarmManager.cancel(kF1ReminderAlarmId);
    if (!Config.isFeatureEnabled('f1_reminder') ||
        !cfg.enabled ||
        cfg.phoneNumber.trim().isEmpty) {
      return;
    }
    final pending = nextPending(cfg);
    if (pending == null) return;
    final soonest = DateTime.now().add(const Duration(seconds: 10));
    final fireAt =
        pending.sendAt.isBefore(soonest) ? soonest : pending.sendAt;
    await AndroidAlarmManager.oneShotAt(
      fireAt,
      kF1ReminderAlarmId,
      f1ReminderAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );
  }
}
