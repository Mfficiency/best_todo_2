import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/ui/alarm_edit_page.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, {Alarm? alarm}) async {
    await tester.pumpWidget(MaterialApp(home: AlarmEditPage(alarm: alarm)));
    await tester.pumpAndSettle();
  }

  // The editor is one ListView; the TextFields inside it have their own
  // Scrollables, so scrolling must target the ListView explicitly.
  Future<void> revealInEditor(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('editor shows the Override Do Not Disturb toggle (off default)',
      (tester) async {
    await pumpEditor(tester);

    final finder = find.text('Override Do Not Disturb');
    await revealInEditor(tester, finder);
    expect(finder, findsOneWidget);

    final tile = tester.widget<SwitchListTile>(
      find.ancestor(of: finder, matching: find.byType(SwitchListTile)),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('melody Preview button toggles between play and stop',
      (tester) async {
    await pumpEditor(tester);

    final preview = find.byTooltip('Preview');
    await revealInEditor(tester, preview);
    expect(preview, findsOneWidget);

    // Start the preview: the button flips to its stop state. (In tests the
    // platform channel has no host, so nothing actually plays.)
    await tester.tap(preview);
    await tester.pump();
    expect(find.byTooltip('Stop preview'), findsOneWidget);

    // Stop it again.
    await tester.tap(find.byTooltip('Stop preview'));
    await tester.pump();
    expect(find.byTooltip('Preview'), findsOneWidget);
  });

  testWidgets('saving keeps the Override Do Not Disturb choice',
      (tester) async {
    Object? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlarmEditPage(
                    alarm: Alarm(name: 'Wake up', volume: 0.6),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final toggle = find.text('Override Do Not Disturb');
    await tester.dragUntilVisible(
      toggle,
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(result, isA<Alarm>());
    final saved = result as Alarm;
    expect(saved.overrideDnd, isTrue);
    expect(saved.volume, 0.6);
    expect(saved.name, 'Wake up');
  });

  testWidgets('the Tags field is editable and saving keeps the tags',
      (tester) async {
    Object? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlarmEditPage(alarm: Alarm(name: 'Wake up')),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final addTagChip = find.text('Add label');
    await tester.dragUntilVisible(
      addTagChip,
      find.byType(ListView),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(addTagChip);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'work');
    await tester.pump();
    await tester.tap(find.text('Add "work"'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(result, isA<Alarm>());
    expect((result as Alarm).tags, 'alarm, work');
  });
}
