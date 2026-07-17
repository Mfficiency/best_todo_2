import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/item_event.dart';

/// Append-only history journal for items (`item_events.jsonl`, one JSON
/// event per line) plus a small per-item sequence index
/// (`item_event_meta.json`, `{uid: lastSeq}`).
///
/// Startup-speed contract: nothing here runs at app start. All writes are
/// fire-and-forget and chained onto [_chain] (the alarm-log pattern), so a
/// task save returns as fast as before; the journal file and the sequence
/// index are only read lazily — on the first append, or when a caller
/// actually asks for history (task details, export). Every I/O failure is
/// swallowed so web and tests keep working without a documents directory.
class ItemEventJournal {
  ItemEventJournal._();

  static ItemEventJournal instance = ItemEventJournal._();

  static const String fileName = 'item_events.jsonl';
  static const String metaFileName = 'item_event_meta.json';

  /// When the journal file outgrows this, the oldest lines are dropped so the
  /// newest [compactKeepEvents] remain (same self-trim idea as alarm_log.txt).
  static const int maxFileBytes = 1024 * 1024;
  static const int compactKeepEvents = 4000;

  /// Task JSON fields the journal watches, mapped to the event type a change
  /// of that field produces. Everything else — listRanking renumbering and
  /// the lifecycle timestamps the events themselves replace — is noise here.
  static const Map<String, String> trackedFields = {
    'title': ItemEvent.typeEdited,
    'description': ItemEvent.typeEdited,
    'note': ItemEvent.typeEdited,
    'label': ItemEvent.typeLabeled,
    'dueDate': ItemEvent.typeScheduled,
    'startAt': ItemEvent.typeScheduled,
    'endAt': ItemEvent.typeScheduled,
    'hasExplicitTime': ItemEvent.typeScheduled,
    'isDone': ItemEvent.typeStatusChanged,
    'projectId': ItemEvent.typeProjectChanged,
    'kanbanStatus': ItemEvent.typeProjectChanged,
    'isWish': ItemEvent.typeWishChanged,
    'isRecurring': ItemEvent.typeRecurrenceChanged,
    'recurrenceIntervalDays': ItemEvent.typeRecurrenceChanged,
    'recurrenceEndDate': ItemEvent.typeRecurrenceChanged,
  };

  Future<void> _chain = Future.value();
  Map<String, int>? _seqByItem;

  /// Computes the events that turn [before] into [after] (both `uid → task
  /// JSON` snapshots). Pure and synchronous for testability; sequence numbers
  /// are assigned through [nextSeq] (which should record the increment).
  /// [wasSeen] tells appearance apart: an appearing uid the journal has seen
  /// before is a restore, a brand-new one a creation.
  static List<ItemEvent> diffSnapshots({
    required Map<String, Map<String, dynamic>> before,
    required Map<String, Map<String, dynamic>> after,
    required int Function(String uid) nextSeq,
    required bool Function(String uid) wasSeen,
    required DateTime at,
  }) {
    final events = <ItemEvent>[];

    for (final entry in after.entries) {
      final uid = entry.key;
      final now = entry.value;
      final was = before[uid];
      if (was == null) {
        final restored = wasSeen(uid);
        events.add(ItemEvent(
          itemId: uid,
          seq: nextSeq(uid),
          at: at,
          type: restored ? ItemEvent.typeRestored : ItemEvent.typeCreated,
          patch: restored
              ? const []
              : [FieldChange('title', null, now['title'])],
        ));
        continue;
      }
      // Group changed fields by their event type so one save produces at
      // most one event per aspect (edit, schedule, status, ...).
      final changesByType = <String, List<FieldChange>>{};
      for (final field in trackedFields.keys) {
        final from = was[field];
        final to = now[field];
        if (from != to) {
          changesByType
              .putIfAbsent(trackedFields[field]!, () => <FieldChange>[])
              .add(FieldChange(field, from, to));
        }
      }
      for (final type in changesByType.keys) {
        events.add(ItemEvent(
          itemId: uid,
          seq: nextSeq(uid),
          at: at,
          type: type,
          patch: changesByType[type],
        ));
      }
    }

    for (final uid in before.keys) {
      if (!after.containsKey(uid)) {
        events.add(ItemEvent(
          itemId: uid,
          seq: nextSeq(uid),
          at: at,
          type: ItemEvent.typeDeleted,
        ));
      }
    }
    return events;
  }

  /// Records the difference between two task-list snapshots. Returns
  /// immediately; the diff and the writes run chained in the background.
  void recordDiff({
    required Map<String, Map<String, dynamic>> before,
    required Map<String, Map<String, dynamic>> after,
  }) {
    final at = DateTime.now();
    _chain = _chain.then((_) async {
      try {
        final seqs = await _loadSeqIndex();
        final events = diffSnapshots(
          before: before,
          after: after,
          nextSeq: (uid) => seqs[uid] = (seqs[uid] ?? 0) + 1,
          wasSeen: (uid) => (seqs[uid] ?? 0) > 0,
          at: at,
        );
        if (events.isEmpty) return;
        await _appendEvents(events);
        await _saveSeqIndex(seqs);
      } catch (_) {}
    });
  }

  /// Appends pre-built events (used by history seeding). Sequence numbers in
  /// [events] are ignored and reassigned so the per-item ordering stays
  /// consistent. Returns immediately; work happens on the chain.
  void recordEvents(List<ItemEvent> events) {
    if (events.isEmpty) return;
    _chain = _chain.then((_) async {
      try {
        final seqs = await _loadSeqIndex();
        for (final event in events) {
          event.seq = (seqs[event.itemId] ?? 0) + 1;
          seqs[event.itemId] = event.seq;
        }
        await _appendEvents(events);
        await _saveSeqIndex(seqs);
      } catch (_) {}
    });
  }

  /// All events currently in the journal, oldest first. Unparseable lines
  /// (e.g. a torn write at the end of the file) are skipped.
  Future<List<ItemEvent>> allEvents() async {
    await pendingWrites;
    try {
      final file = await _journalFile();
      if (!await file.exists()) return <ItemEvent>[];
      final lines = await file.readAsLines();
      final events = <ItemEvent>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          events.add(
              ItemEvent.fromJson(jsonDecode(line) as Map<String, dynamic>));
        } catch (_) {}
      }
      return events;
    } catch (_) {
      return <ItemEvent>[];
    }
  }

  /// The journal entries for one item, oldest first by timestamp. Sorted by
  /// `at` (then seq) rather than file order because seeded history is
  /// appended after any live events but describes an older past.
  Future<List<ItemEvent>> eventsForItem(String itemId) async {
    final events = await allEvents();
    final filtered = events.where((e) => e.itemId == itemId).toList();
    filtered.sort((a, b) {
      final byTime = a.at.compareTo(b.at);
      if (byTime != 0) return byTime;
      return a.seq.compareTo(b.seq);
    });
    return filtered;
  }

  /// Completes when every append enqueued so far has been flushed. Reads use
  /// it so history pages never miss the save that just happened; tests use it
  /// to make the fire-and-forget writes deterministic.
  Future<void> get pendingWrites => _chain;

  /// Clears cached state so tests with fresh temp dirs start clean.
  void resetForTest() {
    _chain = Future.value();
    _seqByItem = null;
  }

  Future<File> _journalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<File> _metaFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$metaFileName');
  }

  Future<Map<String, int>> _loadSeqIndex() async {
    final cached = _seqByItem;
    if (cached != null) return cached;
    var loaded = <String, int>{};
    try {
      final file = await _metaFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          loaded = <String, int>{
            for (final entry in decoded.entries)
              if (entry.value is int) entry.key.toString(): entry.value as int,
          };
        }
      }
    } catch (_) {}
    return _seqByItem = loaded;
  }

  Future<void> _saveSeqIndex(Map<String, int> seqs) async {
    try {
      final file = await _metaFile();
      await file.writeAsString(jsonEncode(seqs), flush: true);
    } catch (_) {}
  }

  Future<void> _appendEvents(List<ItemEvent> events) async {
    final file = await _journalFile();
    final buffer = StringBuffer();
    for (final event in events) {
      buffer.writeln(jsonEncode(event.toJson()));
    }
    await file.writeAsString(buffer.toString(),
        mode: FileMode.append, flush: true);
    await _compactIfNeeded(file);
  }

  Future<void> _compactIfNeeded(File file) async {
    try {
      if (await file.length() <= maxFileBytes) return;
      final lines = await file.readAsLines();
      final keep = lines.length > compactKeepEvents
          ? lines.sublist(lines.length - compactKeepEvents)
          : lines;
      await file.writeAsString('${keep.join('\n')}\n', flush: true);
    } catch (_) {}
  }
}
