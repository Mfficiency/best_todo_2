package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
