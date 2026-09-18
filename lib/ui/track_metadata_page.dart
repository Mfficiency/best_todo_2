import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/music_library_service.dart';
import 'subpage_app_bar.dart';

/// Shows (and lets you fill in) one track's metadata — title/artist/album/
/// genre/year, the fields rule/smart playlists read, plus read-only file
/// info (duration, play count, date added, source, path). Reachable from
/// the "info" button on Now Playing and from tapping a row in
/// `MusicMetadataScanPage`.
///
/// Saving only updates this app's cached record of the track (what's
/// actually stored in `music_library.json` and read by playlist rules) —
/// it does not write ID3 tags back into the file itself.
class TrackMetadataPage extends StatefulWidget {
  const TrackMetadataPage({super.key, required this.trackId});

  final String trackId;

  @override
  State<TrackMetadataPage> createState() => _TrackMetadataPageState();
}

class _TrackMetadataPageState extends State<TrackMetadataPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;
  late final TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final track = MusicLibraryService.instance.byId(widget.trackId);
    _titleController = TextEditingController(text: track?.title ?? '');
    _artistController = TextEditingController(text: track?.artist ?? '');
    _albumController = TextEditingController(text: track?.album ?? '');
    _genreController = TextEditingController(text: track?.genre ?? '');
    _yearController = TextEditingController(text: track?.year?.toString() ?? '');
    _tagsController = TextEditingController(text: (track?.tags ?? const []).join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final yearText = _yearController.text.trim();
    final year = yearText.isEmpty ? null : int.tryParse(yearText);
    if (yearText.isNotEmpty && year == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Year must be a number, e.g. 2021')));
      return;
    }
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await MusicLibraryService.instance.updateTrackMetadata(
      widget.trackId,
      title: _titleController.text.trim(),
      artist: _artistController.text.trim(),
      album: _albumController.text.trim(),
      genre: _genreController.text.trim(),
      year: year,
      tags: tags,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, _, __) {
        final track = MusicLibraryService.instance.byId(widget.trackId);
        return Scaffold(
          appBar: buildSubpageAppBar(
            context,
            title: 'Track info',
            actions: [
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'Save',
                onPressed: _save,
              ),
            ],
          ),
          body: track == null
              ? const Center(child: Text('Track not found.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _artistController,
                      decoration: const InputDecoration(labelText: 'Artist'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _albumController,
                      decoration: const InputDecoration(labelText: 'Album'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _genreController,
                      decoration: const InputDecoration(labelText: 'Genre'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _yearController,
                      decoration: const InputDecoration(labelText: 'Year'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags',
                        helperText: 'Comma-separated, e.g. Wedding songs, Belgian Top Charts',
                      ),
                    ),
                    if (track.metadataEdited) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Manually edited — a rescan keeps these values '
                        'instead of overwriting them from the file\'s tags.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],
                    const Divider(height: 32),
                    _infoRow('Duration', _formatDuration(track.durationMs)),
                    _infoRow('Play count', '${track.playCount}'),
                    _infoRow(
                      'Added',
                      track.dateAdded == null
                          ? 'Unknown'
                          : _formatDate(track.dateAdded!),
                    ),
                    _infoRow('Source',
                        track.source == TrackSource.local ? 'Local file' : 'Subsonic'),
                    if (track.filePath != null) _infoRow('File', track.filePath!),
                  ],
                ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  static String _formatDuration(int? ms) {
    if (ms == null) return 'Unknown';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
