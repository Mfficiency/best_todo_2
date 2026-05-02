import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import 'subpage_app_bar.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tabsHeaderKey = GlobalKey();
  final List<GlobalKey> _sectionKeys = List<GlobalKey>.generate(
    4,
    (_) => GlobalKey(),
  );
  final List<String> _sectionTitles = const [
    'Appearance',
    'Tasks',
    'Widget',
    'Notifications',
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
  double _defaultDelaySeconds = Config.defaultDelaySeconds;
  int _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;
  bool _quietHoursEnabled = Config.quietHoursEnabled;
  int _quietHoursStartMinutes = Config.quietHoursStartMinutes;
  int _quietHoursEndMinutes = Config.quietHoursEndMinutes;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveSectionFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateActiveSectionFromScroll();
    });
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

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSectionFromScroll);
    _scrollController.dispose();
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
