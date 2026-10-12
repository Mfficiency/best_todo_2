import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

void main() {
  late HttpServer server;
  final agents = <String?>[];
  var status = 200;

  setUp(() async {
    agents.clear();
    status = 200;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      agents.add(req.headers.value('user-agent'));
      req.response.statusCode = status;
      if (status == 403) {
        req.response.headers
          ..set('x-ratelimit-remaining', '0')
          ..set('x-ratelimit-reset', '1800000000')
          ..set('x-other', 'dropped');
      }
      req.response.write(jsonEncode([
        {'tag_name': 'v1.0.0-1'},
      ]));
      await req.response.close();
    });
  });
  tearDown(() => server.close(force: true));

  Uri url() => Uri.parse('http://127.0.0.1:${server.port}/releases');

  test('the default HTTP sends the app\'s User-Agent', () async {
    final http = UpdateHttp.io(userAgent: 'MyApp-update-check');
    final json = await http.getJson(url());
    expect(json, isA<List<Object?>>());
    expect(agents.single, 'MyApp-update-check');
  });

  test('an error keeps the rate-limit headers', () async {
    status = 403;
    try {
      await UpdateHttp.io().getJson(url());
      fail('no exception');
    } on UpdateHttpException catch (e) {
      expect(e.status, 403);
      expect(e.headers, {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1800000000',
      });
      expect(e.isRateLimit(), isTrue);
    }
    expect(agents.single, startsWith('Dart/'), reason: 'none set: dart:io\'s');
  });

  test('the default downloader sends it too', () async {
    final dir = await Directory.systemTemp.createTemp('ua');
    addTearDown(() => dir.delete(recursive: true));
    final d = ApkDownloader.io(
      directory: () async => dir.path,
      userAgent: 'MyApp-update-check',
    );
    expect(await d.download(url(), 'a.apk'), isNotNull);
    expect(agents.single, 'MyApp-update-check');
  });
}
