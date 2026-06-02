import 'package:flutter/material.dart';

import '../config.dart';

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats the time of [d] honoring [Config.use24HourFormat].
String formatTimerTime(DateTime d) {
  final mm = d.minute.toString().padLeft(2, '0');
  if (Config.use24HourFormat) {
    return '${d.hour.toString().padLeft(2, '0')}:$mm';
  }
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$mm $period';
}

/// Formats the date of [d] honoring the chosen [Config.dateFormat].
String formatTimerDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  switch (Config.dateFormat) {
    case 'dd/MM/yyyy':
      return '$dd/$mm/$yyyy';
    case 'MM/dd/yyyy':
      return '$mm/$dd/$yyyy';
    case 'yyyy-MM-dd':
      return '$yyyy-$mm-$dd';
    case 'd MMM yyyy':
      return '${d.day} ${_monthsShort[d.month - 1]} $yyyy';
    case 'dd.MM.yyyy':
    default:
      return '$dd.$mm.$yyyy';
  }
}

/// Formats both date and time, e.g. "09.06.2026, 14:30".
String formatTimerDateTime(DateTime d) =>
    '${formatTimerDate(d)}, ${formatTimerTime(d)}';

/// Shows a time picker that honors [Config.use24HourFormat] regardless of the
/// device locale, so the 24-hour setting controls the picker too.
Future<TimeOfDay?> pickTimeOfDay(BuildContext context, TimeOfDay initial) {
  return showTimePicker(
    context: context,
    initialTime: initial,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        alwaysUse24HourFormat: Config.use24HourFormat,
      ),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
