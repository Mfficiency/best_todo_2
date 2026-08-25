import 'package:flutter/material.dart';

import '../config.dart';
import '../models/alarm.dart';
import '../models/task.dart';
import '../services/alarm_service.dart';
import '../services/alarm_widget_service.dart';
import '../services/food_diary_widget_service.dart';
import '../services/item_repository.dart';
import '../services/task_widget_service.dart';
import 'subpage_app_bar.dart';

/// Dev-only tool (drawer entry gated on [Config.isDev]) that renders a mock
/// of each Android home-screen widget using live app data, so the widgets —
/// which live outside the Flutter tree entirely, drawn by
/// `SimpleWidgetProvider`/`AlarmsWidgetProvider`/`FoodDiaryWidgetProvider`/
/// `FoodDiaryButtonWidgetProvider` via `RemoteViews` on the OS home screen —
/// can still be captured by the desktop screenshot integration test.
/// Colors/text mirror those Kotlin providers and their layout XMLs; this
/// page changes nothing they render.
class WidgetPreviewsPage extends StatefulWidget {
  const WidgetPreviewsPage({Key? key}) : super(key: key);

  @override
  State<WidgetPreviewsPage> createState() => _WidgetPreviewsPageState();
}

class _WidgetPreviewsPageState extends State<WidgetPreviewsPage> {
  bool _loading = true;
  List<Task> _tasks = <Task>[];
  List<Alarm> _alarms = <Alarm>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await ItemRepository.instance.loadItems();
    await AlarmService.instance.load();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _alarms = AlarmService.instance.list;
      _loading = false;
    });
  }

  /// A few Food Diary entries for today, spread across the meal checkpoints,
  /// so the Food Diary widget preview is never stuck on the empty state.
  /// Kept in memory only (never saved) — the real Food Diary tool seeds its
  /// own copy the same way the first time it is opened.
  List<Task> _foodDiaryPreviewEntries() {
    if (_tasks.any((t) => t.isEatingHabit)) {
      return _tasks.where((t) => t.isEatingHabit).toList();
    }
    final now = DateTime.now();
    DateTime at(int hour, int minute) =>
        DateTime(now.year, now.month, now.day, hour, minute);
    return [
      Task(
        title: 'Oatmeal with banana',
        createdAt: now,
        dueDate: at(8, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
      Task(
        title: 'Grilled chicken salad',
        createdAt: now,
        dueDate: at(13, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _widgetFrame({required Widget child}) => Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: child,
      );

  /// Mirrors `SimpleWidgetProvider.kt` / `simple_widget_layout.xml`.
  Widget _buildTaskWidget() {
    final rows = TaskWidgetService.todayTasks(_tasks);
    final openTasks = rows.where((t) => !t.isDone).toList();
    final totalCount = rows.length;
    final completedCount = totalCount - openTasks.length;
    final remainingCount = openTasks.length;
    final percent = totalCount == 0
        ? 0
        : ((completedCount / totalCount) * 100).round().clamp(0, 100);

    Color progressColor = const Color(0xFF4CAF50); // green
    if (!(completedCount == totalCount && totalCount > 0)) {
      if (remainingCount >= 5) {
        progressColor = const Color(0xFFF44336); // red
      } else if (remainingCount == 4) {
        progressColor = const Color(0xFFFF9800); // orange
      }
    }

    final checkable = Config.widgetCheckboxes;
    final shown = rows.length > TaskWidgetService.maxRows
        ? TaskWidgetService.maxRows
        : rows.length;
    final overflow = rows.length - shown;

    return _widgetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Config.showWidgetProgressLine)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          const SizedBox(height: 8),
          if (!checkable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                openTasks.isEmpty
                    ? 'Well done!\nNo more tasks for today!'
                    : openTasks.map((t) => '- ${t.title}').join('\n'),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            )
          else if (shown == 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('No tasks for today',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            )
          else
            for (var i = 0; i < shown; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      rows[i].isDone
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rows[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: rows[i].isDone
                              ? const Color(0xFF777777)
                              : Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (checkable && overflow > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text('+$overflow more',
                  style:
                      const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// Mirrors `AlarmsWidgetProvider.kt` / `alarms_widget_layout.xml`.
  Widget _buildAlarmsWidget() {
    final sorted = [..._alarms]
      ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    final shown =
        sorted.length > AlarmWidgetService.maxRows
            ? sorted.sublist(0, AlarmWidgetService.maxRows)
            : sorted;

    return _widgetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text('Alarms',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              Text('+', style: TextStyle(color: Colors.white, fontSize: 20)),
            ],
          ),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('No alarms yet. Tap + to add one.',
                  style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            )
          else
            for (final alarm in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        alarm.timeLabel,
                        style: TextStyle(
                          color: alarm.enabled
                              ? Colors.white
                              : const Color(0xFF777777),
                          fontSize: 18,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alarm.name.isEmpty ? 'Alarm' : alarm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            Text(
                              alarm.scheduleLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFFAAAAAA), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      alarm.enabled ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: alarm.enabled
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF777777),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          if (sorted.length > AlarmWidgetService.maxRows)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${sorted.length - AlarmWidgetService.maxRows} more',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  /// Mirrors `FoodDiaryWidgetProvider.kt` / `food_diary_widget_layout.xml`.
  /// Whether a checkpoint has *passed* is decided against the live clock,
  /// same as the Kotlin provider does at draw time.
  Widget _buildFoodDiaryWidget() {
    final entries = _foodDiaryPreviewEntries();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasEntry = FoodDiaryWidgetService.computeHasEntry(entries, today);
    const checkpointLabels = ['8:00', '13:00', '20:00'];
    final missed = <String>[];
    var loggedCount = 0;
    for (var i = 0; i < FoodDiaryWidgetService.checkpointHours.length; i++) {
      if (hasEntry[i]) loggedCount++;
      final started = now.hour >= FoodDiaryWidgetService.checkpointHours[i];
      if (started && !hasEntry[i]) missed.add(checkpointLabels[i]);
    }

    final backgroundColor =
        missed.isEmpty ? Colors.black : const Color(0xFFB71C1C);
    final status = missed.isNotEmpty
        ? 'Missing: ${missed.join(', ')}'
        : (loggedCount == 0
            ? 'Nothing logged yet today'
            : '$loggedCount/3 meals logged today');

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text('Food Diary',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              Text('+',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22)),
            ],
          ),
          const SizedBox(height: 4),
          Text(status,
              style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
        ],
      ),
    );
  }

  /// Mirrors `FoodDiaryButtonWidgetProvider.kt` /
  /// `food_diary_button_widget_layout.xml`: a fixed 1x1 widget that is
  /// nothing but the "+" button, shown here at roughly its real on-screen
  /// size (one home-screen grid cell) rather than stretched to [_widgetFrame]'s
  /// width like the other mocks.
  Widget _buildFoodDiaryButtonWidget() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Text(
          '+',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Widget Previews'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Mocks of the four Android home-screen widgets, drawn from '
                  'the same data the real widgets show. Dev/debug only — not '
                  'part of the release build\'s navigation.',
                ),
                _sectionLabel('Task widget'),
                _buildTaskWidget(),
                _sectionLabel('Alarms widget'),
                _buildAlarmsWidget(),
                _sectionLabel('Food Diary widget'),
                _buildFoodDiaryWidget(),
                _sectionLabel('Food Diary button widget'),
                _buildFoodDiaryButtonWidget(),
              ],
            ),
    );
  }
}
