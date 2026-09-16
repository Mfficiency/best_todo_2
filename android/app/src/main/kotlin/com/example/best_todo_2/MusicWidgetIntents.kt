package com.mfficiency.best_todo_2

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent

/**
 * Builds the media-button broadcasts the two Music Player widgets send.
 * Rather than routing through the app's Dart code (which, unlike the
 * on-disk task/alarm lists, can't be reached from the widget's separate
 * background isolate while the app isn't running), these simulate a
 * hardware media button — exactly what a Bluetooth headset or wired
 * remote sends — targeted straight at `audio_service`'s own
 * `MediaButtonReceiver`, which is already listening whenever the Music
 * Player's background playback service is alive.
 */
object MusicWidgetIntents {

    private const val RECEIVER_CLASS = "com.ryanheise.audioservice.MediaButtonReceiver"

    private fun mediaButtonPendingIntent(context: Context, keyCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(context.packageName, RECEIVER_CLASS)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            keyCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun playPause(context: Context): PendingIntent =
        mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)

    fun previous(context: Context): PendingIntent =
        mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)

    fun next(context: Context): PendingIntent =
        mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT)
}
