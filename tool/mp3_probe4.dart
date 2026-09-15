import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<int> tryGet(HttpClient c, Uri url, {String? rangeHeader, String label = ''}) async {
  try {
    final r = await c.getUrl(url);
    if (rangeHeader != null) r.headers.set(HttpHeaders.rangeHeader, rangeHeader);
    r.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36');
    final resp = await r.close();
    var n = 0;
    await for (final ch in resp) { n += ch.length; }
    stdout.writeln('  $label -> ${resp.statusCode}, $n bytes');
    return resp.statusCode;
  } catch (e) {
    stdout.writeln('  $label -> EX $e');
    return -1;
  }
}

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'unfzfe8f9NI' : args.first;
  final yt = YoutubeExplode();
  try {
    final manifest = await yt.videos.streamsClient.getManifest(id);
    final mp4 = manifest.audioOnly.where((s) => s.container == StreamContainer.mp4).toList();
    final info = (mp4.isNotEmpty ? mp4 : manifest.audioOnly.toList()).withHighestBitrate();
    final total = info.size.totalBytes;
    final url = info.url;
    stdout.writeln('total=$total');
    stdout.writeln('query keys: ${url.queryParameters.keys.join(",")}');

    final c = HttpClient();
    stdout.writeln('A: same client, repeat first range twice');
    await tryGet(c, url, rangeHeader: 'bytes=0-1048575', label: 'hdr 0-1048575 #1');
    await tryGet(c, url, rangeHeader: 'bytes=0-1048575', label: 'hdr 0-1048575 #2');
    stdout.writeln('B: header range for second chunk');
    await tryGet(c, url, rangeHeader: 'bytes=1048576-2097151', label: 'hdr 1048576-2097151');
    stdout.writeln('C: fresh client, second chunk');
    final c2 = HttpClient();
    await tryGet(c2, url, rangeHeader: 'bytes=1048576-2097151', label: 'fresh hdr chunk2');
    c2.close();
    stdout.writeln('D: &range= query param');
    Uri ranged(int a, int b) => url.replace(queryParameters: {
          ...url.queryParameters,
          'range': '$a-$b',
        });
    await tryGet(c, ranged(0, 1048575), label: 'qry range=0-1048575');
    await tryGet(c, ranged(1048576, 2097151), label: 'qry range=1048576-2097151');
    await tryGet(c, ranged(2097152, total - 1), label: 'qry range=2097152-end');
    stdout.writeln('E: full via &range=0-total');
    await tryGet(c, ranged(0, total - 1), label: 'qry range=0-end');
    c.close();
  } catch (e) {
    stdout.writeln('FAILED: $e');
  } finally {
    yt.close();
  }
}
