package com.example.best_todo_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import androidx.annotation.VisibleForTesting
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray

class VersionWidgetProvider : AppWidgetProvider() {
    companion object {
        private const val TAG = "VersionWidget"
    }
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        logToFile(context, "onUpdate for ${appWidgetIds.size} widget(s)")
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.version_widget)
            views.setTextViewText(R.id.appwidget_text, loadDueTasks(context))
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.appwidget_text, pendingIntent)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    @VisibleForTesting
    internal fun loadDueTasks(context: Context): String {
        return try {
            // tasks.json is stored in the same location as used by Flutter's
            // StorageService.loadTaskList(). Using Context.getDir ensures the
            // path exists on any device or installation type. Some devices
            // store the file in a different location, so check a few common
            // directories before giving up.
            val lines = mutableListOf<String>()
            val file = findTasksFile(context)
            if (file != null) {
                val json = file.readText()
                val tasks = JSONArray(json)
                val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                val today = sdf.parse(sdf.format(Date()))

                for (i in 0 until tasks.length()) {
                    val obj = tasks.getJSONObject(i)
                    val dueDate = obj.optString("dueDate", "")
                    val isDone = obj.optBoolean("isDone", false)
                    val msg = "Processing task: ${obj.optString("title", "")}, dueDate: $dueDate, isDone: $isDone"
                    Log.d(TAG, msg)
                    logToFile(context, msg)
                    if (dueDate.isNotEmpty() && !isDone) {
                        val datePart = dueDate.substring(0, 10)
                        val due = sdf.parse(datePart)
                        if (today != null && due != null && !due.after(today)) {
                            lines.add("• " + obj.optString("title", ""))
                        }
                    }
                }
            } else {
                val msg = "tasks.json not found; using placeholder item"
                Log.d(TAG, msg)
                logToFile(context, msg)
            }
            lines.add("• cow")
            val titlesForLog = lines.map { it.removePrefix("• ") }
            val msg = "tasks loaded to display on widget: ${titlesForLog.joinToString(", ")}"
            Log.d(TAG, msg)
            logToFile(context, msg)
            lines.joinToString("\n")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading tasks", e)
            logToFile(context, "Error loading tasks: ${e.message}")
            "• cow"
        }
    }

    @VisibleForTesting
    internal fun findTasksFile(context: Context): File? {
        val candidates = listOf(
            File(context.getDir("app_flutter", Context.MODE_PRIVATE), "tasks.json"),
            File(context.filesDir, "tasks.json"),
            File(context.noBackupFilesDir, "tasks.json"),
            context.getExternalFilesDir(null)?.let { File(it, "tasks.json") }
        ).filterNotNull()

        for (candidate in candidates) {
            if (candidate.exists()) {
                val msg = "Found tasks.json at: ${candidate.absolutePath}"
                Log.d(TAG, msg)
                logToFile(context, msg)
                return candidate
            } else {
                val msg = "tasks.json not found at: ${candidate.absolutePath}"
                Log.d(TAG, msg)
                logToFile(context, msg)
            }
        }
        return null
    }

    private fun logToFile(context: Context, message: String) {
        try {
            val dir = context.getDir("app_flutter", Context.MODE_PRIVATE)
            val logFile = File(dir, "app_logs.txt")
            val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.getDefault()).format(Date())
            logFile.appendText("$timestamp [VersionWidgetProvider] $message\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to log to file", e)
        }
    }
}
