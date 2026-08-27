package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Companion to [FoodDiaryWidgetProvider]: a fixed 1x1 widget that is nothing
 * but a "+" button. Tapping it opens the same in-app "create entry" dialog
 * (`besttodofood://add` → `FoodDiaryPage(autoAddEntry: true)`) — there is no
 * status to show at this size, so unlike the full widget it never redraws
 * on its own and carries no other tap target.
 */
class FoodDiaryButtonWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val addIntent = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, android.net.Uri.parse("besttodofood://add")
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.food_diary_button_widget_layout)
            views.setOnClickPendingIntent(R.id.food_button_widget_container, addIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
