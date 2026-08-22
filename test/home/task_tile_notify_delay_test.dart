import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/task_tile.dart';

void main() {
  late bool notificationsWere;
  late int defaultDelayWas;

  setUp(() {
    notificationsWere = Config.enableNotifications;
    defaultDelayWas = Config.defaultNotificationDelaySeconds;
  });

  tearDown(() {
    Config.enableNotifications = notificationsWere;
    Config.defaultNotificationDelaySeconds = defaultDelayWas;
  });

  Future<void> pumpExpandedTile(WidgetTester tester, Task task) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: () {},
          onToggle: () {},
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    ));
    // The Notify bell only exists on an expanded tile.
    await tester.tap(find.text(task.title).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the Notify bell asks when: 5 / 20 / 60 minutes or the default',
      (tester) async {
    Config.enableNotifications = true;
    Config.defaultNotificationDelaySeconds = 300;
    await pumpExpandedTile(tester, Task(title: 'Call the vet'));

    await tester.tap(find.byTooltip('Notify'));
    await tester.pumpAndSettle();

    expect(find.text('Notify me about "Call the vet"'), findsOneWidget);
    expect(find.text('In 5 minutes'), findsOneWidget);
    expect(find.text('In 20 minutes'), findsOneWidget);
    expect(find.text('In 1 hour'), findsOneWidget);
    expect(find.text('Default delay'), findsOneWidget);
    expect(find.text('In 05:00 — set in Settings'), findsOneWidget);
  });

  testWidgets('dismissing the sheet schedules nothing', (tester) async {
    Config.enableNotifications = true;
    await pumpExpandedTile(tester, Task(title: 'Book a table'));

    await tester.tap(find.byTooltip('Notify'));
    await tester.pumpAndSettle();
    expect(find.text('In 20 minutes'), findsOneWidget);

    // Tap the barrier above the sheet.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('In 20 minutes'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('with notifications off the bell points at Settings instead',
      (tester) async {
    Config.enableNotifications = false;
    await pumpExpandedTile(tester, Task(title: 'Water the fern'));

    await tester.tap(find.byTooltip('Notify'));
    await tester.pumpAndSettle();

    expect(find.text('Enable notifications in Settings first'), findsOneWidget);
    expect(find.text('In 5 minutes'), findsNothing);
  });
}
