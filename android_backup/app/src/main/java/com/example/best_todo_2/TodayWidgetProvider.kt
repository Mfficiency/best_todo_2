package com.example.best_todo_2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class TodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            val intent = Intent(context, TodayWidgetService::class.java)
            val views = RemoteViews(context.packageName, R.layout.today_widget)
            views.setRemoteAdapter(R.id.widget_list, intent)

            val openAppIntent = Intent(context, MainActivity::class.java)
            val pendingOpen = PendingIntent.getActivity(context, 0, openAppIntent, PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_open, pendingOpen)

            val addIntent = Intent(context, MainActivity::class.java).apply {
                action = "ACTION_ADD_TASK"
            }
            val pendingAdd = PendingIntent.getActivity(context, 1, addIntent, PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_add, pendingAdd)

            appWidgetManager.updateAppWidget(widgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.widget_list)
        }
    }
}
