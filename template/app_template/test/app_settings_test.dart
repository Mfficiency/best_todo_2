import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppSettings.instance.resetForTest());

  group('AppSettings', () {
    test('toMap round-trips through applyMap', () {
      final s = AppSettings.instance;
      s.themeMode = AppThemeMode.dark;
      s.minimalist = true;
      s.use24HourFormat = false;
      s.dateFormat = 'yyyy-MM-dd';
      s.notificationsEnabled = true;
      s.notificationDelaySeconds = 90;
      s.quietHoursEnabled = true;
      s.quietHoursStartMinutes = 1300;
      s.quietHoursEndMinutes = 400;

      final map = s.toMap();
      s.resetForTest();
      s.applyMap(map);

      expect(s.themeMode, AppThemeMode.dark);
      expect(s.minimalist, isTrue);
      expect(s.use24HourFormat, isFalse);
      expect(s.dateFormat, 'yyyy-MM-dd');
      expect(s.notificationsEnabled, isTrue);
      expect(s.notificationDelaySeconds, 90);
      expect(s.quietHoursEnabled, isTrue);
      expect(s.quietHoursStartMinutes, 1300);
      expect(s.quietHoursEndMinutes, 400);
    });

    test('applyMap tolerates missing keys and keeps current values', () {
      final s = AppSettings.instance;
      s.dateFormat = 'yyyy-MM-dd';
      s.applyMap({'minimalist': true}); // partial map
      expect(s.minimalist, isTrue);
      expect(s.dateFormat, 'yyyy-MM-dd'); // untouched
    });

    test('applyMap ignores unknown theme mode and date format', () {
      final s = AppSettings.instance;
      s.applyMap({'themeMode': 'chartreuse', 'dateFormat': 'nonsense'});
      expect(s.themeMode, AppThemeMode.system);
      expect(s.dateFormat, AppSettings.dateFormats.first);
    });

    test('applyMap clamps quiet-hours minutes into range', () {
      final s = AppSettings.instance;
      s.applyMap({'quietHoursStartMinutes': 99999, 'quietHoursEndMinutes': -5});
      expect(s.quietHoursStartMinutes, 1439);
      expect(s.quietHoursEndMinutes, 0);
    });

    test('materialThemeMode maps every case', () {
      final s = AppSettings.instance;
      s.themeMode = AppThemeMode.system;
      expect(s.materialThemeMode, ThemeMode.system);
      s.themeMode = AppThemeMode.light;
      expect(s.materialThemeMode, ThemeMode.light);
      s.themeMode = AppThemeMode.dark;
      expect(s.materialThemeMode, ThemeMode.dark);
    });
  });
}
