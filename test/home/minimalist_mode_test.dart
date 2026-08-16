import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/main.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// True when a colour has no hue (equal red/green/blue channels), i.e. it is
/// pure white/grey/black. Fully transparent colours count as achromatic too.
bool _isAchromatic(Color color) =>
    color.a == 0 || (color.r == color.g && color.g == color.b);

void main() {
  test('minimalist theme uses only achromatic colours', () {
    for (final brightness in Brightness.values) {
      final scheme = buildMinimalistTheme(brightness).colorScheme;
      final colors = <String, Color>{
        'primary': scheme.primary,
        'onPrimary': scheme.onPrimary,
        'primaryContainer': scheme.primaryContainer,
        'secondary': scheme.secondary,
        'secondaryContainer': scheme.secondaryContainer,
        'onSecondaryContainer': scheme.onSecondaryContainer,
        'tertiary': scheme.tertiary,
        'error': scheme.error,
        'surface': scheme.surface,
        'onSurface': scheme.onSurface,
        'outline': scheme.outline,
        'surfaceTint': scheme.surfaceTint,
      };
      colors.forEach((name, color) {
        expect(_isAchromatic(color), isTrue,
            reason: '$name has a hue in $brightness: $color');
      });
    }
  });

  test('minimalist theme underlines selected chips instead of filling them',
      () {
    final chipTheme = buildMinimalistTheme(Brightness.light).chipTheme;
    expect(chipTheme.selectedColor, Colors.transparent);
    expect(chipTheme.showCheckmark, isFalse);

    final labelStyle =
        chipTheme.labelStyle! as WidgetStateProperty<TextStyle>;
    expect(
      labelStyle.resolve({WidgetState.selected}).decoration,
      TextDecoration.underline,
    );
    expect(
      labelStyle.resolve(const {}).decoration,
      TextDecoration.none,
    );
  });

  group('settings toggle', () {
    setUp(() async {
      final tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      Config.minimalistMode = false;
    });

    tearDown(() {
      Config.minimalistMode = false;
    });

    testWidgets('flips Config.minimalistMode and persists it',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      // initState kicks off the SMS config file load; walk real-event-loop
      // slices so the dart:io future completes inside testWidgets (see
      // test/README.md / settings_search_test.dart for the pattern).
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }

      // Settings sections all start collapsed — open Appearance first.
      await tester.tap(find.byTooltip('Expand Appearance'));
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(SwitchListTile, 'Minimalist mode');
      expect(tile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      await tester.tap(tile);
      await tester.pump();
      // The tap handler awaits Config.save(); fixed rounds of runAsync let
      // the write finish before the test ends (save-on-tap pattern).
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }

      expect(Config.minimalistMode, isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);

      // The new value reached settings.json, so it survives a restart. The
      // load does real file I/O, so it must run outside the fake-async zone.
      Config.minimalistMode = false;
      await tester.runAsync(() => Config.load());
      expect(Config.minimalistMode, isTrue);
    });
  });
}
