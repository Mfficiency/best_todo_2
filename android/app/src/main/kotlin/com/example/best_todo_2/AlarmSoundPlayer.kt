package com.mfficiency.best_todo_2

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * Plays the app's built-in alarm melodies at a caller-chosen loudness that is
 * independent of the phone's current media / ringer / alarm volume.
 *
 * How the independence works: the melody is synthesized at full scale, played
 * on the ALARM stream, and while it plays the alarm stream is raised to its
 * maximum (the previous level is restored on [stop]). The requested volume
 * (0.0–1.0) is then applied as the track gain, so "60%" always means 60% of
 * the device's maximum alarm loudness no matter what the user last set their
 * volume rockers to.
 *
 * Do Not Disturb: audio played with USAGE_ALARM is allowed through DND's
 * priority modes by the system. When [overrideDnd] is false the caller asks us
 * to respect DND, so nothing is played while any DND filter is active. When
 * true we always play (adjusting the stream inside "total silence" can throw a
 * SecurityException without notification-policy access — that is caught and
 * playback proceeds at the current stream level as a best effort).
 */
object AlarmSoundPlayer {

    private const val SAMPLE_RATE = 44100

    private var track: AudioTrack? = null
    private var restoreStreamVolume: Int = -1

    /** One note of a melody: frequency in Hz (0 = rest) and duration in ms. */
    private data class Note(val freq: Double, val ms: Int)

    /**
     * The built-in melodies, keyed by the names stored in the Dart `Alarm`
     * model (`kAlarmMelodies`). Keep the keys stable once shipped.
     */
    private fun notesFor(melody: String): List<Note> = when (melody) {
        "Chimes" -> listOf(
            Note(1318.5, 250), Note(0.0, 60), Note(1046.5, 250), Note(0.0, 60),
            Note(880.0, 250), Note(0.0, 60), Note(659.3, 400), Note(0.0, 700),
        )
        "Radar" -> listOf(
            Note(1200.0, 90), Note(0.0, 90), Note(1200.0, 90), Note(0.0, 90),
            Note(1200.0, 90), Note(0.0, 90), Note(1200.0, 90), Note(0.0, 600),
        )
        "Beacon" -> listOf(
            Note(880.0, 700), Note(0.0, 900),
        )
        "Bells" -> listOf(
            Note(784.0, 350), Note(0.0, 80), Note(784.0, 350), Note(0.0, 80),
            Note(988.0, 500), Note(0.0, 600),
        )
        "Digital" -> listOf(
            Note(2093.0, 70), Note(0.0, 50), Note(2093.0, 70), Note(0.0, 50),
            Note(2093.0, 70), Note(0.0, 50), Note(2093.0, 70), Note(0.0, 400),
        )
        "Marimba" -> listOf(
            Note(523.3, 180), Note(659.3, 180), Note(784.0, 180),
            Note(1046.5, 300), Note(784.0, 180), Note(659.3, 180),
            Note(523.3, 300), Note(0.0, 500),
        )
        // "Classic" and anything unknown.
        else -> listOf(
            Note(987.8, 180), Note(0.0, 90), Note(987.8, 180), Note(0.0, 90),
            Note(987.8, 180), Note(0.0, 90), Note(987.8, 300), Note(0.0, 500),
        )
    }

    /** Renders the melody's note list to one full-scale 16-bit PCM loop. */
    private fun synthesize(melody: String): ShortArray {
        val notes = notesFor(melody)
        val totalSamples = notes.sumOf { it.ms * SAMPLE_RATE / 1000 }
        val pcm = ShortArray(totalSamples)
        var i = 0
        for (note in notes) {
            val samples = note.ms * SAMPLE_RATE / 1000
            if (note.freq <= 0.0) {
                i += samples // rest: leave zeros
                continue
            }
            // Short attack/release ramps avoid clicks at note boundaries.
            val ramp = min(samples / 4, SAMPLE_RATE / 100)
            for (s in 0 until samples) {
                val envelope = when {
                    s < ramp -> s.toDouble() / ramp
                    s > samples - ramp -> (samples - s).toDouble() / ramp
                    else -> 1.0
                }
                val value =
                    sin(2.0 * PI * note.freq * s / SAMPLE_RATE) * envelope
                pcm[i + s] = (value * Short.MAX_VALUE * 0.9).toInt().toShort()
            }
            i += samples
        }
        return pcm
    }

    private fun isDndActive(context: Context): Boolean {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        val filter = nm.currentInterruptionFilter
        return filter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            filter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
    }

    /**
     * Starts playing [melody] at [volume] (0.0–1.0 of the device maximum).
     * Returns true when playback actually started; false when it was skipped
     * (DND active and [overrideDnd] false) or failed.
     */
    @Synchronized
    fun start(
        context: Context,
        melody: String,
        volume: Double,
        overrideDnd: Boolean,
        loop: Boolean,
    ): Boolean {
        stop(context)
        if (!overrideDnd && isDndActive(context)) return false

        val pcm = synthesize(melody)
        if (pcm.isEmpty()) return false

        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            // Pin the alarm stream to max for the duration of playback so the
            // track gain below is the only thing deciding the loudness.
            val current = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (current != max) {
                restoreStreamVolume = current
                audioManager.setStreamVolume(AudioManager.STREAM_ALARM, max, 0)
            }
        } catch (_: SecurityException) {
            // DND "total silence" without notification-policy access: keep the
            // stream as-is and still try to play.
        } catch (_: Exception) {
        }

        return try {
            val newTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
            newTrack.write(pcm, 0, pcm.size)
            if (loop) {
                newTrack.setLoopPoints(0, pcm.size, -1)
            }
            newTrack.setVolume(volume.coerceIn(0.0, 1.0).toFloat())
            newTrack.play()
            track = newTrack
            true
        } catch (_: Exception) {
            restoreStreamLevel(context)
            false
        }
    }

    /** Stops playback and restores the alarm stream to its previous level. */
    @Synchronized
    fun stop(context: Context) {
        try {
            track?.stop()
        } catch (_: Exception) {
        }
        try {
            track?.release()
        } catch (_: Exception) {
        }
        track = null
        restoreStreamLevel(context)
    }

    private fun restoreStreamLevel(context: Context) {
        if (restoreStreamVolume < 0) return
        try {
            val audioManager =
                context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.setStreamVolume(
                AudioManager.STREAM_ALARM, restoreStreamVolume, 0
            )
        } catch (_: Exception) {
        }
        restoreStreamVolume = -1
    }
}
