package com.example.best_todo_2

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import com.example.best_todo_2.BuildConfig

class VersionWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.version_widget)
            views.setTextViewText(R.id.appwidget_text, BuildConfig.VERSION_NAME)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
