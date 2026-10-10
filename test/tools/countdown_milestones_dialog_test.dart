import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/countdown_milestone.dart';
import 'package:besttodo/models/countdown_timer.dart';
import 'package:besttodo/ui/countdown_milestones_dialog.dart';

/// Captures what the dialog handed back to its caller.
class _Host {
  MilestonesResult? result;
  bool closed = false;
}

/// Pumps a page whose only button opens the milestone dialog for [timer], taps
/// it, and settles. The dialog does no persistence, so no fake path provider is
/// needed and the fake-async zone is safe here.
Future<_Host> _openDialog(WidgetTester tester, CountdownTimerItem timer) async {
  final host = _Host();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              host.result = await showCountdownMilestonesDialog(context, timer);
              host.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return host;
}

CountdownTimerItem _timer(
  List<CountdownMilestone> milestones, {
  bool enabled = true,
}) {
  return CountdownTimerItem(
    label: 'Launch',
    target: DateTime(2026, 6, 1, 12, 0),
    notifyRoundNumbers: enabled,
    milestones: milestones,
  );
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the timer\'s milestones longest first', (tester) async {
    await _openDialog(
      tester,
      _timer([
        CountdownMilestone(value: 100, unit: MilestoneUnit.seconds),
        CountdownMilestone(value: 2, unit: MilestoneUnit.years),
      ]),
    );

    expect(find.text('Milestone notifications'), findsOneWidget);
    expect(find.text('Launch'), findsOneWidget);

    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(values, ['2', '100']);
  });

  testWidgets('saving returns the edited milestones', (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    await tester.enterText(find.byType(TextField).first, '25');
    await _tapSave(tester);

    expect(host.result, isNotNull);
    expect(host.result!.enabled, isTrue);
    expect(host.result!.milestones, hasLength(1));
    expect(host.result!.milestones.single.value, 25);
    expect(host.result!.milestones.single.unit, MilestoneUnit.days);
  });

  testWidgets('cancelling returns null and leaves the timer untouched',
      (tester) async {
    final timer = _timer([
      CountdownMilestone(value: 10, unit: MilestoneUnit.days),
    ]);
    final host = await _openDialog(tester, timer);

    await tester.enterText(find.byType(TextField).first, '99');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(host.closed, isTrue);
    expect(host.result, isNull);
    // The timer only changes when the caller applies a result.
    expect(timer.milestones.single.value, 10);
  });

  testWidgets('adding a milestone appends an editable row', (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    await tester.tap(find.text('Add milestone'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).last, '3');
    await _tapSave(tester);

    // Both survive, re-sorted longest first.
    expect(
      host.result!.milestones.map((m) => m.label).toList(),
      ['10 days', '3 days'],
    );
  });

  testWidgets('a blank or zero row is dropped on save', (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    await tester.tap(find.text('Add milestone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0');
    await _tapSave(tester);

    expect(host.result!.milestones.map((m) => m.label).toList(), ['10 days']);
  });

  testWidgets('duplicate number+unit rows collapse to one', (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    await tester.tap(find.text('Add milestone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '10');
    // The new row defaults to days too, so it duplicates the existing one.
    await _tapSave(tester);

    expect(host.result!.milestones, hasLength(1));
  });

  testWidgets('removing a row drops that milestone', (tester) async {
    final host = await _openDialog(
      tester,
      _timer([
        CountdownMilestone(value: 10, unit: MilestoneUnit.days),
        CountdownMilestone(value: 2, unit: MilestoneUnit.hours),
      ]),
    );

    await tester.tap(find.byTooltip('Remove milestone').first);
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(host.result!.milestones.map((m) => m.label).toList(), ['2 hours']);
  });

  testWidgets('the direction button cycles both → before → after',
      (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    expect(find.byTooltip('Notify before and after the event'), findsOneWidget);
    await tester.tap(find.byTooltip('Notify before and after the event'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notify before the event only'), findsOneWidget);
    await tester.tap(find.byTooltip('Notify before the event only'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notify after the event only'), findsOneWidget);

    await _tapSave(tester);
    expect(host.result!.milestones.single.direction, MilestoneDirection.after);
  });

  testWidgets('the master switch turns milestone notifications off',
      (tester) async {
    final host = await _openDialog(
      tester,
      _timer([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]),
    );

    await tester.tap(find.text('Notify at milestones'));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(host.result!.enabled, isFalse);
    // Switching off keeps the configured milestones.
    expect(host.result!.milestones, hasLength(1));
  });

  testWidgets('Defaults restores the seven default milestones', (tester) async {
    final host = await _openDialog(
      tester,
      _timer(
        [CountdownMilestone(value: 3, unit: MilestoneUnit.hours)],
        enabled: false,
      ),
    );

    await tester.tap(find.text('Defaults'));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(
      host.result!.milestones.map((m) => m.label).toList(),
      [
        '10 years',
        '10 months',
        '10,000,000 seconds',
        '10 weeks',
        '100,000 minutes',
        '1,000 hours',
        '10 days',
      ],
    );
    // Resetting also switches the bell on.
    expect(host.result!.enabled, isTrue);
  });
}
