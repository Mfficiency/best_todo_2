import 'dart:async' show unawaited;
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/track.dart';
import '../services/music_library_service.dart';
import '../services/music_metadata_csv.dart';
import 'subpage_app_bar.dart';
import 'track_metadata_page.dart';

/// A "scan" you can run at any time (not just the folder-picker/refresh
/// flow): rescans [Config.musicFolder] and shows every track live as it's
/// found, with a check/warning icon for whether it has a genre and a year —
/// the fields rule/smart playlists read. Tap a row to open
/// [TrackMetadataPage] and fill in whatever's missing.
///
/// Also where bulk metadata editing lives: "Export CSV" hands every scanned
/// track's metadata to the share sheet as a CSV — hand it to an AI (or edit
/// it by hand) to fill in whatever's missing, then "Import CSV" reads the
/// edited file back and applies it, matching rows to tracks by the `id`
/// column ([MusicMetadataCsv]).
class MusicMetadataScanPage extends StatefulWidget {
  const MusicMetadataScanPage({super.key});

  @override
  State<MusicMetadataScanPage> createState() => _MusicMetadataScanPageState();
}

class _MusicMetadataScanPageState extends State<MusicMetadataScanPage> {
  bool _scanning = false;
  final List<Track> _results = [];

  @override
  void initState() {
    super.initState();
    // The first scan starts before this widget's first build, so its
    // "scanning" state is set directly rather than through setState (which
    // Flutter disallows before initState finishes) — _runScan()'s own
    // setState calls only ever happen later, from an async gap.
    _scanning = true;
    unawaited(_runScan());
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _results.clear();
    });
    await _runScan();
  }

  Future<void> _runScan() async {
    await MusicLibraryService.instance.ensureFolderPermission();
    await MusicLibraryService.instance.rescan(
      onTrackScanned: (scanned, track) {
        if (!mounted) return;
        setState(() => _results.add(track));
      },
    );
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _exportCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final tracks = MusicLibraryService.instance.tracks.value;
    if (tracks.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('No tracks to export — scan first.')));
      return;
    }
    try {
      final csv = MusicMetadataCsv.encode(tracks);
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}/besttodo_music_metadata_${_timestampForFilename()}.csv');
      await file.writeAsString(csv, flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: 'BestToDo music metadata',
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV', extensions: ['csv']),
    ]);
    if (file == null) return;
    try {
      final csvText = await File(file.path).readAsString();
      final rows = MusicMetadataCsv.decode(csvText);
      if (rows.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content:
              Text('No rows found — make sure the file still has its "id" column.'),
        ));
        return;
      }
      final applied = await MusicLibraryService.instance.applyMetadataRows(rows);
      if (!mounted) return;
      setState(() {
        // Refresh the already-scanned rows in place so their genre/year
        // status icons reflect the import right away, without a rescan.
        for (var i = 0; i < _results.length; i++) {
          final refreshed = MusicLibraryService.instance.byId(_results[i].id);
          if (refreshed != null) _results[i] = refreshed;
        }
      });
      messenger.showSnackBar(SnackBar(
        content: Text(applied == rows.length
            ? 'Updated $applied track(s)'
            : 'Updated $applied of ${rows.length} row(s) — the rest didn\'t '
                'match a track in your library'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  static String _timestampForFilename() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final withGenre = _results.where((t) => t.genre.isNotEmpty).length;
    final withYear = _results.where((t) => t.year != null).length;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Metadata Scan',
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export metadata CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import filled-in CSV',
            onPressed: _importCsv,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan again',
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _scanning
                  ? 'Scanning… ${_results.length} track(s) found so far'
                  : '${_results.length} track(s) — $withGenre with genre, '
                      '$withYear with year',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(_scanning
                        ? 'Starting…'
                        : 'No tracks found. Set a music folder in Settings first.'),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final track = _results[index];
                      final hasGenre = track.genre.isNotEmpty;
                      final hasYear = track.year != null;
                      final complete = hasGenre && hasYear;
                      final partial = hasGenre || hasYear;
                      return ListTile(
                        leading: Icon(
                          complete
                              ? Icons.check_circle
                              : partial
                                  ? Icons.remove_circle_outline
                                  : Icons.error_outline,
                          color: complete
                              ? Colors.green
                              : partial
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        title: Text(
                            track.title.isNotEmpty ? track.title : track.fileBaseName),
                        subtitle: Text([
                          if (track.artist.isNotEmpty) track.artist,
                          hasGenre ? track.genre : 'no genre',
                          hasYear ? '${track.year}' : 'no year',
                        ].join(' • ')),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TrackMetadataPage(trackId: track.id),
                        )),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
