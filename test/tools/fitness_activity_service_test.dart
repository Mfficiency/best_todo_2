import 'package:besttodo/services/fitness_activity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

void main() {
  test('summarizes Health Connect samples into Monday through Sunday', () {
    final monday = DateTime(2026, 8, 24);
    final days = FitnessActivityService.summarize(monday, [
      FitnessSample(HealthDataType.STEPS, monday.add(const Duration(hours: 8)),
          monday.add(const Duration(hours: 9)), 3200),
      FitnessSample(HealthDataType.STEPS, monday.add(const Duration(hours: 18)),
          monday.add(const Duration(hours: 19)), 1800),
      FitnessSample(HealthDataType.DISTANCE_DELTA, monday,
          monday.add(const Duration(hours: 1)), 2500),
      FitnessSample(HealthDataType.WORKOUT, monday,
          monday.add(const Duration(minutes: 45)), 0),
      FitnessSample(HealthDataType.SLEEP_ASLEEP,
          monday.add(const Duration(days: 1)),
          monday.add(const Duration(days: 1, hours: 7, minutes: 30)), 0),
      FitnessSample(HealthDataType.HEART_RATE, monday, monday, 60),
      FitnessSample(HealthDataType.HEART_RATE, monday, monday, 80),
      FitnessSample(HealthDataType.STEPS,
          monday.subtract(const Duration(days: 1)), monday, 9999),
    ]);

    expect(days, hasLength(7));
    expect(days.first.steps, 5000);
    expect(days.first.distanceKm, 2.5);
    expect(days.first.workoutMinutes, 45);
    expect(days.first.averageHeartRate, 70);
    expect(days[1].sleepHours, 7.5);
    expect(days.fold(0, (sum, day) => sum + day.steps), 5000);
  });

  group('computeAutoBests', () {
    test('returns nothing for an empty history', () {
      expect(FitnessActivityService.computeAutoBests(const []), isEmpty);
    });

    test('picks the best day/session per metric across many days', () {
      final day1 = DateTime(2026, 1, 1);
      final day2 = DateTime(2026, 6, 15);
      final samples = [
        // day1: 4000 steps total, split into two chunks
        FitnessSample(HealthDataType.STEPS, day1.add(const Duration(hours: 8)),
            day1.add(const Duration(hours: 9)), 2500),
        FitnessSample(HealthDataType.STEPS, day1.add(const Duration(hours: 18)),
            day1.add(const Duration(hours: 19)), 1500),
        // day2: 9000 steps, the best day
        FitnessSample(HealthDataType.STEPS, day2, day2.add(const Duration(hours: 1)), 9000),
        FitnessSample(HealthDataType.DISTANCE_DELTA, day1,
            day1.add(const Duration(hours: 1)), 3000),
        FitnessSample(HealthDataType.DISTANCE_DELTA, day2,
            day2.add(const Duration(hours: 1)), 8000),
        FitnessSample(HealthDataType.ACTIVE_ENERGY_BURNED, day1,
            day1.add(const Duration(hours: 1)), 200),
        FitnessSample(HealthDataType.ACTIVE_ENERGY_BURNED, day2,
            day2.add(const Duration(hours: 1)), 650),
        FitnessSample(HealthDataType.WORKOUT, day1,
            day1.add(const Duration(minutes: 30)), 0),
        FitnessSample(HealthDataType.WORKOUT, day2,
            day2.add(const Duration(minutes: 75)), 0),
        FitnessSample(HealthDataType.SLEEP_ASLEEP, day1,
            day1.add(const Duration(hours: 6)), 0),
        FitnessSample(HealthDataType.SLEEP_ASLEEP, day2,
            day2.add(const Duration(hours: 9)), 0),
        FitnessSample(HealthDataType.HEART_RATE, day1, day1, 150),
        FitnessSample(HealthDataType.HEART_RATE, day2, day2, 178),
        FitnessSample(HealthDataType.RESTING_HEART_RATE, day1, day1, 58),
        FitnessSample(HealthDataType.RESTING_HEART_RATE, day2, day2, 51),
      ];

      final bests = FitnessActivityService.computeAutoBests(samples);
      AutoPersonalBest of(AutoBestMetric metric) =>
          bests.firstWhere((b) => b.metric == metric);

      expect(bests, hasLength(7));
      expect(of(AutoBestMetric.steps).value, 9000);
      expect(of(AutoBestMetric.steps).date, day2);
      expect(of(AutoBestMetric.distance).value, 8);
      expect(of(AutoBestMetric.calories).value, 650);
      expect(of(AutoBestMetric.workout).value, 75);
      expect(of(AutoBestMetric.sleep).value, 9);
      expect(of(AutoBestMetric.heartRate).value, 178);
      expect(of(AutoBestMetric.restingHeartRate).value, 51);
    });

    test('only includes metrics that had samples', () {
      final day = DateTime(2026, 3, 1);
      final bests = FitnessActivityService.computeAutoBests([
        FitnessSample(HealthDataType.STEPS, day, day.add(const Duration(hours: 1)), 5000),
      ]);

      expect(bests, hasLength(1));
      expect(bests.single.metric, AutoBestMetric.steps);
    });
  });
}
