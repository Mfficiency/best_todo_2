package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget for the Food Diary. The "+" opens the same "create
 * entry" dialog as the in-app Food Diary page (`besttodofood://add`);
 * tapping anywhere else opens the Food Diary list (`besttodofood://open`).
 *
 * Pulses red once today's running entry count falls behind the checkpoint
 * schedule: at least 1 entry logged by 8:00, 2 by 13:00, 3 by 16:30 and 4 by
 * 20:00 (see [FoodDiaryAlert]). The Flutter side only pushes "how many
 * entries logged today" plus the date it describes (see
 * `FoodDiaryWidgetService`); whether a checkpoint has *passed* is decided
 * here against the live clock, so the color is right even when the widget
 * redraws on its own periodic schedule (`updatePeriodMillis`) with the app
 * never opened.
 */
class FoodDiaryWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        if (appWidgetIds.isEmpty()) return
        val status = FoodDiaryAlert.status(widgetData)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.food_diary_widget_layout)

            val addIntent = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("besttodofood://add")
            )
            val openIntent = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("besttodofood://open")
            )
            views.setOnClickPendingIntent(R.id.food_widget_add, addIntent)
            views.setOnClickPendingIntent(R.id.food_widget_container, openIntent)
            views.setOnClickPendingIntent(R.id.food_widget_header, openIntent)
            views.setOnClickPendingIntent(R.id.food_widget_status, openIntent)

            if (!status.behind) {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", FoodDiaryAlert.colorNormal)
                views.setTextViewText(
                    R.id.food_widget_status,
                    if (status.entryCount == 0) "Nothing logged yet today"
                    else "${status.entryCount} logged today"
                )
            } else {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", FoodDiaryAlert.pulseColor())
                views.setTextViewText(
                    R.id.food_widget_status,
                    "Only ${status.entryCount} logged today, need ${status.required} by now"
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        if (status.behind) {
            FoodDiaryAlert.schedulePulse(context, FoodDiaryWidgetProvider::class.java)
        } else {
            FoodDiaryAlert.cancelPulse(context, FoodDiaryWidgetProvider::class.java)
        }
    }
}
