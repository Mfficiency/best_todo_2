import 'package:flutter/material.dart';

import '../models/test_report.dart';
import '../services/test_report_service.dart';
import 'subpage_app_bar.dart';

/// Shows the CI test results bundled with the current build (see
/// `TestReportService`). Reached from the drawer; the drawer/hamburger icon
/// carries a red dot when this report contains failures.
class TestResultsPage extends StatelessWidget {
  const TestResultsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Test Results'),
      body: FutureBuilder<TestReport>(
        future: TestReportService.instance.load(),
        builder: (context, snapshot) {
          final report = snapshot.data;
          if (report == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!report.available) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No test report was bundled with this build.\n\n'
                  'CI embeds the flutter test results into release builds; '
                  'local and dev builds carry no report.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
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
          );
        },
      ),
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
