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
 * Turns red once a meal checkpoint (8:00, 13:00, 20:00 — after
 * breakfast/lunch/dinner) has passed today with nothing logged in that
 * window. The Flutter side only pushes "was anything logged in this window
 * today" booleans plus the date they describe (see `FoodDiaryWidgetService`);
 * whether a checkpoint has *passed* is decided here against the live clock,
 * so the color is right even when the widget redraws on its own periodic
 * schedule (`updatePeriodMillis`) with the app never opened.
 */
class FoodDiaryWidgetProvider : HomeWidgetProvider() {

    private val checkpointHours = intArrayOf(8, 13, 20)
    private val checkpointLabels = arrayOf("8:00", "13:00", "20:00")

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
        val currentHour = now.get(Calendar.HOUR_OF_DAY)

        var loggedCount = 0
        val missed = mutableListOf<String>()
        for (i in checkpointHours.indices) {
            val hasEntry = dataIsToday && widgetData.getBoolean("food_has_$i", false)
            if (hasEntry) loggedCount++
            val started = currentHour >= checkpointHours[i]
            if (started && !hasEntry) missed.add(checkpointLabels[i])
        }

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

            if (missed.isEmpty()) {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", 0xFF000000.toInt())
                views.setTextViewText(
                    R.id.food_widget_status,
                    if (loggedCount == 0) "Nothing logged yet today"
                    else "$loggedCount/3 meals logged today"
                )
            } else {
                views.setInt(R.id.food_widget_container, "setBackgroundColor", 0xFFB71C1C.toInt())
                views.setTextViewText(
                    R.id.food_widget_status,
                    "Missing: " + missed.joinToString(", ")
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
