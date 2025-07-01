import 'package:flutter/material.dart';

/// Calendar tab with week and month views.
class CalendarTab extends StatefulWidget {
  const CalendarTab({Key? key}) : super(key: key);

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
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < days.length; i++)
              Column(
                children: [
                  Text(_weekdays[i]),
                  const SizedBox(height: 4),
                  CircleAvatar(
                    radius: 18,
                    child: Text('${days[i].day}'),
                  ),
                ],
              ),
          ],
        ),
      ],
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
