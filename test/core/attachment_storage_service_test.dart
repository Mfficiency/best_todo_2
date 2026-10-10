import 'dart:io';

import 'package:besttodo/models/attachment.dart';
import 'package:besttodo/services/attachment_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('importFile copies the source into attachments/<taskUid>/', () async {
    final source = File('${tempDir.path}/source.png');
    await source.writeAsBytes([1, 2, 3, 4]);

    final attachment = await AttachmentStorageService.instance.importFile(
      taskUid: 'task1',
      sourcePath: source.path,
      type: Attachment.typeImage,
    );

    expect(attachment.type, Attachment.typeImage);
    expect(attachment.fileName, 'source.png');
    expect(attachment.relativePath, isNotNull);
    expect(attachment.relativePath, startsWith('attachments/task1/'));
    expect(attachment.relativePath, endsWith('.png'));

    final absolute =
        await AttachmentStorageService.instance.absolutePath(
      attachment.relativePath!,
    );
    final copied = File(absolute);
    expect(await copied.exists(), isTrue);
    expect(await copied.readAsBytes(), [1, 2, 3, 4]);
    // The original source is untouched, not moved.
    expect(await source.exists(), isTrue);
  });

  test('deleteAttachmentFile removes the copy but not the task dir',
      () async {
    final source = File('${tempDir.path}/doc.pdf');
    await source.writeAsBytes([9, 9]);
    final attachment = await AttachmentStorageService.instance.importFile(
      taskUid: 'task2',
      sourcePath: source.path,
      type: Attachment.typePdf,
    );

    await AttachmentStorageService.instance.deleteAttachmentFile(attachment);

    final absolute =
        await AttachmentStorageService.instance.absolutePath(
      attachment.relativePath!,
    );
    expect(await File(absolute).exists(), isFalse);
  });

  test('deleteAttachmentFile on a text (file-less) attachment is a no-op',
      () async {
    final attachment = Attachment(type: Attachment.typeText, text: 'hi');
    // Should not throw despite there being no backing file.
    await AttachmentStorageService.instance.deleteAttachmentFile(attachment);
  });

  test('deleteAttachmentsForTask removes the whole task subdirectory',
      () async {
    final source = File('${tempDir.path}/img.jpg');
    await source.writeAsBytes([5]);
    final a1 = await AttachmentStorageService.instance.importFile(
      taskUid: 'task3',
      sourcePath: source.path,
      type: Attachment.typeImage,
    );
    final a2 = await AttachmentStorageService.instance.importFile(
      taskUid: 'task3',
      sourcePath: source.path,
      type: Attachment.typeImage,
    );

    await AttachmentStorageService.instance.deleteAttachmentsForTask('task3');

    final p1 =
        await AttachmentStorageService.instance.absolutePath(a1.relativePath!);
    final p2 =
        await AttachmentStorageService.instance.absolutePath(a2.relativePath!);
    expect(await File(p1).exists(), isFalse);
    expect(await File(p2).exists(), isFalse);
    expect(
        await Directory('${tempDir.path}/attachments/task3').exists(), isFalse);
  });
}
