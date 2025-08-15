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
            views.setTextViewText(R.id.appwidget_text, loadTodayTasks(context))
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

    private fun loadTodayTasks(context: Context): String {
        return try {
            val file = File(context.filesDir, "tasks.json")
            if (!file.exists()) {
                Log.d(TAG, "tasks.json not found at: \${file.absolutePath}")
                return context.getString(R.string.no_tasks_today)
            }
            val json = file.readText()
            val tasks = JSONArray(json)
            val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
            val today = sdf.format(Date())
            val lines = mutableListOf<String>()
            for (i in 0 until tasks.length()) {
                val obj = tasks.getJSONObject(i)
                val dueDate = obj.optString("dueDate", "")
                val isDone = obj.optBoolean("isDone", false)
                if (dueDate.isNotEmpty() && !isDone) {
                    val datePart = dueDate.substring(0, 10)
                    if (datePart == today) {
                        lines.add("• " + obj.optString("title", ""))
                    }
                }
            }
            if (lines.isEmpty()) {
                Log.d(TAG, "No tasks due today")
                context.getString(R.string.no_tasks_today)
            } else {
                lines.joinToString("\n")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading tasks", e)
            context.getString(R.string.no_tasks_today)
        }
    }
}