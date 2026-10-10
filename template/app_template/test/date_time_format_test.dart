import 'package:app_template/app_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppSettings.instance.resetForTest());

  final d = DateTime(2026, 3, 9, 14, 5); // 9 Mar 2026, 14:05

  group('formatDate', () {
    test('honours each selectable format', () {
      final s = AppSettings.instance;
      final expected = {
        'dd.MM.yy': '09.03.26',
        'dd.MM.yyyy': '09.03.2026',
        'dd/MM/yyyy': '09/03/2026',
        'MM/dd/yyyy': '03/09/2026',
        'yyyy-MM-dd': '2026-03-09',
        'd MMM yyyy': '9 Mar 2026',
      };
      for (final entry in expected.entries) {
        s.dateFormat = entry.key;
        expect(formatDate(d), entry.value, reason: entry.key);
      }
    });
  });

  group('formatTime', () {
    test('24-hour and 12-hour', () {
      final s = AppSettings.instance;
      s.use24HourFormat = true;
      expect(formatTime(d), '14:05');
      s.use24HourFormat = false;
      expect(formatTime(d), '2:05 PM');
      expect(formatTime(DateTime(2026, 1, 1, 0, 0)), '12:00 AM');
    });
  });

  group('MM:SS parsing', () {
    test('formats and round-trips', () {
      expect(formatMmSs(90), '01:30');
      expect(formatMmSs(5), '00:05');
      expect(parseMmSs('01:30'), 90);
      expect(parseMmSs('00:05'), 5);
    });

    test('rejects malformed input', () {
      expect(parseMmSs('bad'), isNull);
      expect(parseMmSs('1:99'), isNull);
      expect(parseMmSs('90'), isNull);
    });
  });

  test('formatMinutesOfDay clamps and pads', () {
    expect(formatMinutesOfDay(0), '00:00');
    expect(formatMinutesOfDay(1300), '21:40');
    expect(formatMinutesOfDay(99999), '23:59');
  });
}
