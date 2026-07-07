package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget that lists the user's alarms. Each row can be toggled
 * on/off (handled in the background without opening the app) or tapped to open
 * the alarm editor. The header opens the alarms list / new alarm screen.
 */
class AlarmsWidgetProvider : HomeWidgetProvider() {

    private val maxRows = 4

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val rowContainers = intArrayOf(
            R.id.alarm_row_0, R.id.alarm_row_1, R.id.alarm_row_2, R.id.alarm_row_3
        )
        val timeViews = intArrayOf(
            R.id.alarm_time_0, R.id.alarm_time_1, R.id.alarm_time_2, R.id.alarm_time_3
        )
        val nameViews = intArrayOf(
            R.id.alarm_name_0, R.id.alarm_name_1, R.id.alarm_name_2, R.id.alarm_name_3
        )
        val subViews = intArrayOf(
            R.id.alarm_sub_0, R.id.alarm_sub_1, R.id.alarm_sub_2, R.id.alarm_sub_3
        )
        val toggleViews = intArrayOf(
            R.id.alarm_toggle_0, R.id.alarm_toggle_1, R.id.alarm_toggle_2, R.id.alarm_toggle_3
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.alarms_widget_layout)

            val count = widgetData.getInt("alarm_count", 0)

            // Header + add button open the alarms list / new alarm screen.
            val openIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("besttodoalarm://open")
            )
            views.setOnClickPendingIntent(R.id.alarms_widget_header, openIntent)
            views.setOnClickPendingIntent(R.id.alarms_widget_add, openIntent)

            views.setViewVisibility(
                R.id.alarms_widget_empty,
                if (count == 0) View.VISIBLE else View.GONE
            )

            for (i in 0 until maxRows) {
                val id = widgetData.getString("alarm_${i}_id", "") ?: ""
                if (i < count && id.isNotEmpty()) {
                    views.setViewVisibility(rowContainers[i], View.VISIBLE)

                    val time = widgetData.getString("alarm_${i}_time", "") ?: ""
                    val name = widgetData.getString("alarm_${i}_name", "Alarm") ?: "Alarm"
                    val sub = widgetData.getString("alarm_${i}_sub", "") ?: ""
                    val on = widgetData.getBoolean("alarm_${i}_on", true)

                    views.setTextViewText(timeViews[i], time)
                    views.setTextViewText(nameViews[i], name)
                    views.setTextViewText(subViews[i], sub)
                    views.setTextViewText(toggleViews[i], if (on) "ON" else "OFF")
                    views.setTextColor(
                        toggleViews[i],
                        if (on) 0xFF4CAF50.toInt() else 0xFF777777.toInt()
                    )
                    val timeColor = if (on) 0xFFFFFFFF.toInt() else 0xFF777777.toInt()
                    views.setTextColor(timeViews[i], timeColor)

                    // Tapping the toggle flips the alarm on/off in the background.
                    val toggleIntent = HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("besttodoalarm://toggle?id=$id")
                    )
                    views.setOnClickPendingIntent(toggleViews[i], toggleIntent)

                    // Tapping the row opens the editor for this alarm.
                    val editIntent = HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("besttodoalarm://edit?id=$id")
                    )
                    views.setOnClickPendingIntent(timeViews[i], editIntent)
                    views.setOnClickPendingIntent(nameViews[i], editIntent)
                    views.setOnClickPendingIntent(subViews[i], editIntent)
                } else {
                    views.setViewVisibility(rowContainers[i], View.GONE)
                }
            }

            if (count > maxRows) {
                views.setViewVisibility(R.id.alarms_widget_more, View.VISIBLE)
                views.setTextViewText(
                    R.id.alarms_widget_more,
                    "+${count - maxRows} more"
                )
            } else {
                views.setViewVisibility(R.id.alarms_widget_more, View.GONE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
