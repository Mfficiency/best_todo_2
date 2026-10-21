package com.mfficiency.best_todo_2

import android.net.Uri
import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

/**
 * Receives the Wear OS companion's commands (`/todo/command/complete`, the
 * task's uid as UTF-8). It never touches tasks.json: the command is queued
 * ([WearSync.enqueue]) for the Dart app, which completes the task through its
 * own logic. If the app is running it is poked to do that now; if not, the
 * home-screen widget's existing background path is fired
 * (`besttodotask://complete?id=`, the same Dart callback as the widget's
 * checkbox, but complete-only), and the queued copy is a no-op later.
 */
class WearCommandService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        try {
            if (event.path != PATH_COMPLETE) return
            val id = String(event.data, Charsets.UTF_8).trim()
            if (id.isEmpty() || id.length > 200) return
            if (!WearSync.enqueue(this, "complete", id)) return
            if (!WearSync.pokeApp()) {
                HomeWidgetBackgroundIntent.getBroadcast(
                    this,
                    Uri.parse("besttodotask://complete?id=" + Uri.encode(id))
                ).send()
            }
        } catch (e: Throwable) {
            Log.w("WearCommandService", "command failed: $e")
        }
    }

    companion object {
        const val PATH_COMPLETE = "/todo/command/complete"
    }
}
