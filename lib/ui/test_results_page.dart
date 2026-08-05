import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/test_report.dart';
import '../services/test_report_service.dart';
import 'subpage_app_bar.dart';

/// Data assembled for one render of the Test Results page: the newest report
/// found across the three layers (see `TestReportService`), plus the version of
/// the app the user is currently running.
class _PageData {
  final DisplayedTestReport displayed;
  final String currentVersion;

  const _PageData({required this.displayed, required this.currentVersion});
}

/// Shows the newest known test run in the Tools section. The report is packaged
/// into every build (`assets/test_report.json`), so this page has data offline,
/// on any branch, and in `flutter run -d chrome`; a network refresh pulls the
/// newest run CI published from any branch and caches it for later offline
/// launches (see `TestReportService`).
class TestResultsPage extends StatefulWidget {
  const TestResultsPage({Key? key}) : super(key: key);

  @override
  State<TestResultsPage> createState() => _TestResultsPageState();
}

class _TestResultsPageState extends State<TestResultsPage> {
  late Future<_PageData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PageData> _load() async {
    await Config.ensureVersionLoaded();
    final displayed = await TestReportService.instance.loadForDisplay();
    return _PageData(
      displayed: displayed,
      currentVersion: Config.versionWithBuild,
    );
  }

  Future<void> _refresh() async {
    TestReportService.instance.refreshOnline();
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Test Results',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<_PageData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = data.displayed.report;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _VersionCard(
                currentVersion: data.currentVersion,
                report: report,
                displayed: data.displayed,
              ),
              if (!report.available)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 24, 4, 4),
                  child: Text(
                    'No test run is packaged with this build yet.\n\n'
                    'Every build packages the newest known run into '
                    'assets/test_report.json (CI does this, and so does '
                    'tool/sync_test_report.dart locally). Pull the branch '
                    'again, or run the tests, to fill this in.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                const SizedBox(height: 12),
                _SummaryCard(report: report),
                if (report.failures.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: Text(
                      'Failed tests',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ...report.failures.map((f) => _FailureTile(failure: f)),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Renders "3 hours ago" style ages so a stale report is obvious at a glance —
/// the single most useful fact about a test report you did not just trigger.
String formatReportAge(DateTime generatedAt, {DateTime? now}) {
  final delta = (now ?? DateTime.now()).difference(generatedAt);
  if (delta.isNegative || delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) {
    return '${delta.inMinutes} minute${delta.inMinutes == 1 ? '' : 's'} ago';
  }
  if (delta.inHours < 24) {
    return '${delta.inHours} hour${delta.inHours == 1 ? '' : 's'} ago';
  }
  final days = delta.inDays;
  if (days < 30) return '$days day${days == 1 ? '' : 's'} ago';
  final months = days ~/ 30;
  return '$months month${months == 1 ? '' : 's'} ago';
}

/// States where the shown run came from, how old it is, which branch it ran on,
/// and how its version relates to the one the user is running.
class _VersionCard extends StatelessWidget {
  final String currentVersion;
  final TestReport report;
  final DisplayedTestReport displayed;

  const _VersionCard({
    required this.currentVersion,
    required this.report,
    required this.displayed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tested = report.appVersion.isNotEmpty
        ? report.appVersion
        : (report.available ? 'unknown' : '—');
    final matches =
        report.appVersion.isNotEmpty && report.appVersion == currentVersion;
    final generatedAt = report.generatedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  displayed.online ? Icons.cloud_done : Icons.cloud_off,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayed.sourceLabel,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            if (report.available && generatedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Ran ${formatReportAge(generatedAt.toLocal())}'
                '${report.branch.isNotEmpty ? ' on ${report.branch}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            _VersionRow(label: 'You are running', value: currentVersion),
            const SizedBox(height: 4),
            _VersionRow(label: 'Version tested', value: tested),
            if (report.available) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    matches ? Icons.check_circle_outline : Icons.info_outline,
                    size: 18,
                    color:
                        matches ? Colors.green : theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      matches
                          ? 'These results are for the version you are running.'
                          : 'Heads up: these results are for a different '
                              'version than the one you are running.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (report.runUrl.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open CI run'),
                  onPressed: () => launchUrl(
                    Uri.parse(report.runUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  final String label;
  final String value;

  const _VersionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final TestReport report;

  const _SummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = report.failed == 0;
    final statusColor = ok ? Colors.green : theme.colorScheme.error;
    final generated = report.generatedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.error,
                  color: statusColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ok
                        ? 'All tests passed'
                        : '${report.failed} test'
                            '${report.failed == 1 ? '' : 's'} failed',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${report.passed} passed · ${report.failed} failed · '
              '${report.skipped} skipped · ${report.total} total',
            ),
            if (generated != null || report.commit.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (report.commit.isNotEmpty)
                    'commit ${report.commit}'
                        '${report.branch.isNotEmpty ? ' (${report.branch})' : ''}',
                  if (generated != null)
                    'run ${generated.toLocal().toString().split('.').first}',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FailureTile extends StatelessWidget {
  final TestFailureDetail failure;

  const _FailureTile({required this.failure});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.close, color: theme.colorScheme.error),
        title: Text(failure.name),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            failure.error.isEmpty ? 'No error details recorded.' : failure.error,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
