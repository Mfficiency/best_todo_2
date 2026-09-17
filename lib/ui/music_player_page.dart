import 'dart:async' show unawaited;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/music_playlist.dart';
import '../models/track.dart';
import '../services/m3u_playlist_service.dart';
import '../services/music_audio_handler.dart';
import '../services/music_library_service.dart';
import '../services/music_player_service.dart';
import '../services/music_playlist_service.dart';
import '../services/update_service.dart';
import 'auto_update_dialog.dart';
import 'mp3_downloader_page.dart';
import 'now_playing_page.dart';
import 'subpage_app_bar.dart';

/// Tools → Music Player: browse/play tracks scanned from
/// [Config.musicFolder] (and, once configured, a Subsonic server), manage
/// Favorites/"Don't really like" and imported playlists, and import an
/// M3U/M3U8 playlist (e.g. shared out of Samsung Music).
///
/// Also the Best Music app's home page ([standalone]: true), where it is the
/// root route rather than a BestToDo Tools subpage — no drawer to reach for
/// "Menu"/"Back to Home", and its own MP3 Downloader + update-check actions
/// stand in for BestToDo's drawer entry and About page.
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key, this.standalone = false});

  final bool standalone;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _pickingFolder = false;
  bool _checkingForUpdates = false;

  static final UpdateService _musicUpdateService = UpdateService.forApp(
    appDisplayName: 'Best Music',
    apkPrefix: 'best_music',
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // The MP3 Downloader's folder is the common case for where music already
    // lives, so default straight to it instead of asking the user to pick
    // the same folder twice.
    if (Config.musicFolder.isEmpty && Config.mp3DownloadFolder.isNotEmpty) {
      Config.musicFolder = Config.mp3DownloadFolder;
      unawaited(Config.save());
    }
    if (Config.musicFolder.isNotEmpty &&
        MusicLibraryService.instance.tracks.value.isEmpty) {
      MusicLibraryService.instance.rescan();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    setState(() => _pickingFolder = true);
    try {
      final directory = await getDirectoryPath();
      if (directory != null) {
        Config.musicFolder = directory;
        await Config.save();
        await MusicLibraryService.instance.rescan();
      }
    } finally {
      if (mounted) setState(() => _pickingFolder = false);
    }
  }

  Future<void> _rescan() async {
    final messenger = ScaffoldMessenger.of(context);
    await MusicLibraryService.instance.rescan();
    if (!mounted) return;
    final count = MusicLibraryService.instance.tracks.value.length;
    messenger.showSnackBar(SnackBar(content: Text('Found $count tracks')));
  }

  Future<void> _importM3u() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Playlist', extensions: ['m3u', 'm3u8']),
    ]);
    if (file == null) return;
    final result = await M3uPlaylistService.importFile(File(file.path));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(result.unmatchedEntries.isEmpty
          ? 'Imported "${result.playlist.name}": ${result.matchedCount} tracks'
          : 'Imported "${result.playlist.name}": ${result.matchedCount} matched, '
              '${result.unmatchedEntries.length} not found in your library'),
    ));
  }

  void _openDownloader() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const Mp3DownloaderPage()));
  }

  Future<void> _checkForUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checkingForUpdates = true);
    try {
      final info = await _musicUpdateService.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Best Music is up to date.')));
        return;
      }
      final accepted = await showUpdateAvailableDialog(context, info);
      if (accepted == true && mounted) {
        await downloadUpdateInBackground(context, info,
            service: _musicUpdateService);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text('Could not check for updates: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  /// [standalone] mode is the Best Music app's root page, so there is no
  /// drawer for [buildSubpageAppBar]'s "Menu" button to open — a plain app
  /// bar with the Best Music-specific actions ([_openDownloader],
  /// [_checkForUpdates]) tacked on in front of [actions] instead.
  PreferredSizeWidget _appBar(
    BuildContext context, {
    required String title,
    PreferredSizeWidget? bottom,
    List<Widget> actions = const [],
  }) {
    if (!widget.standalone) {
      return buildSubpageAppBar(context,
          title: title, bottom: bottom, actions: actions);
    }
    return AppBar(
      title: Text(title),
      bottom: bottom,
      actions: [
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: 'Download MP3',
          onPressed: _openDownloader,
        ),
        IconButton(
          icon: _checkingForUpdates
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_outlined),
          tooltip: 'Check for updates',
          onPressed: _checkingForUpdates ? null : _checkForUpdates,
        ),
        ...actions,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Config.musicFolder.isEmpty) {
      return Scaffold(
        appBar: _appBar(context,
            title: widget.standalone ? 'Best Music' : 'Music Player'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open, size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Choose the folder your music lives in. Every subfolder is '
                  'included automatically — you can exclude specific ones '
                  'from Settings → Music Player.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _pickingFolder ? null : _pickFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose music folder'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(
        context,
        title: widget.standalone ? 'Best Music' : 'Music Player',
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            tooltip: 'Shuffle play',
            onPressed: () async {
              await MusicPlayerService.playLibraryShuffled();
              if (mounted) {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NowPlayingPage()));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Import M3U/M3U8 playlist',
            onPressed: _importM3u,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan library',
            onPressed: _rescan,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Library'),
            Tab(text: 'Playlists'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _LibraryTab(),
                _PlaylistsTab(),
              ],
            ),
          ),
          const _MiniPlayerBar(),
        ],
      ),
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, tracks, _) {
        if (tracks.isEmpty) {
          return const Center(child: Text('No tracks found. Tap refresh to rescan.'));
        }
        return TrackListView(tracks: tracks);
      },
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MusicPlaylist>>(
      valueListenable: MusicPlaylistService.instance.playlists,
      builder: (context, playlists, _) {
        return ListView.builder(
          itemCount: playlists.length,
          itemBuilder: (context, index) {
            final playlist = playlists[index];
            return ListTile(
              leading: Icon(playlist.id == MusicPlaylist.favoritesId
                  ? Icons.favorite
                  : playlist.id == MusicPlaylist.dislikedId
                      ? Icons.thumb_down_alt
                      : Icons.playlist_play),
              title: Text(playlist.name),
              subtitle: Text('${playlist.trackIds.length} tracks'),
              trailing: playlist.isSystem
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete playlist',
                      onPressed: () =>
                          MusicPlaylistService.instance.deletePlaylist(playlist.id),
                    ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MusicPlaylistDetailPage(playlist: playlist),
              )),
            );
          },
        );
      },
    );
  }
}

class MusicPlaylistDetailPage extends StatelessWidget {
  const MusicPlaylistDetailPage({super.key, required this.playlist});

  final MusicPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: playlist.name),
      body: ValueListenableBuilder<List<Track>>(
        valueListenable: MusicLibraryService.instance.tracks,
        builder: (context, _, __) {
          final tracks = playlist.trackIds
              .map((id) => MusicLibraryService.instance.byId(id))
              .whereType<Track>()
              .toList();
          if (tracks.isEmpty) {
            return const Center(child: Text('No tracks in this playlist yet.'));
          }
          return TrackListView(tracks: tracks);
        },
      ),
    );
  }
}

/// Shared track list used by the Library tab and playlist detail pages.
/// Tapping a row plays the whole list starting from that track.
class TrackListView extends StatelessWidget {
  const TrackListView({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        return ValueListenableBuilder<List<MusicPlaylist>>(
          valueListenable: MusicPlaylistService.instance.playlists,
          builder: (context, _, __) {
            final isFavorite = MusicPlaylistService.instance.isFavorite(track.id);
            return ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(track.title.isNotEmpty ? track.title : track.fileBaseName),
              subtitle: track.artist.isNotEmpty ? Text(track.artist) : null,
              trailing: IconButton(
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                color: isFavorite ? Colors.pink : null,
                tooltip: 'Favorite',
                onPressed: () => MusicPlaylistService.instance.toggleFavorite(track.id),
              ),
              onTap: () async {
                await MusicPlayerService.playQueue(tracks, startIndex: index);
                if (context.mounted) {
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NowPlayingPage()));
                }
              },
            );
          },
        );
      },
    );
  }
}

/// Small persistent bar showing what's currently playing, with play/pause
/// and a tap-through to [NowPlayingPage].
class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar();

  @override
  Widget build(BuildContext context) {
    if (!MusicPlayerService.isReady) return const SizedBox.shrink();
    final MusicAudioHandler handler = MusicPlayerService.handler;
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();
        return Material(
          elevation: 4,
          child: InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const NowPlayingPage())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.music_note),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if ((item.artist ?? '').isNotEmpty)
                          Text(item.artist!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StreamBuilder<PlaybackState>(
                    stream: handler.playbackState,
                    builder: (context, stateSnapshot) {
                      final playing = stateSnapshot.data?.playing ?? false;
                      return IconButton(
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => playing ? handler.pause() : handler.play(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
