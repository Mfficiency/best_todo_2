import 'dart:io';

import 'package:besttodo/models/sms_recipient.dart';
import 'package:besttodo/models/sms_report_config.dart';
import 'package:besttodo/services/sms_report_config_service.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Saving the config re-arms the daily alarm; tests run as Android, so
    // stub the alarm-manager plugin instead of hitting a missing platform
    // implementation.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      // Same codec as the plugin declares, or the mock cannot decode calls.
      const MethodChannel(
          'dev.fluttercommunity.plus/android_alarm_manager', JSONMethodCodec()),
      (call) async => true,
    );
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // Pre-save the recipients outside the fake-async zone so the settings
    // page has a deterministic list to render (see test/README.md).
    await SmsReportConfigService.save(SmsReportConfig(
      enabled: true,
      recipients: [
        SmsRecipient(nickname: 'Ann', phoneNumber: '+111'),
        SmsRecipient(nickname: 'Bob', phoneNumber: '+222', enabled: false),
      ],
    ));
  });

  /// Runs real-event-loop slices so dart:io futures started by the widget
  /// (config load, save-on-tap) can complete inside testWidgets.
  Future<void> settle(WidgetTester tester, {int rounds = 60}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> openRecipients(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await settle(tester);
    // Jump to the SMS section via the settings search, then scroll the
    // recipient rows into view.
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'recipients');
    await tester.pump();
    await tester.tap(find.text('Recipients').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Message template'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }

  /// The recipient rows sit at the very bottom of a long scroll view — bring
  /// the target fully on-screen before tapping it.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  testWidgets('a recipient can be disabled without being removed',
      (tester) async {
    await openRecipients(tester);

    // Both recipients are listed; the pre-disabled one says so.
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('+111'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('+222 • disabled'), findsOneWidget);

    // Pause Ann via her switch.
    await tapVisible(tester, find.byTooltip('Disable recipient'));
    await settle(tester);

    expect(find.text('+111 • disabled'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);

    final saved = await tester.runAsync(() => SmsReportConfigService.load());
    expect(saved!.recipients.length, 2);
    expect(saved.recipients.map((r) => r.enabled).toList(), [false, false]);
    expect(saved.activeRecipients, isEmpty);
  });

  testWidgets('re-enabling resumes a paused recipient', (tester) async {
    await openRecipients(tester);

    await tapVisible(tester, find.byTooltip('Enable recipient'));
    await settle(tester);

    expect(find.text('+222'), findsOneWidget);
    expect(find.text('+222 • disabled'), findsNothing);

    final saved = await tester.runAsync(() => SmsReportConfigService.load());
    expect(saved!.activeRecipients.map((r) => r.nickname).toList(),
        ['Ann', 'Bob']);
  });

  testWidgets('editing a paused recipient does not silently resume them',
      (tester) async {
    await openRecipients(tester);

    await tapVisible(tester, find.byTooltip('Edit recipient').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Bobby');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Bobby'), findsOneWidget);
    expect(find.text('+222 • disabled'), findsOneWidget);

    final saved = await tester.runAsync(() => SmsReportConfigService.load());
    expect(saved!.activeRecipients.single.nickname, 'Ann');
  });
}
