import '../app_settings.dart';

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats the time of [d] honouring [AppSettings.use24HourFormat].
/// e.g. `14:30` (24h) or `2:30 PM` (12h).
String formatTime(DateTime d, {AppSettings? settings}) {
  final s = settings ?? AppSettings.instance;
  final mm = d.minute.toString().padLeft(2, '0');
  if (s.use24HourFormat) {
    return '${d.hour.toString().padLeft(2, '0')}:$mm';
  }
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$mm $period';
}

/// Formats the date of [d] using the chosen [AppSettings.dateFormat].
String formatDate(DateTime d, {AppSettings? settings}) {
  final s = settings ?? AppSettings.instance;
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  final yy = (d.year % 100).toString().padLeft(2, '0');
  switch (s.dateFormat) {
    case 'dd.MM.yy':
      return '$dd.$mm.$yy';
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

/// Formats both date and time, e.g. `09.06.2026, 14:30`.
String formatDateTime(DateTime d, {AppSettings? settings}) =>
    '${formatDate(d, settings: settings)}, ${formatTime(d, settings: settings)}';

/// Formats minutes-since-midnight as `HH:MM` (used for quiet-hours display).
String formatMinutesOfDay(int totalMinutes) {
  final m = totalMinutes.clamp(0, 1439);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Formats a duration in seconds as `MM:SS` (used for notification delay).
String formatMmSs(int totalSeconds) {
  final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final sec = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}

/// Parses `MM:SS` back to seconds, or null if malformed.
int? parseMmSs(String value) {
  final match = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(value.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}
