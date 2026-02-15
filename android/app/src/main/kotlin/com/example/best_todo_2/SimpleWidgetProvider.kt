package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SimpleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.simple_widget_layout).apply {
                val text = widgetData.getString("text_from_flutter_app", "")
                val displayText = if (text.isNullOrBlank()) "No tasks for today" else text
                setTextViewText(R.id.widget_text, displayText)

                val showProgress = widgetData.getBoolean("widget_progress_visible", true)
                val progressPercent = widgetData.getInt("widget_progress_percent", 0).coerceIn(0, 100)
                val progressColor = widgetData.getString("widget_progress_color", "green")

                val progressVisibility = if (showProgress) View.VISIBLE else View.GONE
                setViewVisibility(R.id.widget_progress_green, progressVisibility)
                setViewVisibility(R.id.widget_progress_orange, View.GONE)
                setViewVisibility(R.id.widget_progress_red, View.GONE)

                if (showProgress) {
                    val activeId = when (progressColor) {
                        "red" -> R.id.widget_progress_red
                        "orange" -> R.id.widget_progress_orange
                        else -> R.id.widget_progress_green
                    }
                    setViewVisibility(R.id.widget_progress_green, View.GONE)
                    setViewVisibility(activeId, View.VISIBLE)
                    setProgressBar(activeId, 100, progressPercent, false)
                }
            }
			val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_text, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
