import 'package:besttodo/utils/linkified_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('text without a URL renders as plain text', (tester) async {
    await pump(tester, const LinkifiedText('just words, no links'));
    expect(find.text('just words, no links'), findsOneWidget);
  });

  testWidgets('tapping a URL fires onOpenLink with the parsed Uri',
      (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      LinkifiedText('see https://example.com/a?b=1 for details',
          onOpenLink: opened.add),
    );

    await tester
        .tapOnText(find.textRange.ofSubstring('https://example.com/a?b=1'));

    expect(opened, [Uri.parse('https://example.com/a?b=1')]);
  });

  testWidgets('trailing sentence punctuation stays out of the link',
      (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      LinkifiedText('docs live at (https://a.bc/d).', onOpenLink: opened.add),
    );

    await tester.tapOnText(find.textRange.ofSubstring('https://a.bc/d'));

    expect(opened, [Uri.parse('https://a.bc/d')]);
  });

  testWidgets('rebuilding with new links and unmounting disposes cleanly',
      (tester) async {
    await pump(tester, const LinkifiedText('one https://a.bc link'));
    await pump(
        tester, const LinkifiedText('two https://x.yz and https://q.rs'));
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    // Passing means no recognizer was used after dispose and none leaked an
    // exception during teardown.
  });
}
