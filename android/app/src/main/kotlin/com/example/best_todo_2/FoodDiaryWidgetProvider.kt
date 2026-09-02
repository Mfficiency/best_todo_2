package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Locale

/**
 * Home-screen widget for the Food Diary. The "+" opens the same "create
 * entry" dialog as the in-app Food Diary page (`besttodofood://add`);
 * tapping anywhere else opens the Food Diary list (`besttodofood://open`).
 *
 * Turns red once today's running entry count falls behind the checkpoint
 * schedule: at least 1 entry logged by 8:00, 2 by 13:00, 3 by 16:30 and 4 by
 * 20:00. The Flutter side only pushes "how many entries logged today" plus
 * the date it describes (see `FoodDiaryWidgetService`); whether a checkpoint
 * has *passed* is decided here against the live clock, so the color is
 * right even when the widget redraws on its own periodic schedule
 * (`updatePeriodMillis`) with the app never opened.
 */
class FoodDiaryWidgetProvider : HomeWidgetProvider() {

    // Minute-of-day for each checkpoint (8:00, 13:00, 16:30, 20:00) paired
    // with the cumulative entry count required by then. Keep in sync with
    // FoodDiaryWidgetService.checkpointMinutes/requiredCounts.
    private val checkpointMinutes = intArrayOf(8 * 60, 13 * 60, 16 * 60 + 30, 20 * 60)
    private val requiredCounts = intArrayOf(1, 2, 3, 4)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val now = Calendar.getInstance()
        val today = String.format(
            Locale.US, "%04d-%02d-%02d",
            now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH)
        )
        val dataIsToday = widgetData.getString("food_data_date", "") == today
        val entryCount = if (dataIsToday) widgetData.getInt("food_entry_count", 0) else 0
        val nowMinutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

        // The count required as of now: the requirement of the latest
        // checkpoint that has already passed, or 0 before the first one.
        var required = 0
        for (i in checkpointMinutes.indices) {
            if (nowMinutes >= checkpointMinutes[i]) required = requiredCounts[i]
        }
        val behind = entryCount < required

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

            if (!behind) {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", 0xFF000000.toInt())
                views.setTextViewText(
                    R.id.food_widget_status,
                    if (entryCount == 0) "Nothing logged yet today"
                    else "$entryCount logged today"
                )
            } else {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", 0xFFB71C1C.toInt())
                views.setTextViewText(
                    R.id.food_widget_status,
                    "Only $entryCount logged today, need $required by now"
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
