import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_settings.dart';
import '../services/backup_service.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';
import 'widgets/settings_section.dart';
import 'widgets/spacing.dart';

/// Single-page, searchable Settings screen.
///
/// Two navigation aids, both lifted from the host app:
///  * A pinned header of **section chips** — tap one to smoothly scroll to that
///    section; the active chip highlights as you scroll.
///  * A **search** (magnifier in the app bar) that filters every individual
///    setting by title/keyword; tapping a result jumps to its section.
///
/// Every setting reads and writes [AppSettings]; saving notifies listeners so
/// the theme updates instantly. Export/import use the versioned
/// [BackupService].
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final AppSettings _s = AppSettings.instance;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tabsHeaderKey = GlobalKey();
  final List<GlobalKey> _sectionKeys =
      List<GlobalKey>.generate(4, (_) => GlobalKey());
  static const List<String> _sectionTitles = [
    'Appearance',
    'Startup',
    'Notifications',
    'Data',
  ];
  int _activeSectionIndex = 0;
  static const double _tabsHeaderHeight = 60;
  static const double _sectionActivationOffset = 56;
  double _lastScrollOffset = 0;

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  /// Every visible setting, so search can find it. Section indexes match
  /// [_sectionTitles]; keywords add synonyms users might type.
  static const List<_SearchEntry> _searchEntries = [
    _SearchEntry('Theme', 0, 'appearance system light dark colour color mode'),
    _SearchEntry('Minimalist mode', 0,
        'monochrome calm plain simple no colours underline'),
    _SearchEntry('24-hour time', 0, 'clock am pm 12-hour format'),
    _SearchEntry('Date format', 0, 'display day month year'),
    _SearchEntry('Start page', 1, 'launch open default'),
    _SearchEntry('Enable notifications', 2, 'push reminders alerts'),
    _SearchEntry('Quiet hours', 2, 'silence night do not disturb'),
    _SearchEntry('Default notification delay', 2, 'reminder seconds'),
    _SearchEntry('Export everything', 3, 'backup save json data settings'),
    _SearchEntry('Export settings', 3, 'backup save json'),
    _SearchEntry('Import', 3, 'restore backup load json'),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveSectionFromScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateActiveSectionFromScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateActiveSectionFromScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // --- Persistence helper ---------------------------------------------------

  Future<void> _apply(VoidCallback mutate) async {
    setState(mutate);
    await _s.save(); // persists + notifies listeners (theme refreshes)
  }

  // --- Scroll / section tracking (verbatim mechanism from the host) ---------

  Future<void> _jumpToSection(int index) async {
    setState(() => _activeSectionIndex = index);
    if (_scrollController.hasClients) {
      var attempts = 0;
      while (_sectionKeys[index].currentContext == null && attempts < 20) {
        final position = _scrollController.position;
        final maxExtent = position.maxScrollExtent;
        if (_scrollController.offset >= maxExtent - 1) break;
        final target = (position.pixels + position.viewportDimension)
            .clamp(0.0, maxExtent);
        await _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
        attempts++;
      }
    }
    final sectionContext = _sectionKeys[index].currentContext;
    if (sectionContext == null) return;
    await Scrollable.ensureVisible(sectionContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        alignment: 0.02);
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

  // --- Search ---------------------------------------------------------------

  List<_SearchEntry> get _searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _searchEntries
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.keywords.contains(q) ||
            _sectionTitles[e.sectionIndex].toLowerCase().contains(q))
        .toList();
  }

  void _closeSearch() => setState(() {
        _searchActive = false;
        _searchController.clear();
        _searchQuery = '';
      });

  void _openSearchResult(_SearchEntry entry) {
    _closeSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToSection(entry.sectionIndex);
    });
  }

  // --- Backups --------------------------------------------------------------

  Future<void> _export({required bool includeData}) async {
    final dir = await getDirectoryPath();
    if (dir == null) {
      _snack('Export canceled');
      return;
    }
    final file =
        await BackupService.instance.exportToDirectory(dir, includeData: includeData);
    _snack(file != null ? 'Exported to ${file.path}' : 'Export failed');
  }

  Future<void> _import() async {
    const typeGroup = XTypeGroup(label: 'json', extensions: ['json']);
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final result = await BackupService.instance.importFile(picked.path);
    if (result.applied) {
      await _s.save(); // persist restored settings + refresh theme
      if (mounted) setState(() {});
    }
    final suffix =
        result.warnings.isEmpty ? '' : ' (${result.warnings.join(' | ')})';
    _snack(result.applied ? 'Import complete$suffix' : 'Import failed$suffix');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Notification helpers -------------------------------------------------

  Future<void> _pickQuietHour({required bool isStart}) async {
    final current =
        isStart ? _s.quietHoursStartMinutes : _s.quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    await _apply(() {
      if (isStart) {
        _s.quietHoursStartMinutes = picked.hour * 60 + picked.minute;
      } else {
        _s.quietHoursEndMinutes = picked.hour * 60 + picked.minute;
      }
    });
  }

  Future<void> _editNotificationDelay() async {
    final controller =
        TextEditingController(text: formatMmSs(_s.notificationDelaySeconds));
    String? errorText;
    final parsed = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
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
                final seconds = parseMmSs(controller.text);
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
      ),
    );
    if (parsed == null) return;
    await _apply(() => _s.notificationDelaySeconds = parsed);
  }

  // --- Sections -------------------------------------------------------------

  Widget _appearanceSection() => SettingsSection(
        sectionKey: _sectionKeys[0],
        title: 'Appearance',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              children: [
                const Expanded(child: Text('Theme')),
                SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(
                        value: AppThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        tooltip: 'System'),
                    ButtonSegment(
                        value: AppThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        tooltip: 'Light'),
                    ButtonSegment(
                        value: AppThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        tooltip: 'Dark'),
                  ],
                  selected: {_s.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (set) =>
                      _apply(() => _s.themeMode = set.first),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Minimalist mode'),
            subtitle: const Text(
                'Calm monochrome look: no colours, underlines instead of '
                'highlights'),
            value: _s.minimalist,
            onChanged: (v) => _apply(() => _s.minimalist = v),
          ),
          SwitchListTile(
            title: const Text('24-hour time'),
            subtitle: const Text('Turn off for 12-hour AM/PM time'),
            value: _s.use24HourFormat,
            onChanged: (v) => _apply(() => _s.use24HourFormat = v),
          ),
          ListTile(
            title: const Text('Date format'),
            subtitle: Text(formatDate(DateTime(2026, 3, 9))),
            trailing: DropdownButton<String>(
              value: _s.dateFormat,
              items: AppSettings.dateFormats
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _apply(() => _s.dateFormat = v);
              },
            ),
          ),
        ],
      );

  Widget _startupSection() => SettingsSection(
        sectionKey: _sectionKeys[1],
        title: 'Startup',
        children: [
          ListTile(
            title: const Text('Start page'),
            subtitle: const Text('Screen to open when the app launches'),
            trailing: DropdownButton<String>(
              value: AppConfig.startPages.any((p) => p.key == _s.startPageKey)
                  ? _s.startPageKey
                  : AppConfig.startPages.first.key,
              items: AppConfig.startPages
                  .map((p) =>
                      DropdownMenuItem(value: p.key, child: Text(p.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) _apply(() => _s.startPageKey = v);
              },
            ),
          ),
        ],
      );

  Widget _notificationsSection() => SettingsSection(
        sectionKey: _sectionKeys[2],
        title: 'Notifications',
        children: [
          SwitchListTile(
            title: const Text('Enable notifications'),
            value: _s.notificationsEnabled,
            onChanged: (v) => _apply(() => _s.notificationsEnabled = v),
          ),
          SwitchListTile(
            title: const Text('Quiet hours'),
            subtitle:
                const Text('Delay notifications until quiet hours end'),
            value: _s.quietHoursEnabled,
            onChanged: (v) => _apply(() => _s.quietHoursEnabled = v),
          ),
          if (_s.quietHoursEnabled) ...[
            ListTile(
              title: const Text('Quiet hours start'),
              subtitle: Text(formatMinutesOfDay(_s.quietHoursStartMinutes)),
              trailing: const Icon(Icons.schedule),
              onTap: () => _pickQuietHour(isStart: true),
            ),
            ListTile(
              title: const Text('Quiet hours end'),
              subtitle: Text(formatMinutesOfDay(_s.quietHoursEndMinutes)),
              trailing: const Icon(Icons.schedule),
              onTap: () => _pickQuietHour(isStart: false),
            ),
          ],
          ListTile(
            title: const Text('Default notification delay'),
            subtitle: Text('MM:SS (${formatMmSs(_s.notificationDelaySeconds)})'),
            trailing: const Icon(Icons.edit),
            onTap: _editNotificationDelay,
          ),
        ],
      );

  Widget _dataSection() => SettingsSection(
        sectionKey: _sectionKeys[3],
        title: 'Data',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: () => _export(includeData: true),
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export Everything'),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _export(includeData: false),
                  icon: const Icon(Icons.tune),
                  label: const Text('Export Settings'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Restore',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import'),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildSearchField() => TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search settings',
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
        onChanged: (v) => setState(() => _searchQuery = v),
      );

  List<Widget> _buildSearchResultTiles() {
    final results = _searchResults;
    if (results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
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
            delegate: _TabsHeaderDelegate(
              height: _tabsHeaderHeight,
              child: Container(
                key: _tabsHeaderKey,
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                child: _searchActive
                    ? _buildSearchField()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              List<Widget>.generate(_sectionTitles.length, (i) {
                            return Padding(
                              padding:
                                  const EdgeInsets.only(right: AppSpacing.sm),
                              child: ChoiceChip(
                                label: Text(_sectionTitles[i]),
                                selected: _activeSectionIndex == i,
                                onSelected: (_) => _jumpToSection(i),
                              ),
                            );
                          }),
                        ),
                      ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                showSearchResults
                    ? _buildSearchResultTiles()
                    : [
                        _appearanceSection(),
                        _startupSection(),
                        _notificationsSection(),
                        _dataSection(),
                      ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A searchable settings entry: title, owning section index, extra keywords.
class _SearchEntry {
  final String title;
  final int sectionIndex;
  final String keywords;
  const _SearchEntry(this.title, this.sectionIndex, [this.keywords = '']);
}

class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;
  const _TabsHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate old) =>
      old.height != height || old.child != child;
}
