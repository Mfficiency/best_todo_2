import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

/// A tiny HTTP server on a raw socket, so a response can be cut off in the
/// middle of the body like a dropped mobile connection.
class ApkServer {
  ApkServer._(this._socket) {
    _socket.listen(_serve);
  }

  static Future<ApkServer> start() async =>
      ApkServer._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _socket;
  List<int> body = List.generate(1000, (i) => i % 251);
  String etag = '"v1"';

  /// The next full answer stops after this many body bytes (then null).
  int? cutAfter;

  /// Answer every range request with 416.
  bool refuseRanges = false;
  final requests = <Map<String, String>>[];

  Uri get url => Uri.parse('http://127.0.0.1:${_socket.port}/app.apk');

  Future<void> close() => _socket.close();

  Future<void> _serve(Socket s) async {
    final head = StringBuffer();
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = s.listen((data) {
      head.write(latin1.decode(data));
      if (head.toString().contains('\r\n\r\n') && !done.isCompleted) {
        done.complete();
      }
    }, onError: (_) {});
    await done.future;
    final lines = head.toString().split('\r\n');
    final headers = <String, String>{
      for (final l in lines.skip(1).where((l) => l.contains(':')))
        l.substring(0, l.indexOf(':')).toLowerCase():
            l.substring(l.indexOf(':') + 1).trim(),
    };
    requests.add(headers);
    final range = RegExp(r'bytes=(\d+)-').firstMatch(headers['range'] ?? '');
    final ifRange = headers['if-range'];
    var from = 0;
    var status = '200 OK';
    final extra = <String>['ETag: $etag'];
    if (range != null && refuseRanges) {
      s.write(
        'HTTP/1.1 416 Range Not Satisfiable\r\n'
        'Content-Length: 0\r\nConnection: close\r\n\r\n',
      );
      await s.flush();
      await s.close();
      await sub.cancel();
      return;
    }
    if (range != null && (ifRange == null || ifRange == etag)) {
      from = int.parse(range.group(1)!);
      status = '206 Partial Content';
      extra.add('Content-Range: bytes $from-${body.length - 1}/${body.length}');
    }
    final part = body.sublist(from);
    s.write(
      'HTTP/1.1 $status\r\nContent-Length: ${part.length}\r\n'
      '${extra.join('\r\n')}\r\nConnection: close\r\n\r\n',
    );
    final cut = cutAfter;
    cutAfter = null;
    s.add(cut == null ? part : part.sublist(0, cut));
    await s.flush();
    if (cut != null) {
      s.destroy();
    } else {
      await s.close();
    }
    await sub.cancel();
  }
}

void main() {
  late ApkServer server;
  late Directory dir;
  late ApkDownloader downloader;

  setUp(() async {
    HttpOverrides.global = null;
    server = await ApkServer.start();
    dir = Directory.systemTemp.createTempSync('apk');
    downloader = ApkDownloader.io(
      directory: () async => dir.path,
      idleTimeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  List<String> files() =>
      dir.listSync().map((f) => f.uri.pathSegments.last).toList()..sort();

  test('downloads as .part, renames when complete, removes other builds',
      () async {
    File('${dir.path}/App-1.0.0-1.apk').writeAsStringSync('old');
    final progress = <double?>[];
    final path = await downloader.download(
      server.url,
      'App-2.0.0-2.apk',
      onProgress: progress.add,
    );
    expect(path, '${dir.path}/App-2.0.0-2.apk');
    expect(File(path!).readAsBytesSync(), server.body);
    expect(files(), ['App-2.0.0-2.apk']);
    expect(progress.last, 1.0);
    expect(await downloader.downloaded('App-2.0.0-2.apk'), path);
    expect(downloader.exists(path), isTrue);
    expect(await downloader.downloaded('App-1.0.0-1.apk'), isNull);
  });

  test('an interrupted download continues where it stopped', () async {
    server.cutAfter = 400;
    expect(await downloader.download(server.url, 'App.apk'), isNull);
    expect(File('${dir.path}/App.apk.part').lengthSync(), 400);
    expect(await downloader.downloaded('App.apk'), isNull);

    final progress = <double?>[];
    final path = await downloader.download(
      server.url,
      'App.apk',
      onProgress: progress.add,
    );
    expect(File(path!).readAsBytesSync(), server.body);
    expect(server.requests.last['range'], 'bytes=400-');
    expect(server.requests.last['if-range'], '"v1"');
    expect(progress.first, greaterThan(0.4), reason: 'counts the .part');
    expect(files(), ['App.apk']);
  });

  test('a file replaced in between starts over (If-Range)', () async {
    server.cutAfter = 400;
    await downloader.download(server.url, 'App.apk');
    server
      ..etag = '"v2"'
      ..body = List.generate(800, (i) => (i * 7) % 256);
    final path = await downloader.download(server.url, 'App.apk');
    expect(File(path!).readAsBytesSync(), server.body);
  });

  test('a server refusing the range starts over', () async {
    server.cutAfter = 400;
    await downloader.download(server.url, 'App.apk');
    server.refuseRanges = true;
    final path = await downloader.download(server.url, 'App.apk');
    expect(File(path!).readAsBytesSync(), server.body);
    expect(server.requests.last['range'], isNull);
  });

  test('another build\'s partial download is dropped', () async {
    server.cutAfter = 400;
    await downloader.download(server.url, 'App-1.apk');
    final path = await downloader.download(server.url, 'App-2.apk');
    expect(File(path!).readAsBytesSync(), server.body);
    expect(server.requests.last['range'], isNull);
    expect(files(), ['App-2.apk']);
  });

  test('an unreachable server fails and keeps nothing complete', () async {
    final missing = server.url.replace(port: 1); // nothing listens there
    expect(await downloader.download(missing, 'App.apk'), isNull);
    expect(await downloader.downloaded('App.apk'), isNull);
  });

  test('a private asset\'s signed link: the redirect, not followed', () async {
    final api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => api.close(force: true));
    final seen = <HttpHeaders>[];
    api.listen((req) async {
      seen.add(req.headers);
      req.response
        ..statusCode = 302
        ..headers.set('Location', 'https://objects.example.com/apk?sig=1');
      await req.response.close();
    });
    final url = await downloader.signedAssetUrl(
      Uri.parse('http://127.0.0.1:${api.port}/assets/42'),
      'tok',
    );
    expect(url.toString(), 'https://objects.example.com/apk?sig=1');
    expect(seen.single.value('authorization'), 'Bearer tok');
    expect(seen.single.value('accept'), 'application/octet-stream');
  });
}
