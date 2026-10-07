package com.mfficiency.best_todo_2

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteOrder
import java.util.concurrent.Executors

// Decodes a slice of an audio file to mono 16-bit little-endian PCM at a
// requested (low) sample rate, for Best Music's on-device BPM detection
// (lib/services/audio_pcm_decoder.dart + bpm_detector.dart). Uses the
// platform's own MediaExtractor/MediaCodec, so every format the player can
// play is covered with no bundled decoder. Runs on its own single worker
// thread — one file at a time, never on the UI thread.
object AudioPcmDecoder {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "besttodo/audio_pcm").setMethodCallHandler { call, result ->
            when (call.method) {
                "decode" -> {
                    val path = call.argument<String>("path")
                    val startMs = call.argument<Number>("startMs")?.toLong() ?: 0L
                    val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 45000L
                    val sampleRate = call.argument<Number>("sampleRate")?.toInt() ?: 11025
                    if (path == null) {
                        result.error("bad-args", "path missing", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        val bytes = try {
                            decode(path, startMs, durationMs, sampleRate)
                        } catch (e: Throwable) {
                            null
                        }
                        mainHandler.post { result.success(bytes) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun decode(path: String, startMs: Long, durationMs: Long, targetRate: Int): ByteArray? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var trackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    trackIndex = i
                    format = f
                    break
                }
            }
            if (trackIndex < 0 || format == null) return null
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            // A song shorter than start + duration: analyze from its start
            // instead of seeking past the end.
            val trackDurationUs = if (format.containsKey(MediaFormat.KEY_DURATION))
                format.getLong(MediaFormat.KEY_DURATION) else -1L
            var startUs = startMs * 1000
            if (trackDurationUs > 0 && startUs + durationMs * 1000 > trackDurationUs) {
                startUs = maxOf(0L, trackDurationUs - durationMs * 1000)
            }
            extractor.selectTrack(trackIndex)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            val endUs = startUs + durationMs * 1000

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            var channels = maxOf(1, format.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, 2))
            var sourceRate = maxOf(1, format.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, 44100))
            var floatPcm = false

            val maxSamples = (durationMs * targetRate / 1000).toInt() + targetRate
            val out = ShortArray(maxSamples)
            var outCount = 0
            var accumulator = 0.0
            var accumulated = 0
            var phase = 0L

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var idleLoops = 0
            while (!outputDone && outCount < maxSamples && idleLoops < 500) {
                if (!inputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        val time = extractor.sampleTime
                        if (size < 0 || time > endUs) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size, time, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val f = codec.outputFormat
                        channels = maxOf(1, f.getIntegerOrDefault(MediaFormat.KEY_CHANNEL_COUNT, channels))
                        sourceRate = maxOf(1, f.getIntegerOrDefault(MediaFormat.KEY_SAMPLE_RATE, sourceRate))
                        floatPcm = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                            f.getIntegerOrDefault(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT) ==
                            AudioFormat.ENCODING_PCM_FLOAT
                    }
                    outIndex >= 0 -> {
                        idleLoops = 0
                        val buffer = codec.getOutputBuffer(outIndex)
                        if (buffer != null && info.size > 0) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            buffer.order(ByteOrder.nativeOrder())
                            if (floatPcm) {
                                val floats = buffer.asFloatBuffer()
                                while (floats.remaining() >= channels && outCount < maxSamples) {
                                    var sum = 0.0
                                    for (c in 0 until channels) sum += floats.get()
                                    accumulator += sum / channels * 32767.0
                                    accumulated++
                                    phase += targetRate
                                    if (phase >= sourceRate) {
                                        phase -= sourceRate
                                        out[outCount++] = clampShort(accumulator / accumulated)
                                        accumulator = 0.0
                                        accumulated = 0
                                    }
                                }
                            } else {
                                val shorts = buffer.asShortBuffer()
                                while (shorts.remaining() >= channels && outCount < maxSamples) {
                                    var sum = 0.0
                                    for (c in 0 until channels) sum += shorts.get()
                                    accumulator += sum / channels
                                    accumulated++
                                    phase += targetRate
                                    if (phase >= sourceRate) {
                                        phase -= sourceRate
                                        out[outCount++] = clampShort(accumulator / accumulated)
                                        accumulator = 0.0
                                        accumulated = 0
                                    }
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                    else -> idleLoops++
                }
            }
            if (outCount == 0) return null
            val bytes = ByteArray(outCount * 2)
            for (i in 0 until outCount) {
                val v = out[i].toInt()
                bytes[i * 2] = (v and 0xff).toByte()
                bytes[i * 2 + 1] = ((v shr 8) and 0xff).toByte()
            }
            return bytes
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            extractor.release()
        }
    }

    private fun clampShort(value: Double): Short =
        value.coerceIn(-32768.0, 32767.0).toInt().toShort()

    private fun MediaFormat.getIntegerOrDefault(key: String, fallback: Int): Int =
        if (containsKey(key)) getInteger(key) else fallback
}
