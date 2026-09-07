package com.mfficiency.best_todo_2

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import java.util.Calendar
import java.util.Locale

/**
 * Shared "behind schedule" alert logic for the two Food Diary home-screen
 * widgets (the full status widget and its 1x1 "+" companion): both turn red
 * once today's logged entry count falls behind the checkpoint schedule (see
 * [status]). AppWidgets have no animation API, so the pulse is faked by
 * re-broadcasting APPWIDGET_UPDATE to the provider itself every
 * [pulseIntervalMs] and alternating the paint color by elapsed-time parity
 * (see [pulseColor]) — a non-wakeup alarm, so it only actually ticks while
 * the device is already awake (i.e. while someone could be looking at the
 * home screen) and costs nothing while the phone sleeps. The loop stops
 * itself the moment [status]'s `behind` next reads false, and stops for good
 * once the widget is removed (an empty id list breaks the reschedule chain).
 */
object FoodDiaryAlert {
    // Keep in sync with FoodDiaryWidgetService.checkpointMinutes/requiredCounts.
    private val checkpointMinutes = intArrayOf(8 * 60, 13 * 60, 16 * 60 + 30, 20 * 60)
    private val requiredCounts = intArrayOf(1, 2, 3, 4)

    const val pulseIntervalMs = 900L
    const val colorNormal = 0xFF000000.toInt()
    const val colorBright = 0xFFE53935.toInt()
    const val colorDim = 0xFF4A0000.toInt()

    /** Today's logged count against the checkpoint due by now, and whether it's behind. */
    data class Status(val entryCount: Int, val required: Int, val behind: Boolean)

    /** Reads [widgetData] against the live clock to compute today's [Status]. */
    fun status(widgetData: SharedPreferences): Status {
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
        return Status(entryCount, required, entryCount < required)
    }

    /** The current pulse frame: alternates between [colorBright] and [colorDim] every [pulseIntervalMs]. */
    fun pulseColor(): Int =
        if ((SystemClock.elapsedRealtime() / pulseIntervalMs) % 2L == 0L) colorBright else colorDim

    private fun updateIntent(context: Context, providerClass: Class<*>): PendingIntent {
        val component = ComponentName(context, providerClass)
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(component)
        val intent = Intent(context, providerClass)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(
            context, providerClass.name.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** Schedules the next repaint tick; call once per `onUpdate` while `status(...).behind` is true. */
    fun schedulePulse(context: Context, providerClass: Class<*>) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.setExact(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + pulseIntervalMs,
            updateIntent(context, providerClass)
        )
    }

    /** Stops the pulse loop for [providerClass]; call once `status(...).behind` reads false. */
    fun cancelPulse(context: Context, providerClass: Class<*>) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(updateIntent(context, providerClass))
    }
}
