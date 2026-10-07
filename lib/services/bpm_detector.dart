import 'dart:math' as math;
import 'dart:typed_data';

/// On-device tempo detection — Best Music's fallback when online lookups
/// (see `music_metadata_enricher.dart`) can't find a BPM for enough of the
/// library. Pure Dart, no Flutter dependency, so it runs inside a
/// `compute` isolate and is unit-testable with synthetic audio.
///
/// Classic onset-autocorrelation tempo estimation (the same idea as
/// librosa's `beat.tempo`):
/// 1. a log-compressed spectral-flux onset envelope (512-sample frames,
///    128-sample hop — ~86 frames/s at 11025 Hz),
/// 2. local-mean subtraction + half-wave rectification so only real
///    attacks remain,
/// 3. autocorrelation of that envelope over the lags for 50–220 BPM,
///    weighted by a log-normal prior around 120 BPM (one-octave spread) so
///    half/double-tempo ambiguities resolve toward a danceable tempo,
/// 4. parabolic interpolation around the best lag for sub-frame precision.
///
/// Returns null when the audio is too short or has no rhythmic content
/// (silence, a pure tone) rather than guessing.
int? estimateBpm(Int16List samples, int sampleRate) {
  final envelope = onsetEnvelope(samples, sampleRate);
  final framesPerSecond = sampleRate / _hop;
  return tempoFromEnvelope(envelope, framesPerSecond);
}

/// Message form of [estimateBpm] for `compute`: `[Int16List, int]`.
int? estimateBpmMessage(List<Object> message) =>
    estimateBpm(message[0] as Int16List, message[1] as int);

const int _frame = 512;
const int _hop = 128;

/// Spectral-flux onset strength per hop, mean-subtracted and rectified.
Float64List onsetEnvelope(Int16List samples, int sampleRate) {
  if (samples.length < _frame * 2) return Float64List(0);
  final frames = (samples.length - _frame) ~/ _hop + 1;
  final window = Float64List(_frame);
  for (var i = 0; i < _frame; i++) {
    window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_frame - 1));
  }
  const bins = _frame ~/ 2;
  var previous = Float64List(bins);
  final flux = Float64List(frames);
  final re = Float64List(_frame);
  final im = Float64List(_frame);
  for (var f = 0; f < frames; f++) {
    final offset = f * _hop;
    for (var i = 0; i < _frame; i++) {
      re[i] = samples[offset + i] / 32768.0 * window[i];
      im[i] = 0;
    }
    _fft(re, im);
    final current = Float64List(bins);
    var sum = 0.0;
    for (var k = 1; k < bins; k++) {
      final magnitude = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      final compressed = math.log(1 + 100 * magnitude);
      current[k] = compressed;
      final diff = compressed - previous[k];
      if (diff > 0) sum += diff;
    }
    flux[f] = f == 0 ? 0 : sum;
    previous = current;
  }
  // Subtract a ~0.5 s moving average so slow loudness swells don't read as
  // onsets, then keep only what pokes above it.
  final radius = math.max(1, (sampleRate / _hop * 0.25).round());
  final prefix = Float64List(frames + 1);
  for (var i = 0; i < frames; i++) {
    prefix[i + 1] = prefix[i] + flux[i];
  }
  final envelope = Float64List(frames);
  for (var i = 0; i < frames; i++) {
    final lo = math.max(0, i - radius);
    final hi = math.min(frames, i + radius + 1);
    final mean = (prefix[hi] - prefix[lo]) / (hi - lo);
    final value = flux[i] - mean;
    envelope[i] = value > 0 ? value : 0;
  }
  return envelope;
}

/// Picks the tempo (BPM, rounded) whose beat period best matches
/// [envelope]'s periodicity. Null when there's nothing periodic in it.
int? tempoFromEnvelope(Float64List envelope, double framesPerSecond,
    {double minBpm = 50, double maxBpm = 220, double minPeakiness = 1.3}) {
  final minLag = math.max(1, (60 * framesPerSecond / maxBpm).floor());
  final maxLag = (60 * framesPerSecond / minBpm).ceil();
  // Need a few beat periods of audio to call it a tempo at all.
  if (envelope.length < maxLag * 3) return null;
  var energy = 0.0;
  var peak = 0.0;
  for (final v in envelope) {
    energy += v * v;
    if (v > peak) peak = v;
  }
  // Below this there are no audible attacks at all, just rounding noise.
  if (energy <= 1e-9 || peak < 5) return null;

  final ac = Float64List(maxLag + 2);
  for (var lag = minLag - 1; lag <= maxLag + 1; lag++) {
    if (lag < 1) continue;
    var sum = 0.0;
    for (var i = 0; i + lag < envelope.length; i++) {
      sum += envelope[i] * envelope[i + lag];
    }
    // Unbiased: longer lags overlap fewer frames.
    ac[lag] = sum / (envelope.length - lag);
  }
  final zeroLag = energy / envelope.length;

  var bestLag = -1;
  var bestScore = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    final bpm = 60 * framesPerSecond / lag;
    final octaves = math.log(bpm / 120) / math.ln2;
    final prior = math.exp(-0.5 * octaves * octaves);
    final score = ac[lag] * prior;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  if (bestLag < 0) return null;
  // Weak periodicity relative to the signal's own energy → no real beat.
  if (ac[bestLag] < zeroLag * 0.05) return null;
  // A beat makes the autocorrelation peaky; noise-level flux (a held tone,
  // decoder dither) leaves it flat.
  var acMean = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    acMean += ac[lag];
  }
  acMean /= maxLag - minLag + 1;
  if (ac[bestLag] < acMean * minPeakiness) return null;

  var refined = bestLag.toDouble();
  if (bestLag > minLag && bestLag < maxLag) {
    final a = ac[bestLag - 1], b = ac[bestLag], c = ac[bestLag + 1];
    final denominator = a - 2 * b + c;
    if (denominator.abs() > 1e-12) {
      final shift = 0.5 * (a - c) / denominator;
      if (shift.abs() <= 1) refined += shift;
    }
  }
  final bpm = 60 * framesPerSecond / refined;
  if (!bpm.isFinite || bpm < 1 || bpm > 999) return null;
  return bpm.round();
}

/// In-place iterative radix-2 FFT; [re]/[im] length must be a power of 2.
void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wr = math.cos(angle), wi = math.sin(angle);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final ar = re[i + k], ai = im[i + k];
        final br = re[i + k + len ~/ 2], bi = im[i + k + len ~/ 2];
        final tr = br * cr - bi * ci;
        final ti = br * ci + bi * cr;
        re[i + k] = ar + tr;
        im[i + k] = ai + ti;
        re[i + k + len ~/ 2] = ar - tr;
        im[i + k + len ~/ 2] = ai - ti;
        final nextCr = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = nextCr;
      }
    }
  }
}
