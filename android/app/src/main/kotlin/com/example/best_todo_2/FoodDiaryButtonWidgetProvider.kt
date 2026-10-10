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
 * status text to show at this size. Its background still pulses red once
 * today's running entry count falls behind the checkpoint schedule (see
 * [FoodDiaryAlert]), matching the full widget.
 */
class FoodDiaryButtonWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        if (appWidgetIds.isEmpty()) return
        val behind = FoodDiaryAlert.status(widgetData).behind
        val color = if (behind) FoodDiaryAlert.pulseColor() else FoodDiaryAlert.colorNormal

        val addIntent = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, android.net.Uri.parse("besttodofood://add")
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.food_diary_button_widget_layout)
            views.setInt(R.id.food_button_widget_container, "setBackgroundColor", color)
            views.setOnClickPendingIntent(R.id.food_button_widget_container, addIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        if (behind) {
            FoodDiaryAlert.schedulePulse(context, FoodDiaryButtonWidgetProvider::class.java)
        } else {
            FoodDiaryAlert.cancelPulse(context, FoodDiaryButtonWidgetProvider::class.java)
        }
    }
}
