import '../../config.dart';
import '../storage_service.dart';
import '../todoist_sync_service.dart';

/// Pulls the whole Todoist account into the browser tab's in-memory store
/// ([Config.webRealData]) with two-way sync on — the "Real data" choice of a
/// Chrome dev run and the approvals website's start. [onStatus] gets the
/// step being worked on. Returns how many tasks were loaded; throws (with
/// the in-memory store reset) when the token is wrong or the import fails.
Future<int> loadRealTodoistData(
  String token, {
  void Function(String status)? onStatus,
}) async {
  try {
    onStatus?.call('Connecting to Todoist…');
    await TodoistSyncService.instance.testConnection(token);
    Config.todoistApiToken = token;
    Config.todoistSyncEnabled = true;
    // Before the import: its saves must land in the in-memory store.
    Config.webRealData = true;
    onStatus?.call('Loading your tasks…');
    final result = await TodoistSyncService.instance.startFirstLaunchImport();
    if (result == null) {
      throw StateError('A Todoist sync is already running — try again');
    }
    // Unlike the phone's first-launch import, wait for everything: the
    // pages read the list once when they open.
    final entry = await result.finishInBackground();
    if (entry != null && !entry.success) {
      throw StateError(entry.message);
    }
    return entry?.itemCount ?? result.todayCount;
  } catch (_) {
    Config.webRealData = false;
    Config.todoistApiToken = '';
    Config.todoistSyncEnabled = false;
    StorageService.resetWebRealDataForTest();
    rethrow;
  }
}
