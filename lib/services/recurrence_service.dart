import '../models/task.dart';

/// Add/remove plan produced by [RecurrenceService.planRefresh]. Kept
/// side-effect free so it's trivial to unit test: the caller decides how
/// (and whether) to apply it to its own task list.
class RecurrenceRefreshPlan {
  final List<Task> toAdd;
  final List<Task> toRemove;
  const RecurrenceRefreshPlan(this.toAdd, this.toRemove);

  bool get isEmpty => toAdd.isEmpty && toRemove.isEmpty;
}

/// Everything about how a recurring series is generated, kept, and split —
/// moved out of the UI layer so it can be unit tested directly and so every
/// caller shares one definition of "what does this series look like".
///
/// A series is one master [Task] (`recurrenceParentUid == null`,
/// `isRecurring == true`) plus zero or more generated child occurrences
/// (`recurrenceParentUid == master.uid`). The master's own due date is
/// always the series' first occurrence ("slot 0"); every other occurrence's
/// due date is a "slot" computed from the master's recurrence rule, and a
/// child's [Task.recurrenceInstanceKey] freezes which slot it represents —
/// letting an occurrence be moved to a different actual date (an "override")
/// without losing track of which slot it filled, and without a later
/// regeneration duplicating that slot.
class RecurrenceService {
  const RecurrenceService._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dayKey(DateTime date) {
    final d = dateOnly(date);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final day = date.day > daysInMonth ? daysInMonth : date.day;
    return DateTime(year, month, day);
  }

  /// The Nth occurrence after [anchor] under a non-weekday-list rule,
  /// computed directly from [anchor] rather than by repeatedly stepping the
  /// previous result — stepping cumulatively would drift a monthly/yearly
  /// rule anchored on a short month (e.g. day 31) onto an ever-earlier day
  /// once a shorter month clamps it once.
  static DateTime _nthOccurrence(
    DateTime anchor,
    String frequency,
    int interval,
    int n,
  ) {
    switch (frequency) {
      case 'weekly':
        return anchor.add(Duration(days: 7 * interval * n));
      case 'monthly':
        return _addMonths(anchor, interval * n);
      case 'yearly':
        return _addMonths(anchor, interval * 12 * n);
      case 'daily':
      default:
        return anchor.add(Duration(days: interval * n));
    }
  }

  /// How far to generate before stopping, given the master's end condition.
  /// A 'never'-ending series only ever generates a rolling window ahead of
  /// [now] — cheap, and it simply grows the window on the next refresh
  /// rather than materializing years of tasks up front.
  static DateTime _horizonFor(Task master, DateTime now) {
    final anchor = dateOnly(master.dueDate!);
    switch (master.recurrenceEndType) {
      case 'date':
        final end = master.recurrenceEndDate;
        return end == null ? anchor : dateOnly(end);
      case 'count':
        // The occurrence count is what actually stops generation; this only
        // needs to be far enough out that the count is reached first.
        return anchor.add(const Duration(days: 365 * 50));
      case 'never':
      default:
        // The furthest a task's own due date can bucket it into a concrete
        // tab is the "next month" tab (30 days out); a bit of headroom past
        // that keeps every visible tab populated between refreshes without
        // materializing months of never-visible future occurrences.
        final rolling = dateOnly(now).add(const Duration(days: 60));
        return rolling.isAfter(anchor) ? rolling : anchor;
    }
  }

  /// The full occurrence sequence (including the master's own slot 0) up to
  /// [horizon], honoring the master's frequency/interval/weekdays and its
  /// occurrence-count limit. [hardCap] is a last-resort safety net against a
  /// pathological rule (e.g. interval 0) looping effectively forever.
  static List<DateTime> occurrenceDates(
    Task master, {
    required DateTime horizon,
    int hardCap = 2000,
  }) {
    final anchor = dateOnly(master.dueDate!);
    final frequency = master.recurrenceFrequency;
    final interval =
        master.recurrenceInterval < 1 ? 1 : master.recurrenceInterval;
    final maxCount = master.recurrenceEndType == 'count'
        ? (master.recurrenceOccurrenceCount ?? 1).clamp(1, hardCap)
        : hardCap;

    final dates = <DateTime>[anchor];
    if (maxCount <= 1 || horizon.isBefore(anchor)) return dates;

    if (frequency == 'weekly' && master.recurrenceWeekdays.isNotEmpty) {
      final weekdays = master.recurrenceWeekdays.toSet();
      final anchorWeekStart =
          anchor.subtract(Duration(days: anchor.weekday - 1));
      var cursor = anchor.add(const Duration(days: 1));
      while (!cursor.isAfter(horizon) && dates.length < maxCount) {
        final weekStart = cursor.subtract(Duration(days: cursor.weekday - 1));
        final weeksSinceAnchor =
            weekStart.difference(anchorWeekStart).inDays ~/ 7;
        if (weeksSinceAnchor % interval == 0 &&
            weekdays.contains(cursor.weekday)) {
          dates.add(cursor);
        }
        cursor = cursor.add(const Duration(days: 1));
      }
    } else {
      var n = 1;
      while (dates.length < maxCount) {
        final candidate = _nthOccurrence(anchor, frequency, interval, n);
        if (candidate.isAfter(horizon)) break;
        dates.add(candidate);
        n++;
      }
    }
    return dates;
  }

  /// Builds one generated occurrence for [master] at [date]/[key]. Content
  /// fields (title/description/note/label/project assignment/...) are
  /// copied so a series member looks and behaves like its master; scheduling
  /// bookkeeping (completedAt/movedAt/...) is deliberately left fresh rather
  /// than copied from the master's own history.
  static Task buildOccurrence(Task master, DateTime date, String key) {
    return Task(
      title: master.title,
      description: master.description,
      note: master.note,
      label: master.label,
      createdAt: DateTime.now(),
      dueDate: date,
      hasExplicitTime: master.hasExplicitTime,
      isWish: master.isWish,
      isEatingHabit: master.isEatingHabit,
      projectId: master.projectId,
      kanbanStatus: master.kanbanStatus,
      recurrenceParentUid: master.uid,
      recurrenceInstanceKey: key,
    );
  }

  /// Computes what should be added to / removed from [tasks] so that
  /// [master]'s series matches its current rule. Does not mutate anything;
  /// [applyPlan] (or equivalent) does that.
  ///
  /// - A slot listed in [Task.recurrenceExceptionDates] is never generated.
  /// - A slot matching a task already sitting in [archivedOrBinned] (the
  ///   Archived Items / Deleted bin lists) is never generated either — a
  ///   compatibility fallback for occurrences archived before a master
  ///   started recording exceptions, so nothing already-deleted comes back.
  /// - An existing child whose slot no longer belongs to the schedule (the
  ///   rule shrank) is removed — unless it's an override, which is always
  ///   preserved so an individually-edited occurrence can never be lost to a
  ///   later refresh.
  static RecurrenceRefreshPlan planRefresh(
    Task master,
    List<Task> tasks, {
    DateTime? now,
    List<Task> archivedOrBinned = const [],
  }) {
    if (master.recurrenceParentUid != null) {
      return const RecurrenceRefreshPlan([], []);
    }
    if (!master.isRecurring || master.dueDate == null) {
      final stale =
          tasks.where((t) => t.recurrenceParentUid == master.uid).toList();
      return RecurrenceRefreshPlan(const [], stale);
    }

    final horizon = _horizonFor(master, now ?? DateTime.now());
    final exceptions = master.recurrenceExceptionDates.toSet();
    for (final t in archivedOrBinned) {
      final d = t.dueDate;
      if (t.recurrenceParentUid == master.uid && d != null) {
        exceptions.add(dayKey(d));
      }
    }
    final expected = <String, DateTime>{};
    for (final date in occurrenceDates(master, horizon: horizon).skip(1)) {
      final key = dayKey(date);
      if (exceptions.contains(key)) continue;
      expected[key] = date;
    }

    final existing =
        tasks.where((t) => t.recurrenceParentUid == master.uid).toList();
    final keptKeys = <String>{};
    final toRemove = <Task>[];
    for (final child in existing) {
      final key = child.recurrenceInstanceKey;
      if (key != null && expected.containsKey(key)) {
        keptKeys.add(key);
      } else if (child.recurrenceOverride) {
        if (key != null) keptKeys.add(key);
      } else {
        toRemove.add(child);
      }
    }

    final toAdd = <Task>[];
    expected.forEach((key, date) {
      if (keptKeys.contains(key)) return;
      toAdd.add(buildOccurrence(master, date, key));
    });

    return RecurrenceRefreshPlan(toAdd, toRemove);
  }

  /// Applies a [RecurrenceRefreshPlan] to a live task list.
  static void applyPlan(List<Task> tasks, RecurrenceRefreshPlan plan) {
    if (plan.isEmpty) return;
    final removeIds = plan.toRemove.map((t) => t.uid).toSet();
    if (removeIds.isNotEmpty) {
      tasks.removeWhere((t) => removeIds.contains(t.uid));
    }
    tasks.addAll(plan.toAdd);
  }

  /// Runs [planRefresh] and applies it in one step — the common case.
  static void refresh(
    Task master,
    List<Task> tasks, {
    DateTime? now,
    List<Task> archivedOrBinned = const [],
  }) {
    applyPlan(
      tasks,
      planRefresh(master, tasks, now: now, archivedOrBinned: archivedOrBinned),
    );
  }

  /// "This event" delete of the master's own occurrence (slot 0): the master
  /// carries the rule, so it can't just vanish — the next occurrence is
  /// promoted to take over as the new master (rule, end condition and
  /// exceptions carried over, minus the one now-consumed occurrence), and
  /// every other child is re-pointed to it. Returns null when there is no
  /// next occurrence to promote (the series was down to just the master).
  static Task? promoteNextOccurrenceAsMaster(Task master, List<Task> tasks) {
    final children = tasks
        .where((t) => t.recurrenceParentUid == master.uid && t.dueDate != null)
        .toList()
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    if (children.isEmpty) return null;
    final newMaster = children.first;
    final consumedCount = master.recurrenceOccurrenceCount;
    newMaster
      ..isRecurring = true
      ..recurrenceFrequency = master.recurrenceFrequency
      ..recurrenceInterval = master.recurrenceInterval
      ..recurrenceWeekdays = List.of(master.recurrenceWeekdays)
      ..recurrenceEndType = master.recurrenceEndType
      ..recurrenceEndDate = master.recurrenceEndDate
      ..recurrenceOccurrenceCount =
          consumedCount == null ? null : (consumedCount - 1).clamp(0, 1 << 30)
      ..recurrenceExceptionDates = List.of(master.recurrenceExceptionDates)
      ..recurrenceParentUid = null
      ..recurrenceInstanceKey = null
      ..recurrenceOverride = false;
    for (final t in tasks) {
      if (t.recurrenceParentUid == master.uid && t.uid != newMaster.uid) {
        t.recurrenceParentUid = newMaster.uid;
      }
    }
    return newMaster;
  }

  /// Ends [master]'s series the day before [splitDate] and returns every
  /// occurrence at or after it — the master itself when [splitDate] doesn't
  /// come after the anchor (i.e. the whole series), otherwise every child
  /// from that slot on. Used for "delete this and following" and "delete all
  /// events" (pass the anchor date as [splitDate] for the latter); the
  /// caller removes the returned tasks from its own list.
  static List<Task> truncateSeriesBefore(
    Task master,
    List<Task> tasks,
    DateTime splitDate,
  ) {
    final split = dateOnly(splitDate);
    final anchor = dateOnly(master.dueDate!);
    final tail = <Task>[];
    if (!split.isAfter(anchor)) {
      tail.add(master);
    } else {
      master.recurrenceEndType = 'date';
      master.recurrenceEndDate = split.subtract(const Duration(days: 1));
      master.recurrenceOccurrenceCount = null;
    }
    for (final t in tasks) {
      if (t.recurrenceParentUid != master.uid) continue;
      final d = t.dueDate;
      if (d != null && !dateOnly(d).isBefore(split)) {
        tail.add(t);
      }
    }
    master.recurrenceExceptionDates =
        master.recurrenceExceptionDates.where((k) {
      final d = DateTime.tryParse(k);
      return d == null || d.isBefore(split);
    }).toList();
    return tail;
  }

  /// "This and following" edit of [splitInstance]'s due date: everything
  /// before it keeps the old master (whose series now ends the day before);
  /// [splitInstance] becomes a new master carrying the same rule (end
  /// condition adjusted for the occurrences already consumed); and every
  /// later, non-overridden sibling is re-pointed to the new master and
  /// shifted by the same delta so its date still matches the (unchanged)
  /// recurrence pattern re-anchored at the new date. An overridden sibling
  /// keeps its own date — only its parent link moves.
  static Task reanchorSeriesFrom(
    Task master,
    List<Task> tasks,
    Task splitInstance,
    DateTime newDate,
  ) {
    final oldSlot = dateOnly(splitInstance.dueDate!);
    final deltaDays = dateOnly(newDate).difference(oldSlot).inDays;
    final consumed = occurrenceDates(master, horizon: oldSlot)
        .where((d) => !d.isAfter(oldSlot))
        .length;
    final originalEndType = master.recurrenceEndType;
    final originalEndDate = master.recurrenceEndDate;
    final originalCount = master.recurrenceOccurrenceCount;

    master.recurrenceEndType = 'date';
    master.recurrenceEndDate = oldSlot.subtract(const Duration(days: 1));
    master.recurrenceOccurrenceCount = null;
    master.recurrenceExceptionDates =
        master.recurrenceExceptionDates.where((k) {
      final d = DateTime.tryParse(k);
      return d == null || d.isBefore(oldSlot);
    }).toList();

    for (final t in tasks) {
      if (t.recurrenceParentUid != master.uid || identical(t, splitInstance)) {
        continue;
      }
      final d = t.dueDate;
      if (d == null || dateOnly(d).isBefore(oldSlot)) continue;
      t.recurrenceParentUid = splitInstance.uid;
      if (!t.recurrenceOverride) {
        final shifted = dateOnly(d).add(Duration(days: deltaDays));
        t.dueDate = shifted;
        t.recurrenceInstanceKey = dayKey(shifted);
      }
    }

    splitInstance
      ..dueDate = newDate
      ..isRecurring = true
      ..recurrenceFrequency = master.recurrenceFrequency
      ..recurrenceInterval = master.recurrenceInterval
      ..recurrenceWeekdays = List.of(master.recurrenceWeekdays)
      ..recurrenceEndType = originalEndType
      ..recurrenceEndDate = originalEndDate
      ..recurrenceOccurrenceCount = originalCount == null
          ? null
          : (originalCount - consumed).clamp(0, 1 << 30)
      ..recurrenceExceptionDates = []
      ..recurrenceParentUid = null
      ..recurrenceInstanceKey = null
      ..recurrenceOverride = false;

    return splitInstance;
  }
}
