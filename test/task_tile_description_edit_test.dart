import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';
import 'package:best_todo_2/ui/task_tile.dart';

void main() {
  testWidgets('editing description does not toggle task done', (tester) async {
    final task = Task(title: 'Task');
    int toggleCount = 0;
    int saveCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: TaskTile(
        task: task,
        onChanged: () => saveCount++,
        onToggle: () => toggleCount++,
        onMove: (_) {},
        onMoveNext: () {},
        onDelete: () {},
        pageIndex: 0,
      ),
    ));

    // Expand the tile to reveal the description field.
    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();

    // Enter description text and unfocus the field.
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'New description');
    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();

    expect(saveCount, 1);
    expect(toggleCount, 0);
  });
}
