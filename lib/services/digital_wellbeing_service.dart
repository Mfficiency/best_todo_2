import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A foreground app session returned by Android's UsageStatsManager.
class PhoneUsageSession {
  final String packageName;
  final String appName;
  final String category;
  final DateTime startedAt;
  final DateTime endedAt;

  const PhoneUsageSession({
    required this.packageName,
    required this.appName,
    required this.category,
    required this.startedAt,
    required this.endedAt,
  });

  Duration get duration => endedAt.difference(startedAt);

  factory PhoneUsageSession.fromMap(Map<Object?, Object?> map) {
    return PhoneUsageSession(
      packageName: map['package'] as String? ?? '',
      appName: map['appName'] as String? ?? map['package'] as String? ?? '',
      category: map['category'] as String? ?? 'Other',
      startedAt: DateTime.fromMillisecondsSinceEpoch(map['start'] as int),
      endedAt: DateTime.fromMillisecondsSinceEpoch(map['end'] as int),
    );
  }
}

class WellbeingGoals {
  final int dailyMinutes;
  final int pickupLimit;
  final int bedtimeHour;
  final int noPhoneStartHour;
  final bool enabled;

  const WellbeingGoals({
    this.dailyMinutes = 180,
    this.pickupLimit = 60,
    this.bedtimeHour = 23,
    this.noPhoneStartHour = 22,
    this.enabled = false,
  });

  WellbeingGoals copyWith({
    int? dailyMinutes,
    int? pickupLimit,
    int? bedtimeHour,
    int? noPhoneStartHour,
    bool? enabled,
  }) =>
      WellbeingGoals(
        dailyMinutes: dailyMinutes ?? this.dailyMinutes,
        pickupLimit: pickupLimit ?? this.pickupLimit,
        bedtimeHour: bedtimeHour ?? this.bedtimeHour,
        noPhoneStartHour: noPhoneStartHour ?? this.noPhoneStartHour,
        enabled: enabled ?? this.enabled,
      );
}

/// Bridges the existing Usage Data tool to optional Android-wide usage data.
class DigitalWellbeingService {
  DigitalWellbeingService._();

  static const _channel = MethodChannel('besttodo/digital_wellbeing');

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  static Future<void> openPermissionSettings() async {
    if (Platform.isAndroid) await _channel.invokeMethod('openPermissionSettings');
  }

  static Future<List<PhoneUsageSession>> sessions(
      DateTime from, DateTime to) async {
    if (!Platform.isAndroid) return const [];
    final raw = await _channel.invokeListMethod<Object?>('querySessions', {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
        }) ??
        const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(PhoneUsageSession.fromMap)
        .where((s) => !s.duration.isNegative && s.duration.inSeconds > 0)
        .toList();
  }

  static Future<WellbeingGoals> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    return WellbeingGoals(
      enabled: prefs.getBool('wellbeing_enabled') ?? false,
      dailyMinutes: prefs.getInt('wellbeing_daily_minutes') ?? 180,
      pickupLimit: prefs.getInt('wellbeing_pickup_limit') ?? 60,
      bedtimeHour: prefs.getInt('wellbeing_bedtime_hour') ?? 23,
      noPhoneStartHour: prefs.getInt('wellbeing_no_phone_hour') ?? 22,
    );
  }

  static Future<void> saveGoals(WellbeingGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('wellbeing_enabled', goals.enabled),
      prefs.setInt('wellbeing_daily_minutes', goals.dailyMinutes),
      prefs.setInt('wellbeing_pickup_limit', goals.pickupLimit),
      prefs.setInt('wellbeing_bedtime_hour', goals.bedtimeHour),
      prefs.setInt('wellbeing_no_phone_hour', goals.noPhoneStartHour),
    ]);
  }
}
