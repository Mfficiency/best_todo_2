import 'package:flutter/material.dart';

import '../models/test_report.dart';
import '../services/test_report_service.dart';
import '../util/date_time_format.dart';
import 'subpage_app_bar.dart';
import 'widgets/spacing.dart';

/// Shows the results of the CI `flutter test` run for this build (see
/// [TestReportService]). Honestly reports "no data" when no report has been
/// generated — it never invents pass/fail numbers.
class TestResultsPage extends StatefulWidget {
  const TestResultsPage({super.key});

  @override
  State<TestResultsPage> createState() => _TestResultsPageState();
}

class _TestResultsPageState extends State<TestResultsPage> {
  Future<DisplayedTestReport>? _future;

  @override
  void initState() {
    super.initState();
    _future = TestReportService.instance.loadForDisplay();
  }

  void _refresh() {
    TestReportService.instance.refreshOnline();
    setState(() {
      _future = TestReportService.instance.loadForDisplay();
    });
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
      body: FutureBuilder<DisplayedTestReport>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final displayed = snapshot.data!;
          final report = displayed.report;
          if (!report.available) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No test report available for this build.\n\n'
                  'CI generates one with tool/generate_test_report.dart; '
                  'local/dev builds ship a placeholder.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _buildReport(context, report, displayed.online);
        },
      ),
    );
  }

  Widget _buildReport(BuildContext context, TestReport report, bool online) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          online
              ? 'Latest online CI run'
              : 'Bundled with this build (offline)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _pill('Passed', report.passed, Colors.green, scheme),
            const SizedBox(width: AppSpacing.sm),
            _pill('Failed', report.failed, Colors.red, scheme),
            const SizedBox(width: AppSpacing.sm),
            _pill('Skipped', report.skipped, Colors.orange, scheme),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (report.appVersion.isNotEmpty)
          _meta('Version', report.appVersion),
        if (report.branch.isNotEmpty) _meta('Branch', report.branch),
        if (report.commit.isNotEmpty) _meta('Commit', report.commit),
        if (report.generatedAt != null)
          _meta('Generated', formatDateTime(report.generatedAt!)),
        if (report.failures.isNotEmpty) ...[
          const Divider(height: AppSpacing.xl),
          Text('Failures',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          ...report.failures.map(
            (f) => Card(
              child: ListTile(
                title: Text(f.name),
                subtitle: Text(f.error),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _pill(String label, int count, Color color, ColorScheme scheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.md),
        ),
        child: Column(
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      );
}
