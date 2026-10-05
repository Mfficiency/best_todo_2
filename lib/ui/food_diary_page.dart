import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/food_diary_widget_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../utils/date_time_format.dart';
import '../utils/description_disclosure.dart';
import '../utils/label_utils.dart';
import 'label_picker.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';

/// The day-grouping header text shared by the diary view, the nutritionist
/// view and the copy-days dialog: "Today · Mon" for [today], "$weekday,
/// $date" (honoring `Config.dateFormat`) for any other day, "No date" for
/// undated entries.
String _foodDiaryDayTitle(DateTime? day, DateTime today) {
  if (day == null) return 'No date';
  final weekday = formatWeekdayShort(day);
  if (day == today) return 'Today · $weekday';
  return '$weekday, ${formatTimerDate(day)}';
}

/// Fixed display order for stomach-issue symptom tokens, independent of the
/// order they were selected in — [_stomachSymptomsLabel] always reads them
/// off in this order.
const List<String> _stomachSymptomOrder = ['gas', 'liquid', 'discomfort'];

/// Display label for one stomach-issue symptom token, defaulting to "Gas"
/// for an unrecognized value.
String _stomachSymptomLabel(String type) {
  switch (type) {
    case 'liquid':
      return 'Liquid';
    case 'discomfort':
      return 'Discomfort';
    default:
      return 'Gas';
  }
}

/// Joins every symptom in [types] (any combination of gas/liquid/discomfort)
/// into one display label in the fixed Gas/Liquid/Discomfort order — "Gas"
/// for a single symptom, "Gas, Liquid" for more than one. Falls back to
/// "Gas" for an empty list, which shouldn't normally happen since the
/// dialog's multi-select segmented button requires at least one symptom.
String _stomachSymptomsLabel(List<String> types) {
  final present = types.toSet();
  final ordered = _stomachSymptomOrder.where(present.contains).toList();
  return ordered.isEmpty
      ? _stomachSymptomLabel('gas')
      : ordered.map(_stomachSymptomLabel).join(', ');
}

/// Display label for a stomach-issue entry's start/stop toggle: "Start" or
/// "Stop" for a set value, `null` when the entry deliberately carries
/// neither (the toggle allows clearing to no selection).
String? _stomachEventLabel(String? type) {
  if (type == 'start') return 'Start';
  if (type == 'stop') return 'Stop';
  return null;
}

/// The headline shown for [entry] everywhere it's displayed (the diary
/// tile, the nutritionist view, both exports) — a food entry's own title, or
/// a stomach entry's symptom(s), plus " · Start"/" · Stop" when that's set,
/// since a stomach entry carries no free-form title of its own.
String foodDiaryEntryTitle(Task entry) {
  if (!entry.isStomachIssue) return entry.title;
  final symptoms = _stomachSymptomsLabel(entry.stomachSymptomTypes);
  final event = _stomachEventLabel(entry.stomachEventType);
  return event == null ? symptoms : '$symptoms · $event';
}

/// Tag -> occurrence count across [entries], most frequent first and
/// alphabetical among ties, using the same splitting rule [_FoodDiaryTile]
/// uses for its chips. Shared by the export summary and the nutritionist
/// view's summary card, so both surface the same pattern.
List<MapEntry<String, int>> _sortedFoodDiaryTagCounts(List<Task> entries) {
  final counts = <String, int>{};
  for (final entry in entries) {
    for (final tag in entry.label.split(RegExp(r'[,\s]+'))) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty) continue;
      counts[trimmed] = (counts[trimmed] ?? 0) + 1;
    }
  }
  return counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
}

/// A summary block (entry/day counts, date range, tag frequency) that leads
/// both the Markdown export and the nutritionist view — the "here's the
/// pattern at a glance" a nutritionist looks for before reading the log.
List<String> _foodDiarySummaryLines(List<Task> sorted) {
  final dated = sorted.where((t) => t.dueDate != null).toList();
  final days = <DateTime>{
    for (final entry in dated)
      DateTime(entry.dueDate!.year, entry.dueDate!.month, entry.dueDate!.day),
  };
  final entryWord = sorted.length == 1 ? 'entry' : 'entries';
  var summary = '- ${sorted.length} $entryWord';
  if (days.isNotEmpty) {
    final dayWord = days.length == 1 ? 'day' : 'days';
    final oldest =
        dated.map((t) => t.dueDate!).reduce((a, b) => a.isBefore(b) ? a : b);
    final newest =
        dated.map((t) => t.dueDate!).reduce((a, b) => a.isAfter(b) ? a : b);
    summary += ' across ${days.length} $dayWord'
        ' (${formatTimerDate(oldest)} – ${formatTimerDate(newest)})';
  }
  final lines = <String>['## Summary', summary];
  final tags = _sortedFoodDiaryTagCounts(sorted);
  if (tags.isNotEmpty) {
    lines.add(
        '- Tags: ${tags.map((t) => '${t.key} (${t.value})').join(', ')}');
  }
  return lines;
}

/// Sorts entries newest day first, chronologically within a day — shared by
/// the Markdown export and the plain-text copy so both read the same way.
List<Task> _sortedForExport(List<Task> entries) {
  return List<Task>.from(entries)
    ..sort((a, b) {
      final aTime = a.dueDate;
      final bTime = b.dueDate;
      if (aTime == null && bTime == null) return a.title.compareTo(b.title);
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      final aDay = DateTime(aTime.year, aTime.month, aTime.day);
      final bDay = DateTime(bTime.year, bTime.month, bTime.day);
      final byDay = bDay.compareTo(aDay);
      return byDay != 0 ? byDay : aTime.compareTo(bTime);
    });
}

/// A scan-friendly Markdown export: a summary block first (entry/day counts,
/// date range, tag frequency — the pattern a nutritionist looks for), then
/// newest day first with meals chronological within each day, details
/// indented beneath the meal they belong to.
String foodDiaryExportText(List<Task> entries) {
  final sorted = _sortedForExport(entries);
  final lines = <String>['# Food Diary', ''];
  if (sorted.isNotEmpty) {
    lines.addAll(_foodDiarySummaryLines(sorted));
    lines.add('');
  }
  String? currentDay;
  for (final entry in sorted) {
    final time = entry.dueDate;
    final day = time == null ? 'No date' : formatTimerDate(time);
    if (day != currentDay) {
      if (currentDay != null) lines.add('');
      lines.add('## $day');
      currentDay = day;
    }
    final timeLabel = time == null ? 'Time not recorded' : formatTimerTime(time);
    lines.add('- **$timeLabel — ${foodDiaryEntryTitle(entry)}**');
    if (entry.isStomachIssue && entry.stomachIntensity != null) {
      lines.add('  - Intensity: ${entry.stomachIntensity}/10');
    }
    if (entry.label.trim().isNotEmpty) {
      lines.add('  - Tags: ${entry.label.trim()}');
    }
    if (entry.description.trim().isNotEmpty) {
      final description = entry.description.trim().replaceAll('\n', '\n    ');
      lines.add('  - Notes: $description');
    }
  }
  return '${lines.join('\n').trimRight()}\n';
}

/// A plain-text (no Markdown syntax) rendering of [entries] for copying to
/// the clipboard — a day header line, then a bullet per entry, blank lines
/// between days. Meant for pasting just a handful of days into a message
/// rather than sharing the whole exported file; same day-grouped,
/// newest-day-first ordering as [foodDiaryExportText].
String foodDiaryPlainText(List<Task> entries) {
  final sorted = _sortedForExport(entries);
  final lines = <String>[];
  String? currentDay;
  for (final entry in sorted) {
    final time = entry.dueDate;
    final day = time == null ? 'No date' : formatTimerDate(time);
    if (day != currentDay) {
      if (currentDay != null) lines.add('');
      lines.add(day);
      currentDay = day;
    }
    final timeLabel = time == null ? 'Time not recorded' : formatTimerTime(time);
    lines.add('- $timeLabel — ${foodDiaryEntryTitle(entry)}');
    if (entry.isStomachIssue && entry.stomachIntensity != null) {
      lines.add('  Intensity: ${entry.stomachIntensity}/10');
    }
    if (entry.label.trim().isNotEmpty) lines.add('  ${entry.label.trim()}');
    if (entry.description.trim().isNotEmpty) {
      lines.add('  ${entry.description.trim().replaceAll('\n', '\n  ')}');
    }
  }
  return lines.join('\n').trimRight();
}

/// Tools → Food Diary: a pre-filtered view over the one task list — like
/// opening the wishlist — showing only tasks flagged [Task.isEatingHabit].
/// Phase 1 is deliberately small: a title, an optional description, the time
/// the item was eaten, and free-form tags (e.g. "sugar", "lactose") reusing
/// the same label picker every other task uses. Entries never appear on the
/// home tabs, the schedule view, projects or Todoist — see
/// [ItemViews.foodDiary] — and swiping one away moves it to the Archived
/// Items list, exactly like deleting a wishlist item.
class FoodDiaryPage extends StatefulWidget {
  /// Opens the "add entry" dialog automatically on first build, used when
  /// arriving from the home-screen widget's "+" (`besttodofood://add`).
  final bool autoAddEntry;

  const FoodDiaryPage({Key? key, this.autoAddEntry = false}) : super(key: key);

  @override
  State<FoodDiaryPage> createState() => _FoodDiaryPageState();
}

class _FoodDiaryPageState extends State<FoodDiaryPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the eating-habit
  /// subset but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  /// Off (default) shows the day-to-day logging UI (collapsed past days,
  /// swipe-to-delete, tap-to-edit). On swaps in [_NutritionistView]: every
  /// day expanded and a tag-frequency summary up top, meant for reviewing
  /// the whole log rather than logging a meal.
  bool _nutritionistView = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    // The dev/demo starter tasks (see home_page._loadTasks) mean the overall
    // list is essentially never empty, so the seed condition has to check
    // for existing food-diary entries specifically, not list emptiness —
    // otherwise it never fires. Dev builds seed a few entries spread across
    // the day so the tool is testable in Chrome and its screenshots always
    // show a populated log.
    if (!tasks.any((t) => t.isEatingHabit) && Config.isDev) {
      tasks.addAll(_buildDevSeed());
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
    if (widget.autoAddEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _editEntry());
    }
  }

  List<Task> _buildDevSeed() {
    final now = DateTime.now();
    DateTime at(int hour, int minute) =>
        DateTime(now.year, now.month, now.day, hour, minute);
    return [
      Task(
        title: 'Oatmeal with banana',
        description: 'Dev seed: a food diary entry',
        label: addLabelToken('gluten', demoToken),
        createdAt: now,
        dueDate: at(8, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
      Task(
        title: 'Grilled chicken salad',
        description: 'Dev seed: a food diary entry',
        label: addLabelToken('dairy-free', demoToken),
        createdAt: now,
        dueDate: at(13, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
      Task(
        title: 'Greek yogurt with honey',
        description: 'Dev seed: a food diary entry',
        label: addLabelToken('sugar, lactose', demoToken),
        createdAt: now,
        dueDate: at(19, 30),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
    ];
  }

  Future<void> _save() async {
    await _repository.saveItems(_tasks);
    await FoodDiaryWidgetService.sync(_tasks);
  }

  static DateTime _yesterday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
  }

  String _timestampForFilename() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<void> _exportEntries() async {
    final entries = _entries();
    if (entries.isEmpty) return;
    final downloads = await getDownloadsDirectory();
    final directory = await getDirectoryPath(initialDirectory: downloads?.path);
    if (!mounted) return;
    if (directory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export canceled')),
      );
      return;
    }
    final separator = Platform.pathSeparator;
    final path = '$directory${directory.endsWith(separator) ? '' : separator}'
        'food_diary_${_timestampForFilename()}.md';
    try {
      await File(path).writeAsString(foodDiaryExportText(entries), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to $path')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export food diary')),
      );
    }
  }

  /// Lets the user pick a subset of days, then puts [foodDiaryPlainText] for
  /// just those days on the clipboard — for pasting a handful of meals into
  /// a message rather than sharing the whole exported file.
  Future<void> _copyDays() async {
    final entries = _entries();
    if (entries.isEmpty) return;
    final days = _days(entries);
    final selectedDays = await showDialog<Set<DateTime?>>(
      context: context,
      builder: (context) => _CopyDaysDialog(days: days),
    );
    if (selectedDays == null || selectedDays.isEmpty) return;
    final selectedEntries = entries.where((entry) {
      final time = entry.dueDate;
      final day =
          time == null ? null : DateTime(time.year, time.month, time.day);
      return selectedDays.contains(day);
    }).toList();
    if (selectedEntries.isEmpty) return;
    await Clipboard.setData(
        ClipboardData(text: foodDiaryPlainText(selectedEntries)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Copied ${selectedDays.length} '
            '${selectedDays.length == 1 ? 'day' : 'days'} to clipboard'),
      ));
  }

  /// Entries sorted newest-eaten-first, undated ones (shouldn't normally
  /// happen) last.
  List<Task> _entries() {
    final entries = ItemViews.foodDiary(
      _tasks,
      rules: Config.viewFilterRules[ViewFilterRules.foodDiary],
    );
    entries.sort((a, b) {
      final aTime = a.dueDate;
      final bTime = b.dueDate;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return entries;
  }

  /// Groups entries by the calendar day on which they were eaten. Historical
  /// days are rendered as collapsed sections so an established diary stays
  /// quick to scan, while today (and any future/undated entries) remains
  /// immediately visible.
  List<_FoodDiaryDay> _days(List<Task> entries) {
    final grouped = <DateTime?, List<Task>>{};
    for (final entry in entries) {
      final time = entry.dueDate;
      final day = time == null
          ? null
          : DateTime(time.year, time.month, time.day);
      grouped.putIfAbsent(day, () => <Task>[]).add(entry);
    }
    return [
      for (final group in grouped.entries)
        _FoodDiaryDay(day: group.key, entries: group.value),
    ];
  }

  /// The default start/stop selection for a fresh stomach-issue entry:
  /// 'stop' when today's most recent stomach entry is an unmatched 'start',
  /// 'start' otherwise (including when nothing has been logged today yet).
  String _defaultStomachEventType() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todaysStomachEntries = _tasks.where((t) {
      final due = t.dueDate;
      return t.isEatingHabit &&
          t.isStomachIssue &&
          due != null &&
          DateTime(due.year, due.month, due.day) == today;
    }).toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    var open = false;
    for (final entry in todaysStomachEntries) {
      if (entry.stomachEventType == 'start') {
        open = true;
      } else if (entry.stomachEventType == 'stop') {
        open = false;
      }
    }
    return open ? 'stop' : 'start';
  }

  Future<void> _editEntry([Task? entry]) async {
    // Only a fresh "add" needs yesterday's meals to copy from — editing an
    // existing entry keeps the dialog focused on that entry.
    final yesterdayMeals = entry == null
        ? FoodDiaryWidgetService.latestEntryPerMealWindow(
            _tasks, _yesterday())
        : const <Task?>[null, null, null, null];
    final result = await showDialog<_FoodDiaryEditResult>(
      context: context,
      builder: (context) => _FoodDiaryEditDialog(
        entry: entry,
        yesterdayMeals: yesterdayMeals,
        defaultStomachEventType: _defaultStomachEventType(),
      ),
    );
    if (result == null) return;
    setState(() {
      if (entry == null) {
        _tasks.insert(
          0,
          Task(
            title: result.title,
            description: result.description,
            label: result.label,
            createdAt: DateTime.now(),
            dueDate: result.time,
            hasExplicitTime: true,
            isEatingHabit: true,
            isStomachIssue: result.isStomachIssue,
            stomachEventType: result.stomachEventType,
            stomachSymptomTypes: result.stomachSymptomTypes,
            stomachIntensity: result.stomachIntensity,
          ),
        );
      } else {
        entry
          ..title = result.title
          ..description = result.description
          ..label = result.label
          ..dueDate = result.time
          ..hasExplicitTime = true
          ..isStomachIssue = result.isStomachIssue
          ..stomachEventType = result.stomachEventType
          ..stomachSymptomTypes = result.stomachSymptomTypes
          ..stomachIntensity = result.stomachIntensity;
      }
    });
    await _save();
  }

  /// Creates a fresh log entry from [entry], preserving the food details but
  /// recording it at the current time. This makes recurring meals quick to
  /// log without changing the historical entry they came from.
  Future<void> _copyEntryToNow(Task entry) async {
    final now = DateTime.now();
    final copy = Task(
      title: entry.title,
      description: entry.description,
      label: entry.label,
      createdAt: now,
      dueDate: now,
      hasExplicitTime: true,
      isEatingHabit: true,
      isStomachIssue: entry.isStomachIssue,
      stomachEventType: entry.stomachEventType,
      stomachSymptomTypes: entry.stomachSymptomTypes,
      stomachIntensity: entry.stomachIntensity,
    );
    setState(() => _tasks.insert(0, copy));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Copied "${entry.title}" to now')),
      );
  }

  /// Moves [entry] to the Archived Items list, with an undo snackbar —
  /// exactly like deleting a wishlist item.
  void _deleteEntry(Task entry) {
    final originalIndex = _tasks.indexOf(entry);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _tasks.remove(entry));
    _save();

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final deleted = await _repository.loadDeletedItems();
      entry.deletedAt = DateTime.now();
      deleted.insert(0, entry);
      await _repository.saveDeletedItems(deleted);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${entry.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                final index = originalIndex.clamp(0, _tasks.length);
                _tasks.insert(index, entry);
              });
              _save();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    final days = _days(entries);
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Food Diary',
        actions: [
          IconButton(
            tooltip: _nutritionistView
                ? 'Switch to diary view'
                : 'Switch to nutritionist view',
            onPressed: () =>
                setState(() => _nutritionistView = !_nutritionistView),
            icon: Icon(
                _nutritionistView ? Icons.menu_book : Icons.health_and_safety),
          ),
          IconButton(
            tooltip: 'Copy days as text',
            onPressed: entries.isEmpty ? null : _copyDays,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Export food diary',
            onPressed: entries.isEmpty ? null : _exportEntries,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add food diary entry',
        onPressed: () => _editEntry(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No food diary entries yet. Log what you eat here — it '
                      'stays out of your task lists.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _nutritionistView
                  ? _NutritionistView(entries: entries, days: days)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                      children: [
                        for (final day in days)
                          _FoodDiaryDaySection(
                            key: ValueKey(day.day),
                            day: day,
                            onEdit: _editEntry,
                            onCopyToNow: _copyEntryToNow,
                            onDelete: _deleteEntry,
                          ),
                      ],
                    ),
    );
  }
}

class _FoodDiaryDay {
  final DateTime? day;
  final List<Task> entries;

  const _FoodDiaryDay({required this.day, required this.entries});
}

/// Lets the user pick which logged days to copy (all checked to start, so a
/// full copy is one tap), then hands the picked day-keys back to
/// [_FoodDiaryPageState._copyDays] to build [foodDiaryPlainText] from just
/// those days.
class _CopyDaysDialog extends StatefulWidget {
  final List<_FoodDiaryDay> days;

  const _CopyDaysDialog({required this.days});

  @override
  State<_CopyDaysDialog> createState() => _CopyDaysDialogState();
}

class _CopyDaysDialogState extends State<_CopyDaysDialog> {
  late final Set<DateTime?> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.days.map((day) => day.day).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return AlertDialog(
      title: const Text('Copy days as text'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final day in widget.days)
              CheckboxListTile(
                value: _selected.contains(day.day),
                title: Text(_foodDiaryDayTitle(day.day, today)),
                subtitle: Text('${day.entries.length} '
                    '${day.entries.length == 1 ? 'entry' : 'entries'}'),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selected.add(day.day);
                  } else {
                    _selected.remove(day.day);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Copy'),
        ),
      ],
    );
  }
}

class _FoodDiaryDaySection extends StatelessWidget {
  final _FoodDiaryDay day;
  final ValueChanged<Task> onEdit;
  final ValueChanged<Task> onCopyToNow;
  final ValueChanged<Task> onDelete;

  const _FoodDiaryDaySection({
    super.key,
    required this.day,
    required this.onEdit,
    required this.onCopyToNow,
    required this.onDelete,
  });

  List<Widget> _tiles() => [
        for (final entry in day.entries)
          _FoodDiaryTile(
            key: ValueKey(entry.uid),
            entry: entry,
            onEdit: () => onEdit(entry),
            onCopyToNow: () => onCopyToNow(entry),
            onDelete: () => onDelete(entry),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPast = day.day != null && day.day!.isBefore(today);
    final title = _foodDiaryDayTitle(day.day, today);

    if (isPast) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey<String>('food-diary-day-$title'),
          initiallyExpanded: false,
          title: Text(title),
          subtitle: Text(
            '${day.entries.length} ${day.entries.length == 1 ? 'entry' : 'entries'}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: _tiles(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ..._tiles(),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A read-oriented layout of the same entries a nutritionist would want to
/// review: a tag-frequency summary up top, then every day grouped and fully
/// expanded (unlike the diary view, nothing collapses) with full-length
/// notes, no swipe-to-delete or per-entry actions.
class _NutritionistView extends StatelessWidget {
  final List<Task> entries;
  final List<_FoodDiaryDay> days;

  const _NutritionistView({super.key, required this.entries, required this.days});

  @override
  Widget build(BuildContext context) {
    final tagCounts = _sortedFoodDiaryTagCounts(entries);
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Summary', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('${entries.length} '
                    '${entries.length == 1 ? 'entry' : 'entries'} across '
                    '${days.length} ${days.length == 1 ? 'day' : 'days'}'),
                if (tagCounts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in tagCounts)
                        Chip(
                          label: Text('${tag.key} (${tag.value})'),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final day in days)
          _NutritionistDaySection(key: ValueKey(day.day), day: day),
      ],
    );
  }
}

class _NutritionistDaySection extends StatelessWidget {
  final _FoodDiaryDay day;

  const _NutritionistDaySection({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_foodDiaryDayTitle(day.day, today),
                style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            for (final entry in day.entries) _NutritionistEntryRow(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _NutritionistEntryRow extends StatelessWidget {
  final Task entry;

  const _NutritionistEntryRow({super.key, required this.entry});

  List<String> _labels() => entry.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final time = entry.dueDate;
    final labels = _labels();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time == null
                ? foodDiaryEntryTitle(entry)
                : '${formatTimerTime(time)} — ${foodDiaryEntryTitle(entry)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (entry.isStomachIssue && entry.stomachIntensity != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Intensity ${entry.stomachIntensity}/10',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (labels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(labels.join(', '),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          if (entry.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(entry.description),
            ),
        ],
      ),
    );
  }
}

class _FoodDiaryEditResult {
  final String title;
  final String description;
  final String label;
  final DateTime time;
  final bool isStomachIssue;
  final String? stomachEventType;
  final List<String> stomachSymptomTypes;
  final int? stomachIntensity;

  const _FoodDiaryEditResult(
    this.title,
    this.description,
    this.label,
    this.time, {
    this.isStomachIssue = false,
    this.stomachEventType,
    this.stomachSymptomTypes = const [],
    this.stomachIntensity,
  });
}

/// Add/edit dialog owning its text controllers, so the dialog's exit
/// animation never touches a disposed one (see task_detail's rule).
class _FoodDiaryEditDialog extends StatefulWidget {
  final Task? entry;

  /// Yesterday's latest breakfast/lunch/snack/dinner entries (`null` where
  /// nothing was logged in that window), in
  /// [FoodDiaryWidgetService.mealNames] order. Only populated — and only
  /// shown — when adding a new entry.
  final List<Task?> yesterdayMeals;

  /// The start/stop toggle's initial value for a fresh stomach-issue entry
  /// — see [_FoodDiaryPageState._defaultStomachEventType].
  final String defaultStomachEventType;

  const _FoodDiaryEditDialog({
    required this.entry,
    this.yesterdayMeals = const <Task?>[null, null, null, null],
    this.defaultStomachEventType = 'start',
  });

  @override
  State<_FoodDiaryEditDialog> createState() => _FoodDiaryEditDialogState();
}

class _FoodDiaryEditDialogState extends State<_FoodDiaryEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _label;
  late DateTime _time;
  late bool _isStomach;
  late String? _stomachEventType;
  late Set<String> _stomachSymptomTypes;
  late int _stomachIntensity;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.entry?.description ?? '');
    _label = widget.entry?.label ?? '';
    _time = widget.entry?.dueDate ?? DateTime.now();
    _isStomach = widget.entry?.isStomachIssue ?? false;
    // A fresh add starts from the computed default; editing an existing
    // entry always opens on its own stored value, even null (the user
    // deliberately left neither Start nor Stop selected).
    _stomachEventType = widget.entry == null
        ? widget.defaultStomachEventType
        : widget.entry!.stomachEventType;
    _stomachSymptomTypes = (widget.entry?.stomachSymptomTypes.isNotEmpty ?? false)
        ? Set<String>.from(widget.entry!.stomachSymptomTypes)
        : {'gas'};
    _stomachIntensity = widget.entry?.stomachIntensity ?? 5;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await pickDateInstantly(context, _time);
    if (date == null || !mounted) return;
    setState(() {
      _time = DateTime(
          date.year, date.month, date.day, _time.hour, _time.minute);
    });
  }

  Future<void> _pickTime() async {
    final time = await pickTimeOfDay(context, TimeOfDay.fromDateTime(_time));
    if (time == null || !mounted) return;
    setState(() {
      _time = DateTime(
          _time.year, _time.month, _time.day, time.hour, time.minute);
    });
  }

  /// Fills the title/tags/description from yesterday's meal at [index] —
  /// the current time is left untouched, so this just makes a recurring
  /// meal quick to re-log without retyping it.
  void _copyYesterdayMeal(int index) {
    final meal = widget.yesterdayMeals[index];
    if (meal == null) return;
    setState(() {
      _titleController.text = meal.title;
      _descriptionController.text = meal.description;
      _label = meal.label;
    });
  }

  Widget _timeRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Time', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(formatTimerDate(_time)),
            ),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time, size: 16),
              label: Text(formatTimerTime(_time)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _foodFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                textInputAction: TextInputAction.next,
              ),
            ),
            SpeechInputButton(controller: _titleController),
          ],
        ),
        if (widget.entry == null) ...[
          const SizedBox(height: 4),
          _CopyYesterdayRow(
            meals: widget.yesterdayMeals,
            onCopy: _copyYesterdayMeal,
          ),
        ],
        const SizedBox(height: 12),
        _timeRow(),
        const SizedBox(height: 12),
        // Tags sit under the time, same row order as a plain task's detail
        // page — the description is the exception and lives at the bottom.
        LabelPickerField(
          value: _label,
          fieldLabel: 'Tags (e.g. sugar, lactose)',
          onChanged: (v) => setState(() => _label = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _stomachFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _timeRow(),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child:
              Text('Start or stop', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        // multiSelectionEnabled + emptySelectionAllowed purely so tapping
        // the already-selected segment clears it — Start and Stop otherwise
        // stay mutually exclusive, resolved by hand below, since the
        // multi-select widget itself would let both end up selected at
        // once (tapping the other one just adds it rather than switching).
        SegmentedButton<String>(
          multiSelectionEnabled: true,
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(
                value: 'start',
                label: Text('Start'),
                icon: Icon(Icons.play_circle_outlined)),
            ButtonSegment(
                value: 'stop',
                label: Text('Stop'),
                icon: Icon(Icons.stop_circle_outlined)),
          ],
          selected: _stomachEventType == null ? const {} : {_stomachEventType!},
          onSelectionChanged: (newSelection) => setState(() {
            // A second item appearing means the tap added the *other*
            // segment on top of the one already selected; keep only that
            // newly-tapped one instead of leaving both lit up.
            final resolved = newSelection.length > 1
                ? newSelection.where((value) => value != _stomachEventType)
                : newSelection;
            _stomachEventType = resolved.isEmpty ? null : resolved.first;
          }),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Type', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 4),
        // Multi-select: any combination of the three is valid (e.g. gas and
        // discomfort together), and emptySelectionAllowed defaults to false
        // so the last remaining type can't be tapped off.
        SegmentedButton<String>(
          multiSelectionEnabled: true,
          segments: const [
            ButtonSegment(value: 'gas', label: Text('Gas')),
            ButtonSegment(value: 'liquid', label: Text('Liquid')),
            ButtonSegment(value: 'discomfort', label: Text('Discomfort')),
          ],
          selected: _stomachSymptomTypes,
          onSelectionChanged: (selection) =>
              setState(() => _stomachSymptomTypes = selection),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Intensity: $_stomachIntensity/10',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        Slider(
          value: _stomachIntensity.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: '$_stomachIntensity',
          onChanged: (value) =>
              setState(() => _stomachIntensity = value.round()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.entry == null ? 'Add food diary entry' : 'Edit entry'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Food'),
                      icon: Icon(Icons.restaurant)),
                  ButtonSegment(
                      value: true,
                      label: Text('Stomach'),
                      icon: Icon(Icons.medical_services_outlined)),
                ],
                selected: {_isStomach},
                onSelectionChanged: (selection) =>
                    setState(() => _isStomach = selection.first),
              ),
              const SizedBox(height: 12),
              _isStomach ? _stomachFields() : _foodFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_isStomach) {
              final symptoms = _stomachSymptomsLabel(_stomachSymptomTypes.toList());
              final eventLabel = _stomachEventLabel(_stomachEventType);
              Navigator.of(context).pop(_FoodDiaryEditResult(
                eventLabel == null ? symptoms : '$symptoms · $eventLabel',
                '',
                '',
                _time,
                isStomachIssue: true,
                stomachEventType: _stomachEventType,
                stomachSymptomTypes: _stomachSymptomTypes.toList(),
                stomachIntensity: _stomachIntensity,
              ));
              return;
            }
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.of(context).pop(_FoodDiaryEditResult(
              title,
              _descriptionController.text.trim(),
              _label.trim(),
              _time,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Row of four small icon buttons — breakfast/lunch/snack/dinner — that
/// fill the add-entry dialog's title/tags/description from yesterday's
/// matching meal, one tap away. Icons rather than labels so the row stays
/// compact next to the title field; a button is disabled when yesterday has
/// nothing logged for that meal.
class _CopyYesterdayRow extends StatelessWidget {
  static const _icons = [
    Icons.free_breakfast,
    Icons.lunch_dining,
    Icons.icecream,
    Icons.dinner_dining,
  ];

  final List<Task?> meals;
  final ValueChanged<int> onCopy;

  const _CopyYesterdayRow({required this.meals, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _icons.length; i++)
          IconButton(
            tooltip: meals[i] == null
                ? 'No ${FoodDiaryWidgetService.mealNames[i].toLowerCase()} logged yesterday'
                : 'Copy yesterday\'s ${FoodDiaryWidgetService.mealNames[i].toLowerCase()}: '
                    '${meals[i]!.title}',
            visualDensity: VisualDensity.compact,
            onPressed: meals[i] == null ? null : () => onCopy(i),
            icon: Icon(_icons[i], size: 20),
          ),
      ],
    );
  }
}

/// One food diary entry: title, time, description and tags — no checkbox,
/// no due-date semantics, just a log line. Swipe (either direction) opens a
/// confirm-free delete, matching the app's general swipe-to-delete feel.
class _FoodDiaryTile extends StatelessWidget {
  final Task entry;
  final VoidCallback onEdit;
  final VoidCallback onCopyToNow;
  final VoidCallback onDelete;

  const _FoodDiaryTile({
    Key? key,
    required this.entry,
    required this.onEdit,
    required this.onCopyToNow,
    required this.onDelete,
  }) : super(key: key);

  List<String> _labels() => entry.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  /// Gives the diary a quick visual rhythm without making the card content
  /// harder to read. Morning runs until noon, the daytime/noon tint continues
  /// until 18:00, and the Bordeaux tint marks the evening. Stomach-issue
  /// entries are deliberately left out of this — `null` falls back to the
  /// theme's plain card color — so they read as a different kind of entry
  /// rather than another meal time slot.
  Color? _cardColor(BuildContext context, DateTime? time) {
    if (entry.isStomachIssue) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hour = time?.hour ?? 12;
    if (hour < 12) {
      return isDark ? const Color(0xFF17324A) : const Color(0xFFE3F2FD);
    }
    if (hour < 18) {
      return isDark ? const Color(0xFF403817) : const Color(0xFFFFF8D6);
    }
    return isDark ? const Color(0xFF451E2D) : const Color(0xFFF3E1E6);
  }

  @override
  Widget build(BuildContext context) {
    final labels = _labels();
    final time = entry.dueDate;
    return Dismissible(
      key: ValueKey(entry.uid),
      background: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        color: _cardColor(context, time),
        child: ListTile(
          title: Text(foodDiaryEntryTitle(entry)),
          trailing: IconButton(
            tooltip: 'Copy entry to now',
            onPressed: onCopyToNow,
            icon: const Icon(Icons.content_copy),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(formatTimerDateTime(time)),
              ],
              if (entry.isStomachIssue) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (_stomachEventLabel(entry.stomachEventType) != null)
                      Chip(
                        avatar: Icon(
                          entry.stomachEventType == 'stop'
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outlined,
                          size: 16,
                        ),
                        label: Text(_stomachEventLabel(entry.stomachEventType)!),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    if (entry.stomachIntensity != null)
                      Chip(
                        label: Text('Intensity ${entry.stomachIntensity}/10'),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final label in labels)
                      Chip(
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
              if (entry.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                DescriptionDisclosure(description: entry.description),
              ],
            ],
          ),
          onTap: onEdit,
        ),
      ),
    );
  }
}
