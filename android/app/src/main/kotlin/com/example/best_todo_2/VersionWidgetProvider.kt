package com.example.best_todo_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class VersionWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.version_widget)

            val tasksFile = File(context.filesDir, "tasks.json")
            val displayText = if (tasksFile.exists()) {
                try {
                    val json = JSONArray(tasksFile.readText())
                    val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
                    val today = sdf.format(Date())
                    val titles = mutableListOf<String>()
                    for (i in 0 until json.length()) {
                        val obj = json.getJSONObject(i)
                        val dueDate = obj.optString("dueDate", "").take(10)
                        val isDone = obj.optBoolean("isDone", false)
                        if (!isDone && dueDate == today) {
                            titles.add(obj.optString("title", ""))
                        }
                    }
                    if (titles.isNotEmpty()) titles.joinToString("\n") else "No tasks for today"
                } catch (e: Exception) {
                    "No tasks for today"
                }
            } else {
                "No tasks for today"
            }

            views.setTextViewText(R.id.appwidget_text, displayText)

            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
