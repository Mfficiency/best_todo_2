import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/bpm_preset.dart';
import '../models/track.dart';
import '../services/music_library_service.dart';
import '../services/music_metadata_enricher.dart';
import '../services/music_player_service.dart';
import '../services/music_playlist_service.dart';
import 'subpage_app_bar.dart';

/// The library songs whose BPM lies within [min]..[max], slowest first
/// (then by title).
List<Track> tracksInBpmRange(List<Track> library, int min, int max) {
  final list = [
    for (final t in library)
      if (t.bpm != null && t.bpm! >= min && t.bpm! <= max) t,
  ];
  list.sort((a, b) {
    final byBpm = a.bpm!.compareTo(b.bpm!);
    return byBpm != 0
        ? byBpm
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return list;
}

/// Lowest and highest BPM in [library]; null when no song has one.
({int min, int max})? bpmBounds(List<Track> library) {
  int? lo, hi;
  for (final t in library) {
    final bpm = t.bpm;
    if (bpm == null) continue;
    if (lo == null || bpm < lo) lo = bpm;
    if (hi == null || bpm > hi) hi = bpm;
  }
  if (lo == null || hi == null) return null;
  return (min: lo, max: hi == lo ? lo + 1 : hi);
}

/// Best Music → Songs by BPM: a two-handled slider picks a BPM range, the
/// library songs in it are listed below, and that list can be played as
/// the queue or saved as a playlist; the range itself can be saved as a
/// preset (chips at the top) to come back to.
class BpmRangePage extends StatefulWidget {
  const BpmRangePage({super.key, this.playQueue});

  /// Starts a queue; defaults to [MusicPlayerService.playQueue]. Tests
  /// pass a recorder.
  final Future<void> Function(List<Track> queue, {int startIndex})? playQueue;

  @override
  State<BpmRangePage> createState() => _BpmRangePageState();
}

class _BpmRangePageState extends State<BpmRangePage> {
  /// The picked range; null until the library's bounds are known.
  RangeValues? _range;

  Future<void> _play(List<Track> list, {int startIndex = 0}) {
    final play = widget.playQueue ?? MusicPlayerService.playQueue;
    return play(list, startIndex: startIndex);
  }

  RangeValues _clamped(({int min, int max}) bounds) {
    final lo = bounds.min.toDouble(), hi = bounds.max.toDouble();
    final r = _range ?? RangeValues(lo, hi);
    final start = r.start.clamp(lo, hi);
    final end = r.end.clamp(start, hi);
    return RangeValues(start, end);
  }

  void _applyPreset(BpmPreset preset, ({int min, int max}) bounds) {
    setState(() => _range = RangeValues(preset.min.toDouble(),
        preset.max.toDouble()));
    final outside = preset.min < bounds.min || preset.max > bounds.max;
    if (outside) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${preset.name}: ${preset.rangeLabel} — your library '
              'only has ${bounds.min}–${bounds.max} BPM')));
    }
  }

  Future<void> _savePreset(int min, int max) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Save BPM preset',
        label: 'Preset name',
        initial: '$min–$max BPM',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      Config.musicBpmPresets = [
        for (final p in Config.musicBpmPresets)
          if (p.name != name) p,
        BpmPreset(name: name, min: min, max: max),
      ];
    });
    await Config.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved preset "$name" ($min–$max BPM)')));
  }

  Future<void> _deletePreset(BpmPreset preset) async {
    setState(() {
      Config.musicBpmPresets = [
        for (final p in Config.musicBpmPresets)
          if (p.name != preset.name) p,
      ];
    });
    await Config.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Deleted preset "${preset.name}"'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          setState(() => Config.musicBpmPresets = [
                ...Config.musicBpmPresets,
                preset,
              ]);
          unawaited(Config.save());
        },
      ),
    ));
  }

  Future<void> _saveAsPlaylist(List<Track> list, int min, int max) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Save as playlist',
        label: 'Playlist name',
        initial: '$min–$max BPM',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await MusicPlaylistService.instance
        .createPlaylist(name, [for (final t in list) t.id]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved playlist "$name" (${list.length} songs)')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Songs by BPM'),
      body: ValueListenableBuilder<List<Track>>(
        valueListenable: MusicLibraryService.instance.tracks,
        builder: (context, library, _) {
          final bounds = bpmBounds(library);
          if (bounds == null) return const _NoBpmYet();
          final range = _clamped(bounds);
          final min = range.start.round(), max = range.end.round();
          final list = tracksInBpmRange(library, min, max);
          final withoutBpm = library.where((t) => t.bpm == null).length;
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Config.musicBpmPresets.isNotEmpty)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    children: [
                      for (final preset in Config.musicBpmPresets)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InputChip(
                            label: Text(
                                '${preset.name} · ${preset.min}–${preset.max}'),
                            selected: preset.min == min && preset.max == max,
                            onPressed: () => _applyPreset(preset, bounds),
                            onDeleted: () => _deletePreset(preset),
                            deleteButtonTooltipMessage:
                                'Delete preset ${preset.name}',
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('$min – $max BPM',
                    key: const ValueKey('bpmRangeLabel'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: RangeSlider(
                  key: const ValueKey('bpmRangeSlider'),
                  values: range,
                  min: bounds.min.toDouble(),
                  max: bounds.max.toDouble(),
                  divisions: bounds.max - bounds.min,
                  labels: RangeLabels('$min', '$max'),
                  onChanged: (v) => setState(() => _range = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${list.length} song${list.length == 1 ? '' : 's'}'
                  '${withoutBpm > 0 ? ' · $withoutBpm without a BPM aren\'t '
                      'shown' : ''}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              // Songs without a BPM get one in the background (online
              // lookup, then on-device detection) — show that it's on it.
              ValueListenableBuilder<String>(
                valueListenable: MusicMetadataEnricher.instance.status,
                builder: (context, status, _) => withoutBpm == 0 ||
                        status.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(status,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall),
                      ),
              ),
              const Divider(),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No songs in this range — widen it '
                              'with the slider.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final t = list[i];
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(t.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: t.artist.isEmpty
                                ? null
                                : Text(t.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            trailing: Text('${t.bpm} BPM'),
                            onTap: () => _play(list, startIndex: i),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: list.isEmpty ? null : () => _play(list),
                        icon: const Icon(Icons.queue_music),
                        label: const Text('Play as queue'),
                      ),
                      OutlinedButton.icon(
                        onPressed: list.isEmpty
                            ? null
                            : () => _saveAsPlaylist(list, min, max),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Save as playlist'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _savePreset(min, max),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save preset'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NoBpmYet extends StatelessWidget {
  const _NoBpmYet();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 64),
            SizedBox(height: 16),
            Text(
              'None of your songs has a BPM yet.\n\n'
              "It's read from your MP3s' BPM tag when the library is "
              'scanned, and filled in automatically in the background — '
              'looked up online, or detected on your phone when it can\'t '
              'be found. You can also type it in on a song\'s Track info '
              'page, or fill in the "bpm" column of the metadata CSV '
              '(Metadata Scan → Export CSV) and import it back.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name; owns its controller (it must outlive the dialog's exit
/// animation).
class _NameDialog extends StatefulWidget {
  const _NameDialog(
      {required this.title, required this.label, required this.initial});

  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
