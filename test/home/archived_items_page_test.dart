import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/archived_items_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('labels automatic archives differently from manual archives',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchivedItemsPage(
          items: [
            Task(
              title: 'Finished yesterday',
              deletedAt: DateTime(2026, 8, 26),
              autoDeleted: true,
            ),
            Task(
              title: 'Swiped away',
              deletedAt: DateTime(2026, 8, 26),
            ),
          ],
          onRestore: (_) {},
          onMoveToBin: (_) {},
          onOpenBin: () {},
        ),
      ),
    );

    expect(find.textContaining('Automatically archived: 2026-08-26'),
        findsOneWidget);
    expect(find.textContaining('Archived: 2026-08-26'), findsOneWidget);
  });
}
