package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar
import java.util.Locale

/**
 * Companion to [FoodDiaryWidgetProvider]: a fixed 1x1 widget that is nothing
 * but a "+" button. Tapping it opens the same in-app "create entry" dialog
 * (`besttodofood://add` → `FoodDiaryPage(autoAddEntry: true)`) — there is no
 * status text to show at this size. Its background still turns red once
 * today's running entry count falls behind the checkpoint schedule, matching
 * the full widget.
 */
class FoodDiaryButtonWidgetProvider : HomeWidgetProvider() {

    // Keep in sync with FoodDiaryWidgetProvider.checkpointMinutes/requiredCounts
    // and FoodDiaryWidgetService.checkpointMinutes/requiredCounts.
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

        var required = 0
        for (i in checkpointMinutes.indices) {
            if (nowMinutes >= checkpointMinutes[i]) required = requiredCounts[i]
        }
        val behind = entryCount < required

        val addIntent = HomeWidgetLaunchIntent.getActivity(
            context, MainActivity::class.java, android.net.Uri.parse("besttodofood://add")
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.food_diary_button_widget_layout)
            views.setInt(
                R.id.food_button_widget_container,
                "setBackgroundColor",
                if (behind) 0xFFB71C1C.toInt() else 0xFF000000.toInt()
            )
            views.setOnClickPendingIntent(R.id.food_button_widget_container, addIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
