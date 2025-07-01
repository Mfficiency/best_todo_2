import 'package:flutter/material.dart';
import '../models/task.dart';

/// Calendar tab with week and month views that displays tasks.
class CalendarTab extends StatefulWidget {
  final List<Task> tasks;
  final DateTime currentDate;

  const CalendarTab({Key? key, required this.tasks, required this.currentDate})
      : super(key: key);

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab>
    with SingleTickerProviderStateMixin {
  late TabController _viewController;
  DateTime _focusedDay = DateTime.now();

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _viewController = TabController(length: 2, vsync: this);
    _focusedDay = widget.currentDate;
  }

  @override
  void didUpdateWidget(covariant CalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentDate != oldWidget.currentDate) {
      setState(() => _focusedDay = widget.currentDate);
    }
  }

  @override
  void dispose() {
    _viewController.dispose();
    super.dispose();
  }

  Widget _buildWeekView() {
    final startOfWeek =
        _focusedDay.subtract(Duration(days: _focusedDay.weekday - 1));
    final days =
        List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < days.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Text(_weekdays[i])),
                      const SizedBox(height: 4),
                      Center(
                        child: CircleAvatar(
                          radius: 18,
                          child: Text('${days[i].day}'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final task in widget.tasks.where((t) =>
                          t.dueDate != null &&
                          t.dueDate!.year == days[i].year &&
                          t.dueDate!.month == days[i].month &&
                          t.dueDate!.day == days[i].day))
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.title,
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthView() {
    return CalendarDatePicker(
      initialDate: _focusedDay,
      firstDate: DateTime(_focusedDay.year - 1),
      lastDate: DateTime(_focusedDay.year + 1),
      onDateChanged: (d) => setState(() => _focusedDay = d),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _viewController,
          tabs: const [Tab(text: 'Week'), Tab(text: 'Month')],
        ),
        Expanded(
          child: TabBarView(
            controller: _viewController,
            children: [
              _buildWeekView(),
              _buildMonthView(),
            ],
          ),
        ),
      ],
    );
  }
}
