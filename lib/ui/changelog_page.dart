import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/install_info_service.dart';
import '../services/update_service.dart';
import '../utils/date_time_format.dart';
import 'auto_update_dialog.dart';
import 'subpage_app_bar.dart';

/// One `## [version] - date` block of CHANGELOG.md.
class ChangelogRelease {
  ChangelogRelease({
    required this.version,
    required this.date,
    required this.entries,
  });

  final String version;
  final DateTime date;
  final List<String> entries;
}

/// A hand-picked chapter in BestToDo's story. Unlike individual releases,
/// these describe the larger ideas that grew across several changelog entries.
class ChangelogMilestone {
  const ChangelogMilestone({
    required this.version,
    required this.date,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String version;
  final String date;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

const List<ChangelogMilestone> changelogMilestones = [
  ChangelogMilestone(
    version: 'v0.1.1',
    date: 'JUN 2025',
    title: 'The fast to-do foundation',
    description:
        'Today, Tomorrow and one quick swipe made planning feel instant.',
    icon: Icons.rocket_launch_rounded,
    color: Color(0xFF536DFE),
  ),
  ChangelogMilestone(
    version: 'v0.1.8',
    date: 'AUG 2025',
    title: 'Tasks left the app',
    description:
        'The Android home-screen widget put today\'s list one glance away.',
    icon: Icons.widgets_rounded,
    color: Color(0xFF7C4DFF),
  ),
  ChangelogMilestone(
    version: 'v0.1.47',
    date: 'FEB 2026',
    title: 'Progress became visible',
    description:
        'Stats, completion heatmaps and goals turned small wins into momentum.',
    icon: Icons.insights_rounded,
    color: Color(0xFFFF6D00),
  ),
  ChangelogMilestone(
    version: 'v0.1.61',
    date: 'MAY 2026',
    title: 'Accountability on autopilot',
    description:
        'Scheduled SMS reports shared the day\'s progress with the people who matter.',
    icon: Icons.sms_rounded,
    color: Color(0xFF00A884),
  ),
  ChangelogMilestone(
    version: 'v0.1.68',
    date: 'MAY 2026',
    title: 'A calendar for real life',
    description:
        'The schedule view brought every day and deadline into one flowing timeline.',
    icon: Icons.calendar_month_rounded,
    color: Color(0xFF0288D1),
  ),
  ChangelogMilestone(
    version: 'v0.1.70',
    date: 'JUN 2026',
    title: 'Time became a tool',
    description:
        'Countdowns and the zoomable Chronize timeline made distant plans tangible.',
    icon: Icons.timer_rounded,
    color: Color(0xFFD84315),
  ),
  ChangelogMilestone(
    version: 'v0.1.83',
    date: 'JUL 2026',
    title: 'Reliable alarms arrived',
    description:
        'Offline alarms, snooze and diagnostics kept reminders dependable—even after reboot.',
    icon: Icons.alarm_on_rounded,
    color: Color(0xFFE53935),
  ),
  ChangelogMilestone(
    version: 'v0.1.130',
    date: 'AUG 2026',
    title: 'Your data, everywhere',
    description:
        'Automatic backups, folder sync and Obsidian export kept plans safe and portable.',
    icon: Icons.cloud_done_rounded,
    color: Color(0xFF00897B),
  ),
  ChangelogMilestone(
    version: 'v0.1.157',
    date: 'AUG 2026',
    title: 'Habits found their spark',
    description:
        'Three daily streaks, a yearly calendar and 26 challenges made consistency fun.',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFFF8F00),
  ),
  ChangelogMilestone(
    version: 'v0.1.291',
    date: 'AUG 2026',
    title: 'A personal productivity hub',
    description:
        'Projects, Todoist, food diary, wellbeing, voice input, attachments and global undo came together.',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF3949AB),
  ),
];

enum _ChangelogView { text, poster, heatmap }

final RegExp _releaseHeader =
    RegExp(r'^##\s*\[([^\]]+)\]\s*-\s*(\d{4})-(\d{1,2})-(\d{1,2})');

/// Parses the changelog markdown into releases, newest first as written.
/// Headings without a parsable date are ignored (they cannot be placed on the
/// heatmap), as is anything before the first release heading.
List<ChangelogRelease> parseChangelogReleases(String markdown) {
  final releases = <ChangelogRelease>[];
  ChangelogRelease? current;
  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trimRight();
    final match = _releaseHeader.firstMatch(line.trim());
    if (match != null) {
      current = ChangelogRelease(
        version: match.group(1)!,
        date: DateTime(
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          int.parse(match.group(4)!),
        ),
        entries: <String>[],
      );
      releases.add(current);
      continue;
    }
    if (line.startsWith('## ')) {
      // A heading we cannot date ends the previous release block.
      current = null;
      continue;
    }
    if (current == null || line.trim().isEmpty) continue;
    final trimmed = line.trim();
    if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      current.entries.add(trimmed.substring(2).trim());
    } else if (current.entries.isNotEmpty) {
      // Continuation of the previous bullet.
      current.entries[current.entries.length - 1] =
          '${current.entries.last} $trimmed';
    } else {
      current.entries.add(trimmed);
    }
  }
  return releases;
}

/// Build metadata written by `tool/append_build_time.dart` (and CI), e.g.
/// `APK size: 64.6 MB`: shown as small chips under a release, not as changes.
final RegExp _buildNote = RegExp(
    r'^(Local build|CI build|Build duration \([^)]*\)|APK size|Build size \([^)]*\)):\s*\S');

/// True when a changelog bullet is build metadata rather than a change.
bool isChangelogBuildNote(String entry) => _buildNote.hasMatch(entry);

/// `0.2.105+413` → `0.2.105 (413)`, the way the status card shows versions.
String changelogVersionLabel(String version) {
  final plus = version.indexOf('+');
  return plus < 0
      ? version
      : '${version.substring(0, plus)} (${version.substring(plus + 1)})';
}

class ChangelogPage extends StatefulWidget {
  const ChangelogPage({
    Key? key,
    this.assetPath = 'CHANGELOG.md',
    this.showStoryPoster = true,
    this.updateService,
  }) : super(key: key);

  /// Whose builds pulling down checks for when no [AutoUpdateFlow] runs
  /// (off Android): Best Music passes its own; default BestToDo's.
  final UpdateService? updateService;

  /// Bundled asset to render — BestToDo's own `CHANGELOG.md` by default, or
  /// Best Music's `CHANGELOG_MUSIC.md` from [MusicPlayerPage]'s drawer (the
  /// two apps changelog independently since the split, CLAUDE.md/SPEC.md
  /// §10.6i).
  final String assetPath;

  /// Whether the "development story" poster toggle is offered. Off for Best
  /// Music: [changelogMilestones] is BestToDo's own curated history and
  /// would be wrong to show under Best Music's changelog.
  final bool showStoryPoster;

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  static const double _cellSize = 12;
  static const double _cellGap = 3;
  static const double _weekGap = 3;
  static const double _monthLabelHeight = 16;
  static const double _monthLabelMaxWidth = 60;
  static const double _leftLabelsWidth = 32;
  static const int _daysPerWeek = 7;

  final ScrollController _heatmapScrollController = ScrollController();
  Future<String>? _changelog;
  _ChangelogView _view = _ChangelogView.text;
  DateTime? _selectedDay;

  /// The running `x.y.z+build` and when it was installed, for the status
  /// card and the installed version's check mark; null until loaded.
  String? _running;
  InstallInfo? _installInfo;

  /// Whose builds the status card and the pull-down are about: Best Music
  /// passes its own; otherwise the running app's [AutoUpdateFlow], which
  /// defaults to BestToDo's.
  UpdateService get _service =>
      widget.updateService ??
      AutoUpdateFlow.current?.service ??
      UpdateService.instance;

  /// The running app's automatic update, when it is about [_service]; null
  /// in tests and off Android.
  AutoUpdateFlow? get _flow {
    final flow = AutoUpdateFlow.current;
    return flow != null && identical(flow.service, _service) ? flow : null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatus());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // DefaultAssetBundle falls back to rootBundle in the app; tests can swap it.
    _changelog ??= DefaultAssetBundle.of(context).loadString(widget.assetPath);
  }

  Future<void> _loadStatus() async {
    final service = _service;
    await service.loadUpdateStatus();
    final running = await service.currentVersionWithBuild();
    final installed = await InstallInfoService.load();
    if (!mounted) return;
    setState(() {
      _running = running;
      _installInfo = installed;
    });
  }

  @override
  void dispose() {
    _heatmapScrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToRight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_heatmapScrollController.hasClients) return;
      final max = _heatmapScrollController.position.maxScrollExtent;
      if (max > 0) _heatmapScrollController.jumpTo(max);
    });
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Map<DateTime, List<ChangelogRelease>> _releasesByDay(
    List<ChangelogRelease> releases,
  ) {
    final byDay = <DateTime, List<ChangelogRelease>>{};
    for (final release in releases) {
      byDay.putIfAbsent(_dateOnly(release.date), () => []).add(release);
    }
    return byDay;
  }

  List<Color> _legendColors(BuildContext context) {
    return [
      Theme.of(context).colorScheme.surfaceContainerHighest,
      Colors.green.shade200,
      Colors.green.shade400,
      Colors.green.shade600,
      Colors.green.shade800,
    ];
  }

  Color _colorForCount(int count, BuildContext context) {
    final colors = _legendColors(context);
    if (count <= 0) return colors[0];
    if (count == 1) return colors[1];
    if (count == 2) return colors[2];
    if (count == 3) return colors[3];
    return colors[4];
  }

  String _shortMonthName(int month) {
    const names = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month];
  }

  /// Label above a week column: the month when it changes, with the year
  /// appended on the first column and whenever the year rolls over.
  String _monthLabel(List<DateTime> weekStarts, int weekIndex) {
    final weekStart = weekStarts[weekIndex];
    final previous = weekIndex == 0 ? null : weekStarts[weekIndex - 1];
    final newYear = previous == null || weekStart.year != previous.year;
    final newMonth = previous == null || weekStart.month != previous.month;
    if (!newMonth && !newYear) return '';
    final month = _shortMonthName(weekStart.month);
    return newYear ? '$month ${weekStart.year}' : month;
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _plural(int count, String word) =>
      '$count $word${count == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Changelog',
        actions: [
          if (widget.showStoryPoster)
            IconButton(
              icon: const Icon(Icons.auto_awesome_rounded),
              tooltip: _view == _ChangelogView.poster
                  ? 'Show changelog text'
                  : 'Show development story',
              onPressed: () {
                setState(() => _view = _view == _ChangelogView.poster
                    ? _ChangelogView.text
                    : _ChangelogView.poster);
              },
            ),
          IconButton(
            icon: const Icon(Icons.calendar_view_month),
            tooltip: _view == _ChangelogView.heatmap
                ? 'Show changelog text'
                : 'Show update heatmap',
            onPressed: () {
              setState(() => _view = _view == _ChangelogView.heatmap
                  ? _ChangelogView.text
                  : _ChangelogView.heatmap);
              if (_view == _ChangelogView.heatmap) _scheduleScrollToRight();
            },
          ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _changelog,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_view == _ChangelogView.text) {
            // Anything above the first release (title, a developer intro)
            // isn't a release and isn't shown.
            final releases = parseChangelogReleases(snapshot.data!);
            return RefreshIndicator(
              onRefresh: _checkForUpdates,
              child: SelectionArea(
                child: ListView.builder(
                  key: const Key('changelog-release-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: releases.length + 1,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: index == 0
                        ? _buildStatusCard()
                        : _buildReleaseCard(releases[index - 1]),
                  ),
                ),
              ),
            );
          }
          if (_view == _ChangelogView.poster) return _buildStoryPoster();
          return _buildHeatmapView(parseChangelogReleases(snapshot.data!));
        },
      ),
    );
  }

  /// Pull-down: checks for a newer build of this app (any channel) right away.
  /// One that is found downloads in the background and the app asks to
  /// install it when it is complete, like the automatic check
  /// ([AutoUpdateFlow]).
  Future<void> _checkForUpdates() async {
    final flow = _flow;
    String message;
    try {
      final update = flow != null
          ? await flow.checkNow()
          : await _service.checkForUpdate();
      message = update == null
          ? 'You have the newest version.'
          : flow == null
              ? 'v${update.version} is out: About → Check for updates.'
              : 'v${update.version} found: downloading in the background, '
                  "you'll be asked to install it.";
    } on UpdateRateLimitedException catch (e) {
      message = e.toString();
    } catch (e) {
      message = 'Update check failed: $e';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The card at the top of the release list (same as Hally Remote and
  /// BestCollage): the running version and whether it is up to date, when
  /// it was downloaded and installed, a newer build waiting to be installed
  /// and when GitHub was last checked. Follows the background poll too.
  Widget _buildStatusCard() {
    final service = _service;
    final flow = _flow;
    return ListenableBuilder(
      listenable: Listenable.merge([
        service.checking,
        service.lastCheck,
        service.lastCheckedAt,
        service.lastDownload,
        if (flow != null) flow.ready,
      ]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final running = _running;
        final check = service.lastCheck.value;
        final latest = check != null && check.hasUpdate ? check.latest : null;
        final checking = service.checking.value;
        final title = [
          running == null
              ? 'Current version'
              : 'Current version ${changelogVersionLabel(running)}',
          if (checking)
            'Checking…'
          else if (latest != null)
            'Update available ${changelogVersionLabel(latest.version)}'
          else if (check != null)
            'Up to date',
        ].join(' · ');
        final download = service.lastDownload.value;
        final installedAt = _installInfo?.installedAt;
        // When the running build was downloaded and installed ...
        final times = [
          if (download != null && download.version == running)
            'Downloaded ${formatTimerDateTime(download.at)}',
          if (installedAt != null)
            'Installed ${formatTimerDateTime(installedAt)}',
        ].join(' · ');
        // ... and a newer one that is downloaded and waiting.
        final waiting = latest != null && download?.version == latest.version
            ? '${changelogVersionLabel(latest.version)} downloaded '
                '${formatTimerDateTime(download!.at)} · ready to install'
            : null;
        final checkedAt = service.lastCheckedAt.value;
        final checked = checkedAt == null
            ? 'Not checked yet'
            : 'Last checked ${formatTimerDateTime(checkedAt)}';
        return Card(
          key: const Key('changelog-update-status'),
          margin: EdgeInsets.zero,
          color: latest != null ? scheme.primaryContainer : null,
          child: ListTile(
            leading: checking
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(latest != null
                    ? Icons.system_update_outlined
                    : Icons.verified_outlined),
            title: Text(title),
            subtitle: Text([
              if (times.isNotEmpty) times,
              if (waiting != null) waiting,
              '$checked · Pull down to check for updates',
            ].join('\n')),
            trailing: latest != null && latest.apkUrl != null && flow != null
                ? FilledButton(
                    key: const Key('changelog-update-install'),
                    onPressed: () => unawaited(flow.install(latest)),
                    child: const Text('Install'),
                  )
                : null,
          ),
        );
      },
    );
  }

  /// One release: version (with a check mark on the installed one) and
  /// date, its changes as bullets, build metadata as small chips.
  Widget _buildReleaseCard(ChangelogRelease release) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = _running;
    final installed =
        running != null && running.split('+').first == release.version;
    final changes =
        release.entries.where((e) => !isChangelogBuildNote(e)).toList();
    final notes = release.entries.where(isChangelogBuildNote).toList();
    return Card(
      key: ValueKey('changelog-release-${release.version}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  release.version,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (installed) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle,
                    key: const Key('changelog-installed-version'),
                    size: 18,
                    color: scheme.primary,
                    semanticLabel: 'Installed version',
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatTimerDate(release.date),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            for (final entry in changes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(child: MarkdownBody(data: entry)),
                  ],
                ),
              ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final note in notes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(note,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStoryPoster() {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: SelectionArea(
        child: ListView(
          key: const Key('development-story-poster'),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text('10 MILESTONES · 15 MONTHS',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  )),
                    ),
                    const SizedBox(height: 14),
                    Text('The story of BestToDo',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                            )),
                    const SizedBox(height: 8),
                    Text(
                      'From a quick swipe list to a private productivity hub—one useful release at a time.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 30),
                    ...List.generate(changelogMilestones.length, (index) {
                      return _buildMilestone(changelogMilestones[index], index);
                    }),
                    const SizedBox(height: 8),
                    Icon(Icons.flag_rounded, color: scheme.primary, size: 30),
                    const SizedBox(height: 8),
                    Text('And the story keeps moving…',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestone(ChangelogMilestone milestone, int index) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = index == changelogMilestones.length - 1;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: milestone.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: milestone.color.withValues(alpha: .25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(milestone.icon, color: Colors.white, size: 25),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                        width: 3,
                        color: milestone.color.withValues(alpha: .28)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 20 : 26),
              child: Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: scheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .65)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 5,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(milestone.date,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: milestone.color,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  )),
                          Text(milestone.version,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  )),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(milestone.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  )),
                      const SizedBox(height: 5),
                      Text(milestone.description,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapView(List<ChangelogRelease> releases) {
    if (releases.isEmpty) {
      return const Center(child: Text('No dated releases in the changelog'));
    }
    final byDay = _releasesByDay(releases);
    final days = byDay.keys.toList()..sort();
    final firstDay = days.first;
    final today = _dateOnly(DateTime.now());
    final lastDay = days.last.isAfter(today) ? days.last : today;
    // Grid starts on the Monday of the first release's week.
    final gridStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    final weeks = (lastDay.difference(gridStart).inDays ~/ _daysPerWeek) + 1;
    final weekStarts = List<DateTime>.generate(
      weeks,
      (index) => gridStart.add(Duration(days: index * _daysPerWeek)),
    );
    final totalEntries =
        releases.fold<int>(0, (sum, r) => sum + r.entries.length);
    // Start on the newest release so the details panel is never empty.
    _selectedDay ??= days.last;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Updates over time',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${_plural(releases.length, 'release')} · '
            '${_plural(totalEntries, 'change')} · '
            'since ${_formatDate(firstDay)}. Tap a day to see its changes.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _leftLabelsWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: _monthLabelHeight + 4),
                  child: Column(
                    children: List.generate(_daysPerWeek, (dayIndex) {
                      const labels = {0: 'Mon', 2: 'Wed', 4: 'Fri'};
                      return SizedBox(
                        height: _cellSize + _cellGap,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            labels[dayIndex] ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _heatmapScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(weeks, (weekIndex) {
                          final label = _monthLabel(weekStarts, weekIndex);
                          return Padding(
                            padding: const EdgeInsets.only(right: _weekGap),
                            child: SizedBox(
                              width: _cellSize,
                              height: _monthLabelHeight,
                              child: label.isEmpty
                                  ? null
                                  // Labels are wider than one cell; let them
                                  // run into the (empty) columns after them.
                                  : OverflowBox(
                                      alignment: Alignment.centerLeft,
                                      maxWidth: _monthLabelMaxWidth,
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(weeks, (weekIndex) {
                          return Padding(
                            padding: const EdgeInsets.only(right: _weekGap),
                            child: Column(
                              children: List.generate(_daysPerWeek, (dayIndex) {
                                final date = weekStarts[weekIndex]
                                    .add(Duration(days: dayIndex));
                                return _buildDayCell(
                                    date, byDay[date] ?? const []);
                              }),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text('Releases', style: Theme.of(context).textTheme.bodySmall),
              ...[
                const MapEntry('0', 0),
                const MapEntry('1', 1),
                const MapEntry('2', 2),
                const MapEntry('3', 3),
                const MapEntry('4+', 4),
              ].map((entry) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _cellSize,
                      height: _cellSize,
                      decoration: BoxDecoration(
                        color: _colorForCount(entry.value, context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(entry.key,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              }),
            ],
          ),
        ),
        const Divider(height: 1),
        SelectionArea(child: _buildDayDetails(byDay)),
      ],
    );
  }

  Widget _buildDayCell(DateTime date, List<ChangelogRelease> releases) {
    final selected = _selectedDay == date;
    final color = _colorForCount(releases.length, context);
    final message = releases.isEmpty
        ? '${_formatDate(date)}: no updates'
        : '${_formatDate(date)}: ${_plural(releases.length, 'release')}, '
            '${_plural(releases.fold<int>(0, (s, r) => s + r.entries.length), 'change')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: _cellGap),
      child: Tooltip(
        message: message,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedDay = date);
          },
          child: Container(
            width: _cellSize,
            height: _cellSize,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayDetails(Map<DateTime, List<ChangelogRelease>> byDay) {
    final day = _selectedDay;
    if (day == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Tap a day in the heatmap to see what changed.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final releases = byDay[day] ?? const <ChangelogRelease>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(day),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (releases.isEmpty)
            Text(
              'No updates on this day.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...releases.map(
              (release) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Version ${release.version}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        if (release.entries.isEmpty)
                          Text(
                            'No details recorded.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        else
                          ...release.entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• '),
                                  Expanded(
                                    child: Text(
                                      entry,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
