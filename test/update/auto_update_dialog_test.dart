import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The background auto-update prompt (`main.dart`'s `AutoUpdateChecker`
/// wiring): the "New version available" Yes/No dialog, and the download
/// dialog's failure path. The success path (an actual APK download) is
/// deliberately not exercised here — same as `about_page_update_test.dart`,
/// [UpdateService.downloadApk] has no test seam and hits real sockets, so
/// only the synchronous "no APK asset" failure of [UpdateDownloadDialog] is
/// covered.
library;

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
      'download dialog reports the failure when the release has no APK',
      (tester) async {
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
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => UpdateDownloadDialog(info: noApk),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Update failed'), findsOneWidget);
    expect(find.textContaining('This release has no APK to download'),
        findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Update failed'), findsNothing);
  });
}
