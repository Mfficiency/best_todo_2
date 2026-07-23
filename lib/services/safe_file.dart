import 'dart:io';

/// Crash- and corruption-safe file primitives for the JSON stores.
///
/// The failure this closes: a data file that fails to parse (torn write,
/// power loss, disk full, a bad migration) used to make its loader silently
/// return an empty list — and the next save then overwrote the user's real
/// data with that emptiness. With these helpers:
///
///  * every save is atomic (write `.tmp`, flush, rename over) — a crash
///    mid-write can never leave a half-written main file, and
///  * the previous good content survives as `<file>.bak`, so
///  * a loader whose main file fails to parse can fall back to the backup,
///    and the unreadable original is quarantined (`<file>.corrupt-<ts>`)
///    instead of being clobbered by the next save — nothing is ever lost,
///    even when it cannot be read.
///
/// All helpers throw on platforms without file support (web); callers keep
/// their existing swallow-errors behavior.
class SafeFile {
  SafeFile._();

  /// Writes to the same path run strictly one after another: overlapping
  /// saves (e.g. a delete immediately followed by an undo) would otherwise
  /// race on the shared `.tmp`/`.bak` companions — the first rename steals
  /// the `.tmp` and the second throws. Chaining keeps every write atomic
  /// and makes the last caller win. Bounded by the number of data files.
  static final Map<String, Future<void>> _writeChains = {};

  /// Atomically replaces [file] with [contents], rotating the previous
  /// content to `<file>.bak` first.
  static Future<void> writeString(File file, String contents) {
    final previous = _writeChains[file.path] ?? Future<void>.value();
    final next =
        previous.then((_) => _writeStringNow(file, contents));
    // Keep the chain alive after a failed write; the failure itself still
    // reaches the caller through `next`.
    _writeChains[file.path] = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<void> _writeStringNow(File file, String contents) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    if (await file.exists()) {
      final bak = File('${file.path}.bak');
      try {
        if (await bak.exists()) await bak.delete();
      } catch (_) {}
      try {
        await file.rename(bak.path);
      } catch (_) {
        // Rotation is best-effort; the atomic replace below still holds.
      }
    }
    await tmp.rename(file.path);
  }

  /// Loads [file] through [parse]. When the main file is missing, returns
  /// null. When it fails to parse, quarantines it as
  /// `<file>.corrupt-<timestamp>` (so no later save can destroy it) and
  /// falls back to `<file>.bak`; when that also fails, returns null. The
  /// backup is never deleted here.
  static Future<T?> readWithRecovery<T>(
    File file,
    T Function(String contents) parse,
  ) async {
    if (await file.exists()) {
      try {
        return parse(await file.readAsString());
      } catch (_) {
        try {
          final stamp = DateTime.now()
              .toIso8601String()
              .replaceAll(':', '-')
              .replaceAll('.', '-');
          await file.rename('${file.path}.corrupt-$stamp');
        } catch (_) {}
      }
    }
    final bak = File('${file.path}.bak');
    if (await bak.exists()) {
      try {
        return parse(await bak.readAsString());
      } catch (_) {}
    }
    return null;
  }
}
