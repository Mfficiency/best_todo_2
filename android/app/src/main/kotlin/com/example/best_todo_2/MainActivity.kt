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
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
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

    // The one blind spot every prior build shared: the render surface itself.
    // The Dart side can report frames built and rasterized, and the engine can
    // report `isDisplayingFlutterUi=true`, while the actual Android surface
    // those frames land on is gone or was never valid — which looks exactly
    // like a black screen and shows up in none of those signals. These watch
    // Flutter's own render view — a TextureView with the render-mode override
    // above, a SurfaceView without it — and log when a SurfaceView's surface is
    // created, resized or destroyed, plus the view's validity/availability on
    // every heartbeat, so a surface that dies or never comes up is finally a
    // recorded event instead of an inference.
    private var renderView: View? = null
    private var surfaceCallbackAdded = false
    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            diag("render surface created ${describeHolder(holder)}")
        }

        override fun surfaceChanged(
            holder: SurfaceHolder, format: Int, width: Int, height: Int
        ) {
            diag("render surface changed format=$format size=${width}x$height ${describeHolder(holder)}")
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            diag("render surface destroyed — nothing Flutter paints now reaches the screen")
        }
    }

    // Repeating post-resume heartbeat (replaces the old two one-shot probes):
    // a black window persists until a force-close, so a line every second for
    // the first dozen seconds after a resume gives an uninterrupted Android
    // record of it even when the Dart isolate has gone silent.
    private var heartbeat: Runnable? = null
    private var heartbeatTick = 0

    // The engine's own answer to "is Flutter's UI on screen?" — the one signal
    // that states the black screen directly instead of inferring it. Kept as a
    // field so the draw probe can ask at any moment.
    private var engine: FlutterEngine? = null

    private fun diag(message: String) = DiagLog.write(applicationContext, "native", message)

    // Render with a TextureView instead of the default SurfaceView.
    //
    // The 0.1.153–154 captures are the first to rule the render surface out as
    // "obviously dead": the engine reports frames built *and* rasterized and
    // `isDisplayingFlutterUi=true` throughout, yet the screen stays black. That
    // is the signature of a SurfaceView whose surface exists but is never
    // composited to the display — a documented Android failure after the OS
    // destroys and recreates a SurfaceView's surface across a background/resume
    // (or a cold start whose window begins 0x0/detached, as these logs show).
    // A TextureView is drawn through the ordinary view pipeline, so it is
    // immune to that surface-recreate race and — a bonus for the diagnostics —
    // its frames register on the window's own OnDrawListener, making
    // `windowDraws` a true present-counter instead of the flat 1–2 it reads for
    // a SurfaceView. The cost (marginally more GPU memory and one extra copy
    // per frame) is irrelevant for a to-do list; reliability is the point here.
    // Every prior renderer change swapped the *engine* (Impeller↔Skia); this
    // changes the *view* the engine presents into, which is the layer the new
    // evidence actually implicates. See SPEC §8.
    override fun getRenderMode(): RenderMode = RenderMode.texture

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
        attachSurfaceWitness()
        startHeartbeat()
    }

    // A once-per-second heartbeat for the first dozen seconds after a resume.
    // Each line carries the verdict (`flutterUi`) plus the render surface's
    // own validity, so a black window shows a steady flutterUi=true /
    // surface-invalid (or windowDraws not moving) trail across the whole
    // episode rather than two isolated samples.
    private fun startHeartbeat() {
        stopHeartbeat()
        heartbeatTick = 0
        val tick = object : Runnable {
            override fun run() {
                heartbeatTick++
                // The surface view can be laid out a beat after resume on a
                // cold start (the window is 0x0/detached at onResume then);
                // keep trying to attach until it is there.
                attachSurfaceWitness()
                val since = drawCount - drawsAtResume
                val age = System.currentTimeMillis() - resumeAtMs
                // The full content-view walk is verbose, so it rides along only
                // on the 1st and 6th beats (≈1 s and 6 s) — enough to see the
                // hierarchy's geometry early and again once a black window has
                // had time to settle, without it on all twelve lines.
                val tree = if (heartbeatTick == 1 || heartbeatTick == 6) {
                    " ${describeContentView()}"
                } else {
                    ""
                }
                diag(
                    "heartbeat +${age}ms flutterUi=${isFlutterUiDisplayed()} " +
                        "windowDraws=$since ${describeRenderSurface()} " +
                        "${describeWindow()}$tree"
                )
                if (heartbeatTick < 12) mainHandler.postDelayed(this, 1000)
            }
        }
        heartbeat = tick
        mainHandler.postDelayed(tick, 1000)
    }

    private fun stopHeartbeat() {
        heartbeat?.let { mainHandler.removeCallbacks(it) }
        heartbeat = null
    }

    // Finds Flutter's render view (a SurfaceView by default, a TextureView in
    // texture render mode) and, for a SurfaceView, subscribes to its surface
    // lifecycle. addCallback is additive — it does not displace the engine's
    // own callback — and does not replay `surfaceCreated` for an
    // already-created surface, so the per-heartbeat validity poll in
    // describeRenderSurface() covers the window between attach and the next
    // create/destroy event.
    private fun attachSurfaceWitness() {
        if (surfaceCallbackAdded) return
        val view = findRenderView(findViewById(android.R.id.content))
        renderView = view
        when (view) {
            is SurfaceView -> {
                try {
                    view.holder.addCallback(surfaceCallback)
                    surfaceCallbackAdded = true
                    diag("render view = SurfaceView ${describeRenderSurface()}")
                } catch (t: Throwable) {
                    diag("could not observe render surface: ${t.message}")
                }
            }
            is TextureView -> {
                // Flutter owns the TextureView's SurfaceTextureListener; the
                // heartbeat polls isAvailable instead of displacing it.
                surfaceCallbackAdded = true
                diag("render view = TextureView ${describeRenderSurface()}")
            }
            null -> {} // Not laid out yet; the next heartbeat retries.
            else -> {
                surfaceCallbackAdded = true
                diag("render view = ${view.javaClass.simpleName} (unexpected)")
            }
        }
    }

    private fun findRenderView(root: View?): View? {
        if (root == null) return null
        if (root is SurfaceView || root is TextureView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findRenderView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun describeHolder(holder: SurfaceHolder): String {
        val surface = holder.surface
        val frame = holder.surfaceFrame
        return "valid=${surface?.isValid} frame=${frame.width()}x${frame.height()}"
    }

    private fun describeRenderSurface(): String = try {
        when (val v = renderView) {
            is SurfaceView -> "renderSurface(SurfaceView ${v.width}x${v.height} " +
                "valid=${v.holder.surface?.isValid} vis=${visibilityName(v.visibility)})"
            is TextureView -> "renderSurface(TextureView ${v.width}x${v.height} " +
                "available=${v.isAvailable} vis=${visibilityName(v.visibility)})"
            null -> "renderSurface(not found yet)"
            else -> "renderSurface(${v.javaClass.simpleName})"
        }
    } catch (t: Throwable) {
        "renderSurface(read failed: ${t.message})"
    }

    private fun isFlutterUiDisplayed(): String = try {
        engine?.renderer?.isDisplayingFlutterUi?.toString() ?: "no engine"
    } catch (t: Throwable) {
        "unknown (${t.message})"
    }

    override fun onPause() {
        super.onPause()
        // The black window only happens while foreground; stop the per-second
        // heartbeat so it neither wastes power nor buries the next resume's
        // evidence under idle lines.
        stopHeartbeat()
        diag("onPause draws=${drawCount - drawsAtResume} since resume")
    }

    override fun onStop() {
        super.onStop()
        stopHeartbeat()
        diag("onStop")
    }

    override fun onDestroy() {
        removeDrawListener()
        removeSurfaceCallback()
        stopHeartbeat()
        mainHandler.removeCallbacksAndMessages(null)
        // isFinishing=true means the activity was closed for good (a Back
        // press, a swipe from recents) — the next widget tap is then a cold
        // start, not the warm re-front the black screen needs.
        diag("onDestroy isFinishing=$isFinishing changingConfig=$isChangingConfigurations")
        engine = null
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        diag("windowFocus=$hasFocus ${describeWindow()}")
    }

    // The engine reports these when its first frame reaches the surface and
    // when it stops rendering to one. A widget tap that comes back black
    // should show the resume without a following "flutter UI displayed".
    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        diag("flutter UI displayed (+${System.currentTimeMillis() - resumeAtMs}ms after resume)")
    }

    override fun onFlutterUiNoLongerDisplayed() {
        super.onFlutterUiNoLongerDisplayed()
        diag("flutter UI no longer displayed")
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

    private fun removeSurfaceCallback() {
        if (!surfaceCallbackAdded) return
        try {
            (renderView as? SurfaceView)?.holder?.removeCallback(surfaceCallback)
        } catch (t: Throwable) {
        }
        surfaceCallbackAdded = false
        renderView = null
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
        val decor = window?.decorView ?: return "window(none)"
        return "window(${visibilityName(decor.visibility)} " +
            "size=${decor.width}x${decor.height} " +
            "focus=${decor.hasWindowFocus()} attached=${decor.isAttachedToWindow})"
    }

    // Walks down the content view reporting size and visibility at each level.
    // Class names are deliberately not matched against "Flutter…": R8 renames
    // them in a release build, which is why the first version of this reported
    // "no Flutter view in hierarchy" on every real device. Geometry survives
    // obfuscation — a re-front that comes back black still shows the view at
    // full size, proving the window is fine and nothing is painted into it.
    private fun describeContentView(): String {
        val root = findViewById<View>(android.R.id.content)
            ?: return "content(missing)"
        val parts = StringBuilder()
        var view: View? = root
        var depth = 0
        try {
            while (view != null && depth < 4) {
                parts.append(
                    "${view.javaClass.simpleName}(${view.width}x${view.height} " +
                        "vis=${visibilityName(view.visibility)}) "
                )
                val group = view as? ViewGroup ?: break
                if (group.childCount == 0) break
                if (group.childCount > 1) parts.append("[${group.childCount} children] ")
                view = group.getChildAt(0)
                depth++
            }
        } catch (t: Throwable) {
            return "content(walk failed: ${t.message})"
        }
        return "content(${parts.toString().trim()})"
    }

    private fun visibilityName(visibility: Int): String = when (visibility) {
        View.VISIBLE -> "visible"
        View.INVISIBLE -> "invisible"
        View.GONE -> "gone"
        else -> visibility.toString()
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
        engine = flutterEngine
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
