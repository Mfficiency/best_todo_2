import 'package:flutter/material.dart';

import '../config.dart';
import '../models/test_report.dart';
import '../services/test_report_service.dart';
import 'subpage_app_bar.dart';

/// Data assembled for one render of the Test Results page: the chosen report,
/// whether it came from the latest online CI run, and the version of the app
/// the user is currently running.
class _PageData {
  final DisplayedTestReport displayed;
  final String currentVersion;

  const _PageData({required this.displayed, required this.currentVersion});
}

/// Shows CI test results in the Tools section. Prefers the latest report
/// published online (dev branch); falls back to the report bundled with this
/// build when offline. The header makes the version you are running and the
/// version the tests ran against explicit (see `TestReportService`).
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
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _VersionCard(
                  currentVersion: data.currentVersion,
                  report: report,
                  online: data.displayed.online,
                ),
                if (!report.available)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 24, 4, 4),
                    child: Text(
                      "Couldn't reach the latest online test report, and no "
                      'report was bundled with this build.\n\n'
                      'CI publishes results for each build; local and dev '
                      'builds carry no bundled report, and the online report '
                      'needs a network connection.',
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
            ),
          );
        },
      ),
    );
  }
}

/// States the version the app is running vs the version the shown report was
/// tested against, and whether the report is the latest online run or the
/// offline bundled fallback.
class _VersionCard extends StatelessWidget {
  final String currentVersion;
  final TestReport report;
  final bool online;

  const _VersionCard({
    required this.currentVersion,
    required this.report,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tested = report.appVersion.isNotEmpty
        ? report.appVersion
        : (report.available ? 'unknown' : '—');
    final matches =
        report.appVersion.isNotEmpty && report.appVersion == currentVersion;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  online ? Icons.cloud_done : Icons.cloud_off,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    online
                        ? 'Latest online run · ${report.branch.isNotEmpty ? report.branch : 'dev'}'
                        : 'Bundled with this build (offline)',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
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
                    color: matches
                        ? Colors.green
                        : theme.colorScheme.tertiary,
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
