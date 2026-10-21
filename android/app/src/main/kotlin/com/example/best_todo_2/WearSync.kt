package com.mfficiency.best_todo_2

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Phone side of the Wear OS companion (wear/, see wear/README.md and
 * lib/services/wear_sync_service.dart).
 *
 *  - [publish] puts the JSON the Dart side built into a Data Layer item
 *    (`/todo/today`, `/todo/alarms`) for the watch.
 *  - Watch commands (`/todo/command/complete`, [WearCommandService]) are only
 *    queued here ([enqueue], own SharedPreferences file, never Flutter's) and
 *    applied by the Dart app, which drains them with [take]. When the app is
 *    running, [channel] is set and the Dart side is poked right away.
 *
 * Everything is wrapped: a phone without Play services keeps working.
 */
object WearSync {
    private const val TAG = "WearSync"
    private const val PREFS = "best_todo_wear"
    private const val KEY_COMMANDS = "commands"
    private const val MAX_COMMANDS = 100
    private val lock = Any()

    /** The running app's `besttodo/wear` channel, null when no engine runs. */
    @Volatile
    var channel: MethodChannel? = null

    fun publish(context: Context, path: String, json: String) {
        try {
            val request = PutDataMapRequest.create(path).apply {
                dataMap.putString("json", json)
                dataMap.putLong("at", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(context.applicationContext)
                .putDataItem(request)
                .addOnFailureListener { e -> Log.w(TAG, "publish $path failed: $e") }
        } catch (e: Throwable) {
            Log.w(TAG, "publish $path failed: $e")
        }
    }

    /** Appends one command; returns false if it could not be stored. */
    fun enqueue(context: Context, action: String, id: String): Boolean {
        return try {
            synchronized(lock) {
                val prefs = context.applicationContext
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val list = try {
                    JSONArray(prefs.getString(KEY_COMMANDS, "[]") ?: "[]")
                } catch (e: Exception) {
                    JSONArray()
                }
                val entry = JSONObject()
                entry.put("action", action)
                entry.put("id", id)
                entry.put("at", System.currentTimeMillis())
                list.put(entry.toString())
                val out = JSONArray()
                val from = if (list.length() > MAX_COMMANDS) list.length() - MAX_COMMANDS else 0
                for (i in from until list.length()) out.put(list.getString(i))
                prefs.edit().putString(KEY_COMMANDS, out.toString()).commit()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "enqueue failed: $e")
            false
        }
    }

    /** Hands over every queued command (JSON strings) and clears the queue. */
    fun take(context: Context): List<String> {
        return try {
            synchronized(lock) {
                val prefs = context.applicationContext
                    .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val raw = prefs.getString(KEY_COMMANDS, "[]") ?: "[]"
                prefs.edit().remove(KEY_COMMANDS).commit()
                val list = try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
                val out = ArrayList<String>()
                for (i in 0 until list.length()) out.add(list.optString(i, ""))
                out
            }
        } catch (e: Throwable) {
            Log.w(TAG, "take failed: $e")
            emptyList()
        }
    }

    /**
     * Tells the running app that commands wait. Returns false when no engine
     * is attached (the caller then uses the widget's background path).
     */
    fun pokeApp(): Boolean {
        val current = channel ?: return false
        Handler(Looper.getMainLooper()).post {
            try {
                current.invokeMethod("wearCommandsPending", null)
            } catch (e: Throwable) {
                Log.w(TAG, "poke failed: $e")
            }
        }
        return true
    }
}
