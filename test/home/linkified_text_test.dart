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

  testWidgets('tapping a dashed phone number opens the dialer with tel: Uri',
      (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      LinkifiedText('call me at 555-123-4567 tomorrow',
          onOpenLink: opened.add),
    );

    await tester.tapOnText(find.textRange.ofSubstring('555-123-4567'));

    expect(opened, [Uri.parse('tel:5551234567')]);
  });

  testWidgets('a parenthesized area code and country code both dial cleanly',
      (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      LinkifiedText('office: (555) 123 4567, mobile: +1 555 987 6543',
          onOpenLink: opened.add),
    );

    await tester.tapOnText(find.textRange.ofSubstring('(555) 123 4567'));
    await tester.tapOnText(find.textRange.ofSubstring('+1 555 987 6543'));

    expect(opened, [
      Uri.parse('tel:5551234567'),
      Uri.parse('tel:+15559876543'),
    ]);
  });

  testWidgets('a bare 11-digit number dials without needing separators',
      (tester) async {
    final opened = <Uri>[];
    await pump(
      tester,
      LinkifiedText('sms 08012345678 please', onOpenLink: opened.add),
    );

    await tester.tapOnText(find.textRange.ofSubstring('08012345678'));

    expect(opened, [Uri.parse('tel:08012345678')]);
  });

  testWidgets('an ISO due date is not treated as a phone number',
      (tester) async {
    await pump(tester, const LinkifiedText('moved to 2026-08-25 instead'));
    expect(find.text('moved to 2026-08-25 instead'), findsOneWidget);
  });

  testWidgets('a short bare number stays plain text', (tester) async {
    await pump(tester, const LinkifiedText('grab item 12345 from aisle 3'));
    expect(find.text('grab item 12345 from aisle 3'), findsOneWidget);
  });
}
