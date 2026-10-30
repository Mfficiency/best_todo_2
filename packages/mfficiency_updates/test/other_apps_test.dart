import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

import 'fakes.dart';

/// Answers per repo: a release list, or an error status.
class RepoHttp extends UpdateHttp {
  final answers = <String, Object>{};
  final requests = <(Uri, Map<String, String>)>[];

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) async {
    requests.add((url, headers));
    final repo = url.pathSegments.skip(1).take(2).join('/');
    final answer = answers[repo] ?? const <Object>[];
    if (answer is int) throw UpdateHttpException(answer);
    return answer;
  }
}

Map<String, Object?> asset(String tag, String repo) => {
      'tag_name': tag,
      'draft': false,
      'prerelease': tag.endsWith('-dev'),
      'html_url': 'https://github.com/$repo/releases/tag/$tag',
      'assets': [
        {
          'name': 'app.apk',
          'url': 'https://api.github.com/repos/$repo/releases/assets/1',
          'browser_download_url':
              'https://github.com/$repo/download/$tag/app.apk',
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RepoHttp http;
  late FakeDownloader downloader;
  late List<MethodCall> calls;
  late Map<String, Map<String, Object?>> installed;
  late String installOutcome;
  late String? token;
  late List<String> staged;

  setUp(() {
    http = RepoHttp();
    downloader = FakeDownloader();
    calls = [];
    installed = {};
    installOutcome = 'ok';
    token = null;
    staged = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(UpdatePlatform.channelName),
      (call) async {
        calls.add(call);
        final args = call.arguments is Map ? call.arguments as Map : const {};
        return switch (call.method) {
          'appId' => 'com.mfficiency.best_todo_2',
          'packageInfo' => installed[args['id']],
          'launchApp' => installed.containsKey(args['id']),
          'installApk' => installOutcome,
          'openUrl' => true,
          _ => null,
        };
      },
    );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(UpdatePlatform.channelName),
      null,
    ),
  );

  OtherAppsController controller({bool phone = true}) => OtherAppsController(
        http: http,
        downloader: downloader,
        platform: UpdatePlatform(supported: phone),
        readToken: () async => token,
        writeToken: (t) async => token = t,
        stageApk: (path) async {
          staged.add(path);
          return '/cache/updates/${path.split('/').last}';
        },
      );

  MfficiencyApp app(String name) =>
      mfficiencyApps.firstWhere((a) => a.name == name);

  group('catalogue', () {
    test('every app reads its own tags, and never the watch builds', () {
      expect(app('BestToDo').tagFormat.parse('v0.2.135-3590000-dev')?.build,
          3590000);
      expect(
          app('Best Music')
              .tagFormat
              .parse('music-v0.3.84-3590846-dev')
              ?.version,
          '0.3.84');
      expect(app('Best Music').tagFormat.parse('wear-music-v0.3.84-1-dev'),
          isNull);
      expect(
          app('Vesta Immo')
              .tagFormat
              .parse('vesta-immo-v0.1.33-b3590848-dev')
              ?.build,
          3590848);
      expect(app('Best Watch').tagFormat.parse('v1.29-3590851-dev')?.version,
          '1.29');
      expect(app('Best Watch').tagFormat.parse('v2.0.1-3591234-dev')?.build,
          3591234);
      expect(
          app('Best Watch').tagFormat.parse('wear-v1.30-3591234-dev'), isNull);
      expect(
          app('BestFloory').tagFormat.parse('wear-v0.7.0-3590840-dev'), isNull);
    });

    test('unique app ids, each in the manifest queries', () {
      final ids = mfficiencyApps.map((a) => a.appId).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final manifest =
          File('android/src/main/AndroidManifest.xml').readAsStringSync();
      for (final id in ids) {
        expect(manifest, contains('<package android:name="$id" />'),
            reason: id);
      }
    });
  });

  group('controller', () {
    test('leaves this app out, knows installed and newest', () async {
      http.answers['Mfficiency/BestCollage'] = [
        asset('v0.4.18-3590000-dev', 'Mfficiency/BestCollage'),
        asset('v0.4.11-3500000', 'Mfficiency/BestCollage'),
      ];
      installed['com.mfficiency.best_collage'] = {
        'versionName': '0.4.11',
        'versionCode': 3500000,
      };
      final c = controller();
      await c.load();
      expect(c.apps.map((a) => a.name), isNot(contains('BestToDo')));
      final s = c.stateOf(app('BestCollage'));
      expect(s.status, OtherAppStatus.ready);
      expect(s.installed?.version, '0.4.11');
      expect(s.release?.label, '0.4.18 (3590000) · dev');
      expect(s.hasUpdate, isTrue);
      expect(s.release?.apkUrl,
          contains('github.com/Mfficiency/BestCollage/download'));
    });

    test('a private repo without access needs the token', () async {
      http.answers['Mfficiency/BestFloory'] = 404;
      final c = controller();
      await c.load();
      expect(c.stateOf(app('BestFloory')).status, OtherAppStatus.needsToken);
      expect(c.stateOf(app('MostlyGoodNews')).status, OtherAppStatus.noRelease);
    });

    test('the token goes along; the page\'s own one first', () async {
      token = 'own';
      final c = OtherAppsController(
        http: http,
        downloader: downloader,
        platform: UpdatePlatform(supported: true),
        readToken: () async => token,
        writeToken: (t) async => token = t,
        fallbackToken: () async => 'fallback',
      );
      await c.load();
      expect(http.requests.first.$2['Authorization'], 'Bearer own');
      await c.setToken('');
      expect(await c.token(), 'fallback');
    });

    test('install: private asset signed with the token, staged, installer',
        () async {
      token = 't';
      http.answers['Mfficiency/BestFloory'] = [
        asset('v0.7.0-3590840-dev', 'Mfficiency/BestFloory'),
      ];
      final c = controller();
      await c.load();
      final done = await c.install(app('BestFloory'));
      expect(done, OtherAppAction.installing);
      expect(downloader.signed.single.$2, 't');
      expect(downloader.urls.single.host, 'objects.example.com');
      expect(
          staged.single, endsWith('app-ch.mfficiency.bestfloory-3590840.apk'));
      final install = calls.lastWhere((c) => c.method == 'installApk');
      expect((install.arguments as Map)['path'],
          '/cache/updates/app-ch.mfficiency.bestfloory-3590840.apk');
    });

    test('install without the permission says so', () async {
      installOutcome = 'needs-permission';
      http.answers['Mfficiency/BestCollage'] = [
        asset('v0.4.18-3590000', 'Mfficiency/BestCollage'),
      ];
      final c = controller();
      await c.load();
      expect(
          await c.install(app('BestCollage')), OtherAppAction.needsPermission);
    });

    test('off a phone or without access: the page in the browser', () async {
      http.answers['Mfficiency/BestCollage'] = [
        asset('v0.4.18-3590000', 'Mfficiency/BestCollage'),
      ];
      final c = controller(phone: false);
      await c.load();
      expect(
          await c.install(app('BestCollage')), OtherAppAction.openedInBrowser);
      final open = calls.lastWhere((c) => c.method == 'openUrl');
      expect((open.arguments as Map)['url'],
          'https://github.com/Mfficiency/BestCollage/releases/tag/v0.4.18-3590000');
      expect(downloader.urls, isEmpty);
    });

    test('open launches an installed app', () async {
      installed['com.mfficiency.best_music'] = {
        'versionName': '0.3.84',
        'versionCode': 1,
      };
      final c = controller();
      await c.load();
      expect(await c.open(app('Best Music')), OtherAppAction.opened);
    });
  });

  group('widgets', () {
    Widget host(OtherAppsController c) => MaterialApp(
          home: Scaffold(
            body: ListView(children: [OtherAppsLink(controller: c)]),
          ),
        );

    testWidgets('the link opens the page with every other app', (tester) async {
      http.answers['Mfficiency/BestCollage'] = [
        asset('v0.4.18-3590000', 'Mfficiency/BestCollage'),
      ];
      http.answers['Mfficiency/BestFloory'] = 404;
      final c = controller();
      await tester.pumpWidget(host(c));
      await tester.tap(find.text('Other apps'));
      await tester.pumpAndSettle();
      expect(find.text('BestToDo'), findsNothing, reason: 'this app');
      expect(find.text('BestCollage'), findsOneWidget);
      expect(find.text('Newest: 0.4.18 (3590000)'), findsOneWidget);
      expect(
          find.byKey(
              const Key('otherApps.install.com.mfficiency.best_collage')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('otherApps.github.ch.mfficiency.bestfloory')),
        200,
      );
      expect(find.textContaining('Private: needs the GitHub token'),
          findsOneWidget);
    });

    testWidgets('Install downloads and hands it to Android', (tester) async {
      http.answers['Mfficiency/BestCollage'] = [
        asset('v0.4.18-3590000', 'Mfficiency/BestCollage'),
      ];
      final c = controller();
      await tester.pumpWidget(MaterialApp(home: OtherAppsPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('otherApps.install.com.mfficiency.best_collage')),
      );
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'installApk'), hasLength(1));
      expect(
          find.text('Android asks next: tap Install there.'), findsOneWidget);
    });

    testWidgets('the key icon explains and saves the token', (tester) async {
      final c = controller();
      await tester.pumpWidget(MaterialApp(home: OtherAppsPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('GitHub token'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Contents: "Read-only"'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('otherApps.token')), 'tok');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(token, 'tok');
      expect(http.requests.last.$2['Authorization'], 'Bearer tok',
          reason: 'asked again with the new token');
    });
  });
}
