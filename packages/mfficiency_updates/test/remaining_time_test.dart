import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

void main() {
  var now = DateTime(2026, 10, 15, 9);
  RemainingTime eta() => RemainingTime(clock: () => now)..start();
  void wait(int seconds) => now = now.add(Duration(seconds: seconds));

  test('nothing for the first 3 seconds', () {
    final e = eta();
    wait(2);
    expect(e.label(0.05), isNull);
    wait(1);
    expect(e.label(0.05), '00:00:57 remaining');
  });

  test('only for work over 30 seconds in total', () {
    final e = eta();
    wait(5);
    expect(e.label(0.5), isNull, reason: '10 s in total');
    expect(e.label(1 / 6), isNull, reason: 'exactly 30 s');
    expect(e.label(0.1), '00:00:45 remaining');
    expect(e.estimate(null, typical: const Duration(seconds: 20)), isNull);
  });

  test('extrapolates from the fraction done', () {
    final e = eta();
    wait(10);
    expect(e.estimate(0.25), const Duration(seconds: 30));
    expect(e.estimate(1), isNull, reason: 'done after 10 s: short work');
    expect(e.estimate(0), isNull, reason: 'nothing to go on yet');
    expect(e.estimate(null), isNull);
  });

  test('without a fraction: a typical duration counts down', () {
    final e = eta();
    wait(5);
    expect(e.estimate(null, typical: const Duration(minutes: 1)),
        const Duration(seconds: 55));
    wait(100);
    expect(e.estimate(null, typical: const Duration(minutes: 1)),
        Duration.zero);
    expect(e.estimate(1), Duration.zero, reason: 'long work, finished');
  });

  test('stopped or never started: nothing', () {
    final e = RemainingTime(clock: () => now);
    wait(10);
    expect(e.label(0.5), isNull);
    e.start();
    wait(10);
    e.stop();
    expect(e.label(0.5), isNull);
  });

  test('hh:mm:ss', () {
    expect(formatHms(Duration.zero), '00:00:00');
    expect(formatHms(const Duration(milliseconds: 1200)), '00:00:02');
    expect(formatHms(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '02:03:04');
    expect(formatHms(const Duration(hours: 120)), '120:00:00');
  });
}
