import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The app's own folders a full backup copies, by archive name: Flutter's
/// documents folder (`app_flutter`), the support folder (`files`) and, on
/// Android, the app-specific external folder. Cache folders never.
Future<Map<String, String>> backupRoots() async {
  final roots = <String, String>{
    'documents': (await getApplicationDocumentsDirectory()).path,
    'support': (await getApplicationSupportDirectory()).path,
  };
  if (Platform.isAndroid) {
    final ext = await getExternalStorageDirectory();
    if (ext != null) roots['external'] = ext.path;
  }
  return roots;
}

/// A scratch folder in the app's cache (emptied first).
Future<String> scratchDir(String name) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir.path;
}

/// What [writeArchive] wrote.
class ArchiveStats {
  ArchiveStats(this.files, this.bytes);
  final int files;
  final int bytes;
}

/// True when [relative] (a path below a root, `/` separated) is in, or is,
/// one of [excluded] (folder or file paths below every root).
bool isExcluded(String relative, Set<String> excluded) {
  for (final e in excluded) {
    if (relative == e || relative.startsWith('$e/')) return true;
  }
  return false;
}

/// Writes a gzip'd tar to [outPath]: first [entries] (name → bytes, e.g.
/// manifest.json), then every file below each root as `<root>/<path>`,
/// skipping [excluded]. Files that vanish or can't be read while it runs
/// are skipped (counted in nothing).
Future<ArchiveStats> writeArchive({
  required String outPath,
  required Map<String, List<int>> entries,
  required Map<String, String> roots,
  Set<String> excluded = const {},
}) async {
  final out = File(outPath).openWrite();
  final sink = gzip.encoder.startChunkedConversion(out);
  var files = 0;
  var bytes = 0;
  try {
    for (final e in entries.entries) {
      _addHeader(sink, e.key, e.value.length, DateTime.now());
      sink.add(e.value);
      _pad(sink, e.value.length);
    }
    for (final root in roots.entries) {
      final dir = Directory(root.value);
      if (!dir.existsSync()) continue;
      final base = dir.absolute.path.replaceAll(r'\', '/');
      final list = _filesBelow(dir)..sort((a, b) => a.path.compareTo(b.path));
      for (final f in list) {
        final rel = f.absolute.path
            .replaceAll(r'\', '/')
            .substring(base.length)
            .replaceFirst(RegExp('^/'), '');
        if (isExcluded(rel, excluded)) continue;
        final int length;
        final DateTime modified;
        try {
          length = f.lengthSync();
          modified = f.lastModifiedSync();
        } on FileSystemException {
          continue;
        }
        _addHeader(sink, '${root.key}/$rel', length, modified);
        var written = 0;
        try {
          final raf = f.openSync();
          try {
            final buf = Uint8List(64 * 1024);
            while (written < length) {
              final want = length - written < buf.length ? length - written : buf.length;
              final n = raf.readIntoSync(buf, 0, want);
              if (n <= 0) break;
              sink.add(Uint8List.sublistView(buf, 0, n));
              written += n;
            }
          } finally {
            raf.closeSync();
          }
        } on FileSystemException {
          // Unreadable midway: fill up so the archive stays valid.
        }
        if (written < length) sink.add(Uint8List(length - written));
        _pad(sink, length);
        files++;
        bytes += length;
      }
    }
    sink.add(Uint8List(1024)); // end of archive
  } finally {
    sink.close();
    await out.close();
  }
  return ArchiveStats(files, bytes);
}

/// Every file below [dir]; folders that can't be listed are skipped.
List<File> _filesBelow(Directory dir) {
  final out = <File>[];
  final List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    return out;
  }
  for (final e in entries) {
    if (e is File) {
      out.add(e);
    } else if (e is Directory) {
      out.addAll(_filesBelow(e));
    }
  }
  return out;
}

void _pad(ByteConversionSink sink, int length) {
  final rest = length % 512;
  if (rest != 0) sink.add(Uint8List(512 - rest));
}

/// A ustar header; names over 100 bytes get a GNU long-name entry first.
void _addHeader(ByteConversionSink sink, String name, int size, DateTime mtime) {
  final nameBytes = utf8.encode(name);
  if (nameBytes.length > 99) {
    final long = [...nameBytes, 0];
    sink.add(_header('././@LongLink', long.length, mtime, 'L'.codeUnitAt(0)));
    sink.add(long);
    _pad(sink, long.length);
  }
  sink.add(_header(name, size, mtime, '0'.codeUnitAt(0)));
}

Uint8List _header(String name, int size, DateTime mtime, int type) {
  final h = Uint8List(512);
  void put(int offset, int length, List<int> value) {
    for (var i = 0; i < value.length && i < length; i++) {
      h[offset + i] = value[i];
    }
  }

  List<int> octal(int value, int length) =>
      ascii.encode('${value.toRadixString(8).padLeft(length - 1, '0')}\u0000');

  put(0, 100, utf8.encode(name));
  put(100, 8, octal(420, 8)); // 0644
  put(108, 8, octal(0, 8));
  put(116, 8, octal(0, 8));
  put(124, 12, octal(size, 12));
  put(136, 12, octal(mtime.millisecondsSinceEpoch ~/ 1000, 12));
  put(148, 8, List.filled(8, 0x20));
  h[156] = type;
  put(257, 6, ascii.encode('ustar\u0000'));
  put(263, 2, ascii.encode('00'));
  var sum = 0;
  for (final b in h) {
    sum += b;
  }
  put(148, 8, ascii.encode('${sum.toRadixString(8).padLeft(6, '0')}\u0000 '));
  return h;
}

/// The tar was cut off or is not one of these backups.
class BadArchiveException implements Exception {
  BadArchiveException(this.message);
  final String message;
  @override
  String toString() => 'BadArchiveException: $message';
}

/// Reads the gzip'd tar at [path] entry by entry: [onEntry] gets each name
/// and returns where to write it (a file path), or null to keep it in
/// memory and get it through [onBytes] (small entries such as JSON), or
/// '' to skip it.
Future<void> readArchive(
  String path, {
  required String? Function(String name) onEntry,
  void Function(String name, Uint8List bytes)? onBytes,
}) async {
  var buffer = Uint8List(0);
  var offset = 0;

  // Entry state.
  String? name;
  String? longName;
  var remaining = 0;
  var padding = 0;
  IOSink? fileOut;
  BytesBuilder? memory;
  var skip = false;
  var isLongName = false;
  var ended = false;

  Future<void> finishEntry() async {
    if (fileOut != null) {
      await fileOut!.close();
      fileOut = null;
    }
    if (isLongName) {
      final b = memory!.takeBytes();
      final end = b.indexOf(0);
      longName = utf8.decode(end < 0 ? b : b.sublist(0, end));
    } else if (memory != null && name != null) {
      onBytes?.call(name!, memory!.takeBytes());
    }
    memory = null;
    name = null;
    isLongName = false;
    skip = false;
  }

  await for (final chunk in File(path).openRead().transform(gzip.decoder)) {
    if (ended) break;
    buffer = (BytesBuilder(copy: false)
          ..add(Uint8List.sublistView(buffer, offset))
          ..add(chunk))
        .takeBytes();
    offset = 0;
    while (!ended) {
      if (remaining > 0) {
        final n = buffer.length - offset < remaining ? buffer.length - offset : remaining;
        if (n == 0) break;
        final part = Uint8List.sublistView(buffer, offset, offset + n);
        if (skip) {
          // Dropped.
        } else if (fileOut != null) {
          fileOut!.add(Uint8List.fromList(part));
        } else if (memory != null) {
          memory!.add(Uint8List.fromList(part));
        }
        offset += n;
        remaining -= n;
        if (remaining > 0) break;
        if (padding == 0) await finishEntry();
        continue;
      }
      if (padding > 0) {
        final n = buffer.length - offset < padding ? buffer.length - offset : padding;
        offset += n;
        padding -= n;
        if (padding > 0) break;
        await finishEntry();
        continue;
      }
      if (buffer.length - offset < 512) break;
      final h = Uint8List.sublistView(buffer, offset, offset + 512);
      offset += 512;
      if (h.every((b) => b == 0)) {
        ended = true;
        break;
      }
      if (!_checksumOk(h)) throw BadArchiveException('bad tar header');
      final type = h[156];
      final size = int.parse(_text(h, 124, 12).trim().isEmpty ? '0' : _text(h, 124, 12).trim(), radix: 8);
      final headerName = _text(h, 0, 100);
      remaining = size;
      padding = size % 512 == 0 ? 0 : 512 - size % 512;
      skip = false;
      if (type == 'L'.codeUnitAt(0)) {
        isLongName = true;
        memory = BytesBuilder(copy: false);
      } else {
        name = longName ?? headerName;
        longName = null;
        final isFile = type == '0'.codeUnitAt(0) || type == 0;
        final target = isFile ? onEntry(name!) : '';
        if (target == null) {
          memory = BytesBuilder(copy: false);
        } else if (target.isEmpty) {
          skip = true;
        } else {
          final f = File(target);
          f.parent.createSync(recursive: true);
          fileOut = f.openWrite();
        }
      }
      // A skipped entry's data is consumed and dropped (no sink).
      if (remaining == 0 && padding == 0) await finishEntry();
    }
  }
  await finishEntry();
  if (!ended) throw BadArchiveException('archive is cut off');
}

bool _checksumOk(Uint8List h) {
  final stored = _text(h, 148, 8).trim();
  if (stored.isEmpty) return false;
  var sum = 0;
  for (var i = 0; i < 512; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : h[i];
  }
  return int.tryParse(stored, radix: 8) == sum;
}

String _text(Uint8List h, int offset, int length) {
  var end = offset;
  while (end < offset + length && h[end] != 0) {
    end++;
  }
  return utf8.decode(h.sublist(offset, end), allowMalformed: true);
}

/// Replaces the contents of every root that [staged] has (a folder holding
/// `<root>/...` as extracted) with the staged copy; [excluded] paths below
/// a root stay as they are. Roots missing from the staging folder stay.
Future<void> replaceRoots(
  String staged,
  Map<String, String> roots, {
  Set<String> excluded = const {},
  Set<String> keepAlso = const {},
}) async {
  for (final root in roots.entries) {
    final from = Directory('$staged/${root.key}');
    if (!from.existsSync()) continue;
    final to = Directory(root.value);
    if (to.existsSync()) {
      final base = to.absolute.path.replaceAll(r'\', '/');
      for (final e in to.listSync(followLinks: false)) {
        final rel = e.absolute.path
            .replaceAll(r'\', '/')
            .substring(base.length)
            .replaceFirst(RegExp('^/'), '');
        if (isExcluded(rel, {...excluded, ...keepAlso})) continue;
        if (_holdsExcluded(rel, {...excluded, ...keepAlso})) {
          // A folder with something kept inside: clear around it.
          _clearAround(e as Directory, rel, {...excluded, ...keepAlso});
          continue;
        }
        try {
          e.deleteSync(recursive: true);
        } on FileSystemException {
          // In use: overwritten below where the backup has it.
        }
      }
    } else {
      to.createSync(recursive: true);
    }
    final fromBase = from.absolute.path.replaceAll(r'\', '/');
    for (final f in from.listSync(recursive: true, followLinks: false).whereType<File>()) {
      final rel = f.absolute.path
          .replaceAll(r'\', '/')
          .substring(fromBase.length)
          .replaceFirst(RegExp('^/'), '');
      final target = File('${to.path}/$rel');
      target.parent.createSync(recursive: true);
      f.copySync(target.path);
    }
  }
}

bool _holdsExcluded(String rel, Set<String> excluded) =>
    excluded.any((e) => e.startsWith('$rel/'));

void _clearAround(Directory dir, String rel, Set<String> excluded) {
  for (final e in dir.listSync(followLinks: false)) {
    final child = '$rel/${e.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    if (isExcluded(child, excluded)) continue;
    if (e is Directory && _holdsExcluded(child, excluded)) {
      _clearAround(e, child, excluded);
      continue;
    }
    try {
      e.deleteSync(recursive: true);
    } on FileSystemException {
      // In use.
    }
  }
}

/// Deletes [path] (file or folder) if it is there.
void deletePath(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.directory) {
    Directory(path).deleteSync(recursive: true);
  } else {
    File(path).deleteSync();
  }
}

/// Size of the file at [path] in bytes.
int fileSize(String path) => File(path).lengthSync();
