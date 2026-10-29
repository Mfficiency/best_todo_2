import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pc_watcher_status.dart';
import '../services/pc_watcher_service.dart';
import 'subpage_app_bar.dart';

/// Which builds the log shows. [built] (the default) is every run that
/// actually built something — all but the "already published" no-ops.
enum _LogFilter { built, published, failed, skipped, all }

/// Tools → PC Watcher: what the laptop builder did — every build with its
/// time, duration, result and APK size, failures with their error, and what
/// is still pending (channels with an unbuilt commit, jobs waiting on the
/// runner). Reads the status the builder pushes to the private
/// Mfficiency/laptop-builder repo (see [PcWatcherService]).
class PcWatcherPage extends StatefulWidget {
  final PcWatcherService? service;

  /// "Now", for the "x min ago" texts; injectable for tests.
  final DateTime Function()? clock;

  const PcWatcherPage({super.key, this.service, this.clock});

  @override
  State<PcWatcherPage> createState() => _PcWatcherPageState();
}

class _PcWatcherPageState extends State<PcWatcherPage> {
  PcWatcherService get _service => widget.service ?? PcWatcherService.instance;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool _loading = true;
  String? _token;
  PcWatcherSnapshot? _snapshot;
  String? _error;
  _LogFilter _filter = _LogFilter.built;
  String? _app;

  /// The log's filter chips start folded away.
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await _service.loadToken();
    final cached = await _service.loadCached();
    if (!mounted) return;
    setState(() {
      _token = token;
      _snapshot = cached;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final token = _token;
    if (token == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.fetch(token);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } on PcWatcherException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editToken() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TokenDialog(initial: _token ?? ''),
    );
    if (result == null) return;
    await _service.saveToken(result);
    final token = await _service.loadToken();
    if (!mounted) return;
    setState(() {
      _token = token;
      if (token == null) _snapshot = null;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'PC Watcher',
        actions: [
          if (_token != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _refresh,
            ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'GitHub token',
            onPressed: _editToken,
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final snapshot = _snapshot;
    if (_token == null && snapshot == null) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : _SetupCard(onAddToken: _editToken);
    }
    if (snapshot == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) _ErrorBanner(message: _error!, onRetry: _refresh),
        ],
      );
    }
    final status = snapshot.status;
    final builds = _filteredBuilds(status);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ErrorBanner(message: _error!, onRetry: _refresh),
            ),
          _MachineCard(snapshot: snapshot, now: _now()),
          _PendingSection(
              status: status, jobs: snapshot.runnerJobs, now: _now()),
          _buildLogHeader(context),
          if (_filtersOpen) _filterChips(status),
          if (builds.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No builds match')),
            ),
          for (final build in builds.take(200))
            _BuildTile(entry: build, now: _now()),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.insights),
            title: const Text('Stats'),
            subtitle: const Text('Last 7 days: published, failed, build times'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _PcWatcherStatsPage(status: status, now: _now()),
            )),
          ),
        ],
      ),
    );
  }

  List<PcWatcherBuild> _filteredBuilds(PcWatcherStatus status) {
    return status.builds.where((b) {
      if (_app != null && b.app != _app) return false;
      switch (_filter) {
        case _LogFilter.built:
          return b.result != PcBuildResult.unchanged;
        case _LogFilter.all:
          return true;
        case _LogFilter.published:
          return b.result == PcBuildResult.published;
        case _LogFilter.failed:
          return b.result == PcBuildResult.failed;
        case _LogFilter.skipped:
          return b.result == PcBuildResult.unchanged;
      }
    }).toList();
  }

  static const _filterLabels = {
    _LogFilter.built: 'Built',
    _LogFilter.published: 'Published',
    _LogFilter.failed: 'Failed',
    _LogFilter.skipped: 'Already published',
    _LogFilter.all: 'All',
  };

  /// "Build log" with the fold-out Filters toggle; while folded, a short
  /// note says what the list is narrowed to.
  Widget _buildLogHeader(BuildContext context) {
    final active = [
      if (_filter != _LogFilter.built) _filterLabels[_filter]!,
      if (_app != null) _app!,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('Build log',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton.icon(
            key: const Key('pc-watcher-filters-toggle'),
            onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
            icon: Icon(_filtersOpen ? Icons.expand_less : Icons.filter_list),
            label: Text(active.isEmpty
                ? 'Filters'
                : 'Filters: ${active.join(', ')}'),
          ),
        ],
      ),
    );
  }

  Widget _filterChips(PcWatcherStatus status) {
    const labels = _filterLabels;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 0,
        children: [
          for (final entry in labels.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _filter == entry.key,
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
          for (final app in status.apps)
            FilterChip(
              label: Text(app),
              selected: _app == app,
              onSelected: (on) => setState(() => _app = on ? app : null),
            ),
        ],
      ),
    );
  }
}

Widget _sectionHeader(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );

/// "just now", "5 min ago", "3 h ago", "2 days ago".
String _ago(DateTime? at, DateTime now) {
  if (at == null) return 'never';
  final diff = now.difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 48) return '${diff.inHours} h ago';
  return '${diff.inDays} days ago';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "Today 17:44", "Yesterday 09:01", "8 Oct 17:44".
String _when(DateTime? at, DateTime now) {
  if (at == null) return '?';
  final time = '${_two(at.hour)}:${_two(at.minute)}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today $time';
  if (days == 1) return 'Yesterday $time';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${at.day} ${months[at.month - 1]} $time';
}

class _SetupCard extends StatelessWidget {
  final VoidCallback onAddToken;

  const _SetupCard({required this.onAddToken});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.computer, size: 56),
        const SizedBox(height: 16),
        Text('Watch the build PC',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'The laptop publishes its build log (builds, failures, durations, '
          'APK sizes and what is still pending) to the private '
          '${PcWatcherService.repo} repo. To read it here, create a '
          'fine-grained GitHub token for that repo only with '
          '"Contents: Read-only" (add "Actions: Read-only" to also see '
          'builds waiting on the runner) and paste it once.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            icon: const Icon(Icons.key),
            label: const Text('Add token'),
            onPressed: onAddToken,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
        title: Text(message,
            style: TextStyle(color: scheme.onErrorContainer)),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}

/// The PC itself: online (checked in the last 20 minutes), what it's
/// building right now.
class _MachineCard extends StatelessWidget {
  final PcWatcherSnapshot snapshot;
  final DateTime now;

  const _MachineCard({required this.snapshot, required this.now});

  @override
  Widget build(BuildContext context) {
    final status = snapshot.status;
    final lastCheck = status.lastCheckAt ?? status.updatedAt;
    final quiet = lastCheck == null ? null : now.difference(lastCheck);
    final Color color;
    final String state;
    if (quiet == null) {
      color = Colors.grey;
      state = 'No check seen yet';
    } else if (quiet.inMinutes <= 20) {
      color = Colors.green;
      state = 'Online';
    } else if (quiet.inHours < 3) {
      color = Colors.orange;
      state = 'Quiet';
    } else {
      color = Colors.grey;
      state = 'Offline';
    }
    final building = status.channels.where((c) => c.state == 'building');
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 12, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.machine.isEmpty ? 'Build PC' : status.machine,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(state, key: const Key('pc-watcher-machine-state')),
              ],
            ),
            const SizedBox(height: 6),
            Text('Last check ${_ago(lastCheck, now)} · '
                'downloaded ${_ago(snapshot.fetchedAt, now)}'),
            for (final c in building)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Building ${c.app} (${c.branch}) since '
                  '${_ago(c.since, now).replaceAll(' ago', '')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The stats, one tap away from the bottom of the page.
class _PcWatcherStatsPage extends StatelessWidget {
  final PcWatcherStatus status;
  final DateTime now;

  const _PcWatcherStatsPage({required this.status, required this.now});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'PC Watcher stats'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [_StatsCard(status: status, now: now)],
      ),
    );
  }
}

/// Last 7 days at a glance.
class _StatsCard extends StatelessWidget {
  final PcWatcherStatus status;
  final DateTime now;

  const _StatsCard({required this.status, required this.now});

  @override
  Widget build(BuildContext context) {
    final week = status.builds.where((b) =>
        b.startedAt != null && now.difference(b.startedAt!).inDays < 7);
    final published =
        week.where((b) => b.result == PcBuildResult.published).toList();
    final failed = week.where((b) => b.result == PcBuildResult.failed).length;
    final durations = published
        .map((b) => b.durationSeconds)
        .whereType<int>()
        .toList();
    final avg = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) ~/ durations.length;
    final buildTime = week
        .map((b) => b.durationSeconds)
        .whereType<int>()
        .fold<int>(0, (a, b) => a + b);
    Widget stat(String value, String label, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text('Last 7 days', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                stat('${published.length}', 'published'),
                stat('$failed', 'failed',
                    color: failed > 0
                        ? Theme.of(context).colorScheme.error
                        : null),
                stat(avg == null ? '–' : formatBuildDuration(avg),
                    'avg build'),
                stat(formatBuildDuration(buildTime), 'PC busy'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Channels with an unbuilt (or failed) commit, plus runner jobs.
class _PendingSection extends StatelessWidget {
  final PcWatcherStatus status;
  final List<PcRunnerJob>? jobs;
  final DateTime now;

  const _PendingSection(
      {required this.status, required this.jobs, required this.now});

  @override
  Widget build(BuildContext context) {
    final pending = status.pending;
    final open = jobs ?? const <PcRunnerJob>[];
    final count = pending.length + open.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, count == 0 ? 'Pending' : 'Pending ($count)'),
        if (count == 0)
          const ListTile(
            leading: Icon(Icons.done_all),
            title: Text('Nothing pending'),
            subtitle: Text('Every channel\'s newest commit is built'),
          ),
        for (final c in pending)
          ListTile(
            leading: _stateIcon(context, c.state),
            title: Text('${c.app} · ${c.branch}'),
            subtitle: Text([
              _stateLabel(c.state),
              if (c.since != null) 'since ${_ago(c.since, now)}',
              if (c.remoteHead.length >= 7) c.remoteHead.substring(0, 7),
              if (c.lastError != null) c.lastError!,
            ].join(' · ')),
            isThreeLine: c.lastError != null,
          ),
        for (final job in open)
          ListTile(
            leading: Icon(job.isRunning ? Icons.sync : Icons.schedule),
            title: Text(job.title),
            subtitle: Text(
                'Runner: ${job.isRunning ? 'running' : job.status.replaceAll('_', ' ')}'
                ' · ${_ago(job.createdAt, now)}'),
          ),
        if (jobs == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Runner jobs hidden: the token has no "Actions: Read-only".',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  static String _stateLabel(String state) {
    switch (state) {
      case 'pending':
        return 'New commit waiting';
      case 'queued':
        return 'Waiting for a running build';
      case 'building':
        return 'Building';
      case 'failed':
        return 'Failed, retried on the next check';
      case 'idle':
        return 'Check failed';
    }
    return state;
  }

  static Widget _stateIcon(BuildContext context, String state) {
    switch (state) {
      case 'building':
        return const Icon(Icons.sync, color: Colors.blue);
      case 'failed':
      case 'idle':
        return Icon(Icons.error, color: Theme.of(context).colorScheme.error);
      case 'queued':
        return const Icon(Icons.hourglass_top);
    }
    return const Icon(Icons.schedule);
  }
}

Widget _resultIcon(BuildContext context, PcBuildResult result) {
  switch (result) {
    case PcBuildResult.published:
      return const Icon(Icons.check_circle, color: Colors.green);
    case PcBuildResult.failed:
      return Icon(Icons.error, color: Theme.of(context).colorScheme.error);
    case PcBuildResult.building:
      return const Icon(Icons.sync, color: Colors.blue);
    case PcBuildResult.unchanged:
      return const Icon(Icons.remove_circle_outline, color: Colors.grey);
    case PcBuildResult.unknown:
      return const Icon(Icons.help_outline, color: Colors.grey);
  }
}

String _resultLabel(PcBuildResult result) {
  switch (result) {
    case PcBuildResult.published:
      return 'Published';
    case PcBuildResult.failed:
      return 'Failed';
    case PcBuildResult.building:
      return 'Building';
    case PcBuildResult.unchanged:
      return 'Already published, nothing built';
    case PcBuildResult.unknown:
      return 'Unknown';
  }
}

class _BuildTile extends StatelessWidget {
  final PcWatcherBuild entry;
  final DateTime now;

  const _BuildTile({required this.entry, required this.now});

  @override
  Widget build(BuildContext context) {
    final b = entry;
    final versions = b.published.map((a) => a.version).toSet().join(', ');
    final title = versions.isEmpty
        ? '${b.app} · ${b.branch}'
        : '${b.app} $versions · ${b.branch}';
    final size = b.apkSizeBytes;
    final details = [
      _when(b.startedAt, now),
      if (b.result == PcBuildResult.building)
        'running ${_ago(b.startedAt, now).replaceAll(' ago', '')}'
      else if (b.durationSeconds != null)
        formatBuildDuration(b.durationSeconds!),
      if (size != null) formatApkSize(size),
      if (b.result == PcBuildResult.unchanged) 'already published',
    ].join(' · ');
    return ListTile(
      leading: _resultIcon(context, b.result),
      title: Text(title),
      subtitle: Text(
        b.result == PcBuildResult.failed && b.error != null
            ? '$details\n${b.error}'
            : details,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: b.result == PcBuildResult.failed && b.error != null,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _BuildDetails(entry: b, now: now),
      ),
    );
  }
}

class _BuildDetails extends StatelessWidget {
  final PcWatcherBuild entry;
  final DateTime now;

  const _BuildDetails({required this.entry, required this.now});

  @override
  Widget build(BuildContext context) {
    final b = entry;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              Expanded(child: SelectableText(value)),
            ],
          ),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              _resultIcon(context, b.result),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${b.app} · ${b.branch}',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: 12),
          row('Result', _resultLabel(b.result)),
          row('Started', _when(b.startedAt, now)),
          if (b.finishedAt != null) row('Finished', _when(b.finishedAt, now)),
          if (b.durationSeconds != null)
            row('Duration', formatBuildDuration(b.durationSeconds!)),
          row('Commit', b.sha.isEmpty ? '?' : b.sha),
          if (b.buildNumber != null) row('Build number', '${b.buildNumber}'),
          row(
              'Started by',
              switch (b.trigger) {
                'push' => 'a push',
                'catch-up' => 'the 10-minute check',
                _ => 'unknown (from the old log)',
              }),
          for (final apk in b.published)
            row(
                apk.app,
                [
                  apk.version,
                  apk.tag,
                  if (apk.sizeBytes != null) formatApkSize(apk.sizeBytes!),
                ].join(' · ')),
          if (b.error != null) ...[
            const SizedBox(height: 12),
            Text('Error', style: Theme.of(context).textTheme.titleSmall),
            SelectableText(b.error!),
          ],
          if (b.log != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('End of the build output',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy output',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: b.log!)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SelectableText(
                b.log!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Paste / replace / remove the read-only token. Owns its controller (see
/// CLAUDE.md: never dispose it right after showDialog returns). Pops the
/// new token, '' to remove it, or null when cancelled.
class _TokenDialog extends StatefulWidget {
  final String initial;

  const _TokenDialog({required this.initial});

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  bool _obscured = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('GitHub token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fine-grained token for ${PcWatcherService.repo} only: '
              'Contents: Read-only (Actions: Read-only optional). Stored on '
              'this phone only.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pc-watcher-token-field'),
            controller: _controller,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Token',
              suffixIcon: IconButton(
                tooltip: _obscured ? 'Show token' : 'Hide token',
                icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscured = !_obscured),
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
