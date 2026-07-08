import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task.dart';

/// Schedule-style body for the home page. Renders one long scrollable list
/// where tasks are grouped under per-day headers. The tab bar above
/// continues to drive [tabAnchorKeys] so tapping a tab scrolls this list
/// to the corresponding day section.
///
/// The day section currently scrolled to the top of the list is the
/// "active" day: its header is highlighted and [onActiveDateChanged]
/// reports its date so the add-task row can target it. A back-to-top
/// arrow appears once the list is scrolled down.
///
/// Tile construction is delegated back to the home page via [buildTile]
/// so swipe / move / delete / toggle behavior stays identical to the
/// list-mode tabs.
class ScheduleView extends StatefulWidget {
  final List<Task> tasks;
  final DateTime currentDate;
  final ScrollController scrollController;

  /// GlobalKeys for the section headers that each tab should scroll to.
  /// Keys: 0 = today, 1 = tomorrow, 2 = day after tomorrow,
  /// 3 = first next-week day section, 4 = first next-month day section,
  /// 5 = "Someday" section. The home page reuses these to scroll.
  final Map<int, GlobalKey> tabAnchorKeys;

  /// Builds the row for a single task. The home page passes a fully wired
  /// TaskTile here so all interactions match list mode.
  final Widget Function(Task task) buildTile;

  /// Add-task input row (same widget the list mode shows above each tab).
  final Widget addTaskRow;

  /// Called when the user reorders tasks within a day section by long
  /// press / drag. [sectionTasks] is the rendered order before the move.
  final void Function(List<Task> sectionTasks, int oldIndex, int newIndex)
      onReorderSection;

  /// Reports the date of the day section currently scrolled to the top of
  /// the list. Empty range sections report their bucket's first day
  /// (today +7 / +30) and the Someday section reports [futureBucketDate].
  final ValueChanged<DateTime>? onActiveDateChanged;

  /// Sentinel due date used for the "future / no specific date" bucket.
  static final DateTime futureBucketDate = DateTime(2300, 1, 1);

  const ScheduleView({
    Key? key,
    required this.tasks,
    required this.currentDate,
    required this.scrollController,
    required this.tabAnchorKeys,
    required this.buildTile,
    required this.addTaskRow,
    required this.onReorderSection,
    this.onActiveDateChanged,
  }) : super(key: key);

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

/// Identity + target date of one top-level section of the schedule list.
class _SectionSpec {
  final String id;
  final DateTime date;
  const _SectionSpec(this.id, this.date);
}

class _ScheduleViewState extends State<ScheduleView> {
  /// A section whose top edge sits at or above this offset (relative to the
  /// list's top edge) can be the active one; the bottom-most such section
  /// wins, i.e. the section currently spanning the top of the viewport.
  static const double _activationOffset = 12.0;

  /// Scroll offset after which the back-to-top arrow is shown.
  static const double _backToTopThreshold = 300.0;

  final Map<String, GlobalKey> _sectionKeys = {};
  final GlobalKey _listKey = GlobalKey();
  List<_SectionSpec> _sections = const [];
  String? _activeSectionId;
  bool _showBackToTop = false;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isSameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);
  String _dayKey(DateTime d) {
    final dd = _dateOnly(d);
    final m = dd.month.toString().padLeft(2, '0');
    final day = dd.day.toString().padLeft(2, '0');
    return '${dd.year}-$m-$day';
  }

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Widget _buildReorderableSection(List<Task> sectionTasks) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: true,
      onReorder: (oldIndex, newIndex) =>
          widget.onReorderSection(sectionTasks, oldIndex, newIndex),
      children: [for (final t in sectionTasks) widget.buildTile(t)],
    );
  }

  String _formatHeader(DateTime date, DateTime today) {
    final d = _dateOnly(date);
    final t = _dateOnly(today);
    final diff = d.difference(t).inDays;
    final base =
        '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';
    if (diff == 0) return 'Today  ·  $base';
    if (diff == 1) return 'Tomorrow  ·  $base';
    if (diff == 2) return 'Day after tomorrow  ·  $base';
    if (d.year != t.year) return '$base, ${d.year}';
    return base;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final showArrow = notification.metrics.pixels > _backToTopThreshold;
    if (showArrow != _showBackToTop) {
      setState(() => _showBackToTop = showArrow);
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _updateActiveSection();
    }
    return false;
  }

  /// Recomputes which section spans the top of the list and, when it
  /// changed, highlights it and reports its date to the home page.
  void _updateActiveSection() {
    if (!mounted) return;
    final listBox = _listKey.currentContext?.findRenderObject();
    if (listBox is! RenderBox || !listBox.attached || !listBox.hasSize) return;
    final listTop = listBox.localToGlobal(Offset.zero).dy;

    _SectionSpec? best;
    var bestTop = double.negativeInfinity;
    for (final section in _sections) {
      // Sections scrolled far out of view are unmounted; the section
      // spanning the top of the viewport is always attached.
      final box = _sectionKeys[section.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy - listTop;
      if (top <= _activationOffset && top > bestTop) {
        bestTop = top;
        best = section;
      }
    }
    // Overscroll at the very top: no section top is past the line yet.
    best ??= _sections.isEmpty ? null : _sections.first;
    if (best == null || best.id == _activeSectionId) return;
    final active = best;
    setState(() => _activeSectionId = active.id);
    widget.onActiveDateChanged?.call(active.date);
  }

  void _scrollToTop() {
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(widget.currentDate);

    // Split tasks into dated vs future-bucket / undated.
    final dated = <Task>[];
    final someday = <Task>[];
    for (final t in widget.tasks) {
      final due = t.dueDate;
      if (due == null || _isSameDay(due, ScheduleView.futureBucketDate)) {
        someday.add(t);
      } else {
        dated.add(t);
      }
    }

    // Group dated tasks by day. Overdue items roll up under today, matching
    // how the Today tab surfaces them.
    final grouped = <String, List<Task>>{};
    final keyToDate = <String, DateTime>{};
    for (final task in dated) {
      final due = _dateOnly(task.dueDate!);
      final groupDate = due.isBefore(today) ? today : due;
      final key = _dayKey(groupDate);
      grouped.putIfAbsent(key, () {
        keyToDate[key] = groupDate;
        return [];
      }).add(task);
    }

    // Ensure today / tomorrow / day-after sections always exist as scroll
    // anchors, even when empty.
    for (final offset in const [0, 1, 2]) {
      final d = today.add(Duration(days: offset));
      final key = _dayKey(d);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        keyToDate[key] = d;
      }
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => keyToDate[a]!.compareTo(keyToDate[b]!));

    // Stable per-day sort within each section.
    for (final list in grouped.values) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final ar = a.listRanking ?? 1 << 30;
        final br = b.listRanking ?? 1 << 30;
        return ar.compareTo(br);
      });
    }

    // Direct day-section anchors for today / tomorrow / day-after (always
    // present because of the materialization above).
    final anchorKeyForKey = <String, GlobalKey>{};
    final todayKey = _dayKey(today);
    final tomorrowKey = _dayKey(today.add(const Duration(days: 1)));
    final dayAfterKey = _dayKey(today.add(const Duration(days: 2)));
    if (widget.tabAnchorKeys[0] != null) {
      anchorKeyForKey[todayKey] = widget.tabAnchorKeys[0]!;
    }
    if (widget.tabAnchorKeys[1] != null) {
      anchorKeyForKey[tomorrowKey] = widget.tabAnchorKeys[1]!;
    }
    if (widget.tabAnchorKeys[2] != null) {
      anchorKeyForKey[dayAfterKey] = widget.tabAnchorKeys[2]!;
    }

    // Partition the remaining sortedKeys into next-week / next-month ranges
    // so we can wrap them in always-on range headers (which tabs 3 and 4
    // anchor to, just like tab 5 anchors to Someday).
    final nextWeekKeys = <String>[];
    final nextMonthKeys = <String>[];
    for (final k in sortedKeys) {
      final diff = keyToDate[k]!.difference(today).inDays;
      if (diff >= 3 && diff < 30) nextWeekKeys.add(k);
      if (diff >= 30) nextMonthKeys.add(k);
    }

    // Each top-level list child is one section (header + rows) so the
    // active-day tracking can measure it as a unit.
    final specs = <_SectionSpec>[];
    final children = <Widget>[];

    void addSection(_SectionSpec spec, List<Widget> widgets) {
      specs.add(spec);
      children.add(Column(
        key: _sectionKeys.putIfAbsent(spec.id, () => GlobalKey()),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      ));
    }

    void addDaySection(String key, {Widget? leading}) {
      final date = keyToDate[key]!;
      final dayTasks = grouped[key]!;
      addSection(_SectionSpec(key, date), [
        if (leading != null) leading,
        _DayHeader(
          key: anchorKeyForKey[key],
          text: _formatHeader(date, today),
          isToday: _isSameDay(date, today),
          isActive: _activeSectionId == key,
        ),
        if (dayTasks.isEmpty)
          const _EmptyDayPlaceholder()
        else
          _buildReorderableSection(dayTasks),
      ]);
    }

    // Today / Tomorrow / Day after — render the first three keys directly.
    for (final k in [todayKey, tomorrowKey, dayAfterKey]) {
      addDaySection(k);
    }

    // Next week range — always render the range header as an anchor for
    // tab 3. When the range has day sections the header is grouped with the
    // first one; when empty it forms its own section targeting today +7.
    const nextWeekEmptyId = 'next-week-empty';
    final nextWeekHeader = _RangeHeader(
      key: widget.tabAnchorKeys[3],
      text: 'Next week',
      isActive: _activeSectionId == nextWeekEmptyId,
    );
    if (nextWeekKeys.isEmpty) {
      addSection(
        _SectionSpec(nextWeekEmptyId, today.add(const Duration(days: 7))),
        [nextWeekHeader, const _EmptyDayPlaceholder()],
      );
    } else {
      addDaySection(nextWeekKeys.first, leading: nextWeekHeader);
      for (final k in nextWeekKeys.skip(1)) {
        addDaySection(k);
      }
    }

    // Next month range — same shape, targeting today +30 when empty.
    const nextMonthEmptyId = 'next-month-empty';
    final nextMonthHeader = _RangeHeader(
      key: widget.tabAnchorKeys[4],
      text: 'Next month',
      isActive: _activeSectionId == nextMonthEmptyId,
    );
    if (nextMonthKeys.isEmpty) {
      addSection(
        _SectionSpec(nextMonthEmptyId, today.add(const Duration(days: 30))),
        [nextMonthHeader, const _EmptyDayPlaceholder()],
      );
    } else {
      addDaySection(nextMonthKeys.first, leading: nextMonthHeader);
      for (final k in nextMonthKeys.skip(1)) {
        addDaySection(k);
      }
    }

    // Someday — always rendered so tab 5 has a reliable anchor.
    const somedayId = 'someday';
    addSection(_SectionSpec(somedayId, ScheduleView.futureBucketDate), [
      _DayHeader(
        key: widget.tabAnchorKeys[5],
        text: 'Someday',
        isToday: false,
        isActive: _activeSectionId == somedayId,
      ),
      if (someday.isEmpty)
        const _EmptyDayPlaceholder()
      else
        _buildReorderableSection(someday),
    ]);

    _sections = specs;
    _sectionKeys.removeWhere((id, _) => !specs.any((s) => s.id == id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveSection());

    return Column(
      children: [
        widget.addTaskRow,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Generous bottom padding so even the last section can be
              // scrolled up to the activation line and become the active day.
              final bottomPadding = math.max(32.0, constraints.maxHeight - 56);
              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView(
                      key: _listKey,
                      controller: widget.scrollController,
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      children: children,
                    ),
                  ),
                  if (_showBackToTop)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        heroTag: null,
                        tooltip: 'Back to top',
                        onPressed: _scrollToTop,
                        child: const Icon(Icons.arrow_upward),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String text;
  final bool isToday;
  final bool isActive;

  const _DayHeader({
    Key? key,
    required this.text,
    required this.isToday,
    this.isActive = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: isActive ? const ValueKey('active-day-header') : null,
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          left: BorderSide(
            width: 3,
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(13, 10, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isActive
              ? theme.colorScheme.onPrimaryContainer
              : (isToday ? theme.colorScheme.primary : null),
        ),
      ),
    );
  }
}

class _RangeHeader extends StatelessWidget {
  final String text;
  final bool isActive;

  const _RangeHeader({Key? key, required this.text, this.isActive = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: isActive ? const ValueKey('active-day-header') : null,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.primary.withValues(alpha: 0.08),
        border: Border(
          left: BorderSide(
            width: 3,
            color: isActive ? theme.colorScheme.primary : Colors.transparent,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(13, 14, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isActive
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _EmptyDayPlaceholder extends StatelessWidget {
  const _EmptyDayPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
      child: Text(
        'No tasks',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).disabledColor,
              fontStyle: FontStyle.italic,
            ),
      ),
    );
  }
}
