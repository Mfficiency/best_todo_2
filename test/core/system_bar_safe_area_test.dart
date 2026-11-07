import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/ui/system_bar_safe_area.dart';

/// A phone with Android's navigation bar: 48 dp of 3-button bar at the bottom.
const _navBar = 48.0;

Widget _app(Widget home) => MaterialApp(
  builder: (context, child) => SystemBarSafeArea(child: child!),
  home: home,
);

Future<void> _withNavBar(WidgetTester tester, {double bottom = _navBar}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: 72, bottom: bottom * 3);
  tester.view.viewPadding = FakeViewPadding(top: 72, bottom: bottom * 3);
  addTearDown(tester.view.reset);
}

double _screenHeight(WidgetTester tester) =>
    tester.view.physicalSize.height / tester.view.devicePixelRatio;

void main() {
  testWidgets('a button at the bottom of a screen stays above the bar', (
    tester,
  ) async {
    await _withNavBar(tester);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              FilledButton(onPressed: () {}, child: const Text('Bottom')),
            ],
          ),
        ),
      ),
    );
    final bottom = tester.getBottomLeft(find.text('Bottom')).dy;
    expect(bottom, lessThanOrEqualTo(_screenHeight(tester) - _navBar));
  });

  testWidgets('bottom sheets end above the bar', (tester) async {
    await _withNavBar(tester);
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 120,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Text('Sheet end'),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final bottom = tester.getBottomLeft(find.text('Sheet end')).dy;
    expect(bottom, lessThanOrEqualTo(_screenHeight(tester) - _navBar));
  });

  testWidgets('pages see no bar padding left (nothing padded twice)', (
    tester,
  ) async {
    await _withNavBar(tester);
    late EdgeInsets padding;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            padding = MediaQuery.paddingOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(padding.bottom, 0);
    expect(padding.top, 24, reason: 'the status bar stays with the app bar');
  });

  testWidgets('no navigation bar, no gap', (tester) async {
    await _withNavBar(tester, bottom: 0);
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: Text('Edge')),
        ),
      ),
    );
    expect(tester.getBottomLeft(find.text('Edge')).dy, _screenHeight(tester));
  });
}
