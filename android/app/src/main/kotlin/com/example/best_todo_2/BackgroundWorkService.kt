package com.mfficiency.best_todo_2

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// Keeps Best Music's background song-info search (MusicMetadataEnricher:
// online lookups + on-device BPM detection) running while other apps are in
// front. The work itself stays in Dart — this foreground service only holds
// the process at foreground priority (so Android doesn't freeze or kill it
// once the app leaves the screen), shows an ongoing low-priority
// notification with the progress line, and holds a partial wake lock so a
// screen turning off doesn't stall it. Driven over channel
// `besttodo/background_work` (lib/services/background_work.dart):
// start(title, text) / update(text) / stop.
class BackgroundWorkService : Service() {
    companion object {
        private const val CHANNEL_ID = "background_work"
        private const val NOTIFICATION_ID = 7301
        private const val WAKE_LOCK_TIMEOUT_MS = 3L * 60 * 60 * 1000

        @Volatile
        private var running = false
        private var title = "Best Music"

        fun register(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, "besttodo/background_work").setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        title = call.argument<String>("title") ?: title
                        val text = call.argument<String>("text") ?: ""
                        val intent = Intent(context, BackgroundWorkService::class.java)
                            .putExtra("text", text)
                        try {
                            if (running) {
                                showNotification(context, text)
                            } else {
                                ContextCompat.startForegroundService(context, intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            // e.g. ForegroundServiceStartNotAllowedException when
                            // asked from the background on Android 12+.
                            result.success(false)
                        }
                    }
                    "update" -> {
                        if (running) showNotification(context, call.argument<String>("text") ?: "")
                        result.success(running)
                    }
                    "stop" -> {
                        context.stopService(Intent(context, BackgroundWorkService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID, "Background song info", NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Shown while Best Music fills in song info in the background"
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        private fun build(context: Context, text: String): Notification {
            ensureChannel(context)
            val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentIntent = launch?.let {
                PendingIntent.getActivity(
                    context, 0, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            }
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_music_note)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setContentIntent(contentIntent)
                .build()
        }

        private fun showNotification(context: Context, text: String) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, build(context, text))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(this, intent?.getStringExtra("text") ?: "")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
        if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BestMusic:background_work").apply {
                setReferenceCounted(false)
                acquire(WAKE_LOCK_TIMEOUT_MS)
            }
        }
        // Not restarted by the system on its own: the Dart side restarts
        // it when it has work again.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Throwable) {
        }
        wakeLock = null
        super.onDestroy()
    }
}
