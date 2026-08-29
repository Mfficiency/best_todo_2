import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';
import '../main.dart';
import '../models/sms_recipient.dart';
import '../models/sms_report_config.dart';
import '../models/streak_kind.dart';
import '../models/streak_reminder.dart';
import '../models/sync_log_entry.dart';
import '../models/view_filter_rules.dart';
import '../services/auto_backup_service.dart';
import '../services/google_calendar_service.dart';
import '../services/sms_report_config_service.dart';
import '../services/sms_report_scheduler.dart';
import '../services/sms_report_service.dart';
import '../services/streak_flame_display.dart';
import '../services/streak_service.dart';
import '../services/sync_service.dart';
import '../services/todoist_api_client.dart';
import '../services/todoist_sync_service.dart';
import 'auto_tag_rules_page.dart';
import 'dice_timer_settings.dart';
import 'fitness_activity_page.dart';
import 'sms_report_log_page.dart';
import 'streak_goal_dialog.dart';
import 'subpage_app_bar.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final Future<void> Function()? onExportTasksRequested;
  final Future<void> Function()? onExportSettingsRequested;
  final Future<void> Function()? onExportEverythingRequested;
  final Future<void> Function()? onImportRequested;
  const SettingsPage({
    Key? key,
    this.onSettingsChanged,
    this.onExportTasksRequested,
    this.onExportSettingsRequested,
    this.onExportEverythingRequested,
    this.onImportRequested,
  }) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tabsHeaderKey = GlobalKey();
  final List<GlobalKey> _sectionKeys = List<GlobalKey>.generate(
    14,
    (_) => GlobalKey(),
  );
  final List<String> _sectionTitles = const [
    'Appearance',
    'Mode & features',
    'Filtering rules',
    'Notifications',
    'Tasks',
    'Streak',
    'Dice timer',
    'SMS report',
    'Widget',
    'Updates',
    'Todoist sync',
    'Sync & export',
    'Backup',
    'Weekly Hours Planner',
  ];

  /// Sections currently on screen, in order. A section belonging to a feature
  /// that is switched off (or hidden by simple mode) drops out of the chip row
  /// and of the settings search along with its content.
  List<int> get _visibleSections => [
        for (var i = 0; i < _sectionTitles.length; i++)
          if (_isSectionVisible(i)) i,
      ];

  bool _isSectionVisible(int index) {
    switch (index) {
      case 5:
        return Config.isFeatureEnabled('streak');
      case 6:
        return Config.isFeatureEnabled('dice_timer');
      case 7:
        return Config.isFeatureEnabled('sms_report');
      case 13:
        return Config.isFeatureEnabled('weekly_hours_planner');
      default:
        return true;
    }
  }

  /// Choices offered for [Config.deletedItemsRetentionDays].
  static const List<int> _deletedItemsRetentionDayOptions = [
    7,
    14,
    30,
    60,
    90,
    180,
    365,
  ];

  int _activeSectionIndex = 0;

  /// Sections whose body is hidden. Tapping a section title toggles it. Every
  /// section starts collapsed so the page opens as a short list of headings
  /// instead of a wall of switches; the chip row and the settings search both
  /// expand the section they jump to.
  final Set<int> _collapsedSections = {
    for (var i = 0; i < 14; i++) i,
  };

  static const double _tabsHeaderHeight = 60;
  static const double _sectionActivationOffset = 56;
  double _lastScrollOffset = 0;

  // Search over the settings entries themselves (independent from the task
  // search on the home page). Matching titles are listed and tapping one
  // jumps to its section.
  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Every visible setting, so the search can find it. Section indexes match
  /// [_sectionTitles]; keywords add synonyms users may type instead.
  static const List<_SettingsSearchEntry> _searchEntries = [
    _SettingsSearchEntry('Dark mode', 0, 'theme light appearance color'),
    _SettingsSearchEntry('Minimalist mode', 0,
        'theme monochrome serene calm plain simple no colours colors underline'),
    _SettingsSearchEntry('Use tab icons', 0, 'tabs labels home'),
    _SettingsSearchEntry('Red dot for failed tests', 0,
        'menu hamburger drawer badge notification ci test results dot'),
    _SettingsSearchEntry('24-hour time', 0, 'clock am pm 12-hour format'),
    _SettingsSearchEntry('Date format', 0, 'display day month year'),
    _SettingsSearchEntry(
        'Simple mode', 1, 'full mode basic minimal features hide tools'),
    _SettingsSearchEntry(
        'Show the mode picker again', 1, 'simple full first start choose'),
    _SettingsSearchEntry('Health data & smart watch', 1,
        'samsung health galaxy watch health connect steps history cloud'),
    _SettingsSearchEntry('Add new tasks at top', 4, 'bottom order insert'),
    _SettingsSearchEntry('Desktop keyboard shortcuts', 4,
        'hotkeys ctrl enter arrows keyboard windows'),
    _SettingsSearchEntry('Save new task shortcut', 4,
        'enter ctrl enter multiline keyboard shortcuts'),
    _SettingsSearchEntry('New tasks go to', 4,
        'default list bucket target tab today future someday quick add'),
    _SettingsSearchEntry('Swipe left to delete', 4, 'gesture direction move'),
    _SettingsSearchEntry('Deleted items retention', 4,
        'archive archived bin trash purge days delete forever'),
    _SettingsSearchEntry('Default delay', 4, 'undo seconds snackbar'),
    _SettingsSearchEntry('Start page', 4, 'tab launch open today'),
    _SettingsSearchEntry('Default start page', 4, 'tool launch open tasks'),
    _SettingsSearchEntry('Start in schedule view', 4, 'calendar launch'),
    _SettingsSearchEntry('Chronize: show hour wheel', 4, 'timeline scroll'),
    _SettingsSearchEntry(
        'Auto-tag new items', 4, 'tags labels keywords automatic'),
    _SettingsSearchEntry(
        'Auto-tag rules', 4, 'tags labels keywords dictionary work bike'),
    _SettingsSearchEntry('Widget progress line', 8, 'home screen completion'),
    _SettingsSearchEntry('Check off tasks on the widget', 8,
        'home screen checkbox tick complete done interactive'),
    _SettingsSearchEntry('Enable notifications', 3, 'push reminders'),
    _SettingsSearchEntry('Quiet hours', 3, 'silence night do not disturb'),
    _SettingsSearchEntry('Default notification delay', 3, 'bell reminder'),
    _SettingsSearchEntry('Show streak', 5, 'flame fire hide daily habit'),
    _SettingsSearchEntry(
        'Streak grace period', 5, '24 48 hours flame miss day forgive'),
    _SettingsSearchEntry('Active challenges', 5,
        'streak flame finish create plan ahead move complete task daily'),
    _SettingsSearchEntry(
        'Streak reminders', 5, 'flame notification evening nudge daily times'),
    _SettingsSearchEntry('Add reminder', 5,
        'streak flame time notification sound vibration silent another'),
    _SettingsSearchEntry(
        'Streak celebration', 5, 'flame animation complete first task'),
    _SettingsSearchEntry('Alert at zero', 6,
        'dice timer melody vibration notification silent sound alarm quiet'),
    _SettingsSearchEntry('Melody', 6, 'dice timer sound tune alarm ring'),
    _SettingsSearchEntry('Volume', 6, 'dice timer loud quiet melody'),
    _SettingsSearchEntry('Also vibrate', 6, 'dice timer buzz vibration'),
    _SettingsSearchEntry(
        'Default timer length', 6, 'dice minutes dial pre-wound 20'),
    _SettingsSearchEntry(
        'Enable daily SMS report', 7, 'text message snitch daily'),
    _SettingsSearchEntry('Send time', 7, 'sms schedule daily'),
    _SettingsSearchEntry('Only send if under threshold', 7, 'sms completion'),
    _SettingsSearchEntry('SIM subscription id', 7, 'sms dual sim'),
    _SettingsSearchEntry(
        'Recipients', 7, 'sms phone number contact disable pause skip'),
    _SettingsSearchEntry('Message template', 7, 'sms tokens text'),
    _SettingsSearchEntry('Sent message history', 7, 'sms log'),
    _SettingsSearchEntry('Send test now', 7, 'sms report'),
    _SettingsSearchEntry('Synced mode', 11,
        'sync offline folder background quit backup automatic tasks'),
    _SettingsSearchEntry('Sync folder', 11, 'sync directory location choose'),
    _SettingsSearchEntry('Sync now', 11, 'sync manual run last synced'),
    _SettingsSearchEntry('Export Tasks', 11, 'backup save json'),
    _SettingsSearchEntry('Export Settings', 11, 'backup save json'),
    _SettingsSearchEntry('Export Everything', 11, 'backup save json'),
    _SettingsSearchEntry('Import', 11, 'restore backup load json'),
    _SettingsSearchEntry('Automatic backup', 12,
        'daily weekly schedule export save everything off'),
    _SettingsSearchEntry('Backup folder', 12, 'directory location path choose'),
    _SettingsSearchEntry('Back up now', 12, 'manual backup export run'),
    _SettingsSearchEntry(
        'Enable Todoist sync', 10, 'two-way api key token integration'),
    _SettingsSearchEntry('Todoist API token', 10, 'key integration secret'),
    _SettingsSearchEntry('Sync with Todoist now', 10, 'manual run two-way'),
    _SettingsSearchEntry('Automatically check for updates', 9,
        'auto update version release new build startup prompt install about'),
    _SettingsSearchEntry('Filtering rules', 2,
        'view home wishlist approval waiting for approval projects archived '
        'deleted bin hide show tag exclude include only filter built in'),
    _SettingsSearchEntry('Google Calendar URL', 13,
        'ics import feed link sync events weekly hours planner overlay calendar'),
    _SettingsSearchEntry('Weekly Hours Planner start hour', 13,
        'grid hour range day begin flexitime'),
    _SettingsSearchEntry('Weekly Hours Planner end hour', 13,
        'grid hour range day end flexitime'),
  ];

  /// The feature switches of the Mode & features section are searchable too,
  /// so "alarms" or "wishlist" finds the switch that turns them on.
  static List<_SettingsSearchEntry> get _featureSearchEntries => [
        for (var i = 0; i < Config.featureKeys.length; i++)
          _SettingsSearchEntry(
            Config.featureLabels[i],
            1,
            'feature show hide ${Config.featureDescriptions[i].toLowerCase()}',
          ),
      ];

  bool _notifications = Config.enableNotifications;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  bool _darkMode = Config.darkMode;
  bool _minimalistMode = Config.minimalistMode;
  bool _useIconTabs = Config.useIconTabs;
  bool _showFailureDotOnMenu = Config.showFailureDotOnMenu;
  bool _showWidgetProgressLine = Config.showWidgetProgressLine;
  bool _widgetCheckboxes = Config.widgetCheckboxes;
  bool _addNewTasksToTop = Config.addNewTasksToTop;
  bool _autoTagEnabled = Config.autoTagEnabled;
  bool _enterSavesNewTask = Config.enterSavesNewTask;
  int _defaultAddTabIndex = Config.defaultAddTabIndex;
  bool _use24HourFormat = Config.use24HourFormat;
  String _dateFormat = Config.dateFormat;
  int _startTabIndex = Config.startTabIndex;
  String _startTool = Config.startTool;
  bool _startInScheduleView = Config.startInScheduleView;
  bool _chronizeShowHourWheel = Config.chronizeShowHourWheel;
  double _defaultDelaySeconds = Config.defaultDelaySeconds;
  int _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;
  bool _quietHoursEnabled = Config.quietHoursEnabled;
  int _quietHoursStartMinutes = Config.quietHoursStartMinutes;
  int _quietHoursEndMinutes = Config.quietHoursEndMinutes;
  bool _showStreak = Config.showStreak;
  int _streakGraceHours = Config.streakGraceHours;
  bool _streakReminderEnabled = Config.streakReminderEnabled;
  bool _streakCompletionAnimation = Config.streakCompletionAnimation;
  bool _simpleMode = Config.simpleMode;
  String _autoBackupFrequency = Config.autoBackupFrequency;
  String _autoBackupDirectory = Config.autoBackupDirectory;
  DateTime? _lastAutoBackup;
  bool _syncEnabled = Config.syncEnabled;
  String _syncFolderPath = Config.syncFolderPath;
  bool _todoistSyncEnabled = Config.todoistSyncEnabled;
  bool _autoUpdateCheckEnabled = Config.autoUpdateCheckEnabled;
  int _deletedItemsRetentionDays = Config.deletedItemsRetentionDays;
  final TextEditingController _todoistTokenController =
      TextEditingController(text: Config.todoistApiToken);
  bool _todoistTokenObscured = true;
  bool _todoistTesting = false;
  String? _todoistTestResult;
  bool _todoistTestSucceeded = false;
  int _weeklyHoursStartHour = Config.weeklyHoursStartHour;
  int _weeklyHoursEndHour = Config.weeklyHoursEndHour;
  final TextEditingController _googleCalendarUrlController =
      TextEditingController(text: Config.googleCalendarUrl);
  bool _gcalImporting = false;
  String? _gcalError;
  int? _gcalEventCount;
  DateTime? _gcalLastImported;

  SmsReportConfig? _smsConfig;
  final TextEditingController _smsTemplateController = TextEditingController();

  /// One text field per view/kind combo in the Filtering rules section,
  /// keyed `'$viewId:$kind'` (`kind` is `exclude` or `include`).
  final Map<String, TextEditingController> _filterTagControllers = {};

  void _syncLocalStateFromConfig() {
    _notifications = Config.enableNotifications;
    _swipeLeftDelete = Config.swipeLeftDelete;
    _darkMode = Config.darkMode;
    _minimalistMode = Config.minimalistMode;
    _useIconTabs = Config.useIconTabs;
    _showFailureDotOnMenu = Config.showFailureDotOnMenu;
    _showWidgetProgressLine = Config.showWidgetProgressLine;
    _widgetCheckboxes = Config.widgetCheckboxes;
    _addNewTasksToTop = Config.addNewTasksToTop;
    _autoTagEnabled = Config.autoTagEnabled;
    _enterSavesNewTask = Config.enterSavesNewTask;
    _defaultAddTabIndex = Config.defaultAddTabIndex;
    _use24HourFormat = Config.use24HourFormat;
    _dateFormat = Config.dateFormat;
    _startTabIndex = Config.startTabIndex;
    _startTool = Config.startTool;
    _startInScheduleView = Config.startInScheduleView;
    _chronizeShowHourWheel = Config.chronizeShowHourWheel;
    _defaultDelaySeconds = Config.defaultDelaySeconds;
    _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;
    _quietHoursEnabled = Config.quietHoursEnabled;
    _quietHoursStartMinutes = Config.quietHoursStartMinutes;
    _quietHoursEndMinutes = Config.quietHoursEndMinutes;
    _showStreak = Config.showStreak;
    _streakGraceHours = Config.streakGraceHours;
    _streakReminderEnabled = Config.streakReminderEnabled;
    _streakCompletionAnimation = Config.streakCompletionAnimation;
    _simpleMode = Config.simpleMode;
    _autoBackupFrequency = Config.autoBackupFrequency;
    _autoBackupDirectory = Config.autoBackupDirectory;
    _syncEnabled = Config.syncEnabled;
    _syncFolderPath = Config.syncFolderPath;
    _todoistSyncEnabled = Config.todoistSyncEnabled;
    _todoistTokenController.text = Config.todoistApiToken;
    _autoUpdateCheckEnabled = Config.autoUpdateCheckEnabled;
    _deletedItemsRetentionDays = Config.deletedItemsRetentionDays;
    _weeklyHoursStartHour = Config.weeklyHoursStartHour;
    _weeklyHoursEndHour = Config.weeklyHoursEndHour;
    _googleCalendarUrlController.text = Config.googleCalendarUrl;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveSectionFromScroll);
    _loadSmsConfig();
    _loadLastAutoBackup();
    _loadGoogleCalendarStatus();
    // Lazy, fire-and-forget: the "Sync now" tile shows the last sync from the
    // persisted history once it arrives.
    unawaited(SyncService.instance.ensureLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateActiveSectionFromScroll();
    });
  }

  Future<void> _loadSmsConfig() async {
    final cfg = await SmsReportConfigService.load();
    if (!mounted) return;
    setState(() {
      _smsConfig = cfg;
      _smsTemplateController.text = cfg.template;
    });
  }

  Future<void> _persistSms() async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    await SmsReportConfigService.save(cfg);
    await SmsReportScheduler.applyFromConfig();
  }

  String _formatHour24(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Future<void> _pickSmsSubscriptionId() async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    final controller =
        TextEditingController(text: cfg.subscriptionId.toString());
    String? errorText;

    final picked = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('SIM subscription id'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '-1 = system default. On dual-SIM devices try 0, 1, or '
                'the subscription id shown in Android Settings → SIMs.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Subscription id',
                  errorText: errorText,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null) {
                  setDialogState(() => errorText = 'Enter an integer');
                  return;
                }
                Navigator.of(context).pop(v);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    setState(() => cfg.subscriptionId = picked);
    await _persistSms();
  }

  Future<void> _pickSmsTime() async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cfg.hour, minute: cfg.minute),
    );
    if (picked == null) return;
    setState(() {
      cfg.hour = picked.hour;
      cfg.minute = picked.minute;
    });
    await _persistSms();
  }

  Future<void> _editSmsRecipient({SmsRecipient? existing, int? index}) async {
    final nicknameController =
        TextEditingController(text: existing?.nickname ?? '');
    final phoneController =
        TextEditingController(text: existing?.phoneNumber ?? '');

    final result = await showDialog<SmsRecipient>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add recipient' : 'Edit recipient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nicknameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nickname'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+1234567890',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.isEmpty) return;
              Navigator.of(context).pop(SmsRecipient(
                nickname: nicknameController.text.trim(),
                phoneNumber: phone,
                // Editing must not silently re-enable a paused recipient.
                enabled: existing?.enabled ?? true,
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final cfg = _smsConfig;
    if (cfg == null) return;
    setState(() {
      if (index == null) {
        cfg.recipients.add(result);
      } else {
        cfg.recipients[index] = result;
      }
    });
    await _persistSms();
  }

  Future<void> _removeSmsRecipient(int index) async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    setState(() => cfg.recipients.removeAt(index));
    await _persistSms();
  }

  /// Pauses/resumes a recipient without deleting them — the daily report skips
  /// disabled ones ([SmsReportConfig.activeRecipients]).
  Future<void> _toggleSmsRecipient(int index, bool enabled) async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    setState(() => cfg.recipients[index].enabled = enabled);
    await _persistSms();
  }

  Future<void> _saveSmsTemplate() async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    cfg.template = _smsTemplateController.text;
    await _persistSms();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template saved')),
    );
  }

  Future<void> _resetSmsTemplate() async {
    final cfg = _smsConfig;
    if (cfg == null) return;
    setState(() {
      cfg.template = kDefaultSmsTemplate;
      _smsTemplateController.text = kDefaultSmsTemplate;
    });
    await _persistSms();
  }

  Future<void> _sendSmsTestNow() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Sending...')));
    final sent = await SmsReportService.runDailyReport();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Sent to $sent recipient(s)')),
    );
  }

  String _formatMmSs(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? _parseMmSs(String value) {
    final normalized = value.trim();
    final match = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(normalized);
    if (match == null) return null;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    return minutes * 60 + seconds;
  }

  String _formatHourMinute(int totalMinutes) {
    final minutes = totalMinutes.clamp(0, 1439);
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickQuietHour({
    required bool isStart,
  }) async {
    final current = isStart ? _quietHoursStartMinutes : _quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: current ~/ 60,
        minute: current % 60,
      ),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (isStart) {
        _quietHoursStartMinutes = minutes;
      } else {
        _quietHoursEndMinutes = minutes;
      }
    });
    Config.quietHoursStartMinutes = _quietHoursStartMinutes;
    Config.quietHoursEndMinutes = _quietHoursEndMinutes;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _editNotificationDelay() async {
    final controller = TextEditingController(
      text: _formatMmSs(_defaultNotificationDelaySeconds),
    );
    String? errorText;

    final parsed = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Default notification delay'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'MM:SS',
                hintText: '00:30',
                errorText: errorText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final seconds = _parseMmSs(controller.text);
                  if (seconds == null) {
                    setDialogState(() => errorText = 'Use format MM:SS');
                    return;
                  }
                  Navigator.of(context).pop(seconds);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (parsed == null) return;
    setState(() => _defaultNotificationDelaySeconds = parsed);
    Config.defaultNotificationDelaySeconds = parsed;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _jumpToSection(int index) async {
    final from = _activeSectionIndex;
    // Jumping to a collapsed section would land on a title with nothing under
    // it, so open it on the way.
    setState(() {
      _activeSectionIndex = index;
      _collapsedSections.remove(index);
    });

    // SliverList lays out children lazily, so a section that hasn't been
    // scrolled into view yet has no RenderObject and ensureVisible would
    // no-op. Walk the scroll one viewport at a time until the target section
    // is laid out, then ensureVisible does the final alignment. Jumping
    // straight to maxScrollExtent overshoots: a mid-list section can fall
    // outside the sliver cache again once the view sits at the bottom,
    // leaving its context null and the jump stuck at the last section.
    //
    // Two things the walk has to respect:
    //  • it must follow the direction of the target — walking only downwards
    //    left "Appearance" (and every earlier section) unreachable whenever
    //    the list already sat further down;
    //  • `maxScrollExtent` is an estimate that grows as each hop lays out more
    //    children, so stopping at "we reached the bottom" strands the jump
    //    halfway. Only a hop that moves neither the offset nor the estimate
    //    means there is really nothing left.
    if (_scrollController.hasClients) {
      final goingUp = index < from;
      var attempts = 0;
      var lastOffset = -1.0;
      var lastMaxExtent = -1.0;
      while (_sectionKeys[index].currentContext == null && attempts < 30) {
        final position = _scrollController.position;
        final maxExtent = position.maxScrollExtent;
        if (_scrollController.offset == lastOffset &&
            maxExtent == lastMaxExtent) {
          break;
        }
        lastOffset = _scrollController.offset;
        lastMaxExtent = maxExtent;
        final step =
            goingUp ? -position.viewportDimension : position.viewportDimension;
        final target = (position.pixels + step).clamp(0.0, maxExtent);
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
        attempts++;
      }
    }

    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) return;
    await Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: 0.02,
    );
  }

  void _updateActiveSectionFromScroll() {
    final currentOffset = _scrollController.hasClients
        ? _scrollController.offset
        : _lastScrollOffset;
    final isScrollingDown = currentOffset > _lastScrollOffset + 0.5;
    final isScrollingUp = currentOffset < _lastScrollOffset - 0.5;
    _lastScrollOffset = currentOffset;

    final tabsContext = _tabsHeaderKey.currentContext;
    if (tabsContext == null) return;
    final tabsBox = tabsContext.findRenderObject() as RenderBox?;
    if (tabsBox == null || !tabsBox.hasSize) return;

    final tabsBottom =
        tabsBox.localToGlobal(Offset.zero).dy + tabsBox.size.height;
    final activationLine = tabsBottom + _sectionActivationOffset;
    var index = 0;

    for (var i = 0; i < _sectionKeys.length; i++) {
      final sectionContext = _sectionKeys[i].currentContext;
      if (sectionContext == null) continue;
      final sectionBox = sectionContext.findRenderObject() as RenderBox?;
      if (sectionBox == null || !sectionBox.hasSize) continue;
      final sectionTop = sectionBox.localToGlobal(Offset.zero).dy;
      if (sectionTop <= activationLine) {
        index = i;
      } else {
        break;
      }
    }

    if (isScrollingDown && index < _activeSectionIndex) return;
    if (isScrollingUp && index > _activeSectionIndex) return;

    if (index != _activeSectionIndex && mounted) {
      setState(() => _activeSectionIndex = index);
    }
  }

  Widget _buildSection({
    required int index,
    required String title,
    required List<Widget> children,
  }) {
    final collapsed = _collapsedSections.contains(index);
    return Container(
      key: _sectionKeys[index],
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _toggleSection(index),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Tooltip(
                      message: collapsed ? 'Expand $title' : 'Collapse $title',
                      child: AnimatedRotation(
                        turns: collapsed ? 0 : 0.5,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.expand_more),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...children,
          ],
        ),
      ),
    );
  }

  void _toggleSection(int index) {
    setState(() {
      if (!_collapsedSections.remove(index)) _collapsedSections.add(index);
    });
    // Collapsing shortens the list, so the chip row has to re-pick the
    // section the viewport now shows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateActiveSectionFromScroll();
    });
  }

  /// One toggle for every section: collapses everything while any section is
  /// still open, expands everything once they are all closed.
  Widget _buildCollapseAllBar() {
    final anyExpanded =
        _visibleSections.any((i) => !_collapsedSections.contains(i));
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: () {
              setState(() {
                if (anyExpanded) {
                  _collapsedSections.addAll(
                    List<int>.generate(_sectionTitles.length, (i) => i),
                  );
                } else {
                  _collapsedSections.clear();
                }
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _updateActiveSectionFromScroll();
              });
            },
            icon: Icon(anyExpanded ? Icons.unfold_less : Icons.unfold_more),
            label: Text(anyExpanded ? 'Collapse all' : 'Expand all'),
          ),
        ],
      ),
    );
  }

  /// Persists a streak setting and lets the service re-arm its reminders.
  Future<void> _applyStreakChange() async {
    await Config.save();
    StreakService.instance.settingsChanged();
    widget.onSettingsChanged?.call();
  }

  /// Row under a customizable flame's toggle: shows its configured goal (or
  /// invites setting one) and opens [StreakGoalDialog] on tap.
  Widget _buildStreakGoalTile(StreakKind kind) {
    final info = streakFlameInfo(kind);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: 16),
      title: Text(
        info.configured ? info.title : 'No goal set',
        style: !info.configured
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      subtitle: Text(info.missing
          ? 'Its target was deleted — pick a new goal'
          : (info.configured
              ? info.description
              : 'Choose a recurring task or project to track')),
      trailing: TextButton(
        onPressed: () => _openStreakGoalDialog(kind),
        child: Text(info.configured ? 'Change' : 'Set goal'),
      ),
    );
  }

  Future<void> _openStreakGoalDialog(StreakKind kind) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => StreakGoalDialog(kind: kind),
    );
    if (changed == true && mounted) {
      setState(() {});
      widget.onSettingsChanged?.call();
    }
  }

  Future<void> _pickStreakReminderTime(int index) async {
    if (index < 0 || index >= Config.streakReminders.length) return;
    final reminder = Config.streakReminders[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: reminder.minutes ~/ 60,
        minute: reminder.minutes % 60,
      ),
    );
    if (picked == null) return;
    setState(() => reminder.minutes = picked.hour * 60 + picked.minute);
    // The first reminder's time doubles as the default for the next one.
    Config.streakReminderMinutes = Config.streakReminders.first.minutes;
    await _applyStreakChange();
  }

  /// Adds a reminder, defaulting to the last one's time plus an hour so two
  /// taps don't produce two identical entries.
  Future<void> _addStreakReminder() async {
    if (Config.streakReminders.length >= maxStreakReminders) return;
    final last = Config.streakReminders.isEmpty
        ? Config.streakReminderMinutes
        : Config.streakReminders.last.minutes + 60;
    setState(() {
      Config.streakReminders.add(StreakReminder(minutes: last % (24 * 60)));
      _streakReminderEnabled = Config.streakReminderEnabled = true;
    });
    await _applyStreakChange();
  }

  Future<void> _removeStreakReminder(int index) async {
    if (index < 0 || index >= Config.streakReminders.length) return;
    setState(() => Config.streakReminders.removeAt(index));
    await _applyStreakChange();
  }

  /// One configured reminder: its time (tap to change), how it announces
  /// itself, an on/off switch and a delete button.
  Widget _buildStreakReminderTile(int index, StreakReminder reminder) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: IconButton(
        tooltip: 'Reminder time',
        icon: const Icon(Icons.schedule),
        onPressed: () => _pickStreakReminderTime(index),
      ),
      title: InkWell(
        onTap: () => _pickStreakReminderTime(index),
        child: Text(
          _formatHourMinute(reminder.minutes),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      subtitle: Wrap(
        spacing: 6,
        children: [
          for (final mode in StreakAlertMode.values)
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              label: Text(mode.label),
              selected: reminder.mode == mode,
              onSelected: (_) async {
                setState(() => reminder.mode = mode);
                await _applyStreakChange();
              },
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: reminder.enabled,
            onChanged: (val) async {
              setState(() => reminder.enabled = val);
              await _applyStreakChange();
            },
          ),
          IconButton(
            tooltip: 'Remove reminder',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _removeStreakReminder(index),
          ),
        ],
      ),
    );
  }

  /// Applies a simple/full mode change: the mode itself is one switch, but a
  /// tool that just became unavailable must not stay the configured start
  /// page, or the app would open a page the user can no longer reach.
  Future<void> _setSimpleMode(bool value) async {
    setState(() => _simpleMode = value);
    Config.simpleMode = value;
    _dropUnavailableStartTool();
    await Config.save();
    StreakService.instance.settingsChanged();
    widget.onSettingsChanged?.call();
  }

  Future<void> _setFeatureEnabled(String key, bool value) async {
    setState(() => Config.setFeatureEnabled(key, value));
    _dropUnavailableStartTool();
    await Config.save();
    if (key == 'streak') StreakService.instance.settingsChanged();
    if (key == 'sms_report') await SmsReportScheduler.applyFromConfig();
    widget.onSettingsChanged?.call();
  }

  void _dropUnavailableStartTool() {
    if (Config.startTool != 'tasks' &&
        !Config.isFeatureEnabled(Config.startTool)) {
      Config.startTool = 'tasks';
      _startTool = 'tasks';
    }
  }

  /// Start-page options that are actually reachable: the task list plus every
  /// enabled tool.
  List<String> get _startToolChoices => [
        for (final tool in Config.startToolOptions)
          if (tool == 'tasks' || Config.isFeatureEnabled(tool)) tool,
      ];

  Widget _buildModeFeaturesSection() {
    final theme = Theme.of(context);
    return _buildSection(
      index: 1,
      title: 'Mode & features',
      children: [
        SwitchListTile(
          title: const Text('Simple mode'),
          subtitle: const Text(
              'Just the task list: hides the tools, streak, dice, schedule '
              'view and search'),
          value: _simpleMode,
          onChanged: _setSimpleMode,
        ),
        ListTile(
          title: const Text('Show the mode picker again'),
          subtitle:
              const Text('Choose simple or full mode on the welcome screen'),
          trailing: const Icon(Icons.restart_alt),
          onTap: () => MyApp.of(context)?.restartModePicker(),
        ),
        ListTile(
          leading: const Icon(Icons.watch_outlined),
          title: const Text('Health data & smart watch'),
          subtitle: const Text(
              'View all Health Connect history or connect Samsung Health and your watch'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const FitnessActivityPage(),
          )),
        ),
        const Divider(height: 1),
        if (_simpleMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Text(
              'Simple mode hides every optional feature. Turn it off to pick '
              'the features you want.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Features in full mode',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Switch off what you do not use — it disappears from the drawer, '
              'the app bar and these settings.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (var i = 0; i < Config.featureKeys.length; i++)
            SwitchListTile(
              title: Text(Config.featureLabels[i]),
              subtitle: Text(Config.featureDescriptions[i]),
              value: Config.featureEnabled[Config.featureKeys[i]] ?? true,
              onChanged: (val) =>
                  _setFeatureEnabled(Config.featureKeys[i], val),
            ),
        ],
      ],
    );
  }

  Widget _buildStreakSection() {
    return _buildSection(
      index: 5,
      title: 'Streak',
      children: [
        SwitchListTile(
          title: const Text('Show streak'),
          subtitle: const Text(
              'Flame next to the dice: grows every day you complete a task'),
          value: _showStreak,
          onChanged: (val) async {
            setState(() => _showStreak = val);
            Config.showStreak = val;
            await Config.save();
            StreakService.instance.settingsChanged();
            widget.onSettingsChanged?.call();
          },
        ),
        ListTile(
          title: const Text('Streak grace period'),
          subtitle: Text(_streakGraceHours >= 48
              ? '48 hours — one missed day is forgiven'
              : '24 hours — complete a task every day'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 24, label: Text('24h')),
              ButtonSegment(value: 48, label: Text('48h')),
            ],
            selected: {_streakGraceHours >= 48 ? 48 : 24},
            onSelectionChanged: (selection) async {
              final hours = selection.first;
              setState(() => _streakGraceHours = hours);
              Config.streakGraceHours = hours;
              await Config.save();
              StreakService.instance.settingsChanged();
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const ListTile(
          title: Text('Active challenges'),
          subtitle:
              Text('The flame in the app bar cycles through the challenges you '
                  'keep on'),
        ),
        for (final kind in StreakKind.values) ...[
          SwitchListTile(
            dense: true,
            secondary: Icon(kind.icon, color: kind.warm),
            title: Text(streakFlameInfo(kind).title),
            subtitle: Text(streakFlameInfo(kind).description),
            value: Config.isStreakKindEnabled(kind.id),
            onChanged: (val) async {
              setState(() => Config.streakKindEnabled[kind.id] = val);
              await _applyStreakChange();
            },
          ),
          if (kind != StreakKind.complete) _buildStreakGoalTile(kind),
        ],
        SwitchListTile(
          title: const Text('Streak reminders'),
          subtitle: const Text(
              'Nudge me at the times below while a challenge is still open'),
          value: _streakReminderEnabled,
          onChanged: (val) async {
            setState(() {
              _streakReminderEnabled = val;
              Config.streakReminderEnabled = val;
              // Turning them on without a single time configured would do
              // nothing, so seed the list with the default evening nudge.
              if (val && Config.streakReminders.isEmpty) {
                Config.streakReminders
                    .add(StreakReminder(minutes: Config.streakReminderMinutes));
              }
            });
            await _applyStreakChange();
          },
        ),
        if (_streakReminderEnabled) ...[
          for (var i = 0; i < Config.streakReminders.length; i++)
            _buildStreakReminderTile(i, Config.streakReminders[i]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: Config.streakReminders.length >= maxStreakReminders
                      ? null
                      : _addStreakReminder,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Add reminder'),
                ),
                const Spacer(),
                if (Config.streakReminders.length >= maxStreakReminders)
                  Text('$maxStreakReminders is the maximum',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
        SwitchListTile(
          title: const Text('Streak celebration'),
          subtitle: const Text(
              'Short flame animation when the first task of the day is done'),
          value: _streakCompletionAnimation,
          onChanged: (val) async {
            setState(() => _streakCompletionAnimation = val);
            Config.streakCompletionAnimation = val;
            await Config.save();
          },
        ),
      ],
    );
  }

  /// The dice timer's own alert settings, shared with the gear on the timer
  /// page ([DiceTimerSettingsList] writes straight through to [Config]).
  Widget _buildDiceTimerSection() {
    return _buildSection(
      index: 6,
      title: 'Dice timer',
      children: [
        DiceTimerSettingsList(onChanged: widget.onSettingsChanged),
      ],
    );
  }

  Widget _buildSmsReportSection() {
    final cfg = _smsConfig;
    if (cfg == null) {
      return _buildSection(
        index: 7,
        title: 'SMS report',
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: LinearProgressIndicator(),
          ),
        ],
      );
    }
    return _buildSection(
      index: 7,
      title: 'SMS report',
      children: [
        SwitchListTile(
          title: const Text('Enable daily SMS report'),
          subtitle: const Text(
              'Sends an SMS each day at the chosen time to enabled recipients'),
          value: cfg.enabled,
          onChanged: (v) async {
            setState(() => cfg.enabled = v);
            // Ask for exact-alarm + battery-optimization exemption up front,
            // otherwise the daily alarm silently never fires on OEMs that
            // deep-sleep background apps (Samsung "Sleeping apps", Doze).
            if (v) {
              await SmsReportScheduler.ensureBackgroundPermissions();
            }
            await _persistSms();
          },
        ),
        ListTile(
          title: const Text('Send time'),
          subtitle: Text(_formatHour24(cfg.hour, cfg.minute)),
          trailing: const Icon(Icons.schedule),
          onTap: _pickSmsTime,
        ),
        SwitchListTile(
          title: const Text('Only send if under threshold'),
          subtitle: Text(
            cfg.thresholdEnabled
                ? 'Send only when percentage of completed tasks is below '
                    '${cfg.completionThresholdPercent}%'
                : 'Always send when enabled',
          ),
          value: cfg.thresholdEnabled,
          onChanged: (v) async {
            setState(() => cfg.thresholdEnabled = v);
            await _persistSms();
          },
        ),
        if (cfg.thresholdEnabled)
          ListTile(
            title: Text(
              'Completion threshold: ${cfg.completionThresholdPercent}%',
            ),
            subtitle: Slider(
              value: cfg.completionThresholdPercent.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '${cfg.completionThresholdPercent}%',
              onChanged: (v) {
                setState(() => cfg.completionThresholdPercent = v.round());
              },
              onChangeEnd: (_) async {
                await _persistSms();
              },
            ),
          ),
        ListTile(
          title: const Text('SIM subscription id'),
          subtitle: Text(cfg.subscriptionId == -1
              ? 'Default (-1). Tap to change for dual-SIM devices.'
              : 'Sending via subscription id ${cfg.subscriptionId}'),
          trailing: const Icon(Icons.sim_card),
          onTap: _pickSmsSubscriptionId,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                'Recipients',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Add recipient',
                icon: const Icon(Icons.add),
                onPressed: () => _editSmsRecipient(),
              ),
            ],
          ),
        ),
        if (cfg.recipients.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('No recipients yet'),
          )
        else
          ...List<Widget>.generate(cfg.recipients.length, (i) {
            final r = cfg.recipients[i];
            final label = r.nickname.isEmpty ? '(no nickname)' : r.nickname;
            final dimmed = Theme.of(context).disabledColor;
            return ListTile(
              title: Text(
                label,
                style: r.enabled ? null : TextStyle(color: dimmed),
              ),
              subtitle: Text(
                r.enabled ? r.phoneNumber : '${r.phoneNumber} • disabled',
                style: r.enabled ? null : TextStyle(color: dimmed),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message:
                        r.enabled ? 'Disable recipient' : 'Enable recipient',
                    child: Switch(
                      value: r.enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) => _toggleSmsRecipient(i, value),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit recipient',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editSmsRecipient(existing: r, index: i),
                  ),
                  IconButton(
                    tooltip: 'Remove recipient',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeSmsRecipient(i),
                  ),
                ],
              ),
            );
          }),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Message template',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Tokens: {hello} {nickname} {completed} {uncompleted} {date} {list}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _smsTemplateController,
            maxLines: 8,
            minLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _saveSmsTemplate,
                icon: const Icon(Icons.save),
                label: const Text('Save template'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _resetSmsTemplate,
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Sent message history'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SmsReportLogPage(),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.send),
          title: const Text('Send test now'),
          subtitle:
              const Text('Run the report immediately using today\'s tasks'),
          onTap: _sendSmsTestNow,
        ),
      ],
    );
  }

  /// Turns synced mode on/off. Enabling without a chosen folder opens the
  /// folder picker right away; declining it keeps the switch on — the missed
  /// sync then surfaces as a red entry and the drawer dot, pointing back here.
  Future<void> _setSyncEnabled(bool value) async {
    setState(() => _syncEnabled = value);
    Config.syncEnabled = value;
    await Config.save();
    widget.onSettingsChanged?.call();
    if (value && _syncFolderPath.trim().isEmpty) {
      await _pickSyncFolder();
    }
  }

  Future<void> _pickSyncFolder() async {
    final current = _syncFolderPath.trim();
    final picked = await getDirectoryPath(
        initialDirectory: current.isEmpty ? null : current);
    if (picked == null) return;
    setState(() => _syncFolderPath = picked);
    Config.syncFolderPath = picked;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Widget _buildExportSection() {
    return _buildSection(
      index: 11,
      title: 'Sync & export',
      children: [
        SwitchListTile(
          title: const Text('Synced mode'),
          subtitle: const Text(
              'Write the tasks to a folder of your choice in the background '
              'whenever you leave the app. Off keeps everything offline.'),
          value: _syncEnabled,
          onChanged: _setSyncEnabled,
        ),
        if (_syncEnabled)
          ListTile(
            title: const Text('Sync folder'),
            subtitle: Text(
              _syncFolderPath.trim().isEmpty
                  ? 'No folder chosen yet — tap to choose'
                  : _syncFolderPath,
            ),
            trailing: const Icon(Icons.folder_open),
            onTap: _pickSyncFolder,
          ),
        if (_syncEnabled)
          ValueListenableBuilder<List<SyncLogEntry>>(
            valueListenable: SyncService.instance.entries,
            builder: (context, entries, _) {
              final folderChosen = _syncFolderPath.trim().isNotEmpty;
              final last = entries.isEmpty ? null : entries.first;
              return ListTile(
                enabled: folderChosen,
                leading: const Icon(Icons.sync),
                title: const Text('Sync now'),
                subtitle: Text(
                  last == null
                      ? (folderChosen
                          ? 'No sync yet'
                          : 'Choose a sync folder first')
                      : last.success
                          ? 'Last sync: ${_formatDateTime(last.at)} '
                              '(${last.itemCount} tasks)'
                          : 'Last sync failed: ${_formatDateTime(last.at)}',
                ),
                onTap: folderChosen ? _syncNow : null,
              );
            },
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: widget.onExportTasksRequested,
                icon: const Icon(Icons.task_alt),
                label: const Text('Export Tasks'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.onExportSettingsRequested,
                icon: const Icon(Icons.tune),
                label: const Text('Export Settings'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.onExportEverythingRequested,
                icon: const Icon(Icons.file_download),
                label: const Text('Export Everything'),
              ),
              const SizedBox(height: 18),
              Text(
                'Import',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: widget.onImportRequested == null
                    ? null
                    : () async {
                        await widget.onImportRequested!();
                        if (!mounted) return;
                        setState(_syncLocalStateFromConfig);
                      },
                icon: const Icon(Icons.file_upload),
                label: const Text('Import'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _syncNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final entry = await SyncService.instance.syncNow();
    if (!mounted || entry == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        entry.success
            ? 'Synced ${entry.itemCount} '
                '${entry.itemCount == 1 ? 'task' : 'tasks'}'
            : 'Sync failed: ${entry.message}',
      ),
    ));
  }

  Future<void> _loadLastAutoBackup() async {
    final last = await AutoBackupService.lastRun();
    if (!mounted) return;
    setState(() => _lastAutoBackup = last);
  }

  Future<void> _pickBackupFolder() async {
    final downloadsDir = await getDownloadsDirectory();
    final directory = await getDirectoryPath(
      initialDirectory: downloadsDir?.path,
    );
    if (directory == null) return;
    setState(() => _autoBackupDirectory = directory);
    Config.autoBackupDirectory = directory;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _setAutoBackupFrequency(String value) async {
    setState(() => _autoBackupFrequency = value);
    Config.autoBackupFrequency = value;
    await Config.save();
    // Turning the schedule on is the moment to ask for the folder; a fresh
    // schedule with a folder writes its first backup right away instead of
    // waiting for the next app start.
    if (value != 'off' && Config.autoBackupDirectory.isEmpty) {
      await _pickBackupFolder();
    }
    if (value != 'off' && Config.autoBackupDirectory.isNotEmpty) {
      await AutoBackupService.maybeRun();
      await _loadLastAutoBackup();
    }
    widget.onSettingsChanged?.call();
  }

  Future<void> _backupNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await AutoBackupService.runNow();
    await _loadLastAutoBackup();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        file != null ? 'Backed up to ${file.path}' : 'Backup failed',
      ),
    ));
  }

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildBackupSection() {
    final folderChosen = _autoBackupDirectory.isNotEmpty;
    return _buildSection(
      index: 12,
      title: 'Backup',
      children: [
        ListTile(
          title: const Text('Automatic backup'),
          subtitle: Text(switch (_autoBackupFrequency) {
            'daily' => 'Writes a full backup once a day when you open the app',
            'weekly' =>
              'Writes a full backup once a week when you open the app',
            _ => 'No automatic backups',
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<String>(
            segments: [
              for (var i = 0; i < Config.autoBackupFrequencies.length; i++)
                ButtonSegment(
                  value: Config.autoBackupFrequencies[i],
                  label: Text(Config.autoBackupFrequencyLabels[i]),
                ),
            ],
            selected: {_autoBackupFrequency},
            onSelectionChanged: (selection) =>
                _setAutoBackupFrequency(selection.first),
          ),
        ),
        ListTile(
          title: const Text('Backup folder'),
          subtitle: Text(
            folderChosen ? _autoBackupDirectory : 'Not set — tap to choose',
          ),
          trailing: const Icon(Icons.folder_open),
          onTap: _pickBackupFolder,
        ),
        ListTile(
          enabled: folderChosen,
          leading: const Icon(Icons.backup),
          title: const Text('Back up now'),
          subtitle: Text(
            _lastAutoBackup == null
                ? (folderChosen
                    ? 'No backup yet'
                    : 'Choose a backup folder first')
                : 'Last backup: ${_formatDateTime(_lastAutoBackup!)}',
          ),
          onTap: folderChosen ? _backupNow : null,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Each backup writes one timestamped JSON file with everything — '
            'tasks, settings and timers — restorable with Export → Import — '
            'plus a matching folder of Markdown notes (one per task, project, '
            'alarm and timer) readable straight in Obsidian.',
          ),
        ),
      ],
    );
  }

  Future<void> _loadGoogleCalendarStatus() async {
    final cached = await GoogleCalendarService.loadCached();
    final lastRefreshed = await GoogleCalendarService.lastRefreshed();
    if (!mounted) return;
    setState(() {
      _gcalEventCount = cached.isEmpty ? null : cached.length;
      _gcalLastImported = lastRefreshed;
    });
  }

  Future<void> _importGoogleCalendar() async {
    final url = _googleCalendarUrlController.text.trim();
    Config.googleCalendarUrl = url;
    await Config.save();
    if (url.isEmpty) {
      await GoogleCalendarService.clearCache();
      setState(() {
        _gcalEventCount = null;
        _gcalLastImported = null;
        _gcalError = null;
      });
      widget.onSettingsChanged?.call();
      return;
    }
    setState(() {
      _gcalImporting = true;
      _gcalError = null;
    });
    try {
      final events = await GoogleCalendarService.refresh(url);
      if (!mounted) return;
      setState(() {
        _gcalEventCount = events.length;
        _gcalLastImported = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _gcalError = 'Could not import that calendar URL');
    } finally {
      if (mounted) setState(() => _gcalImporting = false);
    }
    widget.onSettingsChanged?.call();
  }

  Future<void> _setWeeklyHoursHour({
    required bool isStart,
    required int hour,
  }) async {
    setState(() {
      if (isStart) {
        _weeklyHoursStartHour = hour;
        if (_weeklyHoursEndHour <= hour) _weeklyHoursEndHour = hour + 1;
      } else {
        _weeklyHoursEndHour = hour;
        if (_weeklyHoursStartHour >= hour) _weeklyHoursStartHour = hour - 1;
      }
    });
    Config.weeklyHoursStartHour = _weeklyHoursStartHour;
    Config.weeklyHoursEndHour = _weeklyHoursEndHour;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Widget _buildWeeklyHoursPlannerSection() {
    return _buildSection(
      index: 13,
      title: 'Weekly Hours Planner',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Hour range',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ListTile(
          title: const Text('Start hour'),
          subtitle: const Text('First hour shown on the grid'),
          trailing: DropdownButton<int>(
            value: _weeklyHoursStartHour,
            items: [
              for (var h = 0; h < 23; h++)
                DropdownMenuItem(
                    value: h, child: Text(_formatHourMinute(h * 60))),
            ],
            onChanged: (val) {
              if (val == null) return;
              _setWeeklyHoursHour(isStart: true, hour: val);
            },
          ),
        ),
        ListTile(
          title: const Text('End hour'),
          subtitle: const Text('Last hour shown on the grid'),
          trailing: DropdownButton<int>(
            value: _weeklyHoursEndHour,
            items: [
              for (var h = 1; h <= 24; h++)
                DropdownMenuItem(
                  value: h,
                  child: Text(_formatHourMinute((h % 24) * 60)),
                ),
            ],
            onChanged: (val) {
              if (val == null) return;
              _setWeeklyHoursHour(isStart: false, hour: val);
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Google Calendar',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Paste a public .ics feed URL (Google Calendar settings → '
            '"Secret address in iCal format"). Imported events for this '
            'week show translucent, underneath your work blocks, on the '
            'Weekly Hours Planner.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _googleCalendarUrlController,
            decoration: const InputDecoration(
              labelText: 'Calendar URL',
              hintText:
                  'https://calendar.google.com/calendar/ical/.../basic.ics',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _gcalImporting ? null : _importGoogleCalendar,
                icon: _gcalImporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download),
                label: const Text('Import'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _gcalError ??
                      (_gcalEventCount == null
                          ? 'Not imported yet'
                          : 'Imported $_gcalEventCount event'
                              '${_gcalEventCount == 1 ? '' : 's'}'
                              '${_gcalLastImported == null ? '' : ' · ${_formatDateTime(_gcalLastImported!)}'}'),
                  style: _gcalError == null
                      ? Theme.of(context).textTheme.bodySmall
                      : TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _setTodoistSyncEnabled(bool value) async {
    setState(() => _todoistSyncEnabled = value);
    Config.todoistSyncEnabled = value;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _persistTodoistToken() async {
    Config.todoistApiToken = _todoistTokenController.text.trim();
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _saveTodoistToken() async {
    await _persistTodoistToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Todoist token saved')),
    );
  }

  Future<void> _testTodoistConnection() async {
    final token = _todoistTokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _todoistTestResult = 'Enter an API token first';
        _todoistTestSucceeded = false;
      });
      return;
    }
    setState(() {
      _todoistTesting = true;
      _todoistTestResult = null;
    });
    try {
      await TodoistSyncService.instance.testConnection(token);
      if (!mounted) return;
      setState(() {
        _todoistTestResult = 'Connected';
        _todoistTestSucceeded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _todoistTestResult = e is TodoistApiException
            ? (e.statusCode == 401 ? 'Invalid API token' : e.message)
            : e.toString();
        _todoistTestSucceeded = false;
      });
    } finally {
      if (mounted) setState(() => _todoistTesting = false);
    }
  }

  Future<void> _syncTodoistNow() async {
    await _persistTodoistToken();
    final entry = await TodoistSyncService.instance.syncNow(trigger: 'manual');
    if (!mounted) return;
    widget.onSettingsChanged?.call();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (entry == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Turn on Todoist sync and enter a token first'),
      ));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(entry.success
          ? 'Synced ${entry.itemCount} change(s) with Todoist'
          : 'Todoist sync failed: ${entry.message}'),
    ));
  }

  Widget _buildTodoistSyncSection() {
    return _buildSection(
      index: 10,
      title: 'Todoist sync',
      children: [
        SwitchListTile(
          title: const Text('Enable Todoist sync'),
          subtitle: const Text(
              'Keeps tasks in sync both ways with a Todoist account, including '
              'labels, wishlist items (a Wishlist project) and undated tasks '
              '(a Future project). Recurring tasks stay local-only.'),
          value: _todoistSyncEnabled,
          onChanged: _setTodoistSyncEnabled,
        ),
        if (_todoistSyncEnabled) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'API token',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'From Todoist → Settings → Integrations → Developer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _todoistTokenController,
              obscureText: _todoistTokenObscured,
              decoration: InputDecoration(
                labelText: 'API token',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _todoistTokenObscured ? 'Show token' : 'Hide token',
                  icon: Icon(_todoistTokenObscured
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () => setState(
                      () => _todoistTokenObscured = !_todoistTokenObscured),
                ),
              ),
              onSubmitted: (_) => _saveTodoistToken(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saveTodoistToken,
                  icon: const Icon(Icons.save),
                  label: const Text('Save token'),
                ),
                OutlinedButton.icon(
                  onPressed: _todoistTesting ? null : _testTodoistConnection,
                  icon: _todoistTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Test connection'),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: TodoistSyncService.instance.syncing,
                  builder: (context, syncing, _) => FilledButton.icon(
                    onPressed: syncing ? null : _syncTodoistNow,
                    icon: syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ),
              ],
            ),
          ),
          if (_todoistTestResult != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _todoistTestResult!,
                style: TextStyle(
                  color: _todoistTestSucceeded
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const Divider(height: 1),
          ValueListenableBuilder<List<SyncLogEntry>>(
            valueListenable: TodoistSyncService.instance.entries,
            builder: (context, entries, _) {
              final last = entries.isEmpty ? null : entries.first;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  last == null
                      ? 'Never synced yet'
                      : last.success
                          ? 'Last synced ${_formatDateTime(last.at)} — '
                              '${last.itemCount} change(s)'
                          : 'Last sync failed (${_formatDateTime(last.at)}): '
                              '${last.message}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: (last != null && !last.success)
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                ),
              );
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'Fields Todoist has no room for — note, label, project and '
              'Kanban stage — are appended to the Todoist task\'s '
              'description so nothing is lost round-tripping. Editing that '
              'trailer by hand in Todoist is not recommended; editing the '
              'text above it is fine and syncs back as the task\'s '
              'description. Conflicting edits on both sides favor the '
              'BestToDo side.',
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _setAutoUpdateCheckEnabled(bool value) async {
    setState(() => _autoUpdateCheckEnabled = value);
    Config.autoUpdateCheckEnabled = value;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Widget _buildUpdatesSection() {
    return _buildSection(
      index: 9,
      title: 'Updates',
      children: [
        SwitchListTile(
          title: const Text('Automatically check for updates'),
          subtitle: const Text(
              'Polls for a newer version every minute while the app is open '
              'and asks whether to download and install it the moment one '
              'appears. Manual checks on the About page always work '
              'regardless of this setting.'),
          value: _autoUpdateCheckEnabled,
          onChanged: _setAutoUpdateCheckEnabled,
        ),
      ],
    );
  }

  /// The rules configured for [viewId], creating an empty (no-op) entry on
  /// first touch so the chip editors below always have a list to mutate.
  ViewFilterRules _rulesFor(String viewId) =>
      Config.viewFilterRules.putIfAbsent(viewId, () => ViewFilterRules());

  TextEditingController _filterTagController(String viewId, String kind) =>
      _filterTagControllers.putIfAbsent(
          '$viewId:$kind', () => TextEditingController());

  Future<void> _addFilterTag(String viewId, String kind, String rawTag) async {
    final tag = rawTag.trim();
    if (tag.isEmpty) return;
    final rules = _rulesFor(viewId);
    final list = kind == 'exclude' ? rules.excludeTags : rules.includeTags;
    if (list.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      _filterTagController(viewId, kind).clear();
      return;
    }
    setState(() => list.add(tag));
    _filterTagController(viewId, kind).clear();
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Future<void> _removeFilterTag(String viewId, String kind, String tag) async {
    final rules = _rulesFor(viewId);
    final list = kind == 'exclude' ? rules.excludeTags : rules.includeTags;
    setState(() => list.remove(tag));
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  Widget _buildTagRuleEditor({
    required String viewId,
    required String kind,
    required String label,
    required List<String> tags,
  }) {
    final controller = _filterTagController(viewId, kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in tags)
                    InputChip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => _removeFilterTag(viewId, kind, tag),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Tag name',
                    isDense: true,
                  ),
                  onSubmitted: (value) => _addFilterTag(viewId, kind, value),
                ),
              ),
              IconButton(
                tooltip: 'Add tag',
                icon: const Icon(Icons.add),
                onPressed: () =>
                    _addFilterTag(viewId, kind, controller.text),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Per-view tag filters: hide tasks carrying a tag, or restrict a view to
  /// only tasks carrying one. Layers on top of each view's own structural
  /// rule (e.g. the wishlist still only ever shows [Task.isWish] items) —
  /// see [ItemViews.passesFilterRules].
  Widget _buildFilteringRulesSection() {
    final theme = Theme.of(context);
    final viewIds = ViewFilterRules.viewIds;
    return _buildSection(
      index: 2,
      title: 'Filtering rules',
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Hide tasks by tag, or restrict a view to only tasks carrying a '
            'given tag — configured separately for each view below, on top '
            'of the built-in rule (if any) shown under each one.',
          ),
        ),
        for (var i = 0; i < viewIds.length; i++) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              ViewFilterRules.viewLabels[viewIds[i]]!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              ViewFilterRules.viewDescriptions[viewIds[i]]!,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (ViewFilterRules.builtInRules[viewIds[i]]!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                ViewFilterRules.builtInRules[viewIds[i]]!,
                style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          _buildTagRuleEditor(
            viewId: viewIds[i],
            kind: 'exclude',
            label: 'Hide tasks with any of these tags',
            tags: _rulesFor(viewIds[i]).excludeTags,
          ),
          _buildTagRuleEditor(
            viewId: viewIds[i],
            kind: 'include',
            label:
                'Only show tasks with one of these tags (empty = no restriction)',
            tags: _rulesFor(viewIds[i]).includeTags,
          ),
          if (i < viewIds.length - 1) const Divider(height: 24),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  List<_SettingsSearchEntry> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [..._searchEntries, ..._featureSearchEntries]
        .where((e) => _isSectionVisible(e.sectionIndex))
        .where((e) => _isEntryVisible(e))
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.keywords.contains(q) ||
            _sectionTitles[e.sectionIndex].toLowerCase().contains(q))
        .toList();
  }

  /// Single entries that disappear with their feature even though their
  /// section stays (the feature switches themselves are hidden in simple
  /// mode, where they have no effect).
  bool _isEntryVisible(_SettingsSearchEntry entry) {
    if (entry.sectionIndex == 1 &&
        Config.simpleMode &&
        Config.featureLabels.contains(entry.title)) {
      return false;
    }
    if (entry.title == 'Start in schedule view') {
      return Config.isFeatureEnabled('schedule_view');
    }
    if (entry.title == 'Chronize: show hour wheel') {
      return Config.isFeatureEnabled('chronize');
    }
    if (entry.title == 'Default start page') {
      return !Config.simpleMode;
    }
    if (entry.title == 'Desktop keyboard shortcuts' ||
        entry.title == 'Save new task shortcut') {
      return _showDesktopShortcutSettings(context);
    }
    return true;
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  void _openSearchResult(_SettingsSearchEntry entry) {
    _closeSearch();
    // The sections were replaced by the results list, so let them rebuild
    // before jumping (their contexts don't exist during this frame).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToSection(entry.sectionIndex);
    });
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search settings',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _searchQuery = value),
    );
  }

  List<Widget> _buildSearchResultTiles() {
    final results = _searchResults;
    if (results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No settings match your search')),
        ),
      ];
    }
    return results
        .map<Widget>((e) => ListTile(
              title: Text(e.title),
              subtitle: Text(_sectionTitles[e.sectionIndex]),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openSearchResult(e),
            ))
        .toList();
  }

  bool _showDesktopShortcutSettings(BuildContext context) {
    final platform = defaultTargetPlatform;
    final desktopPlatform = kIsWeb ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.linux;
    return desktopPlatform && MediaQuery.of(context).size.width >= 700;
  }

  Widget _shortcutRow(String keys, String action) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(action),
      trailing: Text(
        keys,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _buildDesktopShortcutSettings() {
    return [
      const Divider(height: 24),
      ListTile(
        leading: const Icon(Icons.keyboard),
        title: const Text('Desktop keyboard shortcuts'),
        subtitle: const Text('Windows-style shortcuts for the task list'),
      ),
      ListTile(
        title: const Text('Save new task shortcut'),
        subtitle: Text(_enterSavesNewTask
            ? 'Enter saves. Shift+Enter inserts a new line.'
            : 'Enter adds a new line. Ctrl+Enter saves.'),
        trailing: DropdownButton<bool>(
          value: _enterSavesNewTask,
          items: const [
            DropdownMenuItem<bool>(
              value: true,
              child: Text('Enter'),
            ),
            DropdownMenuItem<bool>(
              value: false,
              child: Text('Ctrl+Enter'),
            ),
          ],
          onChanged: (val) async {
            if (val == null) return;
            setState(() => _enterSavesNewTask = val);
            Config.enterSavesNewTask = val;
            await Config.save();
            widget.onSettingsChanged?.call();
          },
        ),
      ),
      _shortcutRow('Ctrl+N', 'Focus the new-task field'),
      _shortcutRow('Enter', 'Open the focused task'),
      _shortcutRow('Up / Down', 'Move task focus through the list'),
      _shortcutRow('Right / Left', 'Open the matching swipe action menu'),
      _shortcutRow('Right / Left again', 'Select the next swipe action'),
      _shortcutRow('Enter', 'Confirm the selected swipe action'),
      _shortcutRow('${Config.defaultDelaySeconds.toStringAsFixed(1)}s',
          'Auto-confirm the selected swipe action'),
      _shortcutRow('Space', 'Toggle the focused task complete'),
      _shortcutRow('Delete', 'Delete the focused task'),
      _shortcutRow('Ctrl+F', 'Focus task search'),
      _shortcutRow('Ctrl+,', 'Open settings'),
      _shortcutRow('Esc', 'Cancel the open menu or leave text input'),
    ];
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSectionFromScroll);
    _scrollController.dispose();
    _smsTemplateController.dispose();
    _searchController.dispose();
    _todoistTokenController.dispose();
    _googleCalendarUrlController.dispose();
    for (final controller in _filterTagControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSearchResults = _searchActive && _searchQuery.trim().isNotEmpty;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Settings',
        actions: [
          _searchActive
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Search settings',
                  onPressed: () => setState(() => _searchActive = true),
                ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _SettingsTabsHeaderDelegate(
              height: _tabsHeaderHeight,
              child: Container(
                key: _tabsHeaderKey,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: _searchActive
                    ? _buildSearchField()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final index in _visibleSections)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_sectionTitles[index]),
                                  selected: _activeSectionIndex == index,
                                  onSelected: (_) => _jumpToSection(index),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                showSearchResults
                    ? _buildSearchResultTiles()
                    : [
                        _buildCollapseAllBar(),
                        _buildSection(
                          index: 0,
                          title: 'Appearance',
                          children: [
                            SwitchListTile(
                              title: const Text('Dark mode'),
                              value: _darkMode,
                              onChanged: (val) async {
                                setState(() => _darkMode = val);
                                Config.darkMode = val;
                                await Config.save();
                                MyApp.of(context)?.updateTheme();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Minimalist mode'),
                              subtitle: const Text(
                                  'Calm monochrome look: no colours, underlines '
                                  'instead of highlights'),
                              value: _minimalistMode,
                              onChanged: (val) async {
                                setState(() => _minimalistMode = val);
                                Config.minimalistMode = val;
                                await Config.save();
                                MyApp.of(context)?.updateTheme();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Use tab icons'),
                              subtitle: const Text(
                                  'Show icons instead of text labels on the home screen'),
                              value: _useIconTabs,
                              onChanged: (val) async {
                                setState(() => _useIconTabs = val);
                                Config.useIconTabs = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Red dot for failed tests'),
                              subtitle: const Text(
                                  'Mark the menu icon with a red dot while the '
                                  'newest test run has failures you have not '
                                  'looked at yet'),
                              value: _showFailureDotOnMenu,
                              onChanged: (val) async {
                                setState(() => _showFailureDotOnMenu = val);
                                Config.showFailureDotOnMenu = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('24-hour time'),
                              subtitle:
                                  const Text('Turn off for 12-hour AM/PM time'),
                              value: _use24HourFormat,
                              onChanged: (val) async {
                                setState(() => _use24HourFormat = val);
                                Config.use24HourFormat = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            ListTile(
                              title: const Text('Date format'),
                              trailing: DropdownButton<String>(
                                value: _dateFormat,
                                items: Config.dateFormats
                                    .map(
                                      (f) => DropdownMenuItem<String>(
                                        value: f,
                                        child: Text(f.toLowerCase()),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) async {
                                  if (val == null) return;
                                  setState(() => _dateFormat = val);
                                  Config.dateFormat = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                          ],
                        ),
                        _buildModeFeaturesSection(),
                        _buildFilteringRulesSection(),
                        _buildSection(
                          index: 3,
                          title: 'Notifications',
                          children: [
                            SwitchListTile(
                              title: const Text('Enable notifications'),
                              value: _notifications,
                              onChanged: (val) async {
                                setState(() => _notifications = val);
                                Config.enableNotifications = val;
                                await Config.save();
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Quiet hours'),
                              subtitle: const Text(
                                  'Delay notifications until quiet hours end'),
                              value: _quietHoursEnabled,
                              onChanged: (val) async {
                                setState(() => _quietHoursEnabled = val);
                                Config.quietHoursEnabled = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            if (_quietHoursEnabled)
                              ListTile(
                                title: const Text('Quiet hours start'),
                                subtitle: Text(
                                    _formatHourMinute(_quietHoursStartMinutes)),
                                trailing: const Icon(Icons.schedule),
                                onTap: () => _pickQuietHour(isStart: true),
                              ),
                            if (_quietHoursEnabled)
                              ListTile(
                                title: const Text('Quiet hours end'),
                                subtitle: Text(
                                    _formatHourMinute(_quietHoursEndMinutes)),
                                trailing: const Icon(Icons.schedule),
                                onTap: () => _pickQuietHour(isStart: false),
                              ),
                            ListTile(
                              title: const Text('Default notification delay'),
                              subtitle: Text(
                                'MM:SS (${_formatMmSs(_defaultNotificationDelaySeconds)})',
                              ),
                              trailing: const Icon(Icons.edit),
                              onTap: _editNotificationDelay,
                            ),
                          ],
                        ),
                        _buildSection(
                          index: 4,
                          title: 'Tasks',
                          children: [
                            SwitchListTile(
                              title: const Text('Add new tasks at top'),
                              subtitle: const Text(
                                  'Turn off to add new tasks at the bottom'),
                              value: _addNewTasksToTop,
                              onChanged: (val) async {
                                setState(() => _addNewTasksToTop = val);
                                Config.addNewTasksToTop = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            if (_showDesktopShortcutSettings(context))
                              ..._buildDesktopShortcutSettings(),
                            ListTile(
                              title: const Text('New tasks go to'),
                              subtitle: const Text(
                                  'Which list a task typed in the add row lands in '
                                  '(the schedule view still uses its active day)'),
                              trailing: DropdownButton<int>(
                                value: _defaultAddTabIndex,
                                items: [
                                  const DropdownMenuItem<int>(
                                    value: Config.addToCurrentTab,
                                    child: Text('Current tab'),
                                  ),
                                  for (var index = 0;
                                      index < Config.tabs.length;
                                      index++)
                                    DropdownMenuItem<int>(
                                      value: index,
                                      child: Text(
                                        Config.tabs[index]
                                            .replaceAll('\n', ' ')
                                            .trim(),
                                      ),
                                    ),
                                ],
                                onChanged: (val) async {
                                  if (val == null) return;
                                  setState(() => _defaultAddTabIndex = val);
                                  Config.defaultAddTabIndex = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                            SwitchListTile(
                              title: const Text('Swipe left to delete'),
                              subtitle: const Text(
                                  'Turn off to swipe right to delete and left to move'),
                              value: _swipeLeftDelete,
                              onChanged: (val) async {
                                setState(() => _swipeLeftDelete = val);
                                Config.swipeLeftDelete = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            ListTile(
                              title: const Text('Deleted items retention'),
                              subtitle: const Text(
                                  'How long an item stays in the real Deleted bin '
                                  '(Archived Items → bin icon) before it is purged for good'),
                              trailing: DropdownButton<int>(
                                value: _deletedItemsRetentionDayOptions
                                        .contains(_deletedItemsRetentionDays)
                                    ? _deletedItemsRetentionDays
                                    : _deletedItemsRetentionDayOptions.first,
                                items: [
                                  for (final days
                                      in _deletedItemsRetentionDayOptions)
                                    DropdownMenuItem<int>(
                                      value: days,
                                      child: Text('$days days'),
                                    ),
                                ],
                                onChanged: (val) async {
                                  if (val == null) return;
                                  setState(() => _deletedItemsRetentionDays = val);
                                  Config.deletedItemsRetentionDays = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                            ListTile(
                              title: Text(
                                'Default delay (${_defaultDelaySeconds.toStringAsFixed(1)}s)',
                              ),
                              subtitle: Slider(
                                value: _defaultDelaySeconds,
                                min: 0,
                                max: 10,
                                divisions: 100,
                                onChanged: (val) async {
                                  final newVal = (val * 10).round() / 10;
                                  setState(() => _defaultDelaySeconds = newVal);
                                  Config.defaultDelaySeconds = newVal;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                            ListTile(
                              title: const Text('Start page'),
                              subtitle: const Text(
                                  'Open this tab when launching the app'),
                              trailing: DropdownButton<int>(
                                value: _startTabIndex,
                                items: List.generate(
                                  Config.tabs.length,
                                  (index) => DropdownMenuItem<int>(
                                    value: index,
                                    child: Text(
                                      Config.tabs[index]
                                          .replaceAll('\n', ' ')
                                          .trim(),
                                    ),
                                  ),
                                ),
                                onChanged: (val) async {
                                  if (val == null) return;
                                  setState(() => _startTabIndex = val);
                                  Config.startTabIndex = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            ),
                            if (!_simpleMode)
                              ListTile(
                                title: const Text('Default start page'),
                                subtitle: const Text(
                                    'Open the task list or one of the tools when '
                                    'launching the app'),
                                trailing: DropdownButton<String>(
                                  value: _startToolChoices.contains(_startTool)
                                      ? _startTool
                                      : _startToolChoices.first,
                                  items: [
                                    for (final tool in _startToolChoices)
                                      DropdownMenuItem<String>(
                                        value: tool,
                                        child: Text(Config.startToolLabels[
                                            Config.startToolOptions
                                                .indexOf(tool)]),
                                      ),
                                  ],
                                  onChanged: (val) async {
                                    if (val == null) return;
                                    setState(() => _startTool = val);
                                    Config.startTool = val;
                                    await Config.save();
                                    widget.onSettingsChanged?.call();
                                  },
                                ),
                              ),
                            if (Config.isFeatureEnabled('schedule_view'))
                              SwitchListTile(
                                title: const Text('Start in schedule view'),
                                subtitle: const Text(
                                    'Open the calendar / schedule view on launch instead of the tab list'),
                                value: _startInScheduleView,
                                onChanged: (val) async {
                                  setState(() => _startInScheduleView = val);
                                  Config.startInScheduleView = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            if (Config.isFeatureEnabled('chronize'))
                              SwitchListTile(
                                title: const Text('Chronize: show hour wheel'),
                                subtitle: const Text(
                                    'Add the hour scroll wheel to the Chronize tool (off gives the timeline more room)'),
                                value: _chronizeShowHourWheel,
                                onChanged: (val) async {
                                  setState(() => _chronizeShowHourWheel = val);
                                  Config.chronizeShowHourWheel = val;
                                  await Config.save();
                                  widget.onSettingsChanged?.call();
                                },
                              ),
                            SwitchListTile(
                              title: const Text('Auto-tag new items'),
                              subtitle: const Text(
                                  'Add tags to new tasks/wishes automatically based on keywords in the title'),
                              value: _autoTagEnabled,
                              onChanged: (val) async {
                                setState(() => _autoTagEnabled = val);
                                Config.autoTagEnabled = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.sell_outlined),
                              title: const Text('Auto-tag rules'),
                              subtitle: const Text(
                                  'Edit which groups of words add which tag'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const AutoTagRulesPage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_isSectionVisible(5)) _buildStreakSection(),
                        if (_isSectionVisible(6)) _buildDiceTimerSection(),
                        if (_isSectionVisible(7)) _buildSmsReportSection(),
                        _buildSection(
                          index: 8,
                          title: 'Widget',
                          children: [
                            SwitchListTile(
                              title: const Text('Widget progress line'),
                              subtitle: const Text(
                                  'Show completion line on the home widget'),
                              value: _showWidgetProgressLine,
                              onChanged: (val) async {
                                setState(() => _showWidgetProgressLine = val);
                                Config.showWidgetProgressLine = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                            SwitchListTile(
                              title:
                                  const Text('Check off tasks on the widget'),
                              subtitle: const Text(
                                  'Show today\'s tasks as rows with a checkbox — '
                                  'tapping one completes it without opening the app'),
                              value: _widgetCheckboxes,
                              onChanged: (val) async {
                                setState(() => _widgetCheckboxes = val);
                                Config.widgetCheckboxes = val;
                                await Config.save();
                                widget.onSettingsChanged?.call();
                              },
                            ),
                          ],
                        ),
                        _buildUpdatesSection(),
                        _buildTodoistSyncSection(),
                        _buildExportSection(),
                        _buildBackupSection(),
                        if (_isSectionVisible(13))
                          _buildWeeklyHoursPlannerSection(),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A searchable settings entry: the tile's title, the index of the section
/// (into `_sectionTitles`) it lives in, and extra match keywords.
class _SettingsSearchEntry {
  final String title;
  final int sectionIndex;
  final String keywords;

  const _SettingsSearchEntry(this.title, this.sectionIndex,
      [this.keywords = '']);
}

class _SettingsTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  const _SettingsTabsHeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _SettingsTabsHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}
