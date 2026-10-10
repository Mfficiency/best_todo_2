library;

import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The background auto-update (`main.dart`'s `AutoUpdateChecker` wiring,
/// which downloads and installs with no "Download?" question):
/// [downloadUpdateInBackground]'s failure path. The success path (an actual
/// background download via Android's `DownloadManager`) is exercised through
/// [UpdateService.downloadChannelOverride] in `update_service_test.dart`
/// instead — here only the synchronous "no APK asset" failure is covered,
/// since that's what reaches this widget without a platform channel.

void main() {
  setUp(() {
    UpdateService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'a background download with no APK asset reports failure as a snackbar '
      'instead of blocking the app', (tester) async {
    bool? ok;
    final noApk = UpdateInfo(
      version: '9.9.9+999',
      releaseName: 'BestToDo 9.9.9+999',
      htmlUrl: 'https://example.com/release',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  ok = await downloadUpdateInBackground(context, noApk),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Non-blocking: the button (and the rest of the app behind it) stays
    // interactive — there is no barrier-blocking dialog to dismiss.
    expect(find.text('open'), findsOneWidget);
    expect(find.textContaining('This release has no APK to download'),
        findsOneWidget);
    // False tells the auto-updater not to retry this build every minute.
    expect(ok, isFalse);
  });
}
