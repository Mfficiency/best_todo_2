import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/main.dart';

void main() {
  testWidgets('app smoke test shows intro screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp(showIntro: true));

    expect(find.text('Privacy First'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    // Let the deferred auto-update-check timer (main.dart) fire so it
    // doesn't leak past the end of the test.
    await tester.pump(const Duration(seconds: 3));
  });
}
