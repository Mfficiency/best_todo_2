import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/task_tile.dart';

void main() {
  testWidgets('editing description does not toggle task done', (tester) async {
    final task = Task(title: 'Task');
    int toggleCount = 0;
    int saveCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: () => saveCount++,
          onToggle: () => toggleCount++,
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    ));

    // Expand the tile to reveal the description field.
    await tester.tap(find.text('Task').first);
    await tester.pumpAndSettle();

    // Enter description text.
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'New description');
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(task.description, 'New description');
    expect(toggleCount, 0);
  });
}

