import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/countdown_timer.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../utils/date_time_format.dart';
import 'subpage_app_bar.dart';

/// How the timer list is ordered. [manual] is the user's drag order; the rest
/// are sorted views that can each run ascending or descending.
enum _SortField { manual, name, added, edited, deadline }

class CountdownTimerPage extends StatefulWidget {
  const CountdownTimerPage({Key? key}) : super(key: key);

  @override
  State<CountdownTimerPage> createState() => _CountdownTimerPageState();
}

class _CountdownTimerPageState extends State<CountdownTimerPage> {
  final StorageService _storage = StorageService();

  List<CountdownTimerItem> _timers = [];
  final Set<String> _expanded = {};

  /// Timer uids that should not fire a zero-notification: either they have
  /// already fired this session, or they were already past when the bell was
  /// switched on. Not persisted.
  final Set<String> _notifySuppressed = {};

  Timer? _ticker;
  bool _loading = true;

  /// Bumped each time the inline draft is saved, so the composer's key changes
  /// and it rebuilds fresh (next name + a new one-week-out date).
  int _draftSeq = 0;

  /// uid of the timer currently being edited inline, or null when none.
  String? _editingUid;

  /// Active sort. [_SortField.manual] shows the user's drag order and enables
  /// long-press reordering; the other fields show a sorted view (no dragging).
  _SortField _sortField = _SortField.manual;
  bool _sortAscending = true;

  /// Drives the timer list scroll; used to minimize the composer once scrolled.
  final ScrollController _listController = ScrollController();
  bool _composerMinimized = false;

  @override
  void initState() {
    super.initState();
    _load();
    _listController.addListener(_handleListScroll);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkZeroNotifications();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _listController.removeListener(_handleListScroll);
    _listController.dispose();
    super.dispose();
  }

  void _handleListScroll() {
    final minimized = _listController.hasClients && _listController.offset > 16;
    if (minimized != _composerMinimized) {
      setState(() => _composerMinimized = minimized);
    }
  }

  Future<void> _load() async {
    final loaded = await _storage.loadCountdownTimers();
    final List<CountdownTimerItem> timers;
    // Seed example timers in dev builds when there's nothing to show. We treat
    // an empty list the same as a missing file so the demo timers also appear
    // on platforms where persistence is unavailable (e.g. Flutter web/Chrome,
    // where loading falls back to an empty list).
    if (Config.isDev && (loaded == null || loaded.isEmpty)) {
      timers = _devSeedTimers();
      await _storage.saveCountdownTimers(timers);
    } else {
      timers = loaded ?? <CountdownTimerItem>[];
    }
    // Past timers that have the bell on should not retroactively fire.
    final now = DateTime.now();
    for (final t in timers) {
      if (t.notifyOnZero && !t.target.isAfter(now)) {
        _notifySuppressed.add(t.uid);
      }
    }
    if (!mounted) return;
    setState(() {
      _timers = timers;
      _loading = false;
    });
  }

  List<CountdownTimerItem> _devSeedTimers() {
    final now = DateTime.now();
    return [
      CountdownTimerItem(
        label: 'New Year',
        target: DateTime(now.year + 1, 1, 1, 0, 0),
      ),
      CountdownTimerItem(
        label: 'Project deadline',
        target: now.add(const Duration(days: 30, hours: 6)),
        notifyOnZero: true,
      ),
      CountdownTimerItem(
        label: 'Coffee break',
        target: now.add(const Duration(minutes: 15)),
      ),
    ];
  }

  Future<void> _save() => _storage.saveCountdownTimers(_timers);

  void _checkZeroNotifications() {
    final now = DateTime.now();
    for (final t in _timers) {
      if (!t.notifyOnZero) continue;
      if (_notifySuppressed.contains(t.uid)) continue;
      if (!t.target.isAfter(now)) {
        _notifySuppressed.add(t.uid);
        final name = t.label.trim().isEmpty ? 'Countdown' : t.label.trim();
        NotificationService.showTaskNotification(
          '$name reached zero',
          delaySeconds: 0,
        );
      }
    }
  }

  /// Switches the given timer's row into the inline editor (same UI as adding).
  void _editTimer(CountdownTimerItem timer) {
    setState(() => _editingUid = timer.uid);
  }

  Future<void> _applyEdit(
    CountdownTimerItem timer,
    String label,
    DateTime target,
  ) async {
    final trimmed = label.trim();
    setState(() {
      if (trimmed.isNotEmpty) timer.label = trimmed;
      timer.target = target;
      timer.editedAt = DateTime.now();
      // Re-evaluate suppression against the new target.
      _notifySuppressed.remove(timer.uid);
      if (timer.notifyOnZero && !timer.target.isAfter(DateTime.now())) {
        _notifySuppressed.add(timer.uid);
      }
      _editingUid = null;
    });
    await _save();
  }

  void _toggleNotify(CountdownTimerItem timer) {
    setState(() {
      timer.notifyOnZero = !timer.notifyOnZero;
      if (timer.notifyOnZero) {
        // Don't retroactively notify for an already-elapsed timer.
        if (!timer.target.isAfter(DateTime.now())) {
          _notifySuppressed.add(timer.uid);
        } else {
          _notifySuppressed.remove(timer.uid);
        }
      } else {
        _notifySuppressed.remove(timer.uid);
      }
    });
    _save();
  }

  void _deleteTimer(CountdownTimerItem timer) {
    final index = _timers.indexOf(timer);
    if (index < 0) return;
    final removed = _timers[index];
    setState(() {
      _timers.removeAt(index);
      _expanded.remove(removed.uid);
    });
    _save();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${removed.label.trim().isEmpty ? 'Timer' : removed.label} deleted',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                final insertAt = index <= _timers.length ? index : _timers.length;
                _timers.insert(insertAt, removed);
              });
              _save();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Countdown'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final timers = _displayTimers();
    final canReorder = _sortField == _SortField.manual;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _DraftTimerComposer(
            key: ValueKey('draft-$_draftSeq'),
            initialName: _nextTimerName(),
            initialTarget: DateTime.now().add(const Duration(days: 7)),
            compact: _composerMinimized,
            onSave: _saveDraft,
          ),
        ),
        _buildSortControls(context),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: _listController,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            buildDefaultDragHandles: canReorder,
            itemCount: timers.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final timer = timers[index];
              return _buildTimerRow(context, timer, index);
            },
          ),
        ),
      ],
    );
  }

  /// One row in the reorderable list: the inline editor when this timer is
  /// being edited, otherwise a swipe-to-delete card. Keyed by uid so the
  /// reorderable list can track it.
  Widget _buildTimerRow(
    BuildContext context,
    CountdownTimerItem timer,
    int index,
  ) {
    if (timer.uid == _editingUid) {
      return _DraftTimerComposer(
        key: ValueKey(timer.uid),
        initialName: timer.label,
        initialTarget: timer.target,
        headerLabel: 'Edit timer',
        buttonLabel: 'Save',
        onCancel: () => setState(() => _editingUid = null),
        onSave: (label, target) => _applyEdit(timer, label, target),
      );
    }

    return Dismissible(
      key: ValueKey(timer.uid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteTimer(timer),
      child: _buildTimerCard(context, timer),
    );
  }

  /// The timers in their current display order: the manual (drag) order, or a
  /// sorted copy when a sort field is active.
  List<CountdownTimerItem> _displayTimers() {
    if (_sortField == _SortField.manual) return _timers;
    final sorted = [..._timers];
    int compare(CountdownTimerItem a, CountdownTimerItem b) {
      switch (_sortField) {
        case _SortField.name:
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        case _SortField.added:
          return a.createdAt.compareTo(b.createdAt);
        case _SortField.edited:
          return a.editedAt.compareTo(b.editedAt);
        case _SortField.deadline:
          return a.target.compareTo(b.target);
        case _SortField.manual:
          return 0;
      }
    }

    sorted.sort(compare);
    if (!_sortAscending) {
      return sorted.reversed.toList();
    }
    return sorted;
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (_sortField != _SortField.manual) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _timers.removeAt(oldIndex);
      _timers.insert(newIndex, item);
    });
    _save();
  }

  Widget _buildSortControls(BuildContext context) {
    Widget chip(_SortField field, String label) {
      final active = _sortField == field;
      final showArrow = active && field != _SortField.manual;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (showArrow)
                Icon(
                  _sortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 16,
                ),
            ],
          ),
          selected: active,
          onSelected: (_) {
            setState(() {
              if (field == _SortField.manual) {
                _sortField = _SortField.manual;
              } else if (_sortField == field) {
                _sortAscending = !_sortAscending;
              } else {
                _sortField = field;
                _sortAscending = true;
              }
            });
          },
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip(_SortField.name, 'Name'),
          chip(_SortField.added, 'Added'),
          chip(_SortField.edited, 'Edited'),
          chip(_SortField.deadline, 'Deadline'),
          chip(_SortField.manual, 'Manual'),
        ],
      ),
    );
  }

  /// The next auto-generated draft name: "Timer N", where N is one past the
  /// highest existing "Timer <number>" label (so it never collides).
  String _nextTimerName() {
    final re = RegExp(r'^Timer (\d+)$');
    var maxN = 0;
    for (final t in _timers) {
      final match = re.firstMatch(t.label.trim());
      if (match != null) {
        final n = int.tryParse(match.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return 'Timer ${maxN + 1}';
  }

  /// Commits the inline draft as a new timer and resets the composer (its key
  /// is bumped via [_draftSeq], so it rebuilds with a fresh name and date).
  Future<void> _saveDraft(String label, DateTime target) async {
    final trimmed = label.trim();
    final item = CountdownTimerItem(
      label: trimmed.isEmpty ? _nextTimerName() : trimmed,
      target: target,
    );
    setState(() {
      _timers.add(item);
      _draftSeq++;
    });
    await _save();
  }

  Widget _buildTimerCard(BuildContext context, CountdownTimerItem timer) {
    final now = DateTime.now();
    final isPast = !timer.target.isAfter(now);
    final isExpanded = _expanded.contains(timer.uid);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expanded.remove(timer.uid);
                } else {
                  _expanded.add(timer.uid);
                }
              });
            },
            title: Text(
              timer.label.trim().isEmpty ? 'Untitled timer' : timer.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(_formatTarget(timer.target)),
                const SizedBox(height: 2),
                Text(
                  _relativeSummary(now, timer.target),
                  style: TextStyle(
                    color: isPast
                        ? Colors.orange.shade800
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
                  onPressed: () => _editTimer(timer),
                ),
                IconButton(
                  icon: Icon(
                    timer.notifyOnZero
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: timer.notifyOnZero
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: timer.notifyOnZero
                      ? 'Notify at zero: on'
                      : 'Notify at zero: off',
                  onPressed: () => _toggleNotify(timer),
                ),
              ],
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildExpandedDetail(context, now, timer.target, isPast),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedDetail(
    BuildContext context,
    DateTime now,
    DateTime target,
    bool isPast,
  ) {
    final from = isPast ? target : now;
    final to = isPast ? now : target;
    final d = _Decimals(to.difference(from));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          isPast ? 'Time since the event' : 'Time until the event',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _detailRow('Years', d.years.toStringAsFixed(3)),
        _detailRow('Months', d.months.toStringAsFixed(3)),
        _detailRow('Weeks', d.weeks.toStringAsFixed(3)),
        _detailRow('Days', d.days.toStringAsFixed(3)),
        _detailRow('Hours', d.hours.toStringAsFixed(3)),
        _detailRow('Minutes', d.minutes.toStringAsFixed(3)),
        _detailRow('Seconds', '${d.seconds}'),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Compact whole-unit breakdown shown on the collapsed card, with a
  /// direction prefix/suffix. Counts up once the target has passed.
  String _relativeSummary(DateTime now, DateTime target) {
    final isPast = !target.isAfter(now);
    final from = isPast ? target : now;
    final to = isPast ? now : target;

    final b = _breakdown(from, to);
    final parts = <String>[];
    if (b.months > 0) parts.add('${b.months}mo');
    if (b.weeks > 0) parts.add('${b.weeks}w');
    if (b.days > 0) parts.add('${b.days}d');
    if (b.hours > 0) parts.add('${b.hours}h');
    if (b.minutes > 0) parts.add('${b.minutes}m');
    parts.add('${b.seconds}s');

    final body = parts.join(' ');
    return isPast ? '$body ago (counting up)' : 'in $body';
  }

  /// Whole-unit breakdown using calendar months for the collapsed summary.
  _Breakdown _breakdown(DateTime from, DateTime to) {
    var months = 0;
    var cursor = from;
    while (true) {
      final next = _addMonth(cursor);
      if (next.isAfter(to)) break;
      cursor = next;
      months++;
    }
    var remainder = to.difference(cursor);

    final weeks = remainder.inDays ~/ 7;
    remainder -= Duration(days: weeks * 7);
    final days = remainder.inDays;
    remainder -= Duration(days: days);
    final hours = remainder.inHours;
    remainder -= Duration(hours: hours);
    final minutes = remainder.inMinutes;
    remainder -= Duration(minutes: minutes);
    final seconds = remainder.inSeconds;

    return _Breakdown(
      months: months,
      weeks: weeks,
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

  DateTime _addMonth(DateTime d) {
    var year = d.year;
    var month = d.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute, d.second);
  }

  String _formatTarget(DateTime d) => formatTimerDateTime(d);
}

/// The same duration expressed in several units, all as decimals except
/// seconds. e.g. 1.1 years == 13.2 months == ~57 weeks.
class _Decimals {
  final double years;
  final double months;
  final double weeks;
  final double days;
  final double hours;
  final double minutes;
  final int seconds;

  factory _Decimals(Duration duration) {
    final us = duration.inMicroseconds.abs().toDouble();
    final totalSeconds = us / 1000000.0;
    final totalMinutes = totalSeconds / 60.0;
    final totalHours = totalMinutes / 60.0;
    final totalDays = totalHours / 24.0;
    return _Decimals._(
      years: totalDays / 365.25,
      months: totalDays / 30.4375,
      weeks: totalDays / 7.0,
      days: totalDays,
      hours: totalHours,
      minutes: totalMinutes,
      seconds: totalSeconds.floor(),
    );
  }

  const _Decimals._({
    required this.years,
    required this.months,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });
}

class _Breakdown {
  final int months;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  const _Breakdown({
    required this.months,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });
}

/// Inline row for creating or editing a timer: a name plus separate date and
/// time selectors. Used both for the always-present "add" draft at the top of
/// the list and, with [onCancel], for editing an existing timer in place.
class _DraftTimerComposer extends StatefulWidget {
  final String initialName;
  final DateTime initialTarget;
  final void Function(String label, DateTime target) onSave;
  final String headerLabel;
  final String buttonLabel;
  final VoidCallback? onCancel;

  /// When true, the date/time selectors are collapsed and the action button
  /// moves up beside the name — a slimmer footprint while scrolling the list.
  final bool compact;

  const _DraftTimerComposer({
    Key? key,
    required this.initialName,
    required this.initialTarget,
    required this.onSave,
    this.headerLabel = 'New timer',
    this.buttonLabel = 'Add',
    this.onCancel,
    this.compact = false,
  }) : super(key: key);

  @override
  State<_DraftTimerComposer> createState() => _DraftTimerComposerState();
}

class _DraftTimerComposerState extends State<_DraftTimerComposer> {
  late final TextEditingController _nameController;
  late DateTime _target;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _target = widget.initialTarget;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await pickDateInstantly(context, _target);
    if (date == null || !mounted) return;
    setState(() {
      _target = DateTime(
        date.year,
        date.month,
        date.day,
        _target.hour,
        _target.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final time = await pickTimeOfDay(context, TimeOfDay.fromDateTime(_target));
    if (time == null || !mounted) return;
    setState(() {
      _target = DateTime(
        _target.year,
        _target.month,
        _target.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _save() => widget.onSave(_nameController.text, _target);

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        curve: Curves.easeInOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.headerLabel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (widget.onCancel != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onCancel,
                    ),
                  if (compact) ...[
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _save,
                      child: Text(widget.buttonLabel),
                    ),
                  ],
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event),
                        label: Text(formatTimerDate(_target)),
                        onPressed: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(formatTimerTime(_target)),
                        onPressed: _pickTime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _save,
                      child: Text(widget.buttonLabel),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
