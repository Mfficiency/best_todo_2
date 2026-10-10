import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/streak_challenges.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A Tuesday; DateTime(2026, 8, 1) is a Saturday.
  final day = DateTime(2026, 8, 4);
  DateTime daysAgo(int n) => day.subtract(Duration(days: n));

  final service = StreakService.instance;

  StreakChallenge challenge(String id) =>
      evaluateStreakChallenges(service).singleWhere((c) => c.id == id);

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    StreakService.instance.resetForTest();
    Config.showStreak = true;
    Config.streakGraceHours = 24;
    Config.streakReminderEnabled = false;
  });

  test('at least 20 challenges exist, all unearned without history', () {
    final challenges = evaluateStreakChallenges(service);
    expect(challenges.length, greaterThanOrEqualTo(20));
    expect(challenges.map((c) => c.id).toSet().length, challenges.length,
        reason: 'challenge ids must be unique');
    expect(challenges.where((c) => c.earned), isEmpty);
  });

  test('the first completion earns First Spark', () {
    expect(challenge('first_spark').earned, isFalse);
    service.recordCompletion(day);
    expect(challenge('first_spark').earned, isTrue);
  });

  test('time-of-day challenges: early bird, dawn patrol, night owl, lunch',
      () {
    service.recordCompletion(DateTime(2026, 8, 4, 7, 30));
    expect(challenge('early_bird').earned, isTrue);
    expect(challenge('dawn_patrol').earned, isFalse);
    expect(challenge('night_owl').earned, isFalse);
    expect(challenge('lunch_break').earned, isFalse);

    service.recordCompletion(DateTime(2026, 8, 4, 5, 59));
    expect(challenge('dawn_patrol').earned, isTrue);
    service.recordCompletion(DateTime(2026, 8, 4, 22, 0));
    expect(challenge('night_owl').earned, isTrue);
    service.recordCompletion(DateTime(2026, 8, 4, 12, 45));
    expect(challenge('lunch_break').earned, isTrue);
  });

  test('per-day count challenges track the best day with progress', () {
    for (var i = 0; i < 5; i++) {
      service.recordCompletion(day);
    }
    expect(challenge('hat_trick').earned, isTrue);
    expect(challenge('high_five').earned, isTrue);
    final ten = challenge('perfect_ten');
    expect(ten.earned, isFalse);
    expect(ten.progress, 5);
    expect(ten.fraction, 0.5);
  });

  test('streak-length challenges use the longest streak', () {
    for (var back = 6; back >= 0; back--) {
      service.recordCompletion(daysAgo(back));
    }
    expect(challenge('week_of_fire').earned, isTrue);
    final month = challenge('monthly_blaze');
    expect(month.earned, isFalse);
    expect(month.progress, 7);
    expect(month.target, 30);
  });

  test('weekend warrior needs a Saturday plus the Sunday right after', () {
    final saturday = DateTime(2026, 8, 1);
    expect(saturday.weekday, DateTime.saturday);
    service.recordCompletion(saturday);
    expect(challenge('weekend_warrior').earned, isFalse);
    service.recordCompletion(saturday.add(const Duration(days: 1)));
    expect(challenge('weekend_warrior').earned, isTrue);
    // The 1st of the month also counts as a fresh start.
    expect(challenge('fresh_start').earned, isTrue);
  });

  test('monday hero and comeback kid', () {
    final monday = DateTime(2026, 8, 3);
    expect(monday.weekday, DateTime.monday);
    service.recordCompletion(monday);
    expect(challenge('monday_hero').earned, isTrue);
    expect(challenge('comeback_kid').earned, isFalse);

    // Two missed days break any streak — completing again is the comeback.
    service.recordCompletion(monday.add(const Duration(days: 3)));
    expect(challenge('comeback_kid').earned, isTrue);
  });

  test('full month needs every single day of a calendar month', () {
    for (var d = 1; d <= 27; d++) {
      service.recordCompletion(DateTime(2026, 2, d));
    }
    expect(challenge('full_month').earned, isFalse);
    service.recordCompletion(DateTime(2026, 2, 28));
    expect(challenge('full_month').earned, isTrue);
  });

  test('totals challenges count completions and active days', () {
    for (var back = 0; back < 12; back++) {
      service.recordCompletion(daysAgo(back));
    }
    expect(challenge('explorer').earned, isTrue);
    final regular = challenge('regular');
    expect(regular.earned, isFalse);
    expect(regular.progress, 12);
    final century = challenge('century_club');
    expect(century.earned, isFalse);
    expect(century.progress, 12);
  });
}
