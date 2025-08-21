package com.example.best_todo_2

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
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
                setTextViewText(R.id.widget_text, text)
                val bgColor = ContextCompat.getColor(context, R.color.widget_background)
                val textColor = ContextCompat.getColor(context, R.color.widget_text_color)
                setInt(R.id.widget_container, "setBackgroundColor", bgColor)
                setTextColor(R.id.widget_text, textColor)
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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_CONFIGURATION_CHANGED) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, SimpleWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            val prefs = context.getSharedPreferences(
                HomeWidgetPlugin.SHARED_PREFERENCES_NAME,
                Context.MODE_PRIVATE
            )
            onUpdate(context, manager, ids, prefs)
        }
    }
}
