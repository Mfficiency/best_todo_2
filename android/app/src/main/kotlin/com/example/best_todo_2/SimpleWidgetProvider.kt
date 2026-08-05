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
 * Home-screen widget with today's tasks. It has two looks, picked by the
 * "Check off tasks on the widget" setting (`widget_checkable`, off by default):
 * the read-only text summary it always had, or one row per task whose checkbox
 * completes it in the background (`besttodotask://toggle?id=…`, handled in
 * `main.dart`). Tapping anywhere else — the progress line, a task row, the
 * summary text — opens the app on the task list (`besttodotask://open`), even
 * when the app was left on some other page.
 */
class SimpleWidgetProvider : HomeWidgetProvider() {

    private val maxRows = 5

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val rowContainers = intArrayOf(
            R.id.widget_row_0, R.id.widget_row_1, R.id.widget_row_2,
            R.id.widget_row_3, R.id.widget_row_4
        )
        val checkViews = intArrayOf(
            R.id.widget_check_0, R.id.widget_check_1, R.id.widget_check_2,
            R.id.widget_check_3, R.id.widget_check_4
        )
        val titleViews = intArrayOf(
            R.id.widget_task_0, R.id.widget_task_1, R.id.widget_task_2,
            R.id.widget_task_3, R.id.widget_task_4
        )

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.simple_widget_layout).apply {
                val text = widgetData.getString("text_from_flutter_app", "")
                val displayText = if (text.isNullOrBlank()) "No tasks for today" else text
                setTextViewText(R.id.widget_text, displayText)

                val showProgress = widgetData.getBoolean("widget_progress_visible", true)
                val progressPercent = widgetData.getInt("widget_progress_percent", 0).coerceIn(0, 100)
                val progressColor = widgetData.getString("widget_progress_color", "green")

                val progressVisibility = if (showProgress) View.VISIBLE else View.GONE
                setViewVisibility(R.id.widget_progress_green, progressVisibility)
                setViewVisibility(R.id.widget_progress_orange, View.GONE)
                setViewVisibility(R.id.widget_progress_red, View.GONE)

                if (showProgress) {
                    val activeId = when (progressColor) {
                        "red" -> R.id.widget_progress_red
                        "orange" -> R.id.widget_progress_orange
                        else -> R.id.widget_progress_green
                    }
                    setViewVisibility(R.id.widget_progress_green, View.GONE)
                    setViewVisibility(activeId, View.VISIBLE)
                    setProgressBar(activeId, 100, progressPercent, false)
                }
            }

            val checkable = widgetData.getBoolean("widget_checkable", false)
            views.setViewVisibility(R.id.widget_text, if (checkable) View.GONE else View.VISIBLE)
            views.setViewVisibility(R.id.widget_rows, if (checkable) View.VISIBLE else View.GONE)

            // Every tap that is not a checkbox opens the app on the task list.
            // The URI is what makes that "on the task list" rather than "on
            // whatever page the app was last left on" — `main.dart` pops back
            // to the home page when it sees it.
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("besttodotask://open")
            )
            views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_text, pendingIntent)
            // The progress line sits above the text and is not part of it, so
            // it needs its own handler on each of the three coloured bars.
            views.setOnClickPendingIntent(R.id.widget_progress_green, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_progress_orange, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_progress_red, pendingIntent)

            if (checkable) {
                val count = widgetData.getInt("widget_task_count", 0)
                val overflow = widgetData.getInt("widget_task_overflow", 0)

                for (i in 0 until maxRows) {
                    val id = widgetData.getString("widget_task_${i}_id", "") ?: ""
                    if (i < count && id.isNotEmpty()) {
                        val title = widgetData.getString("widget_task_${i}_title", "") ?: ""
                        val done = widgetData.getBoolean("widget_task_${i}_done", false)

                        views.setViewVisibility(rowContainers[i], View.VISIBLE)
                        views.setTextViewText(titleViews[i], title)
                        views.setTextColor(
                            titleViews[i],
                            if (done) 0xFF777777.toInt() else 0xFFFFFFFF.toInt()
                        )
                        views.setImageViewResource(
                            checkViews[i],
                            if (done) R.drawable.widget_check_box_checked
                            else R.drawable.widget_check_box
                        )

                        // The checkbox completes / un-completes the task without
                        // opening the app; the rest of the row (title and the
                        // space around it) opens the app on the task list.
                        val toggleIntent = HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("besttodotask://toggle?id=$id")
                        )
                        views.setOnClickPendingIntent(checkViews[i], toggleIntent)
                        views.setOnClickPendingIntent(titleViews[i], pendingIntent)
                        views.setOnClickPendingIntent(rowContainers[i], pendingIntent)
                    } else {
                        views.setViewVisibility(rowContainers[i], View.GONE)
                    }
                }

                views.setViewVisibility(
                    R.id.widget_rows_empty,
                    if (count == 0) View.VISIBLE else View.GONE
                )
                views.setOnClickPendingIntent(R.id.widget_rows_empty, pendingIntent)

                if (overflow > 0) {
                    views.setViewVisibility(R.id.widget_rows_more, View.VISIBLE)
                    views.setTextViewText(R.id.widget_rows_more, "+$overflow more")
                    views.setOnClickPendingIntent(R.id.widget_rows_more, pendingIntent)
                } else {
                    views.setViewVisibility(R.id.widget_rows_more, View.GONE)
                }
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
