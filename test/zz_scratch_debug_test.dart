import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/project_board_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  testWidgets('debug edit dialog', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    await tester.runAsync(() => ProjectService.instance.load());

    await tester.pumpWidget(MaterialApp(
      home: ProjectBoardPage(
        project: Project.placeholders.first,
        tasks: const [],
        onChanged: () {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    debugPrint('DBG dialogs: ${find.byType(AlertDialog).evaluate().length}');
    debugPrint('DBG textfields: ${find.byType(TextField).evaluate().length}');

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Household');
    final editables = find.byType(EditableText);
    for (final e in editables.evaluate()) {
      final w = e.widget as EditableText;
      debugPrint('DBG editable text: "${w.controller.text}"');
    }

    await tester.tap(find.text('Save'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (i % 10 == 0) {
        debugPrint(
            'DBG round $i service name=${ProjectService.instance.nameOf('project_1')} dialogOpen=${find.byType(AlertDialog).evaluate().length}');
      }
    }
    await tester.pumpAndSettle();
    debugPrint('DBG final service name=${ProjectService.instance.nameOf('project_1')}');
    debugPrint('DBG household found=${find.text('Household').evaluate().length}');
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      debugPrint('DBG page text: "${w.data}"');
    }
  });
}
