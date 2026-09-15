import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'unfzfe8f9NI' : args.first;
  final yt = YoutubeExplode();
  final sw = Stopwatch()..start();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(id);
    final mp4 = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    final info = (mp4.isNotEmpty ? mp4 : manifest.audioOnly.toList())
        .withHighestBitrate();
    final total = info.size.totalBytes;
    stdout.writeln('stream: ${info.container.name} $total bytes');

    stdout.writeln('--- plain full GET');
    sw.reset();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final req = await client.getUrl(info.url);
    req.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120 Safari/537.36');
    final resp = await req.close();
    stdout.writeln('status=${resp.statusCode} contentLength=${resp.contentLength}');
    var got = 0, lastPrint = 0;
    await for (final c in resp) {
      got += c.length;
      if (sw.elapsedMilliseconds - lastPrint > 1000) {
        lastPrint = sw.elapsedMilliseconds;
        stdout.writeln('  ${(got / total * 100).toStringAsFixed(1)}% after ${sw.elapsedMilliseconds}ms');
      }
    }
    stdout.writeln('plain GET: $got bytes in ${sw.elapsedMilliseconds}ms');

    stdout.writeln('--- ranged GET (0-1048575)');
    sw.reset();
    final r2 = await client.getUrl(info.url);
    r2.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1048575');
    final resp2 = await r2.close();
    stdout.writeln('status=${resp2.statusCode} len=${resp2.contentLength}');
    var got2 = 0;
    await for (final c in resp2) { got2 += c.length; }
    stdout.writeln('ranged GET: $got2 bytes in ${sw.elapsedMilliseconds}ms');
    client.close();
  } catch (e) {
    stdout.writeln('FAILED after ${sw.elapsedMilliseconds}ms: $e');
  } finally {
    yt.close();
  }
}
