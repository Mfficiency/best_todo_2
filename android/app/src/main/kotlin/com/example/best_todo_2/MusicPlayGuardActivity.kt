package com.mfficiency.best_todo_2

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

// The Music widgets' play/pause button. A widget can't show the app's
// Flutter "Play out loud?" dialog, and its old media-button broadcast went
// straight to the player — so pressing play on the home screen started
// music on the phone speaker without asking. This see-through activity
// (no window of its own, not in Recents) decides first:
// - something is playing (pause), "Ask before playing out loud" is off, or
//   headphones / a Bluetooth speaker / a car are connected → it just sends
//   the play/pause press and closes, nothing visible;
// - otherwise → a small "Play out loud?" dialog over the home screen; Play
//   sends the press, Cancel (or tapping outside) does nothing.
// The setting and "playing" come from the widget data the app writes
// (MusicWidgetService: music_confirm_speaker, music_widget_playing).
class MusicPlayGuardActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
        val playing = prefs.getBoolean("music_widget_playing", false)
        val confirm = prefs.getBoolean("music_confirm_speaker", true)
        if (playing || !confirm || AudioOutputs.isExternalConnected(this)) {
            sendPlayPause()
            finish()
            return
        }
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle("Play out loud?")
            .setMessage(
                "No Bluetooth speaker or headphones are connected, so music " +
                    "will play from the phone's speaker."
            )
            .setPositiveButton("Play") { _, _ -> sendPlayPause() }
            .setNegativeButton("Cancel", null)
            .setOnDismissListener { finish() }
            .show()
    }

    private fun sendPlayPause() {
        sendBroadcast(MusicWidgetIntents.playPauseBroadcast(this))
    }
}
