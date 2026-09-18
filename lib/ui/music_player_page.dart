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
import 'app_logs_page.dart';
import 'changelog_page.dart';
import 'home_scaffold_key.dart';
import 'mp3_downloader_page.dart';
import 'music_about_page.dart';
import 'music_metadata_scan_page.dart';
import 'music_settings_page.dart';
import 'now_playing_page.dart';
import 'rule_playlist_editor_page.dart';
import 'startup_times_page.dart';
import 'subpage_app_bar.dart';

/// Tools → Music Player: browse/play tracks scanned from
/// [Config.musicFolder] (and, once configured, a Subsonic server), manage
/// Favorites/"Don't really like" and imported playlists, and import an
/// M3U/M3U8 playlist (e.g. shared out of Samsung Music).
///
/// Also the Best Music app's home page ([standalone]: true), where it is the
/// root route rather than a BestToDo Tools subpage: [homeScaffoldKey] +
/// [_buildDrawer] give it the same drawer-based menu as BestToDo's own home
/// page (Settings, MP3 Downloader, Changelog, Startup Times, App Logs,
/// About), in place of BestToDo's task-list-specific entries.
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
      unawaited(MusicLibraryService.instance
          .ensureFolderPermission()
          .then((_) => MusicLibraryService.instance.rescan()));
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
      await MusicLibraryService.instance.ensureFolderPermission();
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

  /// [standalone] mode is the Best Music app's root page: a real [Drawer]
  /// (matching BestToDo's own home page — see [homeScaffoldKey]) stands in
  /// for the Tools menu + About page, so [buildSubpageAppBar]'s "Menu"
  /// button (used by every page this drawer pushes) has something to open.
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
    return AppBar(title: Text(title), bottom: bottom, actions: actions);
  }

  void _pushStandalonePage(Widget Function() builder) {
    Navigator.of(context).pop(); // close the drawer
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          FutureBuilder<void>(
            future: Config.ensureVersionLoaded(),
            builder: (context, snapshot) {
              return Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primary,
                child: Text(
                  'Best Music v${Config.version}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 18,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('MP3 Downloader'),
            onTap: () =>
                _pushStandalonePage(() => const Mp3DownloaderPage()),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () =>
                _pushStandalonePage(() => const MusicSettingsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Changelog'),
            onTap: () => _pushStandalonePage(() => const ChangelogPage()),
          ),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: const Text('Startup Times'),
            onTap: () =>
                _pushStandalonePage(() => const StartupTimesPage()),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt),
            title: const Text('App Logs'),
            onTap: () => _pushStandalonePage(() => const AppLogsPage()),
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('About'),
            onTap: () => _pushStandalonePage(() => const MusicAboutPage()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Config.musicFolder.isEmpty) {
      return Scaffold(
        key: widget.standalone ? homeScaffoldKey : null,
        drawer: widget.standalone ? _buildDrawer(context) : null,
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
      key: widget.standalone ? homeScaffoldKey : null,
      drawer: widget.standalone ? _buildDrawer(context) : null,
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
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Metadata scan',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MusicMetadataScanPage(),
            )),
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

  IconData _iconFor(MusicPlaylist playlist) {
    if (playlist.id == MusicPlaylist.favoritesId) return Icons.favorite;
    if (playlist.id == MusicPlaylist.dislikedId) return Icons.thumb_down_alt;
    switch (playlist.kind) {
      case PlaylistKind.lastAdded:
        return Icons.new_releases_outlined;
      case PlaylistKind.mostPlayed:
        return Icons.trending_up;
      case PlaylistKind.rule:
        return Icons.rule;
      case PlaylistKind.list:
        return Icons.playlist_play;
    }
  }

  Widget? _trailingFor(BuildContext context, MusicPlaylist playlist) {
    // System entries (Favorites/"Don't really like" plus every computed
    // smart playlist) can't be renamed or deleted.
    if (playlist.isSystem) return null;
    if (playlist.kind == PlaylistKind.rule) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit rules',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RulePlaylistEditorPage(existing: playlist),
            )),
          ),
          _deleteButton(playlist),
        ],
      );
    }
    return _deleteButton(playlist);
  }

  Widget _deleteButton(MusicPlaylist playlist) => IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete playlist',
        onPressed: () => MusicPlaylistService.instance.deletePlaylist(playlist.id),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, _, __) {
        return ValueListenableBuilder<List<MusicPlaylist>>(
          valueListenable: MusicPlaylistService.instance.playlists,
          builder: (context, userPlaylists, __) {
            final playlists = [
              ...MusicPlaylistService.instance.smartPlaylists,
              ...userPlaylists,
            ];
            return ListView.builder(
              itemCount: playlists.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('New playlist'),
                    onTap: () async {
                      final name = await promptPlaylistName(context);
                      if (name == null || name.trim().isEmpty) return;
                      await MusicPlaylistService.instance
                          .createPlaylist(name.trim(), []);
                    },
                  );
                }
                if (index == 1) {
                  return ListTile(
                    leading: const Icon(Icons.rule),
                    title: const Text('New rule playlist'),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RulePlaylistEditorPage(),
                    )),
                  );
                }
                final playlist = playlists[index - 2];
                final trackCount =
                    MusicPlaylistService.instance.resolvedTracks(playlist).length;
                return ListTile(
                  leading: Icon(_iconFor(playlist)),
                  title: Text(playlist.name),
                  subtitle: Text('$trackCount tracks'),
                  trailing: _trailingFor(context, playlist),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MusicPlaylistDetailPage(playlist: playlist),
                  )),
                );
              },
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
      body: ValueListenableBuilder<List<MusicPlaylist>>(
        valueListenable: MusicPlaylistService.instance.playlists,
        builder: (context, __, _) {
          // A persisted playlist (list/rule) may have changed since
          // [playlist] was captured (a rule edit, a favorite toggle); a
          // computed smart playlist isn't in this list at all, so falls
          // back to the one passed in — its kind/genreFilter never change.
          final current =
              MusicPlaylistService.instance.byId(playlist.id) ?? playlist;
          return ValueListenableBuilder<List<Track>>(
            valueListenable: MusicLibraryService.instance.tracks,
            builder: (context, _, __) {
              final tracks = MusicPlaylistService.instance.resolvedTracks(current);
              // Only a hand-built, non-system playlist has a fixed track
              // list a song can actually be removed from — a smart/rule
              // playlist is recomputed, and Favorites/"Don't really like"
              // are toggled via the heart/dislike gesture instead.
              final removable = current.kind == PlaylistKind.list && !current.isSystem;
              if (tracks.isEmpty) {
                return Center(
                  child: Text(current.kind == PlaylistKind.rule
                      ? 'No tracks match these rules yet.'
                      : 'No tracks in this playlist yet.'),
                );
              }
              return TrackListView(
                tracks: tracks,
                onRemove: removable
                    ? (track) =>
                        MusicPlaylistService.instance.removeFrom(current.id, track.id)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

/// Shared track list used by the Library tab and playlist detail pages.
/// Tapping a row plays the whole list starting from that track.
class TrackListView extends StatelessWidget {
  const TrackListView({super.key, required this.tracks, this.onRemove});

  final List<Track> tracks;

  /// When set, each row gets a "Remove from playlist" button — only passed
  /// by [MusicPlaylistDetailPage] for a hand-built playlist the track list
  /// can actually be edited on.
  final void Function(Track track)? onRemove;

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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                    color: isFavorite ? Colors.pink : null,
                    tooltip: 'Favorite',
                    onPressed: () => MusicPlaylistService.instance.toggleFavorite(track.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Add to playlist',
                    onPressed: () => showAddToPlaylistSheet(context, track),
                  ),
                  if (onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove from playlist',
                      onPressed: () => onRemove!(track),
                    ),
                ],
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

/// Prompts for a playlist name (Cancel/Create). The dialog owns its own
/// [TextEditingController] in a dedicated [StatefulWidget] rather than one
/// disposed right after `showDialog` returns — the exit animation still
/// builds the field after the pop.
Future<String?> promptPlaylistName(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PlaylistNameDialog(),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog();

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Playlist name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

/// Bottom sheet listing every hand-built, non-system playlist with a
/// checkbox for whether [track] is already in it — tapping a row adds or
/// removes it immediately, Samsung Music's "Add to playlist" style. "New
/// playlist" at the top creates one (pre-filled with [track]) without
/// leaving the sheet flow.
Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ValueListenableBuilder<List<MusicPlaylist>>(
        valueListenable: MusicPlaylistService.instance.playlists,
        builder: (_, playlists, __) {
          final regular =
              playlists.where((p) => p.kind == PlaylistKind.list && !p.isSystem).toList();
          return ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New playlist'),
                onTap: () async {
                  // Pop the sheet with its own context, then prompt on the
                  // caller's context (the track row's page) — that context
                  // stays mounted after the sheet closes; the sheet's own
                  // builder contexts do not.
                  Navigator.of(sheetContext).pop();
                  if (!context.mounted) return;
                  final name = await promptPlaylistName(context);
                  if (name == null || name.trim().isEmpty) return;
                  await MusicPlaylistService.instance
                      .createPlaylist(name.trim(), [track.id]);
                },
              ),
              if (regular.isNotEmpty) const Divider(height: 1),
              for (final playlist in regular)
                CheckboxListTile(
                  value: playlist.trackIds.contains(track.id),
                  title: Text(playlist.name),
                  onChanged: (checked) {
                    if (checked == true) {
                      MusicPlaylistService.instance.addTo(playlist.id, track.id);
                    } else {
                      MusicPlaylistService.instance.removeFrom(playlist.id, track.id);
                    }
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
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
