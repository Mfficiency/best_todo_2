import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/task.dart';
import 'safe_file.dart';

/// Shared external-storage wishlist file, used today only by BestToDo's own
/// Wishlist tool ([wishlist_page.dart]).
///
/// BestToDo and Best Music are two separate Android apps (different
/// `applicationId`), so their app-private storage
/// (`getApplicationDocumentsDirectory`) is sandboxed from each other. This
/// store reads/writes one file under public external storage instead, which
/// both apps could technically reach since both already hold
/// `MANAGE_EXTERNAL_STORAGE` (declared in the shared `AndroidManifest.xml`,
/// requested at runtime the same way `MusicLibraryService.
/// ensureFolderPermission` already does for the music folder). It briefly
/// made a wishlist item genuinely the same record in both apps (0.2.78-
/// 0.2.83), but that surprised users who didn't expect the two apps' lists
/// to be the same list — checking an item off in Best Music also checked it
/// off in BestToDo. Best Music's Wishlist ([music_wishlist_page.dart]) no
/// longer touches this store at all (0.2.84); only BestToDo's Wishlist does,
/// via its own "Connect" banner.
///
/// Only wishlist items ([Task.isWish]) ever go through this store; every
/// other task stays in each app's own private `tasks.json`, untouched. On
/// load, [wishlist_page.dart] treats this file's content as the source of
/// truth once it exists (replacing the local wish-item subset), and every
/// save re-pushes the current wish-item set out to it.
class SharedWishlistStore {
  SharedWishlistStore._();

  static final SharedWishlistStore instance = SharedWishlistStore._();

  /// Path under the shared storage root ([_sharedDirectory]).
  static const String _relativePath = 'BestToDo/wishlist_shared.json';

  /// Set by tests to redirect reads/writes to a temp directory instead of
  /// real external storage. Implies [isSupported]; by itself it does not
  /// imply "connected" — see [connectionOverride].
  @visibleForTesting
  static Directory? sharedDirectoryOverride;

  /// Set by tests, alongside [sharedDirectoryOverride], to control what
  /// [isConnected]/[requestConnection] report without the real
  /// `permission_handler` plugin (unavailable in `flutter test`). Null (the
  /// default) means "connected", so a test that only cares about file I/O
  /// doesn't also have to set this; a test exercising the "not connected
  /// yet" banner/connect flow sets it to `false` first, then
  /// [requestConnection] flips it to `true` — mirroring a real grant.
  @visibleForTesting
  static bool? connectionOverride;

  bool get _testOverrideActive => sharedDirectoryOverride != null;

  bool get _platformSupported => !kIsWeb && Platform.isAndroid;

  /// Whether this platform can ever connect (Android, or a test override).
  /// Pages use this to decide whether offering to connect makes sense at
  /// all — on Windows/web there is no "other app" to share with.
  bool get isSupported => _testOverrideActive || _platformSupported;

  Directory? _sharedDirectory() {
    if (sharedDirectoryOverride != null) return sharedDirectoryOverride;
    if (!_platformSupported) return null;
    return Directory('/storage/emulated/0');
  }

  Future<File?> _file() async {
    final dir = _sharedDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_relativePath');
  }

  /// Whether this store can currently read/write the shared file — granted
  /// permission on Android, or a test override. Never prompts.
  Future<bool> isConnected() async {
    if (_testOverrideActive) return connectionOverride ?? true;
    if (!_platformSupported) return false;
    return Permission.manageExternalStorage.isGranted;
  }

  /// Requests the permission the shared file needs, showing Android's "All
  /// files access" settings screen if it isn't already granted. Only call
  /// this from an explicit user action (e.g. tapping "Connect") — never
  /// automatically on page load, which would surprise anyone using just one
  /// of the two apps.
  Future<bool> requestConnection() async {
    if (_testOverrideActive) {
      connectionOverride = true;
      return true;
    }
    if (!_platformSupported) return false;
    final status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;
    final result = await Permission.manageExternalStorage.request();
    return result.isGranted;
  }

  /// The shared file's wish items, and whether the file existed at all
  /// (distinguishes "nothing shared yet" from "every shared item was
  /// deleted" — callers need that to decide whether to seed the file from
  /// local data or to treat an empty result as authoritative).
  Future<SharedWishlistLoadResult> load() async {
    if (!await isConnected()) {
      return const SharedWishlistLoadResult(
          items: <Task>[], fileExisted: false);
    }
    try {
      final file = await _file();
      if (file == null || !await file.exists()) {
        return const SharedWishlistLoadResult(
            items: <Task>[], fileExisted: false);
      }
      final items = await SafeFile.readWithRecovery(
            file,
            (contents) => (jsonDecode(contents) as List<dynamic>)
                .map((e) => Task.fromJson(e as Map<String, dynamic>))
                .toList(),
          ) ??
          <Task>[];
      return SharedWishlistLoadResult(items: items, fileExisted: true);
    } catch (_) {
      return const SharedWishlistLoadResult(
          items: <Task>[], fileExisted: false);
    }
  }

  /// Replaces the shared file's content with [items]. No-op (returns false)
  /// when the store isn't connected — callers keep working local-only.
  Future<bool> save(List<Task> items) async {
    if (!await isConnected()) return false;
    try {
      final file = await _file();
      if (file == null) return false;
      await file.parent.create(recursive: true);
      final jsonString = jsonEncode(items.map((t) => t.toJson()).toList());
      await SafeFile.writeString(file, jsonString);
      return true;
    } catch (_) {
      return false;
    }
  }
}

class SharedWishlistLoadResult {
  final List<Task> items;
  final bool fileExisted;

  const SharedWishlistLoadResult(
      {required this.items, required this.fileExisted});
}

/// The wish items a page should keep after reconciling its own [local]
/// wish-item subset against a [SharedWishlistStore.load] result: the shared
/// file wins whenever it exists (so a deletion or edit made in the other
/// app takes effect here too), since every connected save keeps it current;
/// [local] is used only the first time, to seed a not-yet-existing shared
/// file from whatever this app already had.
List<Task> reconcileWishlist(
        List<Task> local, SharedWishlistLoadResult shared) =>
    shared.fileExisted ? shared.items : local;
