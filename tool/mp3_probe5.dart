import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Future<void> main(List<String> args) async {
  final id = args.isEmpty ? 'unfzfe8f9NI' : args.first;
  final clients = <String, YoutubeApiClient>{
    'androidSdkless': YoutubeApiClient.androidSdkless,
    'androidVr': YoutubeApiClient.androidVr,
    'android': YoutubeApiClient.android,
    'ios': YoutubeApiClient.ios,
    'androidMusic': YoutubeApiClient.androidMusic,
    'tv': YoutubeApiClient.tv,
    'mediaConnect': YoutubeApiClient.mediaConnect,
    'mweb': YoutubeApiClient.mweb,
    'safari': YoutubeApiClient.safari,
  };
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  for (final entry in clients.entries) {
    final yt = YoutubeExplode();
    try {
      final m = await yt.videos.streamsClient
          .getManifest(id, ytClients: [entry.value]).timeout(const Duration(seconds: 30));
      final audio = m.audioOnly.toList();
      if (audio.isEmpty) { stdout.writeln('${entry.key}: no audio streams'); continue; }
      final mp4 = audio.where((s) => s.container == StreamContainer.mp4).toList();
      final info = (mp4.isNotEmpty ? mp4 : audio).withHighestBitrate();
      final total = info.size.totalBytes;
      // probe a range well past the 1 MiB wall
      final r = await http.getUrl(info.url);
      final lo = 1500000, hi = (lo + 262143).clamp(0, total - 1);
      r.headers.set(HttpHeaders.rangeHeader, 'bytes=$lo-$hi');
      final resp = await r.close();
      var n = 0;
      await for (final c in resp) { n += c.length; }
      // and a tail range
      final r2 = await http.getUrl(info.url);
      r2.headers.set(HttpHeaders.rangeHeader, 'bytes=${total - 65536}-${total - 1}');
      final resp2 = await r2.close();
      var n2 = 0;
      await for (final c in resp2) { n2 += c.length; }
      stdout.writeln('${entry.key}: total=$total mid=${resp.statusCode}/$n '
          'tail=${resp2.statusCode}/$n2  codec=${info.audioCodec} ${info.container.name}');
    } catch (e) {
      stdout.writeln('${entry.key}: ERROR ${e.toString().split('\n').first}');
    } finally {
      yt.close();
    }
  }
  http.close();
}
