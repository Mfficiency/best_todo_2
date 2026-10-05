import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/youtube_feed.dart';
import '../services/music_library_service.dart';
import '../services/media_volume.dart';
import '../services/music_sleep_timer.dart';
import '../services/youtube_feed_service.dart';
import 'music_about_page.dart';
import 'music_theme.dart';
import 'playback_speed_sheet.dart';
import 'sleep_timer_sheet.dart';
import 'subpage_app_bar.dart';
import 'update_downloads_folder_tile.dart';
import 'volume_sheet.dart';

/// The sections of Best Music's Settings, in page order.
enum MusicSettingsSection {
  library('Library'),
  playback('Playback'),
  appearance('Appearance'),
  feed('Subscriptions feed'),
  sponsorBlock('SponsorBlock'),
  updates('Updates');

  const MusicSettingsSection(this.title);
  final String title;
}

/// Best Music's Settings page, laid out like BestToDo's: a pinned row of
/// section buttons that jump to (and open) a section, collapsible section
/// cards that all start closed, and a Collapse all/Expand all toggle. The
/// music folder fields are the same `Config.musicFolder`/
/// `musicExcludedSubfolders` and `MusicLibraryService` calls as BestToDo's
/// Settings → Music Player section (`lib/ui/settings_page.dart`),
/// reimplemented standalone since that page is a single monolithic widget
/// tightly coupled to BestToDo's full settings list. The Subscriptions
/// feed's settings live here too; the feed's settings button opens this
/// page on that section ([initialSection]).
class MusicSettingsPage extends StatefulWidget {
  const MusicSettingsPage({super.key, this.initialSection, this.feedService});

  /// Opened and scrolled to on arrival; every other section starts closed.
  final MusicSettingsSection? initialSection;

  /// Defaults to [YoutubeFeedService.instance].
  final YoutubeFeedService? feedService;

  @override
  State<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends State<MusicSettingsPage> {
  late final YoutubeFeedService _feed =
      widget.feedService ?? YoutubeFeedService.instance;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewKey = GlobalKey();
  final Map<MusicSettingsSection, GlobalKey> _sectionKeys = {
    for (final s in MusicSettingsSection.values) s: GlobalKey(),
  };
  final Map<MusicSettingsSection, GlobalKey> _buttonKeys = {
    for (final s in MusicSettingsSection.values) s: GlobalKey(),
  };
  late final Set<MusicSettingsSection> _collapsed = {
    for (final s in MusicSettingsSection.values)
      if (s != widget.initialSection) s,
  };
  late MusicSettingsSection _active =
      widget.initialSection ?? MusicSettingsSection.values.first;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    if (initial != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollTo(initial, animate: false));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpToSection(MusicSettingsSection section) {
    setState(() {
      _collapsed.remove(section);
      _active = section;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(section));
  }

  void _scrollTo(MusicSettingsSection section, {bool animate = true}) {
    final ctx = _sectionKeys[section]?.currentContext;
    if (!mounted || ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOut,
    );
    _revealButton(section);
  }

  /// Scrolls the button row so [section]'s button is on screen.
  void _revealButton(MusicSettingsSection section) {
    final ctx = _buttonKeys[section]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.5, duration: const Duration(milliseconds: 200));
  }

  void _toggleSection(MusicSettingsSection section) {
    setState(() {
      if (!_collapsed.remove(section)) _collapsed.add(section);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActive());
  }

  /// Highlights the button of the section at the top of the viewport.
  void _updateActive() {
    if (!mounted || !_scrollController.hasClients) return;
    final viewport =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    var active = MusicSettingsSection.values.first;
    for (final s in MusicSettingsSection.values) {
      final box =
          _sectionKeys[s]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= top + 24) active = s;
    }
    // At the very bottom the last sections can't reach the top.
    final pos = _scrollController.position;
    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 1) {
      final lastOpen = MusicSettingsSection.values.lastWhere(
          (s) => !_collapsed.contains(s),
          orElse: () => active);
      if (lastOpen.index > active.index) active = lastOpen;
    }
    if (active != _active) {
      setState(() => _active = active);
      _revealButton(active);
    }
  }

  Widget _buildSection(MusicSettingsSection section, List<Widget> children) {
    final collapsed = _collapsed.contains(section);
    final title = section.title;
    return Container(
      key: _sectionKeys[section],
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _toggleSection(section),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Tooltip(
                      message: collapsed ? 'Expand $title' : 'Collapse $title',
                      child: AnimatedRotation(
                        turns: collapsed ? 0 : 0.5,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.expand_more),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!collapsed) ...children,
          ],
        ),
      ),
    );
  }

  /// Collapses everything while any section is open, expands everything
  /// once they are all closed.
  Widget _buildCollapseAllBar() {
    final anyExpanded = _collapsed.length < MusicSettingsSection.values.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              if (anyExpanded) {
                _collapsed.addAll(MusicSettingsSection.values);
              } else {
                _collapsed.clear();
              }
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _updateActive());
          },
          icon: Icon(anyExpanded ? Icons.unfold_less : Icons.unfold_more),
          label: Text(anyExpanded ? 'Collapse all' : 'Expand all'),
        ),
      ],
    );
  }

  Widget _buildSectionButtons() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final section in MusicSettingsSection.values)
              Padding(
                key: _buttonKeys[section],
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(section.title),
                  selected: _active == section,
                  onSelected: (_) => _jumpToSection(section),
                ),
              ),
          ],
        ),
      ),
    );
  }
  Future<void> _pickFolder() async {
    await MusicLibraryService.instance.ensureFolderPermission();
    final directory = await getDirectoryPath(
      initialDirectory:
          Config.musicFolder.isNotEmpty ? Config.musicFolder : null,
    );
    if (directory == null) return;
    setState(() {
      Config.musicFolder = directory;
      Config.musicExcludedSubfolders = [];
    });
    await Config.save();
    unawaited(MusicLibraryService.instance.rescan());
  }

  Future<void> _clearFolder() async {
    setState(() {
      Config.musicFolder = '';
      Config.musicExcludedSubfolders = [];
    });
    await Config.save();
    unawaited(MusicLibraryService.instance.rescan());
  }

  Future<void> _openExclusionsDialog() async {
    final subfolders = await MusicLibraryService.instance.listSubfolders();
    if (!mounted) return;
    if (subfolders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No subfolders found under the music folder'),
      ));
      return;
    }
    final excluded = {...Config.musicExcludedSubfolders};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Excluded subfolders'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in subfolders)
                      CheckboxListTile(
                        value: excluded.contains(folder),
                        title: Text(folder),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              excluded.add(folder);
                            } else {
                              excluded.remove(folder);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    setState(() {
                      Config.musicExcludedSubfolders = excluded.toList();
                    });
                    await Config.save();
                    unawaited(MusicLibraryService.instance.rescan());
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = Config.musicFolder.isNotEmpty;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Settings'),
      body: Column(
        children: [
          _buildSectionButtons(),
          Expanded(
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                _updateActive();
                return false;
              },
              child: SingleChildScrollView(
                key: _scrollViewKey,
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCollapseAllBar(),
                    _buildSection(MusicSettingsSection.library, [
                      ListTile(
                        title: const Text('Music folder'),
                        subtitle: Text(chosen
                            ? Config.musicFolder
                            : 'Not set — choose the folder your music lives in'),
                        trailing: const Icon(Icons.folder_open),
                        onTap: _pickFolder,
                      ),
                      if (chosen) ...[
                        ListTile(
                          leading: const Icon(Icons.clear),
                          title: const Text('Forget this folder'),
                          onTap: _clearFolder,
                        ),
                        ListTile(
                          leading: const Icon(Icons.rule_folder_outlined),
                          title: const Text('Excluded subfolders'),
                          subtitle: Text(Config.musicExcludedSubfolders.isEmpty
                              ? 'None — every subfolder is included'
                              : Config.musicExcludedSubfolders.join(', ')),
                          onTap: _openExclusionsDialog,
                        ),
                      ],
                    ]),
                    _buildSection(MusicSettingsSection.playback, [
                      SwitchListTile(
                        secondary: const Icon(Icons.volume_up_outlined),
                        title: const Text('Ask before playing out loud'),
                        subtitle: const Text(
                            "Confirm before music starts on the phone's "
                            'speaker when no Bluetooth speaker or headphones '
                            'are connected'),
                        value: Config.musicConfirmSpeakerPlay,
                        onChanged: (value) {
                          setState(() => Config.musicConfirmSpeakerPlay = value);
                          unawaited(Config.save());
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.volume_up_outlined),
                        title: const Text('Music volume'),
                        subtitle: Text(
                            '${describeRememberedVolume(VolumeKind.music)} — '
                            "your phone's volume for music, put back when "
                            'you switch from videos to music'),
                        onTap: () async {
                          await showVolumeSheet(context, video: false);
                          if (mounted) setState(() {});
                        },
                      ),
                      ValueListenableBuilder<SleepTimerState>(
                        valueListenable: MusicSleepTimer.instance.state,
                        builder: (context, state, _) => ListTile(
                          leading: Icon(state.isActive
                              ? Icons.bedtime
                              : Icons.bedtime_outlined),
                          title: const Text('Sleep timer'),
                          subtitle: Text(state.isActive
                              ? 'On — ${MusicSleepTimer.describe(state)}'
                              : 'Off — pause playback after a while'),
                          onTap: () => showSleepTimerSheet(context),
                        ),
                      ),
                    ]),
                    _buildSection(MusicSettingsSection.appearance, [
                      ValueListenableBuilder<bool>(
                        valueListenable: MusicTheme.darkMode,
                        builder: (context, dark, _) => SwitchListTile(
                          secondary: const Icon(Icons.dark_mode_outlined),
                          title: const Text('Dark mode'),
                          value: dark,
                          onChanged: (value) => MusicTheme.setDarkMode(value),
                        ),
                      ),
                    ]),
                    ValueListenableBuilder<YoutubeFeedSettings>(
                      valueListenable: _feed.settings,
                      builder: (context, settings, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSection(MusicSettingsSection.feed,
                              _feedTiles(settings)),
                          _buildSection(MusicSettingsSection.sponsorBlock,
                              _sponsorBlockTiles(settings)),
                        ],
                      ),
                    ),
                    _buildSection(MusicSettingsSection.updates, [
                      UpdateDownloadsFolderTile(
                          updateService: MusicAboutPage.updateService),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the Subscriptions feed hides and how its videos play.
  List<Widget> _feedTiles(YoutubeFeedSettings settings) {
    void update(YoutubeFeedSettings value) => _feed.updateSettings(value);
    return [
      SwitchListTile(
        secondary: const Icon(Icons.short_text),
        title: const Text('Hide Shorts'),
        value: settings.hideShorts,
        onChanged: (v) => update(settings.copyWith(hideShorts: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.live_tv_outlined),
        title: const Text('Hide livestreams'),
        subtitle: const Text("Live, upcoming and past streams — what a "
            'channel lists under its Live tab'),
        value: settings.hideLivestreams,
        onChanged: (v) => update(settings.copyWith(hideLivestreams: v)),
      ),
      ListTile(
        leading: const Icon(Icons.speed),
        title: const Text('Video speed'),
        subtitle: Text('${formatSpeed(settings.playbackSpeed)} — the last '
            'speed you picked; songs always play at 1×'),
        onTap: () => showPlaybackSpeedSheet(context, forDefault: true),
      ),
      ListTile(
        leading: const Icon(Icons.volume_up_outlined),
        title: const Text('Video volume'),
        subtitle: Text('${describeRememberedVolume(VolumeKind.video)}'
            '${settings.videoBoostDb > 0 ? ', boost ${formatBoost(settings.videoBoostDb)}' : ''}'
            " — your phone's volume for videos, put back when you switch "
            'from music to videos'),
        onTap: () async {
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => VolumeSheet(video: true, feed: _feed),
          );
          if (mounted) setState(() {});
        },
      ),
      SwitchListTile(
        secondary: const Icon(Icons.playlist_play),
        title: const Text('Play the next video automatically'),
        subtitle: const Text('Off: a video stops at its end instead of '
            'moving on to the next unplayed one'),
        value: settings.autoplayNext,
        onChanged: (v) => update(settings.copyWith(autoplayNext: v)),
      ),
    ];
  }

  List<Widget> _sponsorBlockTiles(YoutubeFeedSettings settings) {
    void update(YoutubeFeedSettings value) => _feed.updateSettings(value);
    return [
      SwitchListTile(
        secondary: const Icon(Icons.fast_forward_outlined),
        title: const Text('Skip sponsored segments'),
        subtitle: const Text('Skip sponsor reads and other segments the '
            'SponsorBlock community marked (sponsor.ajay.app)'),
        value: settings.sponsorBlockEnabled,
        onChanged: (v) => update(settings.copyWith(sponsorBlockEnabled: v)),
      ),
      if (settings.sponsorBlockEnabled)
        for (final category in SponsorBlockCategory.values)
          CheckboxListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(category.label),
            value: settings.sponsorBlockCategories.contains(category),
            onChanged: (checked) {
              final categories = {...settings.sponsorBlockCategories};
              if (checked == true) {
                categories.add(category);
              } else {
                categories.remove(category);
              }
              update(settings.copyWith(sponsorBlockCategories: categories));
            },
          ),
    ];
  }
}
