package com.mfficiency.best_todo_2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget with play/pause, skip-previous and skip-next. Like
 * [MusicMiniWidgetProvider], the buttons send real Android media-button
 * broadcasts to `audio_service`'s MediaButtonReceiver rather than going
 * through the app's Dart code directly, so they work without opening it.
 */
class MusicControlsWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.music_controls_widget_layout)

            val hasTrack = widgetData.getBoolean("music_widget_has_track", false)
            val playing = widgetData.getBoolean("music_widget_playing", false)
            val title = widgetData.getString("music_widget_title", "") ?: ""
            val artist = widgetData.getString("music_widget_artist", "") ?: ""
            val label = when {
                !hasTrack || title.isEmpty() -> "Nothing playing"
                artist.isNotEmpty() -> "$title – $artist"
                else -> title
            }

            views.setTextViewText(R.id.music_controls_widget_title, label)
            views.setImageViewResource(
                R.id.music_controls_widget_play_pause,
                if (playing) R.drawable.ic_pause else R.drawable.ic_play_arrow
            )

            views.setOnClickPendingIntent(
                R.id.music_controls_widget_play_pause,
                MusicWidgetIntents.playPause(context)
            )
            views.setOnClickPendingIntent(
                R.id.music_controls_widget_previous,
                MusicWidgetIntents.previous(context)
            )
            views.setOnClickPendingIntent(
                R.id.music_controls_widget_next,
                MusicWidgetIntents.next(context)
            )

            val openIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("besttodomusic://open")
            )
            views.setOnClickPendingIntent(R.id.music_controls_widget_title, openIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
