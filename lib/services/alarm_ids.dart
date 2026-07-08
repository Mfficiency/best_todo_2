/// Deterministic id scheme shared by the primary scheduling path
/// (flutter_local_notifications) and the watchdog backup path
/// (android_alarm_manager_plus), so the watchdog can tell which OS
/// notification a given alarm should have produced.
///
/// Layout per alarm (derived from the alarm uid's hash):
///   base + 0        one-off fire and snooze notification
///   base + 1..7     repeating fires, one slot per weekday (Mon=1 .. Sun=7)
///   base + kWatchdogIdOffset   the watchdog alarm for this alarm
///
/// base is (hash & 0x1FFFFFF) * 8 ≤ 0x0FFFFFF8 and the watchdog offset is
/// 0x10000000, so every id stays inside a signed 32-bit int as Android
/// requires, and the two id spaces can't collide.
library alarm_ids;

const int kWatchdogIdOffset = 0x10000000;

/// Fixed ids for the in-app "test alarm" (fires ~1 minute after requested).
/// 0x20000000+ sits above both the notification id space (< 0x10000000) and
/// the watchdog id space (< 0x20000000), so a test can never collide with a
/// real alarm.
const int kTestAlarmNotificationId = 0x20000000;
const int kTestAlarmWatchdogId = 0x20000001;

/// Uid recorded for test alarms in the watchdog registry.
const String kTestAlarmUid = '__test_alarm__';

int alarmNotificationBaseId(String uid) => (uid.hashCode & 0x1FFFFFF) * 8;

int alarmWatchdogId(String uid) =>
    alarmNotificationBaseId(uid) + kWatchdogIdOffset;

/// Every notification id the alarm [uid] may fire under (one-off/snooze slot
/// plus the seven weekday slots).
List<int> alarmNotificationIds(String uid) {
  final base = alarmNotificationBaseId(uid);
  return [for (var slot = 0; slot <= 7; slot++) base + slot];
}
