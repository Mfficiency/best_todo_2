import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/attachment.dart';

/// Copies picked image/PDF files into the app documents dir so attachments
/// survive independently of wherever the user originally picked them from
/// (a share-sheet cache dir, a Downloads folder that gets cleared, etc.).
/// Text attachments need no file and never touch this service.
class AttachmentStorageService {
  AttachmentStorageService._();
  static final AttachmentStorageService instance =
      AttachmentStorageService._();

  static const String rootDirName = 'attachments';

  static String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  Future<Directory> _rootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/$rootDirName');
  }

  /// Copies the bytes at [sourcePath] into
  /// `attachments/<taskUid>/<attachmentUid>.<ext>` and returns an
  /// [Attachment] pointing at it. [relativePath] is stored relative to the
  /// documents dir so it stays valid regardless of where that dir sits on a
  /// given install.
  Future<Attachment> importFile({
    required String taskUid,
    required String sourcePath,
    required String type,
  }) async {
    final root = await _rootDir();
    final taskDir = Directory('${root.path}/$taskUid');
    await taskDir.create(recursive: true);
    final uid = Attachment.newUid();
    final originalName = _basename(sourcePath);
    final dot = originalName.lastIndexOf('.');
    final ext = dot > 0 ? originalName.substring(dot + 1) : '';
    final storedName = ext.isEmpty ? uid : '$uid.$ext';
    final destFile = File('${taskDir.path}/$storedName');
    await destFile.writeAsBytes(await File(sourcePath).readAsBytes());
    return Attachment(
      uid: uid,
      type: type,
      fileName: originalName,
      relativePath: '$rootDirName/$taskUid/$storedName',
    );
  }

  /// Resolves an [Attachment.relativePath] to an absolute on-disk path.
  Future<String> absolutePath(String relativePath) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$relativePath';
  }

  /// Deletes the on-disk file backing [attachment], if any. Best-effort —
  /// failures (already gone, unsupported platform) are swallowed.
  Future<void> deleteAttachmentFile(Attachment attachment) async {
    final relativePath = attachment.relativePath;
    if (relativePath == null) return;
    try {
      final file = File(await absolutePath(relativePath));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Deletes every attachment file kept for [taskUid] (its whole
  /// subdirectory). Used once a task is purged for good, e.g. the deleted
  /// bin's age-based retention sweep.
  Future<void> deleteAttachmentsForTask(String taskUid) async {
    try {
      final root = await _rootDir();
      final dir = Directory('${root.path}/$taskUid');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
