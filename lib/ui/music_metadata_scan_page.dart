import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/music_library_service.dart';
import 'subpage_app_bar.dart';
import 'track_metadata_page.dart';

/// A "scan" you can run at any time (not just the folder-picker/refresh
/// flow): rescans [Config.musicFolder] and shows every track live as it's
/// found, with a check/warning icon for whether it has a genre and a year —
/// the fields rule/smart playlists read. Tap a row to open
/// [TrackMetadataPage] and fill in whatever's missing.
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
