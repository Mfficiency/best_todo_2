package com.example.best_todo_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
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

    private fun loadDueTasks(context: Context): String {
        return try {
            // tasks.json is stored in the same location as used by Flutter's
            // StorageService.loadTaskList(). Using Context.getDir ensures the
            // path exists on any device or installation type.
            val dir = context.getDir("app_flutter", Context.MODE_PRIVATE)
            val file = File(dir, "tasks.json")
            if (!file.exists()) {
                Log.d(TAG, "tasks.json not found at: \${file.absolutePath}")
                return context.getString(R.string.no_tasks_today)
            }
            val json = file.readText()
            val tasks = JSONArray(json)
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val today = sdf.parse(sdf.format(Date()))
            val lines = mutableListOf<String>()
            for (i in 0 until tasks.length()) {
                val obj = tasks.getJSONObject(i)
                val dueDate = obj.optString("dueDate", "")
                val isDone = obj.optBoolean("isDone", false)
                if (dueDate.isNotEmpty() && !isDone) {
                    val datePart = dueDate.substring(0, 10)
                    val due = sdf.parse(datePart)
                    if (today != null && due != null && !due.after(today)) {
                        lines.add("• " + obj.optString("title", ""))
                    }
                }
            }
            if (lines.isEmpty()) {
                Log.d(TAG, "No due tasks")
                context.getString(R.string.no_tasks_today)
            } else {
                val titlesForLog = lines.map { it.removePrefix("• ") }
                Log.d(TAG, "tasks loaded to display on widget: ${titlesForLog.joinToString(", ")}")
                lines.joinToString("\n")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading tasks", e)
            context.getString(R.string.no_tasks_today)
        }
    }
}