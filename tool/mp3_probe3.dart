import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'unfzfe8f9NI' : args.first;
  final yt = YoutubeExplode();
  final sw = Stopwatch()..start();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final manifest = await yt.videos.streamsClient.getManifest(id);
    final mp4 = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4).toList();
    final info = (mp4.isNotEmpty ? mp4 : manifest.audioOnly.toList())
        .withHighestBitrate();
    final total = info.size.totalBytes;
    stdout.writeln('total=$total');

    stdout.writeln('--- open-ended range "bytes=0-"');
    sw.reset();
    final r = await client.getUrl(info.url);
    r.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final resp = await r.close();
    stdout.writeln('status=${resp.statusCode} len=${resp.contentLength} '
        'contentRange=${resp.headers.value('content-range')}');
    var got = 0, lastPrint = 0;
    await for (final c in resp) {
      got += c.length;
      if (sw.elapsedMilliseconds - lastPrint > 2000) {
        lastPrint = sw.elapsedMilliseconds;
        stdout.writeln('  ${(got / total * 100).toStringAsFixed(1)}% @${sw.elapsedMilliseconds}ms');
      }
    }
    stdout.writeln('open-ended: $got/$total bytes in ${sw.elapsedMilliseconds}ms');

    stdout.writeln('--- segmented (1MB chunks) into a real file');
    sw.reset();
    final f = File('${Directory.systemTemp.path}/probe_seg.m4a');
    final sink = f.openWrite();
    var off = 0;
    const chunkSize = 1 << 20;
    while (off < total) {
      final end = (off + chunkSize - 1).clamp(0, total - 1);
      final rq = await client.getUrl(info.url);
      rq.headers.set(HttpHeaders.rangeHeader, 'bytes=$off-$end');
      final rs = await rq.close();
      if (rs.statusCode != 206 && rs.statusCode != 200) {
        stdout.writeln('  chunk $off failed ${rs.statusCode}');
        break;
      }
      await for (final c in rs) { sink.add(c); off += c.length; }
      stdout.writeln('  ${(off / total * 100).toStringAsFixed(1)}% @${sw.elapsedMilliseconds}ms');
    }
    await sink.close();
    stdout.writeln('segmented: ${await f.length()}/$total in ${sw.elapsedMilliseconds}ms');
    final head = await f.openRead(0, 12).first;
    stdout.writeln('first bytes: ${head.map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
    stdout.writeln('ftyp? ${String.fromCharCodes(head.sublist(4, 8))}');
  } catch (e) {
    stdout.writeln('FAILED: $e');
  } finally {
    client.close();
    yt.close();
  }
}
