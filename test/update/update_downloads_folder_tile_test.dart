import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/update_downloads_folder_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The "Update downloads folder" row shown in both BestToDo's Settings →
/// Updates and Best Music's Settings.
void main() {
  setUp(UpdateService.resetForTest);

  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpdateDownloadsFolderTile(updateService: UpdateService.instance),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the folder path and copies it', (tester) async {
    const path = '/storage/emulated/0/Android/data/x/files/updates';
    UpdateService.instance.downloadChannelOverride = (m, a) async => path;
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpTile(tester);

    expect(find.text('Update downloads folder'), findsOneWidget);
    expect(find.text(path), findsOneWidget);

    await tester.tap(find.byTooltip('Copy path'));
    await tester.pumpAndSettle();
    expect(copied, path);
    expect(find.text('Folder path copied'), findsOneWidget);
  });

  testWidgets('explains when there is no folder (not Android)',
      (tester) async {
    await pumpTile(tester);

    expect(find.text('Update downloads folder'), findsOneWidget);
    expect(find.textContaining('Not available'), findsOneWidget);
    expect(find.byTooltip('Copy path'), findsNothing);
  });
}
