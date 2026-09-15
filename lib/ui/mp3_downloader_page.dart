import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../services/log_service.dart';
import '../services/mp3_download_manager.dart';
import '../services/mp3_downloader_service.dart';
import 'mp3_downloads_page.dart';
import 'subpage_app_bar.dart';

/// Tools → MP3 Downloader: paste a YouTube URL, or type a title to search,
/// and save the video's audio. A pasted URL downloads straight away; a text
/// query shows up to 5 candidates (title, channel, duration, play count) so
/// the ambiguous case — "which video did they mean?" — is the user's call,
/// not a guess. Play count is usually the quickest way to tell the real
/// upload from a reupload.
///
/// The page only *queues* work: [Mp3DownloadManager] owns the transfer, so
/// leaving this page or backgrounding the app doesn't interrupt it, and the
/// download button in the app bar shows what is still running.
///
/// Saves the audio-only stream as delivered (`.m4a`/AAC or `.webm`/Opus)
/// rather than transcoding to a literal `.mp3` — see
/// [Mp3DownloaderService]'s doc comment for why (a real MP3 encoder would
/// have added 100+ MB to the app).
class Mp3DownloaderPage extends StatefulWidget {
  const Mp3DownloaderPage({
    Key? key,
    Mp3DownloaderService? service,
    Mp3DownloadManager? manager,
  })  : _service = service,
        _manager = manager,
        super(key: key);

  final Mp3DownloaderService? _service;
  final Mp3DownloadManager? _manager;

  @override
  State<Mp3DownloaderPage> createState() => _Mp3DownloaderPageState();
}

enum _Stage { idle, searching, picking, error }

class _Mp3DownloaderPageState extends State<Mp3DownloaderPage> {
  late final Mp3DownloaderService _service =
      widget._service ?? Mp3DownloaderService.instance;
  late final Mp3DownloadManager _manager =
      widget._manager ?? Mp3DownloadManager.instance;
  final TextEditingController _controller = TextEditingController();

  _Stage _stage = _Stage.idle;
  List<Mp3SearchResult> _results = <Mp3SearchResult>[];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _manager.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    final hours = duration.inHours;
    final mm = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$mm';
    }
    return '$minutes:$mm';
  }

  /// The folder downloads go to. Asks once, remembers the answer in
  /// [Config.mp3DownloadFolder], and never prompts again — it can be changed
  /// in Settings → MP3 Downloader.
  Future<String?> _ensureDownloadFolder() async {
    final saved = Config.mp3DownloadFolder.trim();
    if (saved.isNotEmpty) return saved;
    String? initial;
    try {
      initial = (await getDownloadsDirectory())?.path;
    } catch (_) {
      initial = null;
    }
    final picked = await getDirectoryPath(initialDirectory: initial);
    if (picked == null) return null;
    Config.mp3DownloadFolder = picked;
    await Config.save();
    LogService.add('MP3', 'Download folder set to $picked');
    return picked;
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _Stage.searching;
      _errorMessage = null;
      _results = <Mp3SearchResult>[];
    });
    try {
      if (looksLikeYoutubeUrl(input)) {
        final result = await _service.resolve(input);
        if (!mounted) return;
        setState(() => _stage = _Stage.idle);
        await _queueDownload(result);
        return;
      }
      final results = await _service.search(input, limit: 5);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _stage = _Stage.error;
          _errorMessage = 'No results found for "$input"';
        });
        return;
      }
      setState(() {
        _stage = _Stage.picking;
        _results = results;
      });
    } catch (e) {
      if (!mounted) return;
      final verb = looksLikeYoutubeUrl(input) ? 'Lookup' : 'Search';
      setState(() {
        _stage = _Stage.error;
        _errorMessage = '$verb failed: $e';
      });
    }
  }

  Future<void> _queueDownload(Mp3SearchResult result) async {
    final folder = await _ensureDownloadFolder();
    if (!mounted || folder == null) return;
    _manager.enqueue(result, folder);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "${result.title}"'),
        action: SnackBarAction(
          label: 'Show',
          onPressed: _openDownloads,
        ),
      ),
    );
  }

  void _openDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Mp3DownloadsPage(manager: _manager),
      ),
    );
  }

  void _reset() {
    setState(() {
      _stage = _Stage.idle;
      _results = <Mp3SearchResult>[];
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) {
      return Scaffold(
        appBar: buildSubpageAppBar(context, title: 'MP3 Downloader'),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "The MP3 Downloader isn't supported on this platform.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'MP3 Downloader',
        actions: [_buildDownloadsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: _stage != _Stage.searching,
              decoration: const InputDecoration(
                labelText: 'YouTube URL or video title',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 4),
            Text(
              'Saves as M4A or WebM (the original audio, not re-encoded)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _stage == _Stage.searching ? null : _submit,
              child: const Text('Find & download'),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  /// Download button with a badge counting whatever is still in flight, so
  /// the queue is visible from here without opening it.
  Widget _buildDownloadsButton() {
    return ValueListenableBuilder<List<Mp3DownloadJob>>(
      valueListenable: _manager.jobs,
      builder: (context, jobs, _) {
        final active = jobs.where((j) => j.isActive).length;
        final button = IconButton(
          tooltip: 'Downloads',
          icon: const Icon(Icons.download),
          onPressed: _openDownloads,
        );
        if (active == 0) return button;
        return Badge.count(count: active, child: button);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.idle:
        return const SizedBox.shrink();
      case _Stage.searching:
        return const Center(child: CircularProgressIndicator());
      case _Stage.picking:
        return ListView.separated(
          itemCount: _results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = _results[index];
            final plays = formatViewCount(result.viewCount);
            return ListTile(
              title: Text(result.title,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${result.channel} · ${_formatDuration(result.duration)}'
                '${plays.isEmpty ? '' : ' · $plays plays'}',
              ),
              trailing: const Icon(Icons.download),
              onTap: () => _queueDownload(result),
            );
          },
        );
      case _Stage.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Something went wrong',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reset, child: const Text('Try again')),
            ],
          ),
        );
    }
  }
}
