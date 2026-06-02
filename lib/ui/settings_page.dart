import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import '../models/sms_recipient.dart';
import '../models/sms_report_config.dart';
import '../services/sms_report_config_service.dart';
import '../services/sms_report_scheduler.dart';
import '../services/sms_report_service.dart';
import 'sms_report_log_page.dart';
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
    6,
    (_) => GlobalKey(),
  );
  final List<String> _sectionTitles = const [
    'Appearance',
    'Tasks',
    'Widget',
    'Notifications',
    'SMS report',
    'Export',
  ];
  int _activeSectionIndex = 0;
  static const double _tabsHeaderHeight = 60;
  static const double _sectionActivationOffset = 56;
  double _lastScrollOffset = 0;

  bool _notifications = Config.enableNotifications;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  bool _darkMode = Config.darkMode;
  bool _useIconTabs = Config.useIconTabs;
  bool _showWidgetProgressLine = Config.showWidgetProgressLine;
  bool _addNewTasksToTop = Config.addNewTasksToTop;
  int _startTabIndex = Config.startTabIndex;
  bool _startInScheduleView = Config.startInScheduleView;
  double _defaultDelaySeconds = Config.defaultDelaySeconds;
  int _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;
  bool _quietHoursEnabled = Config.quietHoursEnabled;
  int _quietHoursStartMinutes = Config.quietHoursStartMinutes;
  int _quietHoursEndMinutes = Config.quietHoursEndMinutes;

  SmsReportConfig? _smsConfig;
  final TextEditingController _smsTemplateController = TextEditingController();

  void _syncLocalStateFromConfig() {
    _notifications = Config.enableNotifications;
    _swipeLeftDelete = Config.swipeLeftDelete;
    _darkMode = Config.darkMode;
    _useIconTabs = Config.useIconTabs;
    _showWidgetProgressLine = Config.showWidgetProgressLine;
    _addNewTasksToTop = Config.addNewTasksToTop;
    _startTabIndex = Config.startTabIndex;
    _startInScheduleView = Config.startInScheduleView;
    _defaultDelaySeconds = Config.defaultDelaySeconds;
    _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;
    _quietHoursEnabled = Config.quietHoursEnabled;
    _quietHoursStartMinutes = Config.quietHoursStartMinutes;
    _quietHoursEndMinutes = Config.quietHoursEndMinutes;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveSectionFromScroll);
    _loadSmsConfig();
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
    setState(() => _activeSectionIndex = index);

    // SliverList lays out children lazily, so a section that hasn't been
    // scrolled into view yet has no RenderObject and ensureVisible would
    // no-op. Walk the scroll forward in chunks until the target section
    // is laid out, then ensureVisible does the final alignment.
    if (_scrollController.hasClients) {
      var attempts = 0;
      while (_sectionKeys[index].currentContext == null && attempts < 10) {
        final position = _scrollController.position;
        final maxExtent = position.maxScrollExtent;
        if (_scrollController.offset >= maxExtent - 1) break;
        await _scrollController.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 200),
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
    return Container(
      key: _sectionKeys[index],
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSmsReportSection() {
    final cfg = _smsConfig;
    if (cfg == null) {
      return _buildSection(
        index: 4,
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
      index: 4,
      title: 'SMS report',
      children: [
        SwitchListTile(
          title: const Text('Enable daily SMS report'),
          subtitle: const Text(
              'Sends an SMS each day at the chosen time to all recipients'),
          value: cfg.enabled,
          onChanged: (v) async {
            setState(() => cfg.enabled = v);
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
            return ListTile(
              title: Text(label),
              subtitle: Text(r.phoneNumber),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () =>
                        _editSmsRecipient(existing: r, index: i),
                  ),
                  IconButton(
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

  Widget _buildExportSection() {
    return _buildSection(
      index: 5,
      title: 'Export',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSectionFromScroll);
    _scrollController.dispose();
    _smsTemplateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Settings'),
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        List<Widget>.generate(_sectionTitles.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_sectionTitles[index]),
                          selected: _activeSectionIndex == index,
                          onSelected: (_) => _jumpToSection(index),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
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
                    ],
                  ),
                  _buildSection(
                    index: 1,
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
                        subtitle:
                            const Text('Open this tab when launching the app'),
                        trailing: DropdownButton<int>(
                          value: _startTabIndex,
                          items: List.generate(
                            Config.tabs.length,
                            (index) => DropdownMenuItem<int>(
                              value: index,
                              child: Text(
                                Config.tabs[index].replaceAll('\n', ' ').trim(),
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
                    ],
                  ),
                  _buildSection(
                    index: 2,
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
                    ],
                  ),
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
                          subtitle:
                              Text(_formatHourMinute(_quietHoursStartMinutes)),
                          trailing: const Icon(Icons.schedule),
                          onTap: () => _pickQuietHour(isStart: true),
                        ),
                      if (_quietHoursEnabled)
                        ListTile(
                          title: const Text('Quiet hours end'),
                          subtitle:
                              Text(_formatHourMinute(_quietHoursEndMinutes)),
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
                  _buildSmsReportSection(),
                  _buildExportSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
