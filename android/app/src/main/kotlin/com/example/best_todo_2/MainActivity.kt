package com.mfficiency.best_todo_2

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    // Texts shared into the app (see ShareActivity), waiting for the Dart
    // side to collect them. On a cold start the queue fills before the
    // Flutter engine runs; ShareIntentService drains it once initialized.
    private val pendingSharedTexts = ArrayDeque<String>()
    private var shareChannel: MethodChannel? = null

    // Black-screen diagnostics (see DiagLog). Counting the window's draws is
    // the one signal that does not depend on the Flutter side being healthy:
    // if a widget tap re-fronts the app and the window never draws afterwards,
    // this is where that shows up.
    private val mainHandler = Handler(Looper.getMainLooper())
    private var drawCount = 0
    private var drawsAtResume = 0
    private var resumeAtMs = 0L
    private var drawListenerAdded = false
    private val drawListener = ViewTreeObserver.OnDrawListener { drawCount++ }

    private fun diag(message: String) = DiagLog.write(applicationContext, "native", message)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        diag(
            "onCreate taskId=$taskId isTaskRoot=$isTaskRoot " +
                "recreated=${savedInstanceState != null} ${describeIntent(intent)}"
        )
        // A widget tap while the app is already running must re-front the
        // existing UI, never build a second copy of it. singleTop plus the
        // default task affinity (see AndroidManifest.xml) make that the normal
        // outcome; if a launcher still routes the widget's PendingIntent into
        // a duplicate MainActivity stacked on the real one, close the
        // duplicate so the live instance underneath shows instead of this
        // one's never-finishing launch window (a black screen).
        if (!isTaskRoot &&
            intent?.action == "es.antonborri.home_widget.action.LAUNCH"
        ) {
            // If the app comes back black after a widget tap, this line says
            // whether a duplicate activity was created and closed again — the
            // instance revealed underneath is then the one that stayed black.
            diag("onCreate: duplicate widget launch on a non-root task -> finish()")
            finish()
            return
        }
        showOverLockScreenIfAlarmLaunch(intent)
        queueSharedText(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The healthy warm path for a widget tap: the running activity is
        // re-fronted and the URI arrives here (home_widget then forwards it to
        // Dart's widgetClicked stream).
        diag("onNewIntent taskId=$taskId isTaskRoot=$isTaskRoot ${describeIntent(intent)}")
        showOverLockScreenIfAlarmLaunch(intent)
        queueSharedText(intent)
    }

    override fun onStart() {
        super.onStart()
        diag("onStart")
    }

    override fun onResume() {
        super.onResume()
        addDrawListener()
        drawsAtResume = drawCount
        resumeAtMs = System.currentTimeMillis()
        diag("onResume ${describeWindow()}")
        // Two probes after the resume: by 1.5 s a healthy re-front has drawn
        // several frames. "draws=0" here is the black window, caught on the
        // Android side regardless of what Flutter believes.
        scheduleDrawProbe(1500)
        scheduleDrawProbe(5000)
    }

    private fun scheduleDrawProbe(delayMs: Long) {
        mainHandler.postDelayed({
            val since = drawCount - drawsAtResume
            val age = System.currentTimeMillis() - resumeAtMs
            val verdict = if (since == 0) "NO DRAW since resume — black window" else "ok"
            diag(
                "draw probe +${age}ms draws=$since $verdict " +
                    "${describeWindow()} ${describeFlutterViews()}"
            )
        }, delayMs)
    }

    override fun onPause() {
        super.onPause()
        diag("onPause draws=${drawCount - drawsAtResume} since resume")
    }

    override fun onStop() {
        super.onStop()
        diag("onStop")
    }

    override fun onDestroy() {
        removeDrawListener()
        mainHandler.removeCallbacksAndMessages(null)
        diag("onDestroy isFinishing=$isFinishing changingConfig=$isChangingConfigurations")
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        diag("windowFocus=$hasFocus ${describeWindow()}")
    }

    private fun addDrawListener() {
        if (drawListenerAdded) return
        try {
            val observer = window?.decorView?.viewTreeObserver ?: return
            if (!observer.isAlive) return
            observer.addOnDrawListener(drawListener)
            drawListenerAdded = true
        } catch (t: Throwable) {
            diag("could not observe draws: ${t.message}")
        }
    }

    private fun removeDrawListener() {
        if (!drawListenerAdded) return
        try {
            val observer = window?.decorView?.viewTreeObserver
            if (observer != null && observer.isAlive) {
                observer.removeOnDrawListener(drawListener)
            }
        } catch (t: Throwable) {
        }
        drawListenerAdded = false
    }

    private fun describeIntent(intent: Intent?): String {
        if (intent == null) return "intent=null"
        val flags = Integer.toHexString(intent.flags)
        val categories = intent.categories?.joinToString("+") ?: "-"
        val extras = try {
            intent.extras?.keySet()?.joinToString("+") ?: "-"
        } catch (t: Throwable) {
            "?"
        }
        return "action=${intent.action} data=${intent.dataString} " +
            "flags=0x$flags categories=$categories extras=$extras"
    }

    private fun describeWindow(): String {
        val decor = window?.decorView
        return "window(visible=${decor?.visibility} size=${decor?.width}x${decor?.height} " +
            "focus=${decor?.hasWindowFocus()} attached=${decor?.isAttachedToWindow})"
    }

    // Reports the Flutter surface/texture views by class name only — no
    // compile-time dependency on engine internals, so this keeps working
    // across engine versions. A re-front that comes back black typically
    // still has the view here at full size: proof the window is fine and the
    // content simply never gets painted into it.
    private fun describeFlutterViews(): String {
        val decor = window?.decorView ?: return "views(no decorView)"
        val found = StringBuilder()
        fun walk(view: View) {
            val name = view.javaClass.simpleName
            if (name.contains("Flutter") || name.contains("Surface") ||
                name.contains("Texture")
            ) {
                found.append(
                    "$name(${view.width}x${view.height} vis=${view.visibility} " +
                        "alpha=${view.alpha} attached=${view.isAttachedToWindow}) "
                )
            }
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) walk(view.getChildAt(i))
            }
        }
        try {
            walk(decor)
        } catch (t: Throwable) {
            return "views(walk failed: ${t.message})"
        }
        return if (found.isEmpty()) "views(no Flutter view in hierarchy)"
        else "views(${found.toString().trim()})"
    }

    // Queues text forwarded by ShareActivity and pokes the Dart side. When
    // the poke arrives before ShareIntentService registered its handler
    // (cold start), it is simply lost — the service's own initial
    // takeSharedTexts pull drains the queue instead, so nothing is dropped
    // and nothing is delivered twice (delivery is always pull-with-clear).
    private fun queueSharedText(intent: Intent?) {
        if (intent?.action != ShareActivity.ACTION_SHARED_TEXT) return
        val shared = intent.getStringExtra(ShareActivity.EXTRA_SHARED_TEXT)
        if (shared.isNullOrBlank()) return
        pendingSharedTexts.add(shared)
        shareChannel?.invokeMethod("sharedTextsPending", null)
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
        diag("configureFlutterEngine — Dart side attaching")
        // Black-screen diagnostics: reading and appending to the native
        // breadcrumb file. The Dart side mirrors its own lifecycle/frame
        // verdicts in here so App Logs → Device shows one ordered timeline of
        // both sides, and it survives the force-close that ends the black
        // screen.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/diag",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> result.success(DiagLog.read(applicationContext))
                "clear" -> {
                    DiagLog.clear(applicationContext)
                    result.success(null)
                }
                "note" -> {
                    val message = call.argument<String>("message") ?: ""
                    DiagLog.write(applicationContext, "dart", message)
                    result.success(null)
                }
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
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/share",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Hands over every queued shared text and empties the
                    // queue in the same step, so a text can never be
                    // delivered twice.
                    "takeSharedTexts" -> {
                        val texts = pendingSharedTexts.toList()
                        pendingSharedTexts.clear()
                        result.success(texts)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "besttodo/update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
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
    }
}
