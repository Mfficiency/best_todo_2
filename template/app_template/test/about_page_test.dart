import 'package:app_template/app_template.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppVersion.setForTest('2.1.0', '9'));
  tearDown(AppVersion.resetForTest);

  testWidgets('shows app name, version and action buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();

    expect(find.text(AppConfig.appName), findsOneWidget);
    expect(find.textContaining('v2.1.0+9'), findsOneWidget);
    expect(find.text('Replay Introduction'), findsOneWidget);
    expect(find.text('Update App'), findsOneWidget);
  });
}
