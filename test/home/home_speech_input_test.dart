import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/speech_recognition_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Stands in for the on-device recognizer: [available] controls whether
/// [listen] "succeeds", and [emit] simulates the recognizer reporting a
/// transcript back to whoever is currently listening.
class _FakeSpeechRecognitionService extends SpeechRecognitionService {
  bool available = true;
  bool _listening = false;
  void Function(String)? _onResult;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> listen({
    required void Function(String text) onResult,
    VoidCallback? onDone,
  }) async {
    if (!available) return false;
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

Finder _addTaskField(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );

void main() {
  late _FakeSpeechRecognitionService fakeSpeech;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    fakeSpeech = _FakeSpeechRecognitionService();
    SpeechRecognitionService.instance = fakeSpeech;
  });

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text(tasks.first.title);
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  testWidgets('mic button sits beside the add-task field', (tester) async {
    await pumpHome(tester, [Task(title: 'Existing', dueDate: DateTime.now())]);

    expect(find.byTooltip('Speak instead of typing'), findsOneWidget);
  });

  testWidgets(
      'transcribing fills the add-task field without submitting, and it stays editable',
      (tester) async {
    await pumpHome(tester, [Task(title: 'Existing', dueDate: DateTime.now())]);

    await tester.tap(find.byTooltip('Speak instead of typing'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Stop recording'), findsOneWidget);

    fakeSpeech.emit('buy milk');
    await tester.pump();

    expect(find.text('buy milk'), findsOneWidget);
    // Not submitted yet: no new task, just the field's text.
    expect(find.text('Existing'), findsOneWidget);

    // Still editable — appending more text works normally.
    await tester.enterText(_addTaskField('Add task'), 'buy milk and eggs');
    expect(find.text('buy milk and eggs'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop recording'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Speak instead of typing'), findsOneWidget);

    // Only the explicit add button creates the task, and exactly one.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    final saved = await tester.runAsync(() => StorageService().loadTaskList());
    expect(
      saved!.where((t) => t.title == 'buy milk and eggs'),
      hasLength(1),
    );
  });

  testWidgets('shows a message when speech recognition is unavailable',
      (tester) async {
    fakeSpeech.available = false;
    await pumpHome(tester, [Task(title: 'Existing', dueDate: DateTime.now())]);

    await tester.tap(find.byTooltip('Speak instead of typing'));
    await tester.pumpAndSettle();

    expect(find.text('Speech recognition is not available on this device'),
        findsOneWidget);
    // Never flips into "recording" state.
    expect(find.byTooltip('Stop recording'), findsNothing);
  });
}
