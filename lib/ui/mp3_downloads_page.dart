import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/mp3_download_manager.dart';
import 'subpage_app_bar.dart';

/// The public `https://youtube.com/watch?v=<id>` URL for a job's source
/// video — used both to open it in a browser/YouTube app and to share it.
String _youtubeUrlFor(Mp3DownloadJob job) =>
    'https://www.youtube.com/watch?v=${job.videoId}';

/// Tools → MP3 Downloader → the downloads button: everything the queue knows
/// about, in one list — what is downloading now, what is waiting, and what
/// already finished (with the path it landed at, or why it failed).
///
/// Reads [Mp3DownloadManager.jobs] directly so progress keeps ticking here
/// even though the download was started from the other page.
class Mp3DownloadsPage extends StatelessWidget {
  const Mp3DownloadsPage({Key? key, Mp3DownloadManager? manager})
      : _manager = manager,
        super(key: key);

  final Mp3DownloadManager? _manager;

  Mp3DownloadManager get _m => _manager ?? Mp3DownloadManager.instance;

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Downloads',
        actions: [
          IconButton(
            tooltip: 'Clear finished',
            icon: const Icon(Icons.clear_all),
            onPressed: () => _m.clearFinished(),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Mp3DownloadJob>>(
        valueListenable: _m.jobs,
        builder: (context, jobs, _) {
          if (jobs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No downloads yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _JobTile(
              job: jobs[index],
              manager: _m,
            ),
          );
        },
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.manager});

  final Mp3DownloadJob job;
  final Mp3DownloadManager manager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = <Widget>[];

    switch (job.status) {
      case Mp3DownloadStatus.queued:
        subtitle.add(const Text('Waiting…'));
        break;
      case Mp3DownloadStatus.running:
        subtitle.add(LinearProgressIndicator(value: job.progress));
        subtitle.add(const SizedBox(height: 4));
        subtitle.add(Text(
          job.totalBytes > 0
              ? '${Mp3DownloadsPage.formatBytes(job.receivedBytes)} of '
                  '${Mp3DownloadsPage.formatBytes(job.totalBytes)} · '
                  '${((job.progress ?? 0) * 100).round()}%'
              : 'Starting…',
          style: theme.textTheme.bodySmall,
        ));
        break;
      case Mp3DownloadStatus.completed:
        subtitle.add(Text(
          'Saved to ${job.filePath ?? job.destinationDir}',
          style: theme.textTheme.bodySmall,
        ));
        break;
      case Mp3DownloadStatus.failed:
        subtitle.add(Text(
          job.error ?? 'Failed',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.error),
        ));
        break;
      case Mp3DownloadStatus.cancelled:
        subtitle.add(Text('Cancelled', style: theme.textTheme.bodySmall));
        break;
    }

    return ListTile(
      leading: _statusIcon(theme),
      title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job.channel.isNotEmpty)
            Text(job.channel, style: theme.textTheme.bodySmall),
          ...subtitle,
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (job.videoId.isNotEmpty) ...[
            IconButton(
              tooltip: 'Open original video',
              icon: const Icon(Icons.smart_display_outlined),
              visualDensity: VisualDensity.compact,
              onPressed: () => _openVideo(context, job),
            ),
            IconButton(
              tooltip: 'Share YouTube link',
              icon: const Icon(Icons.share_outlined),
              visualDensity: VisualDensity.compact,
              onPressed: () => _shareVideoLink(job),
            ),
          ],
          job.isActive
              ? IconButton(
                  tooltip: 'Cancel download',
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => manager.cancel(job.id),
                )
              : IconButton(
                  tooltip: 'Remove from list',
                  icon: const Icon(Icons.delete_outline),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => manager.remove(job.id),
                ),
        ],
      ),
    );
  }

  Future<void> _openVideo(BuildContext context, Mp3DownloadJob job) async {
    final uri = Uri.parse(_youtubeUrlFor(job));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final opened =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(content: Text("Couldn't open the video")),
        );
      }
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't open the video")),
      );
    }
  }

  Future<void> _shareVideoLink(Mp3DownloadJob job) async {
    await SharePlus.instance.share(
      ShareParams(text: _youtubeUrlFor(job), subject: job.title),
    );
  }

  Widget _statusIcon(ThemeData theme) {
    switch (job.status) {
      case Mp3DownloadStatus.queued:
        return const Icon(Icons.schedule);
      case Mp3DownloadStatus.running:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case Mp3DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case Mp3DownloadStatus.failed:
        return Icon(Icons.error_outline, color: theme.colorScheme.error);
      case Mp3DownloadStatus.cancelled:
        return const Icon(Icons.cancel_outlined);
    }
  }
}
