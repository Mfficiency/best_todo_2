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

/// Fixed id of the single daily streak reminder as it was scheduled before
/// the reminder list existed. Only cancelled nowadays, so an app updating from
/// an older version does not keep a stale reminder pending forever.
const int kStreakReminderNotificationId = 0x20000002;

/// Fixed id range for the streak reminders: one slot per entry of the user's
/// reminder list. Lives in the same fixed-id space (0x20000000+) as the test
/// alarm, above both dynamic alarm id spaces, so it can never collide with a
/// real alarm or its watchdog.
const int kStreakReminderNotificationIdBase = 0x20000010;

/// Notification id of reminder [slot] (0-based, < `maxStreakReminders`).
int streakReminderNotificationId(int slot) =>
    kStreakReminderNotificationIdBase + slot;

/// Fixed ids for the dice timer's end-of-countdown alarm — the OS-scheduled
/// ring that fires even when the app is closed. Same fixed-id space as the
/// test alarm; only one dice timer exists at a time, so one slot is enough.
const int kDiceTimerNotificationId = 0x20000003;
const int kDiceTimerWatchdogId = 0x20000004;

/// Uid recorded for test alarms in the watchdog registry.
const String kTestAlarmUid = '__test_alarm__';

/// Uid carried by the dice timer's alarm payload. Marks a ring that belongs
/// to the timer rather than to a saved alarm: nothing to reschedule from
/// storage afterwards, and stopping it returns to the timer page.
const String kDiceTimerUid = '__dice_timer__';

/// The alarm payload for the dice timer's ring. One builder for both delivery
/// paths — the OS-scheduled notification and the in-app full-screen ring —
/// so the alarm screen looks and behaves the same either way. [melody]/
/// [volume] are only set when the timer should actually play a melody.
Map<String, dynamic> diceRingPayload(
  String taskTitle, {
  String? melody,
  double? volume,
  bool vibrate = false,
}) {
  final title = taskTitle.trim();
  return <String, dynamic>{
    'uid': kDiceTimerUid,
    'name': 'Time is up',
    'body': title.isEmpty ? 'Your timer finished' : title,
    'vibrate': vibrate,
    'snoozeEnabled': false,
    'snoozeMinutes': 9,
    'snoozeId': kDiceTimerNotificationId,
    if (melody != null) 'melody': melody,
    if (volume != null) 'volume': volume,
  };
}

int alarmNotificationBaseId(String uid) => (uid.hashCode & 0x1FFFFFF) * 8;

int alarmWatchdogId(String uid) =>
    alarmNotificationBaseId(uid) + kWatchdogIdOffset;

/// Every notification id the alarm [uid] may fire under (one-off/snooze slot
/// plus the seven weekday slots).
List<int> alarmNotificationIds(String uid) {
  final base = alarmNotificationBaseId(uid);
  return [for (var slot = 0; slot <= 7; slot++) base + slot];
}
