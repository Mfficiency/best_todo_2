import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/waiting_approval_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  tearDown(() {
    Config.viewFilterRules = {};
  });

  testWidgets(
      'a configured Waiting for Approval rule narrows the queue on top of '
      'the pending gate', (tester) async {
    Config.viewFilterRules[ViewFilterRules.approval] =
        ViewFilterRules(includeTags: ['urgent']);

    final tasks = [
      Task(title: 'Keep this', label: 'Waiting_for_approval, urgent'),
      Task(title: 'Hide this', label: 'Waiting_for_approval'),
      Task(title: 'Already approved', label: 'urgent'),
    ];
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: WaitingApprovalPage()));
    final markerFinder = find.text('Keep this');
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();

    expect(find.text('Keep this'), findsOneWidget);
    expect(find.text('Hide this'), findsNothing);
    expect(find.text('Already approved'), findsNothing);
  });
}
