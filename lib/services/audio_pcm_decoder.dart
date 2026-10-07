import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Decodes a slice of an audio file to mono 16-bit PCM for on-device BPM
/// detection ([estimateBpm]). Android uses the platform's own decoders
/// (MediaExtractor + MediaCodec, `AudioPcmDecoder.kt`, channel
/// `besttodo/audio_pcm`) so every format the player handles works with no
/// extra native library. Desktop falls back to an `ffmpeg` on PATH when
/// there is one. Anything else (web, tests, no ffmpeg) returns null —
/// detection is simply skipped.
class AudioPcmDecoder {
  const AudioPcmDecoder();

  static const MethodChannel _channel = MethodChannel('besttodo/audio_pcm');

  /// Sample rate the slice is resampled to: plenty for onset detection and
  /// a quarter of the data a 44.1 kHz decode would hand across.
  static const int sampleRate = 11025;

  /// Mono PCM for [durationMs] of [path] starting at [startMs] (clamped by
  /// the decoder to the file's length), or null when it can't be decoded.
  Future<Int16List?> decode(String path,
      {int startMs = 0, int durationMs = 45000}) async {
    try {
      if (Platform.isAndroid) {
        final bytes = await _channel.invokeMethod<Uint8List>('decode', {
          'path': path,
          'startMs': startMs,
          'durationMs': durationMs,
          'sampleRate': sampleRate,
        });
        return _asInt16(bytes);
      }
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run(
          'ffmpeg',
          [
            '-v', 'quiet',
            '-ss', (startMs / 1000).toStringAsFixed(3),
            '-t', (durationMs / 1000).toStringAsFixed(3),
            '-i', path,
            '-ac', '1',
            '-ar', '$sampleRate',
            '-f', 's16le',
            '-',
          ],
          stdoutEncoding: null,
        );
        if (result.exitCode != 0) return null;
        final out = result.stdout;
        return out is List<int> ? _asInt16(Uint8List.fromList(out)) : null;
      }
    } catch (_) {
      // MissingPluginException, no ffmpeg, unreadable file — no detection.
    }
    return null;
  }

  static Int16List? _asInt16(Uint8List? bytes) {
    if (bytes == null || bytes.length < 2) return null;
    final even = bytes.length - bytes.length % 2;
    final copy = Uint8List.fromList(bytes.sublist(0, even));
    return copy.buffer.asInt16List();
  }
}
