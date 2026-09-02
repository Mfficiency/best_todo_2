library;

import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The background auto-update prompt (`main.dart`'s `AutoUpdateChecker`
/// wiring): the "New version available" Yes/No dialog, and
/// [downloadUpdateInBackground]'s failure path. The success path (an actual
/// background download via Android's `DownloadManager`) is exercised through
/// [UpdateService.downloadChannelOverride] in `update_service_test.dart`
/// instead — here only the synchronous "no APK asset" failure is covered,
/// since that's what reaches this widget without a platform channel.

/// Captures what the "New version available" dialog handed back.
class _Host {
  bool? result;
}

Future<_Host> _openAvailableDialog(WidgetTester tester, UpdateInfo info) async {
  final host = _Host();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              host.result = await showUpdateAvailableDialog(context, info);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  setUp(() {
    UpdateService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  final info = UpdateInfo(
    version: '9.9.9+999',
    releaseName: 'BestToDo 9.9.9+999',
    htmlUrl: 'https://example.com/release',
    apkUrl: 'https://example.com/BestToDo.apk',
  );

  testWidgets('shows the version and asks to download and install',
      (tester) async {
    await _openAvailableDialog(tester, info);

    expect(find.text('New version available'), findsOneWidget);
    expect(
        find.textContaining('Version 9.9.9+999 is available'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
  });

  testWidgets('Yes resolves true and closes the dialog', (tester) async {
    final host = await _openAvailableDialog(tester, info);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(host.result, isTrue);
    expect(find.text('New version available'), findsNothing);
  });

  testWidgets('No resolves false and closes the dialog', (tester) async {
    final host = await _openAvailableDialog(tester, info);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(host.result, isFalse);
    expect(find.text('New version available'), findsNothing);
  });

  testWidgets(
      'a background download with no APK asset reports failure as a snackbar '
      'instead of blocking the app', (tester) async {
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
              onPressed: () => downloadUpdateInBackground(context, noApk),
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
  });
}
