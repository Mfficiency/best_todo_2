import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/attachment.dart';
import '../models/shared_payload.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../utils/task_utils.dart';
import 'attachment_storage_service.dart';
import 'item_repository.dart';
import 'log_service.dart';

/// Receives Android share-sheet content (text, links, images, PDFs — see
/// `ShareActivity.kt`) and turns it into a normal [Task] via the quick-add
/// screen (`QuickAddSharePage`).
///
/// Native side: `ShareActivity` receives the ACTION_SEND(_MULTIPLE) intent,
/// copies any shared file into the app's cache dir (a `content://` URI's
/// read grant dies with the trampoline activity that received it) and
/// forwards everything to `MainActivity`, which queues it. Delivery to Dart
/// is always pull-with-clear (`takeSharedContent`), so a share is never
/// pulled twice: the initial pull in [init] covers a cold start, and a
/// `sharedContentPending` poke triggers another pull when a share arrives
/// while the app is already running. A short content-signature window (see
/// [dedupWindow]) drops a share that Android (or a fast double-tap on the
/// share target) redelivers.
///
/// [setOnSharedPayload] is how `main.dart` hooks up the quick-add screen —
/// every payload from here on (including ones that arrived before the
/// callback was attached) is handed to it, one at a time. The screen itself
/// builds the [Task] (title/description/due bucket, imported attachments)
/// and hands it to [saveTask], which mirrors task creation everywhere else
/// in the app: the live home page (if any) claims it via [registerConsumer]
/// and adds it to its own in-memory list (no second `tasks.json` writer);
/// without one it is persisted straight through [ItemRepository].
class ShareIntentService {
  ShareIntentService._();

  static final ShareIntentService instance = ShareIntentService._();

  static const MethodChannel _channel = MethodChannel('besttodo/share');
  static const String sharedLabel = 'shared';

  /// How long a content signature is remembered to reject a redelivered
  /// share. Overridable so tests don't sleep.
  static Duration dedupWindow = const Duration(seconds: 5);

  void Function(SharedPayload payload)? _onPayload;
  final List<SharedPayload> _pendingPayloads = [];
  void Function(Task task)? _consumer;
  final Map<String, DateTime> _recentSignatures = {};
  bool _initialized = false;

  /// Hooks up the platform channel and drains any content queued before the
  /// Flutter engine was ready. Android-only; elsewhere the channel has no
  /// implementation and the pull simply fails silently.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedContentPending') await _pull();
    });
    await _pull();
  }

  Future<void> _pull() async {
    List<Object?>? items;
    try {
      items = await _channel.invokeListMethod<Object?>('takeSharedContent');
    } catch (_) {
      return;
    }
    for (final item in items ?? const <Object?>[]) {
      if (item is Map) {
        handleSharedPayload(SharedPayload.fromMap(item.cast<Object?, Object?>()));
      }
    }
  }

  /// Routes one shared payload to the registered callback, or queues it
  /// until [setOnSharedPayload] attaches one. Drops an empty payload and a
  /// redelivered duplicate (same content within [dedupWindow]). Exposed for
  /// tests.
  void handleSharedPayload(SharedPayload payload) {
    if (payload.isEmpty || _isDuplicate(payload)) return;
    final onPayload = _onPayload;
    if (onPayload != null) {
      onPayload(payload);
    } else {
      _pendingPayloads.add(payload);
    }
  }

  bool _isDuplicate(SharedPayload payload) {
    final now = DateTime.now();
    _recentSignatures.removeWhere(
        (_, seenAt) => now.difference(seenAt) > dedupWindow);
    final signature = payload.signature;
    if (_recentSignatures.containsKey(signature)) return true;
    _recentSignatures[signature] = now;
    return false;
  }

  /// Attaches the app-level handler that presents the quick-add screen for
  /// every payload — queued ones are handed over immediately, later ones as
  /// they arrive. Passing null detaches it, so anything arriving afterwards
  /// queues again.
  void setOnSharedPayload(void Function(SharedPayload payload)? callback) {
    _onPayload = callback;
    if (callback == null || _pendingPayloads.isEmpty) return;
    final queued = List.of(_pendingPayloads);
    _pendingPayloads.clear();
    for (final payload in queued) {
      callback(payload);
    }
  }

  /// The home page claims tasks built from a share while it is alive; see
  /// [saveTask].
  void registerConsumer(void Function(Task task) consumer) {
    _consumer = consumer;
  }

  /// Detaches [consumer] if it is still the active one, so a disposed home
  /// page never receives tasks (a newer registration stays untouched).
  void unregisterConsumer(void Function(Task task) consumer) {
    if (_consumer == consumer) _consumer = null;
  }

  /// Persists a task built by the quick-add screen: handed to the live home
  /// page's in-memory list if there is one, otherwise saved straight through
  /// [ItemRepository] (same fallback every other direct-to-storage write
  /// uses).
  Future<void> saveTask(Task task) async {
    final consumer = _consumer;
    if (consumer != null) {
      consumer(task);
      return;
    }
    final repository = ItemRepository.instance;
    final tasks = await repository.loadItems();
    tasks.add(task);
    applyDefaultDeadlineTimes(tasks);
    await repository.saveItems(tasks, source: TaskChangeSource.share);
    LogService.add(
        'ShareIntentService', 'Created task from share: ${task.title}');
  }

  /// Copies every image/PDF in [files] into permanent attachment storage
  /// under [taskUid] and deletes the share's cache copy once each is safely
  /// copied. Best-effort per file — one bad file doesn't drop the rest, and
  /// a file type [AttachmentsField] has no viewer for is skipped rather than
  /// attached unusably.
  static Future<List<Attachment>> importAttachments(
    String taskUid,
    List<SharedFile> files,
  ) async {
    final attachments = <Attachment>[];
    for (final file in files) {
      if (!(file.isImage || file.isPdf)) continue;
      try {
        final attachment = await AttachmentStorageService.instance.importFile(
          taskUid: taskUid,
          sourcePath: file.path,
          type: file.isPdf ? Attachment.typePdf : Attachment.typeImage,
        );
        attachments.add(attachment);
        final cached = File(file.path);
        if (await cached.exists()) await cached.delete();
      } catch (_) {}
    }
    return attachments;
  }

  /// Tells the platform side to background the app (Android:
  /// `moveTaskToBack`), re-fronting whatever the share came from. Called
  /// once the quick-add screen is done, saved or dismissed. Best-effort:
  /// no-op off Android/web, where the channel has no implementation.
  Future<void> returnToPreviousApp() async {
    try {
      await _channel.invokeMethod<void>('returnToPreviousApp');
    } catch (_) {}
  }

  /// Builds the quick-add screen's starting title/description from a shared
  /// payload: the first non-empty line of the text (or the subject, when
  /// there's no text — an email with a subject and empty body, say) titles
  /// it, capped at 120 chars; the rest is preserved in the description
  /// whenever the title alone doesn't carry all of it. A file-only share
  /// (an image/PDF with no caption) titles itself from the file instead.
  static Task buildDraftTask(SharedPayload payload, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final source = payload.text.isNotEmpty ? payload.text : payload.subject;
    var title = '';
    var description = '';
    if (source.isNotEmpty) {
      final trimmed = source.trim();
      final firstLine = trimmed
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => trimmed);
      title = firstLine.length > 120
          ? '${firstLine.substring(0, 119)}…'
          : firstLine;
      description = title == trimmed ? '' : trimmed;
    } else if (payload.files.isNotEmpty) {
      title = _titleForFileOnlyShare(payload.files.first, payload.files.length);
    }
    return Task(
      title: title,
      description: description,
      label: sharedLabel,
      createdAt: timestamp,
    );
  }

  /// A gallery/camera app names shared images with a generated id
  /// (`IMG_20260825_...`, a UUID, ...) that makes a poor task title; a real
  /// display name (from a file picker, a Files app share) is worth keeping.
  static String _titleForFileOnlyShare(SharedFile first, int count) {
    final name = first.fileName;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final looksGenerated = base.isEmpty ||
        RegExp(r'^[0-9a-fA-F-]{8,}$').hasMatch(base) ||
        RegExp(r'^(img|dsc|vid|pxl|screenshot|photo|image)[_-]?\d',
                caseSensitive: false)
            .hasMatch(base);
    final kind = first.isPdf ? 'PDF' : 'photo';
    final label = looksGenerated ? 'Shared $kind' : base;
    return count > 1 ? '$label (+${count - 1} more)' : label;
  }

  /// Clears all singleton state between tests.
  void resetForTest() {
    _consumer = null;
    _onPayload = null;
    _pendingPayloads.clear();
    _recentSignatures.clear();
    _initialized = false;
    _channel.setMethodCallHandler(null);
    dedupWindow = const Duration(seconds: 5);
  }
}
