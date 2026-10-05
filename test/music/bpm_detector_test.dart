import 'dart:math' as math;
import 'dart:typed_data';

import 'package:besttodo/services/bpm_detector.dart';
import 'package:flutter_test/flutter_test.dart';

const int _rate = 11025;

/// [seconds] of a drum-machine-ish loop at [bpm]: a decaying noise burst
/// ("kick") on every beat, a quieter one on the off-beat ("hat"), over a
/// soft sustained tone so the signal is never silent between hits.
Int16List _beat(double bpm, {double seconds = 30, int seed = 1}) {
  final random = math.Random(seed);
  final n = (seconds * _rate).round();
  final out = Int16List(n);
  final period = 60 / bpm * _rate;
  for (var i = 0; i < n; i++) {
    final beatPos = i % period;
    final halfPos = (i + period / 2) % period;
    var v = 0.05 * math.sin(2 * math.pi * 220 * i / _rate);
    if (beatPos < 0.08 * _rate) {
      v += (random.nextDouble() * 2 - 1) * math.exp(-beatPos / (0.015 * _rate));
    }
    if (halfPos < 0.03 * _rate) {
      v += 0.3 *
          (random.nextDouble() * 2 - 1) *
          math.exp(-halfPos / (0.005 * _rate));
    }
    out[i] = (v.clamp(-1.0, 1.0) * 30000).round();
  }
  return out;
}

void main() {
  group('estimateBpm', () {
    for (final bpm in [85.0, 100.0, 120.0, 128.0, 140.0, 174.0]) {
      test('finds $bpm BPM in a synthetic beat', () {
        final found = estimateBpm(_beat(bpm), _rate);
        expect(found, isNotNull);
        expect((found! - bpm).abs(), lessThanOrEqualTo(2),
            reason: 'detected $found for $bpm');
      });
    }

    test('handles a non-integer tempo', () {
      final found = estimateBpm(_beat(97.5, seed: 3), _rate);
      expect(found, anyOf(97, 98));
    });

    test('silence has no tempo', () {
      expect(estimateBpm(Int16List(_rate * 20), _rate), isNull);
    });

    test('a steady tone has no tempo', () {
      final tone = Int16List(_rate * 20);
      for (var i = 0; i < tone.length; i++) {
        tone[i] = (10000 * math.sin(2 * math.pi * 440 * i / _rate)).round();
      }
      expect(estimateBpm(tone, _rate), isNull);
    });

    test('too short to tell → null', () {
      expect(estimateBpm(_beat(120, seconds: 1), _rate), isNull);
      expect(estimateBpm(Int16List(100), _rate), isNull);
    });

    test('estimateBpmMessage is the compute() form', () {
      expect(estimateBpmMessage(<Object>[_beat(120), _rate]),
          closeTo(120, 2));
    });
  });
}
