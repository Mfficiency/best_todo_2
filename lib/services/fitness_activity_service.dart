import 'package:flutter/services.dart';
import 'package:health/health.dart';

/// A normalized Health Connect sample. Keeping the dashboard independent of
/// the plugin makes its calculations deterministic and easy to test.
class FitnessSample {
  final HealthDataType type;
  final DateTime from;
  final DateTime to;
  final double value;

  const FitnessSample(this.type, this.from, this.to, this.value);
}

class FitnessDay {
  final DateTime day;
  int steps = 0;
  double distanceKm = 0;
  double activeCalories = 0;
  int workoutMinutes = 0;
  double sleepHours = 0;
  final List<double> heartRates = [];
  double? restingHeartRate;
  double? weightKg;

  FitnessDay(this.day);

  double? get averageHeartRate => heartRates.isEmpty
      ? null
      : heartRates.reduce((a, b) => a + b) / heartRates.length;
}

class FitnessActivityService {
  FitnessActivityService._();

  static const types = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.WEIGHT,
  ];

  static final Health _health = Health();
  static const MethodChannel _channel = MethodChannel('besttodo/health');

  /// Whether the Health Connect app is installed on this device. Must be
  /// checked before requesting authorization — calling that (or any other
  /// getter/setter) while Health Connect isn't installed throws instead of
  /// just reporting "denied", which made the Fitness Activity page's
  /// "Connect" button look like it silently did nothing.
  static Future<bool> isAvailable() async {
    await _health.configure();
    return _health.isHealthConnectAvailable();
  }

  /// Sends the user to the Play Store to install Health Connect.
  static Future<void> promptInstall() => _health.installHealthConnect();

  /// Opens Android's Health Connect data-source screen. Samsung Health can be
  /// selected there as a source, which is how Galaxy Watch measurements are
  /// made available to other apps without giving this app Samsung credentials.
  static Future<bool> openDataSources() async =>
      await _channel.invokeMethod<bool>('openDataSources') ?? false;

  static Future<List<FitnessSample>?> read(DateTime from, DateTime to) async {
    await _health.configure();
    final granted = await _health.requestAuthorization(types);
    if (!granted) return null;
    // Health Connect otherwise limits reads to the most recent 30 days. This
    // separate system permission lets the week picker browse everything that
    // Samsung Health (or another source) has synced to the phone.
    if (from.isBefore(DateTime.now().subtract(const Duration(days: 30)))) {
      await _health.requestHealthDataHistoryAuthorization();
    }
    final points = await _health.getHealthDataFromTypes(
      types: types,
      startTime: from,
      endTime: to,
    );
    return points.map((point) {
      final value = point.value;
      final numeric = value is NumericHealthValue
          ? value.numericValue.toDouble()
          : 0.0;
      return FitnessSample(
          point.type, point.dateFrom, point.dateTo, numeric);
    }).toList();
  }

  static List<FitnessDay> summarize(
      DateTime weekStart, List<FitnessSample> samples) {
    final days = List.generate(7, (i) {
      final date = weekStart.add(Duration(days: i));
      return FitnessDay(DateTime(date.year, date.month, date.day));
    });
    for (final sample in samples) {
      final index = DateTime(sample.from.year, sample.from.month, sample.from.day)
          .difference(days.first.day)
          .inDays;
      if (index < 0 || index > 6) continue;
      final day = days[index];
      switch (sample.type) {
        case HealthDataType.STEPS:
          day.steps += sample.value.round();
          break;
        case HealthDataType.DISTANCE_DELTA:
          day.distanceKm += sample.value / 1000;
          break;
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          day.activeCalories += sample.value;
          break;
        case HealthDataType.WORKOUT:
          day.workoutMinutes += sample.to.difference(sample.from).inMinutes;
          break;
        case HealthDataType.SLEEP_ASLEEP:
          day.sleepHours += sample.to.difference(sample.from).inMinutes / 60;
          break;
        case HealthDataType.HEART_RATE:
          day.heartRates.add(sample.value);
          break;
        case HealthDataType.RESTING_HEART_RATE:
          day.restingHeartRate = sample.value;
          break;
        case HealthDataType.WEIGHT:
          day.weightKg = sample.value;
          break;
        default:
          break;
      }
    }
    return days;
  }
}
