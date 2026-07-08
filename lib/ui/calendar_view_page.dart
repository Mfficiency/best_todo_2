import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../models/task.dart';

/// Identifies the schedule section currently "active" (scrolled to the top
/// of the schedule view). The home page uses [date] as the due date for
/// tasks added while this section is highlighted and [label] to hint the
/// target day in the add-task field.
class ScheduleSectionInfo {
  /// Stable key for the section ('yyyy-mm-dd' for day sections,
  /// 'range-next-week' / 'range-next-month' / 'someday' otherwise).
  final String key;

  /// Short human-readable name ("Today", "Fri, Aug 1", "Someday", ...).
  final String label;

  /// Due date a task added while this section is active should get.
  final DateTime date;

  const ScheduleSectionInfo({
    required this.key,
    required this.label,
    required this.date,
  });
}

class _SectionAnchor {
  final ScheduleSectionInfo info;
  final GlobalKey key;

  const _SectionAnchor({required this.info, required this.key});
}

/// Schedule-style body for the home page. Renders one long scrollable list
/// where tasks are grouped under per-day headers. The tab bar above
/// continues to drive [tabAnchorKeys] so tapping a tab scrolls this list
/// to the corresponding day section.
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

  /// Fired whenever scrolling moves a different section header to the top
  /// of the viewport. The home page stores this and routes new tasks to it.
  final ValueChanged<ScheduleSectionInfo>? onActiveSectionChanged;

  /// Key of the section the home page currently treats as the add-task
  /// target; the matching header is rendered highlighted.
  final String? highlightedSectionKey;

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
    this.onActiveSectionChanged,
    this.highlightedSectionKey,
  }) : super(key: key);

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  /// Header keys for day sections that are not one of the six tab anchors.
  /// Kept across builds so scroll tracking survives rebuilds.
  final Map<String, GlobalKey> _extraSectionKeys = {};

  /// Section anchors in rendered order, rebuilt on every build.
  List<_SectionAnchor> _anchors = const [];

  ScheduleSectionInfo? _lastNotified;
  bool _showBackToTop = false;

  /// Header tops within this many pixels below the viewport top still count
  /// as the active section.
  static const double _activationSlopPx = 16;

  /// Scroll offset past which the back-to-top arrow appears.
  static const double _backToTopThresholdPx = 300;

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

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_handleScroll);
      widget.scrollController.addListener(_handleScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_handleScroll);
    super.dispose();
  }

  /// Determines which section header currently sits at (or just above) the
  /// top of the scroll viewport, toggles the back-to-top arrow, and notifies
  /// the home page when the active section changes.
  void _handleScroll() {
    if (!mounted) return;
    // Scroll corrections can notify listeners mid-layout, where setState
    // (here and in the home page) is illegal — re-run after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
      return;
    }
    final controller = widget.scrollController;
    if (!controller.hasClients) return;
    final pixels = controller.position.pixels;

    final showBackToTop = pixels > _backToTopThresholdPx;
    if (showBackToTop != _showBackToTop) {
      setState(() => _showBackToTop = showBackToTop);
    }

    if (_anchors.isEmpty) return;

    // At the very bottom the last sections' headers may never reach the
    // viewport top (the tail is shorter than the viewport), so treat the
    // final section as active there — otherwise "Someday" could be
    // impossible to target.
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent > 0 && pixels >= maxExtent - 8) {
      _notifyActive(_anchors.last);
      return;
    }

    // Among headers that are currently built, pick the lowest one whose top
    // is at or above the viewport top. Headers scrolled far off-screen get
    // unmounted, so also track the first built header below the top: the
    // section owning the viewport is then the anchor just before it in
    // rendered order (whose info stays valid even when its header widget is
    // unmounted).
    _SectionAnchor? active;
    var activeOffset = double.negativeInfinity;
    var firstBelowIndex = -1;
    var firstBelowOffset = double.infinity;
    for (var i = 0; i < _anchors.length; i++) {
      final ctx = _anchors[i].key.currentContext;
      if (ctx == null) continue;
      final renderObject = ctx.findRenderObject();
      if (renderObject == null || !renderObject.attached) continue;
      final viewport = RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null) continue;
      final reveal = viewport.getOffsetToReveal(renderObject, 0.0).offset;
      if (reveal <= pixels + _activationSlopPx) {
        if (reveal > activeOffset) {
          activeOffset = reveal;
          active = _anchors[i];
        }
      } else if (reveal < firstBelowOffset) {
        firstBelowOffset = reveal;
        firstBelowIndex = i;
      }
    }
    if (active == null && firstBelowIndex >= 0) {
      active = _anchors[firstBelowIndex > 0 ? firstBelowIndex - 1 : 0];
    }
    if (active == null) return;
    _notifyActive(active);
  }

  void _notifyActive(_SectionAnchor active) {
    // Compare date as well as key: range sections keep their key when the
    // current date changes but their target date moves with it.
    if (active.info.key != _lastNotified?.key ||
        active.info.date != _lastNotified?.date) {
      _lastNotified = active.info;
      widget.onActiveSectionChanged?.call(active.info);
    }
  }

  void _scrollToTop() {
    if (!widget.scrollController.hasClients) return;
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

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

  /// Short name used in the add-task hint ("Today", "Fri, Aug 1", ...).
  String _shortLabel(DateTime date, DateTime today) {
    final d = _dateOnly(date);
    final t = _dateOnly(today);
    final diff = d.difference(t).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == 2) return 'Day after tomorrow';
    final base =
        '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';
    if (d.year != t.year) return '$base, ${d.year}';
    return base;
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

    final children = <Widget>[];
    final anchors = <_SectionAnchor>[];

    GlobalKey headerKeyFor(String sectionKey, GlobalKey? preferred) {
      if (preferred != null) return preferred;
      return _extraSectionKeys.putIfAbsent(sectionKey, () => GlobalKey());
    }

    void addDaySection(String key) {
      final date = keyToDate[key]!;
      final dayTasks = grouped[key]!;
      final headerKey = headerKeyFor(key, anchorKeyForKey[key]);
      anchors.add(
        _SectionAnchor(
          info: ScheduleSectionInfo(
            key: key,
            label: _shortLabel(date, today),
            date: date,
          ),
          key: headerKey,
        ),
      );
      children.add(
        _DayHeader(
          key: headerKey,
          text: _formatHeader(date, today),
          isToday: _isSameDay(date, today),
          highlighted: widget.highlightedSectionKey == key,
        ),
      );
      if (dayTasks.isEmpty) {
        children.add(const _EmptyDayPlaceholder());
      } else {
        children.add(_buildReorderableSection(dayTasks));
      }
    }

    void addRangeSection({
      required String sectionKey,
      required String label,
      required DateTime date,
      required GlobalKey? tabAnchorKey,
    }) {
      final headerKey = headerKeyFor(sectionKey, tabAnchorKey);
      anchors.add(
        _SectionAnchor(
          info: ScheduleSectionInfo(key: sectionKey, label: label, date: date),
          key: headerKey,
        ),
      );
      children.add(
        _RangeHeader(
          key: headerKey,
          text: label,
          highlighted: widget.highlightedSectionKey == sectionKey,
        ),
      );
    }

    // Today / Tomorrow / Day after — render the first three keys directly.
    final immediateKeys = <String>[todayKey, tomorrowKey, dayAfterKey];
    for (final k in immediateKeys) {
      addDaySection(k);
    }

    // Next week range — always render the range header as an anchor for
    // tab 3, followed by any day sections in the +3..+29 window. Tasks added
    // while the bare range header is active get the same due date as the
    // next-week tab in list mode.
    addRangeSection(
      sectionKey: 'range-next-week',
      label: 'Next week',
      date: widget.currentDate.add(const Duration(days: 7)),
      tabAnchorKey: widget.tabAnchorKeys[3],
    );
    if (nextWeekKeys.isEmpty) {
      children.add(const _EmptyDayPlaceholder());
    } else {
      for (final k in nextWeekKeys) {
        addDaySection(k);
      }
    }

    // Next month range — always render the range header as an anchor for
    // tab 4, followed by any day sections >= 30 days out.
    addRangeSection(
      sectionKey: 'range-next-month',
      label: 'Next month',
      date: widget.currentDate.add(const Duration(days: 30)),
      tabAnchorKey: widget.tabAnchorKeys[4],
    );
    if (nextMonthKeys.isEmpty) {
      children.add(const _EmptyDayPlaceholder());
    } else {
      for (final k in nextMonthKeys) {
        addDaySection(k);
      }
    }

    // Someday — always rendered so tab 5 has a reliable anchor.
    const somedayKey = 'someday';
    final somedayHeaderKey =
        headerKeyFor(somedayKey, widget.tabAnchorKeys[5]);
    anchors.add(
      _SectionAnchor(
        info: ScheduleSectionInfo(
          key: somedayKey,
          label: 'Someday',
          date: ScheduleView.futureBucketDate,
        ),
        key: somedayHeaderKey,
      ),
    );
    children.add(
      _DayHeader(
        key: somedayHeaderKey,
        text: 'Someday',
        isToday: false,
        highlighted: widget.highlightedSectionKey == somedayKey,
      ),
    );
    if (someday.isEmpty) {
      children.add(const _EmptyDayPlaceholder());
    } else {
      children.add(_buildReorderableSection(someday));
    }

    _anchors = anchors;
    // Re-evaluate the active section once this frame is laid out, so the
    // highlight is correct right after entering the view or after tasks
    // shift the section layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleScroll();
    });

    return Column(
      children: [
        widget.addTaskRow,
        Expanded(
          child: Stack(
            children: [
              ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.only(bottom: 32),
                children: children,
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: IgnorePointer(
                  ignoring: !_showBackToTop,
                  child: AnimatedOpacity(
                    opacity: _showBackToTop ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: FloatingActionButton.small(
                      heroTag: 'scheduleBackToTop',
                      tooltip: 'Back to top',
                      onPressed: _scrollToTop,
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String text;
  final bool isToday;
  final bool highlighted;

  const _DayHeader({
    Key? key,
    required this.text,
    required this.isToday,
    this.highlighted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withOpacity(0.16)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        border: highlighted
            ? Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(highlighted ? 13 : 16, 10, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: (isToday || highlighted) ? theme.colorScheme.primary : null,
        ),
      ),
    );
  }
}

class _RangeHeader extends StatelessWidget {
  final String text;
  final bool highlighted;

  const _RangeHeader({
    Key? key,
    required this.text,
    this.highlighted = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary
            .withOpacity(highlighted ? 0.18 : 0.08),
        border: highlighted
            ? Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(highlighted ? 13 : 16, 14, 16, 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
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
