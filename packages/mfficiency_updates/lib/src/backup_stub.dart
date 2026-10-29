import 'dart:typed_data';

// Off dart:io (the browser): full backups don't exist there.

Never _unsupported() => throw UnsupportedError('Full backups need dart:io');

Future<Map<String, String>> backupRoots() async => _unsupported();
Future<String> scratchDir(String name) async => _unsupported();

class ArchiveStats {
  ArchiveStats(this.files, this.bytes);
  final int files;
  final int bytes;
}

class BadArchiveException implements Exception {
  BadArchiveException(this.message);
  final String message;
}

Future<ArchiveStats> writeArchive({
  required String outPath,
  required Map<String, List<int>> entries,
  required Map<String, String> roots,
  Set<String> excluded = const {},
}) async =>
    _unsupported();

Future<void> readArchive(
  String path, {
  required String? Function(String name) onEntry,
  void Function(String name, Uint8List bytes)? onBytes,
}) async =>
    _unsupported();

Future<void> replaceRoots(
  String staged,
  Map<String, String> roots, {
  Set<String> excluded = const {},
  Set<String> keepAlso = const {},
}) async =>
    _unsupported();

bool anyFile(Map<String, String> roots, Set<String> excluded) => _unsupported();
void deletePath(String path) => _unsupported();
int fileSize(String path) => _unsupported();
