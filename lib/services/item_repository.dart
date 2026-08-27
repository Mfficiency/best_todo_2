import '../models/daily_task_stats.dart';
import '../models/item_event.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import 'item_event_journal.dart';
import 'storage_service.dart';

/// The one seam between the UI and however items are stored.
///
/// Pages talk to this facade for the item store (active list, deleted list,
/// daily stats, per-item history); today it delegates to the proven
/// JSON-file [StorageService] + [ItemEventJournal]. Swapping the backend
/// (e.g. to SQLite, or adding sync) means implementing this class
/// differently — no page changes. The trade-offs behind staying on JSON
/// files for now are recorded in `docs/architecture/storage-decision.md`;
/// backup/export tooling intentionally stays on [StorageService] directly,
/// as it is about files, not about the item store.
class ItemRepository {
  ItemRepository._();

  static final ItemRepository instance = ItemRepository._();

  final StorageService _storage = StorageService();

  /// The active item list (includes the day-rollover sweep and legacy
  /// wishlist migration, exactly like [StorageService.loadTaskList]).
  Future<List<Task>> loadItems() => _storage.loadTaskList();

  /// Persists the active list. Side effects ride along fire-and-forget:
  /// history journaling, label registration, reminder sync. [source]
  /// (see [TaskChangeSource]) is stamped on every history event this save
  /// produces.
  Future<void> saveItems(
    List<Task> items, {
    String source = TaskChangeSource.user,
  }) =>
      _storage.saveTaskList(items, source: source);

  Future<List<Task>> loadDeletedItems() => _storage.loadDeletedTaskList();

  Future<void> saveDeletedItems(List<Task> items) =>
      _storage.saveDeletedTaskList(items);

  /// The real Deleted bin — see [StorageService.loadBinTaskList] for the
  /// age-based purge that runs on every read.
  Future<List<Task>> loadBinItems() => _storage.loadBinTaskList();

  Future<void> saveBinItems(List<Task> items) =>
      _storage.saveBinTaskList(items);

  Future<Map<String, DailyTaskStats>> loadDailyStats() =>
      _storage.loadDailyTaskStats();

  Future<void> saveDailyStats(Map<String, DailyTaskStats> statsByDay) =>
      _storage.saveDailyTaskStats(statsByDay);

  /// One item's history, oldest first (see [ItemEventJournal.eventsForItem]).
  Future<List<ItemEvent>> historyOf(String itemUid) =>
      ItemEventJournal.instance.eventsForItem(itemUid);

  /// The full journal, in file order (exports).
  Future<List<ItemEvent>> allHistory() =>
      ItemEventJournal.instance.allEvents();
}
