import 'package:besttodo/ui/usage_data_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wellbeing chart labels only six-hour boundaries', () {
    expect(
      List.generate(24, (hour) => wellbeingHourLabel(hour.toDouble())),
      [
        '0:00',
        '',
        '',
        '',
        '',
        '',
        '6:00',
        '',
        '',
        '',
        '',
        '',
        '12:00',
        '',
        '',
        '',
        '',
        '',
        '18:00',
        '',
        '',
        '',
        '',
        '',
      ],
    );
  });

  test('wellbeing chart ignores values outside its whole-hour range', () {
    expect(wellbeingHourLabel(-6), isEmpty);
    expect(wellbeingHourLabel(6.5), isEmpty);
    expect(wellbeingHourLabel(24), isEmpty);
  });

  test('wellbeing minute axis labels minutes and whole hours', () {
    expect(wellbeingMinuteLabel(0), '0');
    expect(wellbeingMinuteLabel(-5), '0');
    expect(wellbeingMinuteLabel(45), '45m');
    expect(wellbeingMinuteLabel(60), '1h');
    expect(wellbeingMinuteLabel(150), '150m');
    expect(wellbeingMinuteLabel(180), '3h');
  });
}
