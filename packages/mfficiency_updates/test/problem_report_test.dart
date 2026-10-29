import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

void main() {
  late List<(Uri, Map<String, String>, Object?)> posts;
  late List<String> opened;
  late String? token;
  late Object? answer;

  setUp(() {
    posts = [];
    opened = [];
    token = null;
    answer = {'number': 12, 'html_url': 'https://github.com/o/app/issues/12'};
  });

  ProblemReporter reporter({
    String repo = 'o/app',
    String logs = 'line 1\nline 2',
    String channel = 'dev',
  }) =>
      ProblemReporter(
        config: ProblemReportConfig(
          appName: 'App',
          version: '1.2.3',
          build: 45,
          channel: channel,
          githubRepo: repo,
        ),
        collectLogs: () async => logs,
        readToken: () async => token,
        writeToken: (t) async => token = t,
        post: (url, headers, body) async {
          posts.add((url, headers, body));
          if (answer is UpdateHttpException) throw answer!;
          return answer;
        },
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
        clock: () => DateTime(2026, 10, 29, 9, 30),
        platformName: 'android',
      );

  group('compose', () {
    test('marker, description, app facts and logs', () {
      final r = reporter().compose('Alarm did not ring\nat 7:00', logs: 'a\nb');
      expect(r.title, 'Problem report: Alarm did not ring');
      expect(r.body, startsWith(ProblemReportConfig.marker));
      expect(r.body, contains('Alarm did not ring\nat 7:00'));
      expect(r.body, contains('- App 1.2.3 (build 45) · dev'));
      expect(r.body, contains('- Platform: android'));
      expect(r.body, contains('```text\na\nb\n```'));
    });

    test('no description: a title from the app, logs only', () {
      final r = reporter().compose('  ', logs: 'x');
      expect(r.title, 'Problem report: App 1.2.3');
      expect(r.body, contains('no description'));
    });

    test('long logs keep the newest lines and fit the limit', () {
      final logs = List.generate(5000, (i) => 'line $i').join('\n');
      final r = reporter().compose('x', logs: logs, maxChars: 4000);
      expect(r.body.length, lessThanOrEqualTo(4000));
      expect(r.body, contains('line 4999'));
      expect(r.body, isNot(contains('line 0\n')));
      expect(r.body, contains('older characters cut'));
    });

    test('the token never ends up in the report', () {
      final r = reporter()
          .compose('x', logs: 'auth ghp_secret', secret: 'ghp_secret');
      expect(r.body, isNot(contains('ghp_secret')));
    });
  });

  group('send', () {
    test('with a token: an issue labelled claude-fix', () async {
      token = ' ghp_abc ';
      final result = await reporter().send('Broken');
      expect(result.outcome, ProblemReportOutcome.sent);
      expect(result.issueNumber, 12);
      expect(posts, hasLength(1));
      final (url, headers, body) = posts.single;
      expect(url.toString(), 'https://api.github.com/repos/o/app/issues');
      expect(headers['Authorization'], 'Bearer ghp_abc');
      final map = body! as Map;
      expect(map['labels'], ['claude-fix']);
      expect(map['body'], contains('line 2'));
      expect(opened, isEmpty);
    });

    test('logs off: none attached', () async {
      token = 't';
      await reporter().send('Broken', includeLogs: false);
      final map = posts.single.$3! as Map;
      expect(map['body'], contains('No logs attached'));
      expect(map['body'], isNot(contains('line 2')));
    });

    test('a refused token says so', () async {
      token = 't';
      answer = const UpdateHttpException(401);
      expect(
          (await reporter().send('x')).outcome, ProblemReportOutcome.badToken);
      answer = const UpdateHttpException(404);
      expect(
          (await reporter().send('x')).outcome, ProblemReportOutcome.badToken);
      answer = const UpdateHttpException(null, 'offline');
      expect((await reporter().send('x')).outcome, ProblemReportOutcome.failed);
    });

    test('no token: the new-issue page, filled in and short enough', () async {
      final logs = List.generate(3000, (i) => 'line $i').join('\n');
      final result = await reporter(logs: logs).send('Broken');
      expect(result.outcome, ProblemReportOutcome.openedInBrowser);
      expect(posts, isEmpty);
      final url = Uri.parse(opened.single);
      expect(url.host, 'github.com');
      expect(url.path, '/o/app/issues/new');
      expect(url.queryParameters['labels'], 'claude-fix');
      expect(url.queryParameters['body'], contains(ProblemReportConfig.marker));
      expect(url.queryParameters['body'], contains('line 2999'));
      expect(opened.single.length, lessThanOrEqualTo(7000));
    });

    test('no dart:io (web) with a token: the browser instead', () async {
      token = 't';
      answer = const UpdateHttpException(null, 'unsupported');
      final result = await reporter().send('x');
      expect(result.outcome, ProblemReportOutcome.openedInBrowser);
      expect(opened, hasLength(1));
    });

    test('no repo: not configured', () async {
      final result = await reporter(repo: '').send('x');
      expect(result.outcome, ProblemReportOutcome.notConfigured);
    });
  });

  group('widgets', () {
    Widget host(ProblemReporter r) => MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: ProblemReportTrigger(
                reporter: r,
                child: const Text('App 1.2.3'),
              ),
            ),
            body: ListView(children: [ProblemReportSettingsTile(reporter: r)]),
          ),
        );

    Future<void> doubleTap(WidgetTester tester, Finder f) async {
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('double tap opens the sheet; Send files the issue', (
      tester,
    ) async {
      token = 't';
      await tester.pumpWidget(host(reporter()));
      await tester.pumpAndSettle();
      await doubleTap(tester, find.text('App 1.2.3'));
      expect(find.text('Report a problem to Claude'), findsOneWidget);
      expect(find.text('2 lines'), findsOneWidget);
      expect(find.text('Goes straight to GitHub as an issue in o/app.'),
          findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('problemReport.text')), 'It crashed');
      await tester.tap(find.text('Send to Claude'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect((posts.single.$3! as Map)['title'], 'Problem report: It crashed');
      expect(find.text('Report a problem to Claude'), findsNothing);
      expect(find.textContaining('Sent as issue #12'), findsOneWidget);
    });

    testWidgets('a single tap does nothing', (tester) async {
      await tester.pumpWidget(host(reporter()));
      await tester.tap(find.text('App 1.2.3'));
      await tester.pumpAndSettle();
      expect(find.text('Report a problem to Claude'), findsNothing);
    });

    testWidgets('a refused token keeps the sheet open with the reason', (
      tester,
    ) async {
      token = 't';
      answer = const UpdateHttpException(403);
      await tester.pumpWidget(host(reporter()));
      await doubleTap(tester, find.text('App 1.2.3'));
      await tester.tap(find.text('Send to Claude'));
      await tester.pumpAndSettle();
      expect(find.textContaining('GitHub refused the token'), findsOneWidget);
      expect(find.text('Report a problem to Claude'), findsOneWidget);
    });

    testWidgets('settings: explanation, token saved as typed, removable', (
      tester,
    ) async {
      final r = reporter();
      await tester.pumpWidget(host(r));
      await tester.pumpAndSettle();
      expect(find.textContaining('No token'), findsOneWidget);
      await tester.tap(find.byKey(const Key('problemReport.settings')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Issues: "Read and write"'), findsOneWidget);
      expect(find.textContaining('CLAUDE_CODE_OAUTH_TOKEN'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('problemReport.createToken')),
      );
      await tester.tap(find.byKey(const Key('problemReport.createToken')));
      expect(opened.single, ProblemReportConfig.tokenPage);
      await tester.enterText(
          find.byKey(const Key('problemReport.token')), 'ghp_new');
      await tester.pumpAndSettle();
      expect(token, 'ghp_new');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('GitHub token set'), findsOneWidget);
      await tester.tap(find.byKey(const Key('problemReport.settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove token'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(token, isNull);
      expect(find.textContaining('No token'), findsOneWidget);
    });
  });
}
