import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/shared_payload.dart';
import '../models/task.dart';
import '../services/auto_tag_service.dart';
import '../services/share_intent_service.dart';

enum ShareBucket { today, inbox }

/// The very small screen a share (from Chrome, YouTube, Maps, Gmail,
/// Photos, ...) opens into: a title/description prefilled from the shared
/// content (see [ShareIntentService.buildDraftTask]), the file(s) that came
/// with it, and one tap to save to Today or the Inbox (an undated task,
/// which lands in the Future tab like any other undated task). Saving (or
/// discarding) hands the app back to whatever was sharing — see
/// [ShareIntentService.returnToPreviousApp].
class QuickAddSharePage extends StatefulWidget {
  final SharedPayload payload;

  const QuickAddSharePage({Key? key, required this.payload}) : super(key: key);

  @override
  State<QuickAddSharePage> createState() => _QuickAddSharePageState();
}

class _QuickAddSharePageState extends State<QuickAddSharePage> {
  late final String _taskUid = Task.newUid();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  // Whether _finish() already ran (Save or the close button) — dispose()
  // uses this to also return to the sharing app on a bare back-gesture
  // dismissal, without double-firing the platform call.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final draft = ShareIntentService.buildDraftTask(widget.payload);
    _titleController = TextEditingController(text: draft.title);
    _descriptionController = TextEditingController(text: draft.description);
  }

  @override
  void dispose() {
    if (!_finished) unawaited(ShareIntentService.instance.returnToPreviousApp());
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save(ShareBucket bucket) async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final attachments = await ShareIntentService.importAttachments(
      _taskUid,
      widget.payload.files,
    );
    final task = Task(
      uid: _taskUid,
      title: title,
      description: _descriptionController.text.trim(),
      label: AutoTagService.instance
          .withAutoTags(title, ShareIntentService.sharedLabel),
      createdAt: now,
      dueDate: bucket == ShareBucket.today
          ? DateTime(now.year, now.month, now.day)
          : Task.futureBucketMarker,
      attachments: attachments,
    );
    await ShareIntentService.instance.saveTask(task);
    _finish();
  }

  void _discard() {
    if (_saving) return;
    _finish();
  }

  void _finish() {
    _finished = true;
    unawaited(ShareIntentService.instance.returnToPreviousApp());
    if (mounted) Navigator.of(context).maybePop();
  }

  Widget _attachmentPreview(SharedFile file) {
    if (file.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(file.path),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined),
        ),
      );
    }
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.picture_as_pdf_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.payload.files;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Add to BestToDo'),
        actions: [
          IconButton(
            tooltip: 'Discard',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : _discard,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                maxLines: null,
                decoration: const InputDecoration(labelText: 'Title'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              if (files.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: files.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _attachmentPreview(files[i]),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                FilledButton.icon(
                  onPressed: () => _save(ShareBucket.today),
                  icon: const Icon(Icons.today_outlined),
                  label: const Text('Save to Today'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _save(ShareBucket.inbox),
                  icon: const Icon(Icons.inbox_outlined),
                  label: const Text('Save to Inbox'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
