import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/attachment.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/task_tile.dart';

Widget _wrap(Task task, {VoidCallback? onChanged}) => MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: onChanged ?? () {},
          onToggle: () {},
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    );

Future<void> _expand(WidgetTester tester, Task task) async {
  await tester.tap(find.text(task.title).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('adding a note attachment updates the task and shows in list',
      (tester) async {
    final task = Task(title: 'Plan trip');
    var changed = 0;
    await tester.pumpWidget(_wrap(task, onChanged: () => changed++));
    await _expand(tester, task);

    expect(find.text('Attachments'), findsOneWidget);
    expect(task.attachments, isEmpty);

    await tester.tap(find.byTooltip('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Pack sunscreen');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(task.attachments, hasLength(1));
    expect(task.attachments.single.type, Attachment.typeText);
    expect(task.attachments.single.text, 'Pack sunscreen');
    expect(find.text('Pack sunscreen'), findsOneWidget);
    expect(changed, greaterThan(0));
  });

  testWidgets('tapping a note attachment opens it for editing',
      (tester) async {
    final task = Task(
      title: 'Plan trip',
      attachments: [Attachment(type: Attachment.typeText, text: 'Old note')],
    );
    await tester.pumpWidget(_wrap(task));
    await _expand(tester, task);

    expect(find.text('Old note'), findsOneWidget);

    await tester.tap(find.text('Old note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Updated note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(task.attachments.single.text, 'Updated note');
    expect(find.text('Updated note'), findsOneWidget);
    expect(find.text('Old note'), findsNothing);
  });

  testWidgets('removing an attachment clears it from the task',
      (tester) async {
    final task = Task(
      title: 'Plan trip',
      attachments: [Attachment(type: Attachment.typeText, text: 'Old note')],
    );
    await tester.pumpWidget(_wrap(task));
    await _expand(tester, task);

    expect(task.attachments, hasLength(1));

    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();

    expect(task.attachments, isEmpty);
    expect(find.text('Old note'), findsNothing);
  });
}
