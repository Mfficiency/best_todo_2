import 'package:flutter/foundation.dart';

import '../models/task.dart';

class DemoService {
  static final ValueNotifier<bool> demoMode = ValueNotifier(false);
  static List<Task> backupTasks = [];

  static List<Task> demoTasks(DateTime now) {
    return [
      Task(title: 'Welcome to BestToDo', dueDate: now),
      Task(title: 'Swipe to reschedule or delete', dueDate: now),
      Task(title: 'Tomorrow\'s task example', dueDate: now.add(const Duration(days: 1))),
      Task(title: 'Plan for the day after', dueDate: now.add(const Duration(days: 2))),
      Task(title: 'Prepare for next week', dueDate: now.add(const Duration(days: 7))),
      Task(title: 'Long term idea', dueDate: now.add(const Duration(days: 30))),
    ];
  }
}
