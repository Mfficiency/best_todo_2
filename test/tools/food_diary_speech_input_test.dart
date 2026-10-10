import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/speech_recognition_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/food_diary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _FakeSpeechRecognitionService extends SpeechRecognitionService {
  bool _listening = false;
  void Function(String)? _onResult;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> listen({
    required void Function(String text) onResult,
    VoidCallback? onDone,
  }) async {
    _listening = true;
    _onResult = onResult;
    return true;
  }

  @override
  Future<void> stop() async {
    _listening = false;
  }

  void emit(String transcript) => _onResult?.call(transcript);
}

void main() {
  late Directory tempDir;
  late _FakeSpeechRecognitionService fakeSpeech;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Config.swipeLeftDelete = true;
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    fakeSpeech = _FakeSpeechRecognitionService();
    SpeechRecognitionService.instance = fakeSpeech;
  });

  Future<void> pumpFoodDiary(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: FoodDiaryPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'FoodDiaryPage never loaded the tasks');
  }

  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets(
      'transcribing into the add-entry Title field keeps the dialog open '
      'and editable, saving one entry', (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [Task(title: 'Greek yogurt', isEatingHabit: true)],
      marker: 'Greek yogurt',
    );

    await tester.tap(find.byTooltip('Add food diary entry'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Speak instead of typing'), findsOneWidget);

    await tester.tap(find.byTooltip('Speak instead of typing'));
    await tester.pumpAndSettle();
    fakeSpeech.emit('oatmeal with banana');
    await tester.pump();

    // Dialog did not auto-close, and the transcript landed in the field.
    expect(find.text('Add food diary entry'), findsOneWidget);
    final titleField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Title'));
    expect(titleField.controller?.text, 'oatmeal with banana');

    // Still editable before the final confirmation.
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Oatmeal with banana');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Oatmeal with banana'), findsOneWidget);
  });
}
