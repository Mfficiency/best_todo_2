import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/attachment.dart';
import '../services/attachment_storage_service.dart';

const XTypeGroup _imageTypeGroup = XTypeGroup(
  label: 'images',
  extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
);
const XTypeGroup _pdfTypeGroup = XTypeGroup(
  label: 'pdf',
  extensions: ['pdf'],
);

/// Attachments editor for a task: a "Note"/"Image"/"PDF" add row plus a list
/// of what's already attached, each tappable to view (or open, for a PDF)
/// and removable. Image/PDF attachments are copied into the app documents
/// dir via [AttachmentStorageService]; text notes carry their content inline
/// and never touch the filesystem.
class AttachmentsField extends StatefulWidget {
  final String taskUid;
  final List<Attachment> attachments;
  final ValueChanged<List<Attachment>> onChanged;

  /// When true, attachments can only be viewed/opened — no add row and no
  /// per-item remove button. Used by the read-only task detail page.
  final bool readOnly;

  const AttachmentsField({
    Key? key,
    required this.taskUid,
    required this.attachments,
    required this.onChanged,
    this.readOnly = false,
  }) : super(key: key);

  @override
  State<AttachmentsField> createState() => _AttachmentsFieldState();
}

class _AttachmentsFieldState extends State<AttachmentsField> {
  late List<Attachment> _attachments;

  @override
  void initState() {
    super.initState();
    _attachments = [...widget.attachments];
  }

  @override
  void didUpdateWidget(covariant AttachmentsField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachments != widget.attachments) {
      _attachments = [...widget.attachments];
    }
  }

  void _commit(List<Attachment> next) {
    setState(() => _attachments = next);
    widget.onChanged(next);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(hintText: 'Note text'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _commit([
      ..._attachments,
      Attachment(type: Attachment.typeText, text: text.trim()),
    ]);
  }

  Future<void> _addFile(String type, XTypeGroup typeGroup) async {
    final XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (_) {
      _showError('Could not open file picker');
      return;
    }
    if (picked == null) return;
    try {
      final attachment = await AttachmentStorageService.instance.importFile(
        taskUid: widget.taskUid,
        sourcePath: picked.path,
        type: type,
      );
      _commit([..._attachments, attachment]);
    } catch (_) {
      _showError('Could not attach file');
    }
  }

  Future<void> _removeAt(int index) async {
    final attachment = _attachments[index];
    final next = [..._attachments]..removeAt(index);
    _commit(next);
    await AttachmentStorageService.instance.deleteAttachmentFile(attachment);
  }

  Future<void> _editNote(int index) async {
    final attachment = _attachments[index];
    final controller = TextEditingController(text: attachment.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final next = [..._attachments];
    next[index] = Attachment(
      uid: attachment.uid,
      type: attachment.type,
      text: text.trim(),
      createdAt: attachment.createdAt,
    );
    _commit(next);
  }

  Future<void> _viewImage(Attachment attachment) async {
    final relativePath = attachment.relativePath;
    if (relativePath == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: FutureBuilder<String>(
            future:
                AttachmentStorageService.instance.absolutePath(relativePath),
            builder: (context, snapshot) {
              final path = snapshot.data;
              if (path == null) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return InteractiveViewer(
                child: Image.file(File(path), fit: BoxFit.contain),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openFileAttachment(Attachment attachment) async {
    final relativePath = attachment.relativePath;
    if (relativePath == null) return;
    try {
      final path =
          await AttachmentStorageService.instance.absolutePath(relativePath);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: attachment.fileName),
      );
    } catch (_) {
      _showError('Could not open ${attachment.fileName}');
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case Attachment.typeImage:
        return Icons.image_outlined;
      case Attachment.typePdf:
        return Icons.picture_as_pdf_outlined;
      default:
        return Icons.notes_outlined;
    }
  }

  String _titleFor(Attachment attachment) {
    if (attachment.type == Attachment.typeText) {
      final firstLine = attachment.text.split('\n').first.trim();
      return firstLine.isEmpty ? 'Note' : firstLine;
    }
    return attachment.fileName.isEmpty ? 'Attachment' : attachment.fileName;
  }

  Future<void> _viewNoteReadOnly(Attachment attachment) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Note'),
        content: SingleChildScrollView(child: Text(attachment.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _onTap(int index) {
    final attachment = _attachments[index];
    switch (attachment.type) {
      case Attachment.typeText:
        widget.readOnly ? _viewNoteReadOnly(attachment) : _editNote(index);
        break;
      case Attachment.typeImage:
        _viewImage(attachment);
        break;
      default:
        _openFileAttachment(attachment);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly && _attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Attachments'),
            const Spacer(),
            if (!widget.readOnly) ...[
              IconButton(
                tooltip: 'Add note',
                icon: const Icon(Icons.note_add_outlined),
                onPressed: _addNote,
              ),
              IconButton(
                tooltip: 'Add image',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: () =>
                    _addFile(Attachment.typeImage, _imageTypeGroup),
              ),
              IconButton(
                tooltip: 'Add PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _addFile(Attachment.typePdf, _pdfTypeGroup),
              ),
            ],
          ],
        ),
        for (var i = 0; i < _attachments.length; i++)
          Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(_attachments[i].type)),
              title: Text(
                _titleFor(_attachments[i]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _onTap(i),
              trailing: widget.readOnly
                  ? null
                  : IconButton(
                      tooltip: 'Remove attachment',
                      icon: const Icon(Icons.close),
                      onPressed: () => _removeAt(i),
                    ),
            ),
          ),
      ],
    );
  }
}
