// Real end-to-end check of the MP3 Downloader against live YouTube.
//
// Not part of `flutter test` — it needs the network and takes a few seconds
// per track, so it is a tool you run by hand after touching
// `lib/services/mp3_downloader_service.dart`:
//
// It searches, prints what the picker would show (including play counts),
// downloads the top hit through the real service, and verifies the saved
// file is a complete, well-formed audio container rather than the truncated
// 1 MiB YouTube hands out to a client it doesn't like.
//
// It lives in `tool/` rather than `test/` on purpose: `flutter test` with no
// arguments only walks `test/`, so a flaky network or a YouTube change can
// never turn CI red from here. Run it explicitly:
//
//   flutter test tool/check_mp3_download.dart
//   flutter test tool/check_mp3_download.dart --dart-define=QUERY="mamma mia"
import 'dart:io';

import 'package:besttodo/services/log_service.dart';
import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _queryOverride = String.fromEnvironment('QUERY');

void main() {
  test('downloads real audio from YouTube end to end', _run,
      timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _run() async {
  final queries = _queryOverride.isEmpty
      ? const ['mamma mia abba', 'never gonna give you up']
      : [_queryOverride];

  final service = Mp3DownloaderService.instance;
  final tempDir = await Directory.systemTemp.createTemp('besttodo_mp3_check');
  var failures = 0;

  for (final query in queries) {
    stdout.writeln('=== $query');
    try {
      final results = await service.search(query, limit: 5);
      for (final r in results) {
        final plays = formatViewCount(r.viewCount);
        stdout.writeln('  ${r.title} | ${r.channel} | ${r.duration} | '
            '${plays.isEmpty ? '(no count)' : '$plays plays'}');
      }
      if (results.isEmpty) {
        stdout.writeln('  FAIL: no results');
        failures++;
        continue;
      }
      // A play count on the top hit is the feature under test; a missing one
      // is legal (live streams) but worth flagging when every hit lacks it.
      if (results.every((r) => r.viewCount == null)) {
        stdout.writeln('  FAIL: no result reported a play count');
        failures++;
      }

      final pick = results.first;
      final stopwatch = Stopwatch()..start();
      var lastPercent = -1;
      final path = await service.downloadMp3(
        pick,
        tempDir.path,
        onProgress: (received, total) {
          final percent = total > 0 ? (received * 100 ~/ total) : 0;
          if (percent >= lastPercent + 25) {
            lastPercent = percent;
            stdout.writeln('    $percent% ($received/$total)');
          }
        },
      );

      final file = File(path);
      final length = await file.length();
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      final header = await file.openRead(0, 12).first;
      final brand = String.fromCharCodes(header.sublist(4, 8));
      final isMp4 = path.endsWith('.m4a');
      final looksValid = isMp4 ? brand == 'ftyp' : header[0] == 0x1A;

      stdout.writeln('  saved ${(length / 1024 / 1024).toStringAsFixed(2)} MB '
          'in ${seconds.toStringAsFixed(1)}s '
          '(${(length / 1024 / (seconds <= 0 ? 1 : seconds)).round()} KiB/s)');
      stdout.writeln('  -> $path');

      if (!looksValid) {
        stdout.writeln('  FAIL: header is not a valid '
            '${isMp4 ? 'MP4/M4A' : 'WebM'} container');
        failures++;
      } else if (length <= 1024 * 1024 + 4096) {
        // The exact failure this whole client-probing dance exists to catch.
        stdout.writeln('  FAIL: only ${length}B — looks truncated at the '
            '1 MiB PoToken wall');
        failures++;
      } else {
        stdout.writeln('  OK');
      }
      // No `.part` file should survive a successful download.
      if (await File('$path.part').exists()) {
        stdout.writeln('  FAIL: leftover .part file');
        failures++;
      }
    } catch (e) {
      stdout.writeln('  FAIL: $e');
      failures++;
    }
  }

  stdout.writeln('\n--- app log ---');
  for (final line in LogService.logs.value) {
    stdout.writeln(line);
  }

  await tempDir.delete(recursive: true);
  stdout.writeln(failures == 0
      ? '\nAll checks passed.'
      : '\n$failures check(s) FAILED.');
  expect(failures, 0, reason: '$failures end-to-end check(s) failed');
}
