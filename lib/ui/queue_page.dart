import 'package:flutter/material.dart';

import '../services/music_player_service.dart';
import 'subpage_app_bar.dart';

/// Shows the current play queue; drag the handles to reorder it into a
/// custom order (works whether or not shuffle is on — dragging just
/// overrides the current order going forward).
class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  @override
  Widget build(BuildContext context) {
    final handler = MusicPlayerService.handler;
    final tracks = handler.currentQueueTracks;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Queue'),
      body: tracks.isEmpty
          ? const Center(child: Text('Queue is empty'))
          : ReorderableListView.builder(
              buildDefaultDragHandles: true,
              itemCount: tracks.length,
              onReorder: (oldIndex, newIndex) {
                setState(() => handler.reorderQueue(oldIndex, newIndex));
              },
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isCurrent = track.id == handler.currentTrack?.id;
                return ListTile(
                  key: ValueKey(track.id),
                  leading: Icon(
                    isCurrent ? Icons.play_arrow : Icons.music_note,
                    color:
                        isCurrent ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(
                    track.title.isNotEmpty ? track.title : track.fileBaseName,
                    style: isCurrent
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                  subtitle:
                      track.artist.isNotEmpty ? Text(track.artist) : null,
                );
              },
            ),
    );
  }
}
