import 'dart:io';

import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:besttodo/services/youtube_network_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    YoutubeRoute.lastWorking = null;
    Mp3DownloaderService.instance.routeResolverOverride = null;
  });

  test('tries the last working route first, then the rest in order', () {
    expect(YoutubeRoute.tryOrder(), [
      YoutubeRoute.system,
      YoutubeRoute.ipv4,
      YoutubeRoute.ipv6,
      YoutubeRoute.invidious,
    ]);
    YoutubeRoute.lastWorking = YoutubeRoute.ipv4;
    expect(YoutubeRoute.tryOrder(), [
      YoutubeRoute.ipv4,
      YoutubeRoute.system,
      YoutubeRoute.ipv6,
      YoutubeRoute.invidious,
    ]);
  });

  group('resolveAudioStream walks the routes', () {
    test('a blocked default connection falls through to IPv4, which is '
        'remembered and handed to playback', () async {
      final tried = <YoutubeRoute>[];
      Mp3DownloaderService.instance.routeResolverOverride =
          (id, route) async {
        tried.add(route);
        if (route == YoutubeRoute.system) {
          throw Exception("Sign in to confirm you're not a bot");
        }
        return ResolvedAudioStream(
            url: Uri.parse('https://example.com/$id'),
            totalBytes: 5000,
            contentType: 'audio/mp4');
      };
      final r = await Mp3DownloaderService.instance.resolveAudioStream('v1');
      expect(tried, [YoutubeRoute.system, YoutubeRoute.ipv4]);
      expect(r.route, YoutubeRoute.ipv4);
      expect(YoutubeRoute.lastWorking, YoutubeRoute.ipv4);

      // Next video: straight to IPv4.
      tried.clear();
      await Mp3DownloaderService.instance.resolveAudioStream('v2');
      expect(tried, [YoutubeRoute.ipv4]);
    });

    test('Invidious is the last resort', () async {
      Mp3DownloaderService.instance.routeResolverOverride =
          (id, route) async {
        if (route != YoutubeRoute.invidious) throw Exception('blocked');
        return ResolvedAudioStream(
            url: Uri.parse('https://inv.example/videoplayback'),
            totalBytes: 5000,
            contentType: 'audio/webm');
      };
      final r = await Mp3DownloaderService.instance.resolveAudioStream('v1');
      expect(r.route, YoutubeRoute.invidious);
      expect(r.contentType, 'audio/webm');
    });

    test('every route failing explains it', () async {
      Mp3DownloaderService.instance.routeResolverOverride =
          (_, __) async => throw Exception('nope');
      await expectLater(
          Mp3DownloaderService.instance.resolveAudioStream('v1'),
          throwsA(isA<Mp3DownloadException>().having((e) => e.toString(),
              'message', allOf(contains('IPv4 only'), contains('Invidious')))));
    });
  });

  test('pickInvidiousAudio prefers the best mp4 audio and resolves its URL',
      () {
    final base = Uri.parse('https://inv.example');
    final pick = pickInvidiousAudio({
      'adaptiveFormats': [
        {'type': 'video/mp4', 'url': '/videoplayback?v=1', 'clen': '999999'},
        {
          'type': 'audio/webm; codecs="opus"',
          'url': '/videoplayback?itag=251',
          'clen': '4000',
          'bitrate': '160000'
        },
        {
          'type': 'audio/mp4; codecs="mp4a.40.2"',
          'url': '/videoplayback?itag=139',
          'clen': '2000',
          'bitrate': '48000'
        },
        {
          'type': 'audio/mp4; codecs="mp4a.40.2"',
          'url': '/videoplayback?itag=140',
          'clen': '3000',
          'bitrate': '128000'
        },
        {'type': 'audio/mp4', 'url': '/no-size'},
      ],
    }, base)!;
    expect(pick.url.toString(), 'https://inv.example/videoplayback?itag=140');
    expect(pick.totalBytes, 3000);
    expect(pick.extension, 'm4a');

    final webmOnly = pickInvidiousAudio({
      'adaptiveFormats': [
        {
          'type': 'audio/webm',
          'url': 'https://elsewhere.example/a',
          'clen': '10',
        },
      ],
    }, base)!;
    expect(webmOnly.url.host, 'elsewhere.example');
    expect(webmOnly.extension, 'webm');
    expect(pickInvidiousAudio({'adaptiveFormats': []}, base), isNull);
    expect(pickInvidiousAudio('junk', base), isNull);
  });

  test('a pinned route only connects over its address family', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..write('hi from ${request.connectionInfo!.remoteAddress.type.name}')
        ..close();
    });
    addTearDown(() => server.close(force: true));
    final url = Uri.parse('http://localhost:${server.port}/');

    final v4 = httpClientForRoute(YoutubeRoute.ipv4);
    final response = await (await v4.getUrl(url)).close();
    expect(await response.transform(const SystemEncoding().decoder).join(),
        'hi from IPv4');
    v4.close(force: true);

    // The server only listens on IPv4, so pinning to IPv6 can't reach it.
    final v6 = httpClientForRoute(YoutubeRoute.ipv6);
    await expectLater(
        () async => (await v6.getUrl(url)).close(), throwsA(anything));
    v6.close(force: true);
  });
}
