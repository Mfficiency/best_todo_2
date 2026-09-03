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

/// Which health metric an [AutoPersonalBest] was computed from — lets the UI
/// pick an icon/color without string-matching a label.
enum AutoBestMetric { steps, distance, calories, workout, sleep, heartRate, restingHeartRate }

/// A personal-best record derived automatically from Health Connect history,
/// as opposed to [PersonalBest] which the user types in by hand.
class AutoPersonalBest {
  final AutoBestMetric metric;
  final String label;
  final double value;
  final String unit;
  final DateTime date;

  const AutoPersonalBest(this.metric, this.label, this.value, this.unit, this.date);
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

  /// Scans every sample (typically a wide window, e.g. the last year) and
  /// picks the single best day/session per metric — "most steps in a day",
  /// "longest workout", etc. — the way Samsung Health surfaces personal
  /// records automatically instead of requiring them to be typed in.
  /// Per-day totals (steps/distance/calories) are bucketed by calendar day
  /// first since Health Connect reports those in many small chunks; workouts,
  /// sleep and heart-rate readings are compared sample-by-sample since a
  /// single session is the meaningful unit there. Returns only the metrics
  /// that had at least one sample.
  static List<AutoPersonalBest> computeAutoBests(List<FitnessSample> samples) {
    DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

    final stepsByDay = <DateTime, double>{};
    final distanceByDay = <DateTime, double>{};
    final caloriesByDay = <DateTime, double>{};
    AutoPersonalBest? bestWorkout;
    AutoPersonalBest? bestSleep;
    AutoPersonalBest? maxHeartRate;
    AutoPersonalBest? minRestingHeartRate;

    for (final sample in samples) {
      final day = dayOf(sample.from);
      switch (sample.type) {
        case HealthDataType.STEPS:
          stepsByDay[day] = (stepsByDay[day] ?? 0) + sample.value;
          break;
        case HealthDataType.DISTANCE_DELTA:
          distanceByDay[day] = (distanceByDay[day] ?? 0) + sample.value / 1000;
          break;
        case HealthDataType.ACTIVE_ENERGY_BURNED:
          caloriesByDay[day] = (caloriesByDay[day] ?? 0) + sample.value;
          break;
        case HealthDataType.WORKOUT:
          final minutes = sample.to.difference(sample.from).inMinutes.toDouble();
          if (bestWorkout == null || minutes > bestWorkout.value) {
            bestWorkout = AutoPersonalBest(
                AutoBestMetric.workout, 'Longest workout', minutes, 'min', day);
          }
          break;
        case HealthDataType.SLEEP_ASLEEP:
          final hours = sample.to.difference(sample.from).inMinutes / 60;
          if (bestSleep == null || hours > bestSleep.value) {
            bestSleep = AutoPersonalBest(
                AutoBestMetric.sleep, 'Longest sleep', hours, 'h', day);
          }
          break;
        case HealthDataType.HEART_RATE:
          if (maxHeartRate == null || sample.value > maxHeartRate.value) {
            maxHeartRate = AutoPersonalBest(AutoBestMetric.heartRate,
                'Highest heart rate', sample.value, 'bpm', day);
          }
          break;
        case HealthDataType.RESTING_HEART_RATE:
          if (minRestingHeartRate == null || sample.value < minRestingHeartRate.value) {
            minRestingHeartRate = AutoPersonalBest(AutoBestMetric.restingHeartRate,
                'Lowest resting heart rate', sample.value, 'bpm', day);
          }
          break;
        default:
          break;
      }
    }

    AutoPersonalBest? bestSteps;
    stepsByDay.forEach((day, value) {
      if (bestSteps == null || value > bestSteps!.value) {
        bestSteps = AutoPersonalBest(AutoBestMetric.steps, 'Most steps in a day', value, 'steps', day);
      }
    });
    AutoPersonalBest? bestDistance;
    distanceByDay.forEach((day, value) {
      if (bestDistance == null || value > bestDistance!.value) {
        bestDistance = AutoPersonalBest(
            AutoBestMetric.distance, 'Longest distance in a day', value, 'km', day);
      }
    });
    AutoPersonalBest? bestCalories;
    caloriesByDay.forEach((day, value) {
      if (bestCalories == null || value > bestCalories!.value) {
        bestCalories = AutoPersonalBest(
            AutoBestMetric.calories, 'Most active energy in a day', value, 'kcal', day);
      }
    });

    return [
      bestSteps,
      bestDistance,
      bestCalories,
      bestWorkout,
      bestSleep,
      maxHeartRate,
      minRestingHeartRate,
    ].whereType<AutoPersonalBest>().toList();
  }
}
