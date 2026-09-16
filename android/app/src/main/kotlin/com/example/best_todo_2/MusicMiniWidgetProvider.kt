package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Minimal home-screen widget: a single play/pause button, nothing else.
 * The button sends a real Android media-button broadcast (the same path a
 * Bluetooth headset uses) straight to `audio_service`'s MediaButtonReceiver,
 * so it works whether or not the app is in the foreground — as long as
 * music has been started at least once this session (see
 * [MusicWidgetIntents]). Tapping the title opens the app's Music Player.
 */
class MusicMiniWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.music_mini_widget_layout)

            val hasTrack = widgetData.getBoolean("music_widget_has_track", false)
            val playing = widgetData.getBoolean("music_widget_playing", false)
            val title = widgetData.getString("music_widget_title", "") ?: ""

            views.setTextViewText(
                R.id.music_mini_widget_title,
                if (hasTrack && title.isNotEmpty()) title else "Nothing playing"
            )
            views.setImageViewResource(
                R.id.music_mini_widget_play_pause,
                if (playing) R.drawable.ic_pause else R.drawable.ic_play_arrow
            )

            views.setOnClickPendingIntent(
                R.id.music_mini_widget_play_pause,
                MusicWidgetIntents.playPause(context)
            )

            val openIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("besttodomusic://open")
            )
            views.setOnClickPendingIntent(R.id.music_mini_widget_title, openIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
