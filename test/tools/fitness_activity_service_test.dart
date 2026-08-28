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
}
