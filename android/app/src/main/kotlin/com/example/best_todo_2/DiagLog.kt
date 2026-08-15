package com.mfficiency.best_todo_2

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Append-only breadcrumb file written by the Android side of the app.
 *
 * It exists for the "widget tap shows a black screen while the app is in the
 * background" bug. In that state the Flutter UI never repaints, so nothing the
 * Dart side would normally log can be trusted to have run — and the only way
 * out is a force-close, which used to take every in-memory log with it. These
 * lines are written straight from the activity's lifecycle callbacks to
 * `native_log.txt` in the app's private files dir, so after the force-close
 * the next launch can read them back (`besttodo/diag` method channel) and show
 * them in App Logs → Device.
 *
 * The Dart side mirrors its own key breadcrumbs in here through the same
 * channel, so one file holds both halves of the timeline in order.
 */
object DiagLog {
    private const val FILE_NAME = "native_log.txt"
    private const val MAX_BYTES = 128 * 1024L
    private const val KEEP_BYTES = 80 * 1024L

    private val lock = Any()

    fun write(context: Context, tag: String, message: String) {
        Log.i("BestToDoDiag", "$tag | $message")
        synchronized(lock) {
            try {
                val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
                    .format(Date())
                val file = File(context.filesDir, FILE_NAME)
                if (file.exists() && file.length() > MAX_BYTES) trim(file)
                file.appendText("$stamp [$tag] $message\n")
            } catch (t: Throwable) {
                // Diagnostics must never take the app down with them.
            }
        }
    }

    fun read(context: Context): String {
        synchronized(lock) {
            return try {
                val file = File(context.filesDir, FILE_NAME)
                if (file.exists()) file.readText() else ""
            } catch (t: Throwable) {
                "Could not read the device log: ${t.message}"
            }
        }
    }

    fun clear(context: Context) {
        synchronized(lock) {
            try {
                File(context.filesDir, FILE_NAME).delete()
            } catch (t: Throwable) {
            }
        }
    }

    private fun trim(file: File) {
        try {
            val content = file.readText()
            var cut = (content.length - KEEP_BYTES).toInt()
            if (cut <= 0) return
            val nl = content.indexOf('\n', cut)
            if (nl != -1) cut = nl + 1
            file.writeText("(older entries trimmed)\n" + content.substring(cut))
        } catch (t: Throwable) {
        }
    }
}
