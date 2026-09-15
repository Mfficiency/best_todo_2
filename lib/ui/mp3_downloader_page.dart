import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/mp3_downloader_service.dart';
import 'subpage_app_bar.dart';

/// Tools → MP3 Downloader: paste a YouTube URL, or type a title to search,
/// and save the video's audio as an .mp3 file. A pasted URL downloads
/// straight away; a text query shows up to 5 candidates (title, channel,
/// duration) so the ambiguous case — "which video did they mean?" — is the
/// user's call, not a guess.
class Mp3DownloaderPage extends StatefulWidget {
  const Mp3DownloaderPage({Key? key, Mp3DownloaderService? service})
      : _service = service,
        super(key: key);

  final Mp3DownloaderService? _service;

  @override
  State<Mp3DownloaderPage> createState() => _Mp3DownloaderPageState();
}

enum _Stage { idle, searching, picking, downloading, done, error }

class _Mp3DownloaderPageState extends State<Mp3DownloaderPage> {
  late final Mp3DownloaderService _service =
      widget._service ?? Mp3DownloaderService.instance;
  final TextEditingController _controller = TextEditingController();

  _Stage _stage = _Stage.idle;
  List<Mp3SearchResult> _results = <Mp3SearchResult>[];
  String? _errorMessage;
  String? _savedPath;
  double _progress = 0;

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

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _stage = _Stage.searching;
      _errorMessage = null;
      _savedPath = null;
      _results = <Mp3SearchResult>[];
    });
    try {
      if (looksLikeYoutubeUrl(input)) {
        final result = await _service.resolve(input);
        await _startDownload(result);
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

  Future<void> _startDownload(Mp3SearchResult result) async {
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _errorMessage = null;
    });
    try {
      final downloads = await getDownloadsDirectory();
      final directory =
          await getDirectoryPath(initialDirectory: downloads?.path);
      if (!mounted) return;
      if (directory == null) {
        setState(() => _stage = _Stage.idle);
        return;
      }
      final path = await _service.downloadMp3(
        result,
        directory,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _savedPath = path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = 'Download failed: $e';
      });
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.idle;
      _results = <Mp3SearchResult>[];
      _errorMessage = null;
      _savedPath = null;
      _progress = 0;
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
      appBar: buildSubpageAppBar(context, title: 'MP3 Downloader'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              enabled: _stage != _Stage.searching &&
                  _stage != _Stage.downloading,
              decoration: const InputDecoration(
                labelText: 'YouTube URL or video title',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
              textInputAction: TextInputAction.search,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_stage == _Stage.searching ||
                      _stage == _Stage.downloading)
                  ? null
                  : _submit,
              child: const Text('Find & download'),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
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
            return ListTile(
              title: Text(result.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${result.channel} · ${_formatDuration(result.duration)}',
              ),
              trailing: const Icon(Icons.download),
              onTap: () => _startDownload(result),
            );
          },
        );
      case _Stage.downloading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: _progress > 0 ? _progress : null,
              ),
              const SizedBox(height: 12),
              Text('Downloading… ${(_progress * 100).round()}%'),
            ],
          ),
        );
      case _Stage.done:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              Text('Saved to $_savedPath', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _reset,
                child: const Text('Download another'),
              ),
            ],
          ),
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
