import 'dart:async' show unawaited;
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../services/log_service.dart';
import '../services/mp3_download_manager.dart';
import '../services/mp3_downloader_service.dart';
import '../services/music_share_link.dart';
import '../services/share_intent_service.dart';
import '../services/track_title.dart';
import 'mp3_downloads_page.dart';
import 'subpage_app_bar.dart';

/// Tools → MP3 Downloader: paste a YouTube URL, a playlist link, or type a
/// title to search, and save audio. A pasted video URL downloads straight
/// away; a text query shows up to 5 candidates (title, channel, duration,
/// play count) so the ambiguous case — "which video did they mean?" — is
/// the user's call, not a guess. Play count is usually the quickest way to
/// tell the real upload from a reupload.
///
/// A pasted playlist link instead shows every track with a checkbox, all
/// pre-selected except ones already sitting — under the same
/// "Artist - Title" name a fresh download would use — in the download
/// folder, the phone's standard Music folder (or, if Settings → MP3
/// Downloader has one configured instead, that folder), or any of their
/// subfolders — so re-pasting a list you've partly downloaded before only
/// offers to fetch what's missing.
///
/// The page only *queues* work: [Mp3DownloadManager] owns the transfer, so
/// leaving this page or backgrounding the app doesn't interrupt it, and the
/// download button in the app bar shows what is still running.
///
/// Also the destination for a Spotify, YouTube or Shazam link shared into
/// BestToDo (see [MusicShareLink]/`main.dart`): [sharedLink] feeds this same
/// search box automatically, so a shared YouTube link downloads immediately
/// and a Spotify/Shazam link (resolved to a search query via
/// [MusicLinkResolverService]) lands straight on the candidate picker below.
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
    MusicLinkResolverService? resolver,
    this.sharedLink,
  })  : _service = service,
        _manager = manager,
        _resolver = resolver,
        super(key: key);

  final Mp3DownloaderService? _service;
  final Mp3DownloadManager? _manager;
  final MusicLinkResolverService? _resolver;

  /// Set when this page was opened from the Android share sheet (a Spotify,
  /// YouTube or Shazam link shared into BestToDo — see `main.dart`) rather
  /// than from Tools. Drives the search box straight from the link instead
  /// of waiting for the user to type, and swaps the app bar for one that can
  /// hand control back to the sharing app.
  final MusicShareLink? sharedLink;

  @override
  State<Mp3DownloaderPage> createState() => _Mp3DownloaderPageState();
}

enum _Stage { idle, searching, picking, playlist, error }

enum _UnwritableFolderChoice { grantPermission, useFallback }

class _Mp3DownloaderPageState extends State<Mp3DownloaderPage> {
  late final Mp3DownloaderService _service =
      widget._service ?? Mp3DownloaderService.instance;
  late final Mp3DownloadManager _manager =
      widget._manager ?? Mp3DownloadManager.instance;
  late final MusicLinkResolverService _resolver =
      widget._resolver ?? MusicLinkResolverService.instance;
  final TextEditingController _controller = TextEditingController();

  _Stage _stage = _Stage.idle;
  List<Mp3SearchResult> _results = <Mp3SearchResult>[];
  String? _errorMessage;

  Mp3PlaylistInfo? _playlistInfo;
  String? _playlistFolder;
  Set<String> _selectedVideoIds = <String>{};
  Set<String> _alreadyDownloadedVideoIds = <String>{};

  // Whether _finishShare() already ran — dispose() uses this to also return
  // to the sharing app on a bare back-gesture dismissal, without
  // double-firing the platform call. Mirrors QuickAddSharePage.
  bool _shareFinished = false;

  @override
  void initState() {
    super.initState();
    _manager.load();
    final sharedLink = widget.sharedLink;
    if (sharedLink != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleSharedLink(sharedLink));
    }
  }

  @override
  void dispose() {
    if (widget.sharedLink != null && !_shareFinished) {
      unawaited(ShareIntentService.instance.returnToPreviousApp());
    }
    _controller.dispose();
    super.dispose();
  }

  /// Resolves the shared link into a search query (straight through for a
  /// YouTube link, a page-title lookup for Spotify/Shazam — see
  /// [MusicLinkResolverService]) and feeds it into the same [_submit] path a
  /// typed query uses, so a YouTube link downloads immediately and a
  /// Spotify/Shazam link lands on the usual candidate picker.
  Future<void> _handleSharedLink(MusicShareLink link) async {
    setState(() {
      _stage = _Stage.searching;
      _errorMessage = null;
    });
    try {
      final query = await _resolver.resolveSearchQuery(link);
      if (!mounted) return;
      _controller.text = query;
      await _submit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = "Couldn't use the shared link: $e";
      });
    }
  }

  void _finishShare() {
    _shareFinished = true;
    unawaited(ShareIntentService.instance.returnToPreviousApp());
    if (mounted) Navigator.of(context).maybePop();
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
  ///
  /// The picked folder is write-tested before it is stored. On Android the
  /// picker will happily return a shared path like
  /// `/storage/emulated/0/Music` that scoped storage forbids this app from
  /// writing to without "All files access" — catching that here offers to
  /// request the permission (so the folder the user actually picked works)
  /// before falling back to the app's own storage.
  Future<String?> _ensureDownloadFolder() async {
    final saved = Config.mp3DownloadFolder.trim();
    if (saved.isNotEmpty) return saved;

    final fallback = await defaultDownloadFolder();
    final picked = await getDirectoryPath(initialDirectory: fallback);
    if (picked == null || !mounted) return null;

    var target = picked;
    if (!await canWriteToFolder(target)) {
      LogService.add('MP3', 'Folder $target is not writable');
      if (!mounted) return null;
      target = await _resolveUnwritableFolder(target, fallback) ?? '';
      if (target.isEmpty) return null;
    }

    Config.mp3DownloadFolder = target;
    await Config.save();
    LogService.add('MP3', 'Download folder set to $target');
    return target;
  }

  /// [picked] failed the write test. Offers to request Android's "All files
  /// access" permission so [picked] itself becomes writable; only if that's
  /// unavailable or still doesn't work does it fall back to [fallback].
  /// Returns the folder to use, or null if the user cancelled.
  Future<String?> _resolveUnwritableFolder(
      String picked, String? fallback) async {
    final canRequestPermission = Platform.isAndroid &&
        !await Permission.manageExternalStorage.isGranted;
    final choice = await _confirmUnwritableFolder(picked, fallback,
        canRequestPermission: canRequestPermission);
    if (choice == null) return null;
    if (choice == _UnwritableFolderChoice.useFallback) return fallback;

    await Permission.manageExternalStorage.request();
    if (!mounted) return null;
    if (await canWriteToFolder(picked)) {
      LogService.add('MP3', 'Permission granted; using $picked');
      return picked;
    }
    LogService.add('MP3', 'Permission not granted; $picked still not writable');
    if (!mounted) return null;
    final useFallback = fallback == null
        ? false
        : await _confirmFallbackFolder(picked, fallback);
    return useFallback == true ? fallback : null;
  }

  Future<_UnwritableFolderChoice?> _confirmUnwritableFolder(
    String picked,
    String? fallback, {
    required bool canRequestPermission,
  }) {
    return showDialog<_UnwritableFolderChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Can't save there"),
        content: Text(
          canRequestPermission
              ? "Android won't let the app write to $picked — apps can only "
                  'write to shared folders once you grant "All files '
                  'access". Grant it to save there, or save to the app\'s '
                  'own folder instead.'
              : fallback == null
                  ? "Android won't let the app write to $picked. Pick a "
                      'different folder.'
                  : "Android won't let the app write to $picked — apps can "
                      'only write to their own storage unless you grant a '
                      'permission this app does not ask for.\n\nSave to '
                      '$fallback instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (fallback != null)
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pop(_UnwritableFolderChoice.useFallback),
              child: const Text('Use that folder'),
            ),
          if (canRequestPermission)
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(_UnwritableFolderChoice.grantPermission),
              child: const Text('Grant permission'),
            ),
        ],
      ),
    );
  }

  Future<bool?> _confirmFallbackFolder(String picked, String fallback) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Still can't save there"),
        content: Text(
          "Permission wasn't granted, so Android still won't let the app "
          'write to $picked.\n\nSave to $fallback instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Use that folder'),
          ),
        ],
      ),
    );
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
      if (looksLikeYoutubePlaylistUrl(input)) {
        await _resolvePlaylistInput(input);
        return;
      }
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
      final verb = looksLikeYoutubePlaylistUrl(input)
          ? 'Playlist lookup'
          : looksLikeYoutubeUrl(input)
              ? 'Lookup'
              : 'Search';
      setState(() {
        _stage = _Stage.error;
        _errorMessage = '$verb failed: $e';
      });
    }
  }

  /// Resolves a playlist link into its track list, then asks for (or
  /// reuses) the download folder to work out which tracks are already
  /// saved there — those start out unchecked rather than being hidden, so
  /// picking one back up is still one tap away.
  ///
  /// "Already saved" is checked against the download folder itself plus the
  /// phone's actual Music folder (or whatever folder Settings → MP3
  /// Downloader has been told to compare against instead) — see
  /// [compareFoldersFor] — since tracks this app downloaded may not be the
  /// only place a title already exists on the phone.
  Future<void> _resolvePlaylistInput(String input) async {
    final info = await _service.resolvePlaylist(input);
    if (!mounted) return;
    final folder = await _ensureDownloadFolder();
    if (!mounted) return;
    if (folder == null) {
      setState(() => _stage = _Stage.idle);
      return;
    }
    final compareFolders = await compareFoldersFor(
      folder,
      configuredCompareFolder: Config.mp3CompareFolder,
    );
    if (!mounted) return;
    final existing = await existingTrackBaseNamesAcross(compareFolders);
    if (!mounted) return;
    final alreadyDownloaded = <String>{};
    final toSelect = <String>{};
    for (final track in info.tracks) {
      final baseName =
          parseTrackTitle(track.title, track.channel).fileBaseName.toLowerCase();
      if (existing.contains(baseName)) {
        alreadyDownloaded.add(track.videoId);
      } else {
        toSelect.add(track.videoId);
      }
    }
    setState(() {
      _stage = _Stage.playlist;
      _playlistInfo = info;
      _playlistFolder = folder;
      _alreadyDownloadedVideoIds = alreadyDownloaded;
      _selectedVideoIds = toSelect;
    });
  }

  Future<void> _queueSelectedPlaylistTracks() async {
    final info = _playlistInfo;
    final folder = _playlistFolder;
    if (info == null || folder == null) return;
    final selected =
        info.tracks.where((t) => _selectedVideoIds.contains(t.videoId)).toList();
    for (final track in selected) {
      _manager.enqueue(track, folder);
    }
    if (!mounted) return;
    _reset();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloading ${selected.length} '
          '${selected.length == 1 ? 'track' : 'tracks'}',
        ),
        action: SnackBarAction(label: 'Show', onPressed: _openDownloads),
      ),
    );
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
      _playlistInfo = null;
      _playlistFolder = null;
      _selectedVideoIds = <String>{};
      _alreadyDownloadedVideoIds = <String>{};
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
    final fromShare = widget.sharedLink != null;
    return Scaffold(
      appBar: fromShare
          ? AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Find & Download Song'),
              actions: [
                _buildDownloadsButton(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _finishShare,
                ),
              ],
            )
          : buildSubpageAppBar(
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
                labelText: 'YouTube URL, playlist link, or video title',
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
            const SizedBox(height: 12),
            _buildQueueStatus(context),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  /// Live status for the queue, right under the search box.
  ///
  /// A failure has to be visible *here* — the page you are looking at —
  /// rather than only in the downloads list: the bug this replaces left a
  /// spinner at 0% with no way to find out what went wrong. A failed job
  /// shows its reason in full, in the error colour, with a retry.
  Widget _buildQueueStatus(BuildContext context) {
    return ValueListenableBuilder<List<Mp3DownloadJob>>(
      valueListenable: _manager.jobs,
      builder: (context, jobs, _) {
        final theme = Theme.of(context);
        final failed = jobs
            .where((j) => j.status == Mp3DownloadStatus.failed)
            .toList();
        final running = jobs
            .where((j) => j.status == Mp3DownloadStatus.running)
            .toList();
        final queued =
            jobs.where((j) => j.status == Mp3DownloadStatus.queued).length;

        final cards = <Widget>[];

        if (failed.isNotEmpty) {
          final job = failed.first;
          cards.add(Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Couldn't download \"${job.title}\"",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    job.error ?? 'Unknown error',
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _manager.remove(job.id),
                        child: const Text('Dismiss'),
                      ),
                      TextButton(
                        onPressed: () => _retry(job),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ));
        }

        if (running.isNotEmpty) {
          final job = running.first;
          cards.add(Card(
            child: ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text(job.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: job.progress),
                  const SizedBox(height: 4),
                  Text(
                    job.totalBytes > 0
                        ? '${((job.progress ?? 0) * 100).round()}%'
                            '${queued > 0 ? ' · $queued waiting' : ''}'
                        : 'Contacting YouTube…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Cancel download',
                icon: const Icon(Icons.close),
                onPressed: () => _manager.cancel(job.id),
              ),
              onTap: _openDownloads,
            ),
          ));
        }

        if (cards.isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: cards),
        );
      },
    );
  }

  Future<void> _retry(Mp3DownloadJob job) async {
    await _manager.remove(job.id);
    if (!mounted) return;
    _manager.enqueue(
      Mp3SearchResult(
        videoId: job.videoId,
        title: job.title,
        channel: job.channel,
        duration: null,
        uploadDate: job.uploadDate,
      ),
      job.destinationDir,
    );
  }

  /// The playlist stage: every track with a checkbox, "All"/"None" to bulk
  /// (re)select, and a "Download N" button that queues whatever's checked.
  Widget _buildPlaylistPicker(BuildContext context) {
    final info = _playlistInfo!;
    final tracks = info.tracks;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${info.title} · ${_selectedVideoIds.length} of '
                '${tracks.length} selected',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () => setState(
                () => _selectedVideoIds =
                    tracks.map((t) => t.videoId).toSet(),
              ),
              child: const Text('All'),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedVideoIds = <String>{}),
              child: const Text('None'),
            ),
          ],
        ),
        Expanded(
          child: ListView.separated(
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final alreadyDownloaded =
                  _alreadyDownloadedVideoIds.contains(track.videoId);
              final plays = formatViewCount(track.viewCount);
              return CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: _selectedVideoIds.contains(track.videoId),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _selectedVideoIds.add(track.videoId);
                  } else {
                    _selectedVideoIds.remove(track.videoId);
                  }
                }),
                title: Text(track.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  alreadyDownloaded
                      ? 'Already downloaded'
                      : '${track.channel} · ${_formatDuration(track.duration)}'
                          '${plays.isEmpty ? '' : ' · $plays plays'}',
                  style: alreadyDownloaded
                      ? theme.textTheme.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic)
                      : null,
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _reset,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _selectedVideoIds.isEmpty
                      ? null
                      : _queueSelectedPlaylistTracks,
                  child: Text('Download ${_selectedVideoIds.length}'),
                ),
              ),
            ],
          ),
        ),
      ],
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
      case _Stage.playlist:
        return _buildPlaylistPicker(context);
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
