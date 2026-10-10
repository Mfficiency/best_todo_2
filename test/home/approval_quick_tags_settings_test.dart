import 'dart:io';

import 'package:besttodo/models/approval_quick_tag.dart';
import 'package:besttodo/services/approval_quick_tag_service.dart';
import 'package:besttodo/ui/approval_quick_tags_page.dart';
import 'package:besttodo/ui/settings_page.dart';
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
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ApprovalQuickTagService.instance.resetForTest();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('Tasks section has an Approval quick tags entry point',
      (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byTooltip('Expand Tasks'));
    await tester.pumpAndSettle();

    final entry = find.text('Approval quick tags');
    await tester.scrollUntilVisible(entry, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(ApprovalQuickTagsPage), findsOneWidget);
  });

  testWidgets(
      'Approval quick tags page lists the default pair and can delete one',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: ApprovalQuickTagsPage()));
    await settle(tester);

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(
        find.text('Approves into Wishlist'), findsOneWidget);
    expect(
        find.text('Approves into Research'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete quick tag').first);
    await settle(tester);

    expect(find.text('Wishlist'), findsNothing);
    expect(find.text('Research'), findsOneWidget);
    expect(ApprovalQuickTagService.instance.list.length, 1);
  });

  testWidgets('adding a quick tag persists a label and its chosen target',
      (tester) async {
    await tester.runAsync(() => ApprovalQuickTagService.instance.save([]));
    await tester.pumpWidget(
        const MaterialApp(home: ApprovalQuickTagsPage()));
    await settle(tester);

    expect(find.textContaining('No quick tags yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Add quick tag'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Button label'), 'Rabbit hole');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Research').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('Rabbit hole'), findsOneWidget);
    expect(ApprovalQuickTagService.instance.list.single,
        isA<ApprovalQuickTag>()
            .having((t) => t.label, 'label', 'Rabbit hole')
            .having((t) => t.target, 'target',
                ApprovalQuickTag.researchTarget));
  });
}
