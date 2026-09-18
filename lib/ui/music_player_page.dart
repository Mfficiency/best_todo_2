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
import 'music_wishlist_page.dart';
import 'now_playing_page.dart';
import 'rule_playlist_editor_page.dart';
import 'startup_times_page.dart';
import 'subpage_app_bar.dart';
import 'track_metadata_page.dart';

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
    _tabController = TabController(length: 5, vsync: this);
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
            leading: const Icon(Icons.star_border),
            title: const Text('Wishlist'),
            onTap: () => _pushStandalonePage(() => const MusicWishlistPage()),
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
            onTap: () => _pushStandalonePage(() => const ChangelogPage(
                  assetPath: 'CHANGELOG_MUSIC.md',
                  showStoryPoster: false,
                )),
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
            icon: const Icon(Icons.search),
            tooltip: 'Search music',
            onPressed: () => showSearch(
              context: context,
              delegate: _MusicSearchDelegate(),
            ),
          ),
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Favourites'),
            Tab(text: 'Playlists'),
            Tab(text: 'Tracks'),
            Tab(text: 'Artists'),
            Tab(text: 'Folders'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _FavouritesTab(),
                _PlaylistsTab(),
                _TracksTab(),
                _ArtistsTab(),
                _FoldersTab(),
              ],
            ),
          ),
          const _MiniPlayerBar(),
        ],
      ),
    );
  }
}

/// Every track whose [Track.title]/[Track.artist] (or filename, as a
/// fallback) contains [query], case-insensitively. Used by
/// [_MusicSearchDelegate].
List<Track> _filterTracks(List<Track> tracks, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return tracks;
  return tracks
      .where((t) =>
          t.title.toLowerCase().contains(q) ||
          t.fileBaseName.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q))
      .toList();
}

/// Library-wide search reached from the app bar's search icon — Samsung
/// Music style: type to filter by title or artist, tap a result to start
/// playing it from that point.
class _MusicSearchDelegate extends SearchDelegate<void> {
  Widget _buildTrackResults(BuildContext context) {
    final tracks = _filterTracks(MusicLibraryService.instance.tracks.value, query);
    if (tracks.isEmpty) {
      return Center(
        child: Text(query.trim().isEmpty
            ? 'Search by title or artist'
            : 'No matches for "$query"'),
      );
    }
    return TrackListView(tracks: tracks);
  }

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear search',
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const BackButtonIcon(),
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildTrackResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildTrackResults(context);
}

class _TracksTab extends StatelessWidget {
  const _TracksTab();

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

/// Shortcut tab straight to the Favorites system playlist — the same track
/// list also reachable from Playlists → Favorites, just one tap away like
/// Samsung Music's own Favourites tab.
class _FavouritesTab extends StatelessWidget {
  const _FavouritesTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, _, __) {
        return ValueListenableBuilder<List<MusicPlaylist>>(
          valueListenable: MusicPlaylistService.instance.playlists,
          builder: (context, __, ___) {
            final tracks = MusicPlaylistService.instance
                .resolvedTracks(MusicPlaylistService.instance.favorites);
            if (tracks.isEmpty) {
              return const Center(
                child: Text(
                    'No favorites yet. Tap the heart on a track to add one.'),
              );
            }
            return TrackListView(tracks: tracks);
          },
        );
      },
    );
  }
}

/// Every artist present in the library (an empty [Track.artist] groups
/// under "Unknown artist"), sorted alphabetically with "Unknown artist"
/// last. Tapping one opens its own filtered track list.
class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();

  static const String _unknownArtist = 'Unknown artist';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, tracks, _) {
        if (tracks.isEmpty) {
          return const Center(child: Text('No tracks found. Tap refresh to rescan.'));
        }
        final byArtist = <String, List<Track>>{};
        for (final track in tracks) {
          final artist = track.artist.trim().isEmpty ? _unknownArtist : track.artist.trim();
          byArtist.putIfAbsent(artist, () => []).add(track);
        }
        final artists = byArtist.keys.toList()
          ..sort((a, b) {
            if (a == _unknownArtist) return b == _unknownArtist ? 0 : 1;
            if (b == _unknownArtist) return -1;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
        return ListView.builder(
          itemCount: artists.length,
          itemBuilder: (context, index) {
            final artist = artists[index];
            final artistTracks = byArtist[artist]!;
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(artist),
              subtitle: Text(
                  '${artistTracks.length} track${artistTracks.length == 1 ? '' : 's'}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _FilteredTracksPage(title: artist, tracks: artistTracks),
              )),
            );
          },
        );
      },
    );
  }
}

/// The folder (relative to [Config.musicFolder]) a local [track] lives in,
/// for grouping in the Folders tab. Tracks right under the music folder
/// itself group under "(Music folder)"; a Subsonic track (no [Track.filePath])
/// groups under "Other".
String folderLabelOf(Track track) {
  final path = track.filePath;
  if (path == null) return 'Other';
  final root = MusicLibraryService.normalizePath(Config.musicFolder.trim());
  final normalized = MusicLibraryService.normalizePath(path);
  var rel = normalized.startsWith(root) ? normalized.substring(root.length) : normalized;
  if (rel.startsWith('/')) rel = rel.substring(1);
  final slash = rel.lastIndexOf('/');
  final folder = slash >= 0 ? rel.substring(0, slash) : '';
  return folder.isEmpty ? '(Music folder)' : folder;
}

/// Every folder tracks were scanned from, sorted alphabetically — the
/// leading "(" on "(Music folder)" sorts it ahead of any real subfolder
/// name. Tapping one opens its own filtered track list.
class _FoldersTab extends StatelessWidget {
  const _FoldersTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, tracks, _) {
        if (tracks.isEmpty) {
          return const Center(child: Text('No tracks found. Tap refresh to rescan.'));
        }
        final byFolder = <String, List<Track>>{};
        for (final track in tracks) {
          byFolder.putIfAbsent(folderLabelOf(track), () => []).add(track);
        }
        final folders = byFolder.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return ListView.builder(
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            final folderTracks = byFolder[folder]!;
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder),
              subtitle: Text(
                  '${folderTracks.length} track${folderTracks.length == 1 ? '' : 's'}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _FilteredTracksPage(title: folder, tracks: folderTracks),
              )),
            );
          },
        );
      },
    );
  }
}

/// Plain subpage showing a fixed track list — used by the Artists and
/// Folders tabs to drill into one artist/folder's songs.
class _FilteredTracksPage extends StatelessWidget {
  const _FilteredTracksPage({required this.title, required this.tracks});

  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: title),
      body: TrackListView(tracks: tracks),
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
    return ValueListenableBuilder<List<MusicPlaylist>>(
      valueListenable: MusicPlaylistService.instance.playlists,
      builder: (context, __, _) {
        // A persisted playlist (list/rule) may have changed since
        // [playlist] was captured (a rule edit, a favorite toggle); a
        // computed smart playlist isn't in this list at all, so falls
        // back to the one passed in — its kind/genreFilter never change.
        final current =
            MusicPlaylistService.instance.byId(playlist.id) ?? playlist;
        // Only a hand-built, non-system playlist has a fixed track list
        // songs can actually be added to or removed from — a smart/rule
        // playlist is recomputed, and Favorites/"Don't really like" are
        // toggled via the heart/dislike gesture instead.
        final editable = current.kind == PlaylistKind.list && !current.isSystem;
        return Scaffold(
          appBar: buildSubpageAppBar(
            context,
            title: current.name,
            actions: [
              if (editable)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add songs',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AddSongsToPlaylistPage(playlistId: current.id),
                  )),
                ),
            ],
          ),
          body: ValueListenableBuilder<List<Track>>(
            valueListenable: MusicLibraryService.instance.tracks,
            builder: (context, _, __) {
              final tracks = MusicPlaylistService.instance.resolvedTracks(current);
              if (tracks.isEmpty) {
                return Center(
                  child: Text(current.kind == PlaylistKind.rule
                      ? 'No tracks match these rules yet.'
                      : 'No tracks in this playlist yet.'),
                );
              }
              return TrackListView(
                tracks: tracks,
                onRemove: editable
                    ? (track) =>
                        MusicPlaylistService.instance.removeFrom(current.id, track.id)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

/// Multi-select track picker reached from a playlist's "+" app bar button —
/// every library track not already in the playlist, with a checkbox each;
/// "Add" applies the whole selection in one go.
class AddSongsToPlaylistPage extends StatefulWidget {
  const AddSongsToPlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  State<AddSongsToPlaylistPage> createState() => _AddSongsToPlaylistPageState();
}

class _AddSongsToPlaylistPageState extends State<AddSongsToPlaylistPage> {
  final Set<String> _selected = {};

  Future<void> _confirm() async {
    await MusicPlaylistService.instance.addAllTo(widget.playlistId, _selected);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final playlist = MusicPlaylistService.instance.byId(widget.playlistId);
    final existing = playlist?.trackIds.toSet() ?? <String>{};
    return ValueListenableBuilder<List<Track>>(
      valueListenable: MusicLibraryService.instance.tracks,
      builder: (context, allTracks, _) {
        final candidates = allTracks.where((t) => !existing.contains(t.id)).toList();
        return Scaffold(
          appBar: buildSubpageAppBar(
            context,
            title: 'Add songs',
            actions: [
              IconButton(
                icon: const Icon(Icons.check),
                tooltip: 'Add selected',
                onPressed: _selected.isEmpty ? null : _confirm,
              ),
            ],
          ),
          body: candidates.isEmpty
              ? const Center(child: Text('Every track is already in this playlist.'))
              : ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (context, index) {
                    final track = candidates[index];
                    return CheckboxListTile(
                      value: _selected.contains(track.id),
                      title: Text(track.title.isNotEmpty ? track.title : track.fileBaseName),
                      subtitle: track.artist.isNotEmpty ? Text(track.artist) : null,
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selected.add(track.id);
                        } else {
                          _selected.remove(track.id);
                        }
                      }),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// Quick ways to reorder a [TrackListView] — mirrors the sort options
/// Samsung Music offers on its Tracks list.
enum TrackSortOrder { dateAddedDesc, titleAsc, artistAsc, durationDesc }

String trackSortLabel(TrackSortOrder order) {
  switch (order) {
    case TrackSortOrder.dateAddedDesc:
      return 'Date added';
    case TrackSortOrder.titleAsc:
      return 'Title';
    case TrackSortOrder.artistAsc:
      return 'Artist';
    case TrackSortOrder.durationDesc:
      return 'Duration';
  }
}

List<Track> sortTracks(List<Track> tracks, TrackSortOrder order) {
  final sorted = [...tracks];
  switch (order) {
    case TrackSortOrder.dateAddedDesc:
      sorted.sort((a, b) {
        final aDate = a.dateAdded;
        final bDate = b.dateAdded;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
      break;
    case TrackSortOrder.titleAsc:
      sorted.sort((a, b) {
        final aTitle = a.title.isNotEmpty ? a.title : a.fileBaseName;
        final bTitle = b.title.isNotEmpty ? b.title : b.fileBaseName;
        return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
      });
      break;
    case TrackSortOrder.artistAsc:
      sorted.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
      break;
    case TrackSortOrder.durationDesc:
      sorted.sort((a, b) => (b.durationMs ?? 0).compareTo(a.durationMs ?? 0));
      break;
  }
  return sorted;
}

/// Shared track list used by the Tracks/Favourites tabs, artist/folder
/// drill-downs, search results and playlist detail pages. Tapping a row
/// plays the whole (sorted) list starting from that track; the header row
/// offers a quick sort menu plus shuffle/play-all, Samsung Music style.
class TrackListView extends StatefulWidget {
  const TrackListView({super.key, required this.tracks, this.onRemove});

  final List<Track> tracks;

  /// When set, each row's "more options" menu gets a "Remove from
  /// playlist" entry — only passed by [MusicPlaylistDetailPage] for a
  /// hand-built playlist the track list can actually be edited on.
  final void Function(Track track)? onRemove;

  @override
  State<TrackListView> createState() => _TrackListViewState();
}

class _TrackListViewState extends State<TrackListView> {
  TrackSortOrder _sortOrder = TrackSortOrder.dateAddedDesc;

  Future<void> _play(List<Track> tracks, {int startIndex = 0}) async {
    await MusicPlayerService.playQueue(tracks, startIndex: startIndex);
    if (context.mounted) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = sortTracks(widget.tracks, _sortOrder);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              PopupMenuButton<TrackSortOrder>(
                tooltip: 'Sort tracks',
                initialValue: _sortOrder,
                onSelected: (value) => setState(() => _sortOrder = value),
                itemBuilder: (context) => [
                  for (final order in TrackSortOrder.values)
                    PopupMenuItem(
                      value: order,
                      child: Row(
                        children: [
                          if (order == _sortOrder)
                            const Icon(Icons.check, size: 18)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(trackSortLabel(order),
                                  overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(trackSortLabel(_sortOrder)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: 'Shuffle these tracks',
                onPressed: () =>
                    _play(MusicPlaylistService.instance.weightedShuffle(tracks)),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Play all',
                onPressed: () => _play(tracks),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
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
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      tooltip: 'More options',
                      onSelected: (value) async {
                        switch (value) {
                          case 'favorite':
                            await MusicPlaylistService.instance.toggleFavorite(track.id);
                            break;
                          case 'add':
                            if (context.mounted) {
                              await showAddToPlaylistSheet(context, track);
                            }
                            break;
                          case 'remove':
                            widget.onRemove?.call(track);
                            break;
                          case 'info':
                            if (context.mounted) {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => TrackMetadataPage(trackId: track.id),
                              ));
                            }
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'favorite',
                          child: Row(
                            children: [
                              Icon(
                                isFavorite ? Icons.favorite : Icons.favorite_border,
                                size: 18,
                                color: isFavorite ? Colors.pink : null,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(children: [
                            Icon(Icons.playlist_add, size: 18),
                            SizedBox(width: 8),
                            Flexible(child: Text('Add to playlist', overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                        if (widget.onRemove != null)
                          const PopupMenuItem(
                            value: 'remove',
                            child: Row(children: [
                              Icon(Icons.remove_circle_outline, size: 18),
                              SizedBox(width: 8),
                              Flexible(
                                  child: Text('Remove from playlist',
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                          ),
                        const PopupMenuItem(
                          value: 'info',
                          child: Row(children: [
                            Icon(Icons.info_outline, size: 18),
                            SizedBox(width: 8),
                            Flexible(child: Text('Track info', overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                      ],
                    ),
                    onTap: () => _play(tracks, startIndex: index),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Prompts for a playlist name (Cancel/Create). The dialog owns its own
/// [TextEditingController] in a dedicated [StatefulWidget] rather than one
/// disposed right after `showDialog` returns — the exit animation still
/// builds the fields after the pop.
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
