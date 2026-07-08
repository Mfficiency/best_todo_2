import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/alarm.dart';
import 'alarm_fullscreen.dart';
import 'alarm_log_service.dart';
import 'alarm_storage_service.dart';

/// "Alarm doctor": writes a full snapshot of every device / permission /
/// schedule state that can stop an alarm from ringing into the alarm log,
/// each with a concrete fix hint. Runs on app start and on demand from the
/// in-app log page, so the state at the time of a missed alarm is always in
/// the file just above the failure.
class AlarmDiagnostics {
  AlarmDiagnostics._();

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Full snapshot with a section banner. [trigger] says why it ran.
  static Future<void> run({String trigger = 'manual'}) async {
    if (kIsWeb) return;
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = ' v${info.version}+${info.buildNumber}';
    } catch (_) {}
    await AlarmLog.section('ALARM DIAGNOSTICS ($trigger)$version');

    if (!_isAndroid) {
      await AlarmLog.info(
          'ENV',
          'platform is ${defaultTargetPlatform.name} — alarm delivery is '
          'handled by the OS notification scheduler, Android-specific checks '
          'skipped');
      return;
    }

    var sdk = 0;
    var manufacturer = '';
    try {
      final device = await DeviceInfoPlugin().androidInfo;
      sdk = device.version.sdkInt;
      manufacturer = device.manufacturer.toLowerCase();
      await AlarmLog.info(
          'ENV',
          'device: ${device.manufacturer} ${device.model}, '
          'Android ${device.version.release} (SDK $sdk)');
    } catch (e) {
      await AlarmLog.warn('ENV', 'could not read device info: $e');
    }

    await _checkNotificationsEnabled();
    await _checkAlarmChannel();
    await _checkExactAlarms();
    await _checkBatteryOptimization();
    await _oemHints(manufacturer);

    await _checkFullScreenIntent(sdk);
    await AlarmLog.info(
        'ENV',
        'note: force-stopping the app (Settings → Apps → Force stop, and on '
        'some OEMs swiping it away in recents) cancels ALL scheduled alarms '
        'until the app is opened again — no app can survive that');

    await _logScheduleState();
  }

  static Future<void> _checkNotificationsEnabled() async {
    try {
      final enabled = await _android?.areNotificationsEnabled();
      if (enabled == true) {
        await AlarmLog.ok('PERM', 'notifications: enabled');
      } else {
        await AlarmLog.fail(
            'PERM',
            'notifications: BLOCKED — no alarm can ever show or ring. Fix: '
            'system Settings → Apps → BestToDo → Notifications → allow');
      }
    } catch (e) {
      await AlarmLog.warn('PERM', 'could not check notification state: $e');
    }
  }

  static Future<void> _checkAlarmChannel() async {
    try {
      final channels = await _android?.getNotificationChannels();
      if (channels == null) return;
      final matches =
          channels.where((c) => c.id == 'alarm_notifications_v2').toList();
      if (matches.isEmpty) {
        await AlarmLog.warn(
            'PERM',
            'alarm notification channel not created yet (first run?) — it is '
            'created automatically before scheduling');
        return;
      }
      final channel = matches.first;
      if (channel.importance == Importance.none) {
        await AlarmLog.fail(
            'PERM',
            'the "Alarms" notification channel is BLOCKED — scheduled alarms '
            'fire but Android shows nothing. Fix: system Settings → Apps → '
            'BestToDo → Notifications → Alarms → allow');
      } else if (channel.importance.value < Importance.high.value) {
        await AlarmLog.warn(
            'PERM',
            'the "Alarms" channel importance was lowered to '
            '${channel.importance.name} — alarms may appear silently. Fix: '
            'system Settings → Apps → BestToDo → Notifications → Alarms → '
            'set to urgent');
      } else {
        await AlarmLog.ok(
            'PERM',
            'alarm channel: exists, importance ${channel.importance.name}, '
            'sound ${channel.playSound ? 'on' : 'OFF'}');
      }
    } catch (e) {
      await AlarmLog.warn('PERM', 'could not check alarm channel: $e');
    }
  }

  static Future<void> _checkExactAlarms() async {
    try {
      final canExact = await _android?.canScheduleExactNotifications();
      if (canExact == true) {
        await AlarmLog.ok(
            'PERM', 'exact alarms (SCHEDULE_EXACT_ALARM): allowed');
      } else {
        await AlarmLog.fail(
            'PERM',
            'exact alarms: NOT allowed — alarms are deferred by minutes to '
            'hours. Fix: system Settings → Apps → Special app access → '
            'Alarms & reminders → BestToDo → allow');
      }
    } catch (e) {
      await AlarmLog.warn('PERM', 'could not check exact-alarm permission: $e');
    }
  }

  /// Ringing alarms present a full-screen ring UI over the lock screen via a
  /// full-screen intent; Android 14+ can revoke that special access, in which
  /// case the alarm degrades to a (still audible) notification banner.
  static Future<void> _checkFullScreenIntent(int sdk) async {
    try {
      final can = await AlarmFullScreen.canUseFullScreenIntent();
      if (can == true) {
        await AlarmLog.ok(
            'PERM',
            'full-screen intent: allowed — a ringing alarm shows the '
            'full-screen alarm screen, also over the lock screen');
        return;
      }
      if (can == false) {
        await AlarmLog.fail(
            'PERM',
            'full-screen intent: REVOKED — while locked, alarms only show a '
            'banner instead of the full-screen alarm screen. Fix: system '
            'Settings → Apps → BestToDo → Manage full screen intents → allow');
        return;
      }
    } catch (_) {}
    if (sdk >= 34) {
      await AlarmLog.info(
          'ENV',
          'Android 14+: full-screen alarm UI over the lock screen needs '
          '"Manage full screen intents" — if the alarm only shows a silent '
          'banner while locked, check system Settings → Apps → BestToDo → '
          'Manage full screen intents');
    }
  }

  static Future<void> _checkBatteryOptimization() async {
    try {
      final exempt = await Permission.ignoreBatteryOptimizations.isGranted;
      if (exempt) {
        await AlarmLog.ok(
            'PERM', 'battery optimization: app is exempted (unrestricted)');
      } else {
        await AlarmLog.warn(
            'PERM',
            'battery optimization: NOT exempted — in deep sleep (Doze) the '
            'OS may delay alarms; aggressive OEMs may drop them entirely. '
            'Fix: system Settings → Apps → BestToDo → Battery → Unrestricted');
      }
    } catch (e) {
      await AlarmLog.warn(
          'PERM', 'could not check battery-optimization state: $e');
    }
  }

  static Future<void> _oemHints(String manufacturer) async {
    const hints = <String, String>{
      'samsung':
          'Samsung: check Settings → Battery → Background usage limits → '
              '"Sleeping apps" / "Deep sleeping apps" and make sure BestToDo '
              'is NOT listed (or add it to "Never sleeping apps")',
      'xiaomi': 'Xiaomi/MIUI: enable Autostart for BestToDo (Settings → Apps '
          '→ Manage apps → BestToDo → Autostart) and set Battery saver to '
          '"No restrictions"',
      'redmi': 'Xiaomi/MIUI: enable Autostart for BestToDo and set Battery '
          'saver to "No restrictions"',
      'huawei': 'Huawei/EMUI: Settings → Battery → App launch → BestToDo → '
          'Manage manually → enable all three toggles',
      'honor': 'Honor: Settings → Battery → App launch → BestToDo → Manage '
          'manually → enable all three toggles',
      'oppo': 'Oppo/ColorOS: allow Auto-startup and disable battery '
          'optimization for BestToDo in Settings → Battery',
      'vivo': 'Vivo: allow Autostart and set High background power '
          'consumption for BestToDo',
      'oneplus': 'OnePlus: Settings → Battery → Battery optimization → '
          'BestToDo → Don\'t optimize; disable "Advanced optimization"',
      'meizu': 'Meizu: Settings → Apps → BestToDo → Permissions → allow '
          'background running',
      'asus': 'Asus: allow BestToDo in Mobile Manager → Auto-start manager',
    };
    for (final entry in hints.entries) {
      if (manufacturer.contains(entry.key)) {
        await AlarmLog.warn(
            'ENV',
            '${entry.key} device detected — this OEM ships an aggressive '
            'power saver that is the #1 cause of silently dropped alarms. '
            '${entry.value}');
        return;
      }
    }
  }

  /// Logs what is currently registered with the OS: our alarm list vs. the
  /// pending notification schedules Android reports back.
  static Future<void> _logScheduleState() async {
    try {
      final alarms = await AlarmStorageService().loadAlarms();
      final enabled = alarms.where((a) => a.enabled).toList();
      if (enabled.isEmpty) {
        await AlarmLog.info('VERIFY', 'no enabled alarms configured');
      }
      for (final Alarm a in enabled) {
        final next = a.nextOccurrence();
        await AlarmLog.info(
            'VERIFY',
            '"${a.name.isEmpty ? 'Alarm' : a.name}" ${a.timeLabel} '
            '(${a.scheduleLabel}) → next fire: '
            '${next?.toString() ?? 'NONE (in the past)'}');
      }
      final pending = await FlutterLocalNotificationsPlugin()
          .pendingNotificationRequests();
      await AlarmLog.info(
          'VERIFY',
          'OS reports ${pending.length} pending scheduled notification(s): '
          '[${pending.map((p) => p.id).join(', ')}]');
    } catch (e) {
      await AlarmLog.warn('VERIFY', 'could not read schedule state: $e');
    }
  }
}
