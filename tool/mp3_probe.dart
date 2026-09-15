// Temporary probe: does the MP3 downloader path actually work end-to-end?
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'mamma mia abba' : args.join(' ');
  final yt = YoutubeExplode();
  try {
    stdout.writeln('--- search: $query');
    final sw = Stopwatch()..start();
    final results = await yt.search.search(query);
    stdout.writeln('search took ${sw.elapsedMilliseconds}ms, ${results.length} hits');
    for (final v in results.take(5)) {
      stdout.writeln('  ${v.id.value} | ${v.title} | ${v.author} | '
          'dur=${v.duration} | views=${v.engagement.viewCount}');
    }
    final first = results.first;
    stdout.writeln('--- manifest for ${first.id.value}');
    sw.reset();
    final manifest = await yt.videos.streamsClient.getManifest(first.id.value);
    stdout.writeln('manifest took ${sw.elapsedMilliseconds}ms');
    for (final s in manifest.audioOnly) {
      stdout.writeln('  ${s.container.name} ${s.bitrate} ${s.size} codec=${s.audioCodec}');
    }
    final mp4 = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    final info = (mp4.isNotEmpty ? mp4 : manifest.audioOnly.toList()).withHighestBitrate();
    stdout.writeln('chose ${info.container.name} ${info.size} url=${info.url.toString().substring(0, 120)}...');

    stdout.writeln('--- yt_explode streaming download');
    sw.reset();
    var received = 0;
    final total = info.size.totalBytes;
    final file = File('${Directory.systemTemp.path}/probe_yt.${info.container.name}');
    final sink = file.openWrite();
    var lastPrint = 0;
    try {
      await for (final chunk in yt.videos.streamsClient.get(info)) {
        sink.add(chunk);
        received += chunk.length;
        if (sw.elapsedMilliseconds - lastPrint > 1000) {
          lastPrint = sw.elapsedMilliseconds;
          stdout.writeln('  ${(received / total * 100).toStringAsFixed(1)}% '
              '($received/$total) after ${sw.elapsedMilliseconds}ms');
        }
      }
    } finally {
      await sink.close();
    }
    stdout.writeln('yt_explode download done in ${sw.elapsedMilliseconds}ms, '
        '${await file.length()} bytes');

    stdout.writeln('--- plain HTTP GET of the same url (what DownloadManager would do)');
    sw.reset();
    final client = HttpClient();
    final req = await client.getUrl(info.url);
    final resp = await req.close();
    stdout.writeln('status=${resp.statusCode} len=${resp.contentLength}');
    var plain = 0;
    lastPrint = 0;
    await for (final chunk in resp) {
      plain += chunk.length;
      if (sw.elapsedMilliseconds - lastPrint > 1000) {
        lastPrint = sw.elapsedMilliseconds;
        stdout.writeln('  plain ${(plain / total * 100).toStringAsFixed(1)}% after ${sw.elapsedMilliseconds}ms');
      }
    }
    stdout.writeln('plain GET done in ${sw.elapsedMilliseconds}ms, $plain bytes');
    client.close();
  } catch (e, st) {
    stdout.writeln('FAILED: $e');
    stdout.writeln(st.toString().split('\n').take(6).join('\n'));
  } finally {
    yt.close();
  }
}
