package com.mfficiency.best_todo_2

import android.app.DownloadManager
import android.app.NotificationManager
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.content.pm.ApplicationInfo

// FlutterFragmentActivity (not the plain FlutterActivity) because the
// health plugin's Health Connect permission flow needs a FragmentActivity
// to launch its Activity Result contract on Android 14+.
class MainActivity : FlutterFragmentActivity() {

    // Content shared into the app (see ShareActivity), waiting for the Dart
    // side to collect it. On a cold start the queue fills before the Flutter
    // engine runs; ShareIntentService drains it once initialized. Each entry
    // is a map of {"text": String, "files": [{"path": String, "mimeType":
    // String}, ...]}.
    private val pendingSharedContent = ArrayDeque<Map<String, Any?>>()
    private var shareChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreenIfAlarmLaunch(intent)
        queueSharedContent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showOverLockScreenIfAlarmLaunch(intent)
        queueSharedContent(intent)
    }

    // Queues content forwarded by ShareActivity and pokes the Dart side. When
    // the poke arrives before ShareIntentService registered its handler
    // (cold start), it is simply lost — the service's own initial
    // takeSharedContent pull drains the queue instead, so nothing is dropped
    // and nothing is delivered twice (delivery is always pull-with-clear).
    private fun queueSharedContent(intent: Intent?) {
        if (intent?.action != ShareActivity.ACTION_SHARED_CONTENT) return
        val text = intent.getStringExtra(ShareActivity.EXTRA_SHARED_TEXT).orEmpty()
        val paths = intent.getStringArrayListExtra(ShareActivity.EXTRA_SHARED_FILE_PATHS)
            ?: arrayListOf()
        val mimeTypes = intent.getStringArrayListExtra(ShareActivity.EXTRA_SHARED_FILE_MIME_TYPES)
            ?: arrayListOf()
        if (text.isBlank() && paths.isEmpty()) return
        val files = paths.mapIndexed { i, path ->
            mapOf("path" to path, "mimeType" to (mimeTypes.getOrNull(i) ?: ""))
        }
        pendingSharedContent.add(mapOf("text" to text, "files" to files))
        shareChannel?.invokeMethod("sharedContentPending", null)
    }

    // When an alarm notification's full-screen intent launches (or re-fronts)
    // this activity while the device is locked, let it appear over the lock
    // screen with the screen on — the Flutter side then presents the
    // full-screen ring page, like a stock clock app. Ordinary launches (home
    // screen, task notifications without an alarm payload) never get these
    // flags, so the todo list itself is never exposed on the lock screen.
    private fun showOverLockScreenIfAlarmLaunch(intent: Intent?) {
        if (intent?.action != "SELECT_NOTIFICATION") return
        // flutter_local_notifications puts the notification payload in the
        // "payload" extra; only alarm payloads carry a uid.
        val payload = intent.getStringExtra("payload") ?: return
        if (!payload.contains("\"uid\"")) return
        setLockScreenFlags(true)
    }

    private fun setLockScreenFlags(show: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(show)
            setTurnScreenOn(show)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (show) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    private fun vibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    // Buzz-pause-buzz until stopVibration(), on the alarm usage so it keeps
    // going the way an alarm would. Returns false when the device has no
    // vibrator.
    private fun startVibration(): Boolean {
        val vibrator = vibrator() ?: return false
        if (!vibrator.hasVibrator()) return false
        val pattern = longArrayOf(0, 600, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            vibrator.vibrate(
                VibrationEffect.createWaveform(pattern, 0),
                attributes,
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, 0)
        }
        return true
    }

    private fun stopVibration() {
        vibrator()?.cancel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/digital_wellbeing",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> {
                    val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                            android.os.Process.myUid(), packageName)
                    } else {
                        @Suppress("DEPRECATION")
                        ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS,
                            android.os.Process.myUid(), packageName)
                    }
                    result.success(mode == AppOpsManager.MODE_ALLOWED)
                }
                "openPermissionSettings" -> {
                    result.success(openUsageAccessSettings())
                }
                "querySessions" -> {
                    val from = call.argument<Number>("from")?.toLong()
                    val to = call.argument<Number>("to")?.toLong()
                    if (from == null || to == null) {
                        result.error("bad-args", "from/to missing", null)
                    } else {
                        result.success(queryUsageSessions(from, to))
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/health",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDataSources" -> result.success(openHealthDataSources())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/alarm_ring",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 14+ can revoke the USE_FULL_SCREEN_INTENT special
                // access; the alarm diagnostics read this to explain why an
                // alarm only showed a banner instead of the full-screen UI.
                "canUseFullScreenIntent" -> {
                    val granted = if (Build.VERSION.SDK_INT >= 34) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                            as NotificationManager
                        nm.canUseFullScreenIntent()
                    } else {
                        true
                    }
                    result.success(granted)
                }
                // Called when the ring page closes, so the rest of the app
                // does not stay visible over the lock screen.
                "clearLockScreenFlags" -> {
                    setLockScreenFlags(false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/alarm_audio",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Plays a built-in melody at an absolute loudness (fraction of
                // the device maximum), independent of the current volume
                // settings. Used by the full-screen ring page and the melody
                // Preview button in the alarm editor.
                "play" -> {
                    val melody = call.argument<String>("melody") ?: "Classic"
                    val volume = call.argument<Double>("volume") ?: 0.8
                    val overrideDnd =
                        call.argument<Boolean>("overrideDnd") ?: false
                    val loop = call.argument<Boolean>("loop") ?: true
                    val started = AlarmSoundPlayer.start(
                        applicationContext, melody, volume, overrideDnd, loop
                    )
                    result.success(started)
                }
                "stop" -> {
                    AlarmSoundPlayer.stop(applicationContext)
                    result.success(null)
                }
                // Repeating alarm-style vibration, used on its own by the dice
                // timer's vibrate-only alert and alongside a melody when the
                // user asked for both.
                "vibrate" -> result.success(startVibration())
                "stopVibrate" -> {
                    stopVibration()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Hands the update APK to Android's DownloadManager instead
                // of downloading it on the Dart side: the transfer then runs
                // as a system service, so it survives the app being
                // backgrounded and DownloadManager itself resumes the
                // transfer (via HTTP range requests) when the network drops
                // or switches between Wi-Fi and mobile mid-download — a raw
                // socket held open by the app process would just break.
                "startBackgroundDownload" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    if (url == null || fileName == null) {
                        result.error("bad-args", "url/fileName missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        // DownloadManager runs as a separate system process
                        // (the downloads provider), which cannot write into
                        // this app's private *internal* storage (filesDir) —
                        // only into the app's own slice of *external*
                        // storage, which needs no runtime permission and is
                        // still private to this app. getExternalFilesDir is
                        // null only if external storage isn't currently
                        // available (e.g. a removed SD card on very old
                        // devices).
                        val baseDir = getExternalFilesDir(null)
                        if (baseDir == null) {
                            result.error(
                                "download-failed", "External storage unavailable", null
                            )
                            return@setMethodCallHandler
                        }
                        val destDir = File(baseDir, "updates")
                        destDir.mkdirs()
                        val destFile = File(destDir, fileName)
                        if (destFile.exists()) destFile.delete()
                        val downloadManager =
                            getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle("BestToDo update")
                            .setDestinationUri(Uri.fromFile(destFile))
                            .setNotificationVisibility(
                                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                            )
                            .setAllowedNetworkTypes(
                                DownloadManager.Request.NETWORK_WIFI or
                                    DownloadManager.Request.NETWORK_MOBILE
                            )
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(true)
                        val id = downloadManager.enqueue(request)
                        result.success(mapOf("downloadId" to id))
                    } catch (e: Exception) {
                        result.error("download-failed", e.message, null)
                    }
                }
                // Snapshot of a download started by startBackgroundDownload:
                // status ("pending"/"running"/"paused"/"successful"/"failed"),
                // bytesDownloaded/bytesTotal for a progress bar, and the
                // local file path once successful.
                "queryDownload" -> {
                    val id = call.argument<Number>("downloadId")?.toLong()
                    if (id == null) {
                        result.error("bad-args", "downloadId missing", null)
                        return@setMethodCallHandler
                    }
                    val downloadManager =
                        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    val cursor = downloadManager.query(
                        DownloadManager.Query().setFilterById(id)
                    )
                    cursor.use {
                        if (!it.moveToFirst()) {
                            result.success(
                                mapOf(
                                    "status" to "failed",
                                    "bytesDownloaded" to 0,
                                    "bytesTotal" to 0,
                                    "reason" to "not-found",
                                )
                            )
                            return@setMethodCallHandler
                        }
                        val statusCode = it.getInt(
                            it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                        )
                        val status = when (statusCode) {
                            DownloadManager.STATUS_SUCCESSFUL -> "successful"
                            DownloadManager.STATUS_FAILED -> "failed"
                            DownloadManager.STATUS_RUNNING -> "running"
                            DownloadManager.STATUS_PAUSED -> "paused"
                            else -> "pending"
                        }
                        val bytesDownloaded = it.getLong(
                            it.getColumnIndexOrThrow(
                                DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                            )
                        )
                        val bytesTotal = it.getLong(
                            it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
                        )
                        val reason = it.getInt(
                            it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
                        )
                        val localUri = it.getString(
                            it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                        )
                        result.success(
                            mapOf(
                                "status" to status,
                                "bytesDownloaded" to bytesDownloaded,
                                "bytesTotal" to bytesTotal,
                                "localPath" to localUri?.let { uri -> Uri.parse(uri).path },
                                "reason" to reason,
                            )
                        )
                    }
                }
                // Cancels a download and deletes its partial file.
                "cancelDownload" -> {
                    val id = call.argument<Number>("downloadId")?.toLong()
                    if (id == null) {
                        result.error("bad-args", "downloadId missing", null)
                        return@setMethodCallHandler
                    }
                    val downloadManager =
                        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    downloadManager.remove(id)
                    result.success(null)
                }
                // Hands a downloaded update APK to the system package
                // installer. Returns "needs-permission" (after opening the
                // "install unknown apps" settings screen for this app) when
                // the one-time install permission is still missing — the
                // Dart side tells the user to grant it and tap Install again.
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("bad-args", "path missing", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !packageManager.canRequestPackageInstalls()
                    ) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success("needs-permission")
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", File(path)
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(
                                uri,
                                "application/vnd.android.package-archive",
                            )
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        }
                        startActivity(intent)
                        result.success("ok")
                    } catch (e: Exception) {
                        result.error("install-failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/share",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Hands over every queued shared item and empties the
                    // queue in the same step, so one can never be delivered
                    // twice.
                    "takeSharedContent" -> {
                        val items = pendingSharedContent.toList()
                        pendingSharedContent.clear()
                        result.success(items)
                    }
                    // Backgrounds this app's task once the quick-add screen
                    // is done (saved or dismissed), re-fronting whatever the
                    // share came from — the standard "quick capture" pattern,
                    // since this activity was launched fresh by that app's
                    // share sheet.
                    "returnToPreviousApp" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun openHealthDataSources(): Boolean {
        val attempts = listOf(
            Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"),
            Intent("android.health.connect.action.HEALTH_HOME_SETTINGS"),
            packageManager.getLaunchIntentForPackage("com.google.android.apps.healthdata"),
            packageManager.getLaunchIntentForPackage("com.sec.android.app.shealth"),
        )
        for (intent in attempts) {
            if (intent == null) continue
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
                // Try the next action/package; availability differs by Android
                // and One UI version.
            }
        }
        return false
    }

    // ACTION_USAGE_ACCESS_SETTINGS with a package: data URI throws
    // ActivityNotFoundException on some OEMs (MIUI, some One UI builds) that
    // don't register that specific action+data combination — previously
    // uncaught, so the "Allow" button silently did nothing. Fall back to the
    // same action without the data extra, then to this app's details page,
    // so the user always lands somewhere they can grant the permission.
    private fun openUsageAccessSettings(): Boolean {
        val attempts = listOf(
            { startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }) },
            { startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) },
            { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }) },
        )
        for (attempt in attempts) {
            try {
                attempt()
                return true
            } catch (_: Exception) {
                continue
            }
        }
        return false
    }

    private fun queryUsageSessions(from: Long, to: Long): List<Map<String, Any>> {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to)
        val event = UsageEvents.Event()
        val starts = mutableMapOf<String, Long>()
        val sessions = mutableListOf<Map<String, Any>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                starts[pkg] = maxOf(event.timeStamp, from)
            } else if (event.eventType == UsageEvents.Event.ACTIVITY_PAUSED ||
                event.eventType == UsageEvents.Event.MOVE_TO_BACKGROUND) {
                val start = starts.remove(pkg) ?: continue
                if (event.timeStamp <= start) continue
                val info = try { packageManager.getApplicationInfo(pkg, 0) } catch (_: Exception) { null }
                val name = info?.let { packageManager.getApplicationLabel(it).toString() } ?: pkg
                val category = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && info != null) {
                    when (info.category) {
                        ApplicationInfo.CATEGORY_GAME -> "Games"
                        ApplicationInfo.CATEGORY_AUDIO, ApplicationInfo.CATEGORY_VIDEO -> "Entertainment"
                        ApplicationInfo.CATEGORY_SOCIAL -> "Social"
                        ApplicationInfo.CATEGORY_PRODUCTIVITY -> "Productivity"
                        ApplicationInfo.CATEGORY_NEWS -> "News"
                        ApplicationInfo.CATEGORY_MAPS -> "Travel"
                        else -> "Other"
                    }
                } else "Other"
                sessions.add(mapOf("package" to pkg, "appName" to name,
                    "category" to category, "start" to start,
                    "end" to minOf(event.timeStamp, to)))
            }
        }
        starts.forEach { (pkg, start) ->
            sessions.add(mapOf("package" to pkg, "appName" to pkg,
                "category" to "Other", "start" to start, "end" to to))
        }
        return sessions
    }
}
