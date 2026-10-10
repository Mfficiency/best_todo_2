import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/task_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => ProjectService.instance.resetForTest());

  testWidgets('the info icon reveals the hidden sync trailer and raw fields',
      (tester) async {
    final task = Task(
      title: 'Plan trip',
      note: 'secret note',
      label: 'travel',
      dueDate: DateTime(2026, 8, 1, 18),
    );

    await tester.pumpWidget(MaterialApp(home: TaskDetailPage(task: task)));
    await tester.pump();

    // The note text is hidden behind the info icon, not shown plainly on
    // the page body until then.
    expect(find.textContaining('sync-data:'), findsNothing);

    await tester.tap(find.byTooltip('Show all task metadata'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sync-data:'), findsOneWidget);
    expect(find.textContaining(task.uid), findsWidgets);
    expect(find.textContaining('"note": "secret note"'), findsOneWidget);
  });
}
