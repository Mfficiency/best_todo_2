import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/bulk_add_page.dart';

void main() {
  setUp(() => ProjectService.instance.resetForTest());

  test('bulk_add is a registered tool and feature', () {
    expect(Config.featureKeys, contains('bulk_add'));
    expect(Config.startToolOptions, contains('bulk_add'));
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });

  test('parseBulkTitles: one per line, list markers stripped, blanks dropped',
      () {
    expect(
      parseBulkTitles('Buy milk\n\n  - Call Bob \r\n* Email\n1. First\n'
          '2) Second\n- [ ] Box\n[x] Done one\n• Dot\n   \n'),
      [
        'Buy milk',
        'Call Bob',
        'Email',
        'First',
        'Second',
        'Box',
        'Done one',
        'Dot',
      ],
    );
    expect(parseBulkTitles(''), isEmpty);
    // A hyphen inside the title (no space after it) is kept.
    expect(parseBulkTitles('-5 kg'), ['-5 kg']);
  });

  testWidgets('submits every line with the chosen project and tab',
      (tester) async {
    BulkAddRequest? received;
    await tester.pumpWidget(MaterialApp(
      home: BulkAddPage(onAdd: (request) {
        received = request;
        return request.titles.length;
      }),
    ));

    await tester.enterText(
        find.byKey(const Key('bulk-add-items')), 'One\n- Two\n\nThree');
    await tester.pump();
    expect(find.text('Add 3 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bulk-add-project')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project 2').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bulk-add-tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add 3 items'));
    await tester.pump();

    expect(received, isNotNull);
    expect(received!.titles, ['One', 'Two', 'Three']);
    expect(received!.projectId, 'project_2');
    expect(received!.tabIndex, 1);
    expect(received!.label, '');
    expect(find.text('Added 3 items'), findsOneWidget);
    // The text area clears for the next batch; project/tab stay.
    expect(find.text('Add items'), findsOneWidget);
    expect(find.text('Project 2'), findsOneWidget);
  });
}
