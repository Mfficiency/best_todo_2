# CI test reports

Machine-written store, no app code lives here.

- `latest.json` — the newest `flutter test` run across all branches.
- `branches/<branch>.json` — the newest run per branch.

The app fetches `latest.json` (`TestReportService.onlineReportUrl`) and builds
package it into `assets/test_report.json` via `tool/sync_test_report.dart`, so
the Test Results page shows the latest run offline and on any branch.
Written by `tool/ci/publish_test_report.sh`.
