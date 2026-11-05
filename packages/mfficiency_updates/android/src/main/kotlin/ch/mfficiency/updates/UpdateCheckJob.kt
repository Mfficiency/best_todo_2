package ch.mfficiency.updates

import android.app.Activity
import android.app.Application
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * The update check while the app is closed (Dart: `UpdateBackground`).
 *
 * [schedule] has JobScheduler run this job every hour (the app's
 * `backgroundInterval`) when a network is there, kept across reboots. Each
 * run starts a headless Flutter engine with the app's background entry
 * point (its callback handle, stored in [PREFS]), which checks GitHub and
 * downloads a newer build silently, then calls `done` on
 * `mfficiency_updates/background`. Nothing is shown; the app offers the
 * install when it is opened.
 *
 * Skipped while one of the app's activities is started (the app checks by
 * itself then), and stopped as soon as one starts during a run, so the
 * app and this job never download the same APK at once (the downloader's
 * lock file covers the rest).
 *
 * An interrupted download is continued by a second, one-off job
 * ([scheduleResume]: the app left the screen while downloading, or a
 * download was cut off): it runs once a network is there and, while the run
 * says the APK is still `incomplete`, again with back-off (30 s, doubling),
 * each time continuing the `.part` where it stopped.
 */
class UpdateCheckJob : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var params: JobParameters? = null

    override fun onStartJob(params: JobParameters): Boolean {
        val handle = getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(KEY_HANDLE, 0L)
        if (handle == 0L || startedActivities > 0) return false
        this.params = params
        running = this
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationCompleteAsync(applicationContext, null, main) {
            if (running !== this) return@ensureInitializationCompleteAsync
            val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            if (info == null) {
                Log.w(TAG, "background entry point not found")
                finish(false)
                return@ensureInitializationCompleteAsync
            }
            val e = FlutterEngine(applicationContext)
            engine = e
            MethodChannel(e.dartExecutor.binaryMessenger, "mfficiency_updates/background")
                .setMethodCallHandler { call, result ->
                    if (call.method == "done") {
                        result.success(null)
                        val outcome = call.argument<String>("outcome")
                        Log.i(TAG, "background check: $outcome")
                        val incomplete = outcome == "incomplete"
                        if (incomplete && params.jobId == JOB_ID) {
                            // The hourly run found it cut off: continue soon.
                            scheduleResume(applicationContext)
                        }
                        finish(incomplete && params.jobId == RESUME_JOB_ID)
                    } else {
                        result.notImplemented()
                    }
                }
            e.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(assets, loader.findAppBundlePath(), info),
            )
            // A run that never says it is done is stopped after 9 minutes
            // (JobScheduler allows 10).
            main.postDelayed({ if (running === this) finish(true) }, TIMEOUT_MS)
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        stopEngine()
        return true // run again later
    }

    /** One of the app's activities started: the app takes over. */
    private fun stopForApp() {
        val p = params ?: return
        stopEngine()
        jobFinished(p, false)
    }

    private fun finish(retry: Boolean) {
        val p = params ?: return
        stopEngine()
        jobFinished(p, retry)
    }

    private fun stopEngine() {
        if (running === this) running = null
        main.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        params = null
    }

    companion object {
        private const val TAG = "MfficiencyUpdates"
        private const val PREFS = "mfficiency_updates"
        private const val KEY_HANDLE = "background.handle"

        /** Unusual on purpose: an app's own jobs use small ids. */
        private const val JOB_ID = 0x4d465550 // "MFUP"
        private const val RESUME_JOB_ID = 0x4d465551 // "MFUQ"
        private const val RESUME_BACKOFF_MS = 30 * 1000L
        private const val TIMEOUT_MS = 9 * 60 * 1000L

        private var running: UpdateCheckJob? = null
        private var startedActivities = 0
        private var watching = false

        /** Counts the app's started activities (see [UpdateCheckJob]). */
        fun watchActivities(app: Application) {
            if (watching) return
            watching = true
            app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
                override fun onActivityStarted(activity: Activity) {
                    startedActivities++
                    running?.let { job -> Handler(Looper.getMainLooper()).post { job.stopForApp() } }
                }

                override fun onActivityStopped(activity: Activity) {
                    if (startedActivities > 0) startedActivities--
                }

                override fun onActivityCreated(activity: Activity, state: Bundle?) {}
                override fun onActivityResumed(activity: Activity) {}
                override fun onActivityPaused(activity: Activity) {}
                override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
                override fun onActivityDestroyed(activity: Activity) {}
            })
        }

        /** Runs the entry point [handle] every [minutes] (at least 15). */
        fun schedule(context: Context, handle: Long, minutes: Int): Boolean {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putLong(KEY_HANDLE, handle).apply()
            val every = minutes.coerceAtLeast(15) * 60 * 1000L
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return false
            val existing = scheduler.getPendingJob(JOB_ID)
            if (existing != null && existing.intervalMillis == every && existing.isPersisted) {
                return true // keeps its place in the schedule
            }
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, UpdateCheckJob::class.java))
                .setPeriodic(every, every / 4)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build()
            return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
        }

        /**
         * Continues an interrupted download soon: once a network is there
         * (at the earliest after [delayMs]), then with back-off while it is
         * still incomplete. Needs the entry point stored by [schedule].
         */
        fun scheduleResume(context: Context, delayMs: Long = 15 * 1000L): Boolean {
            val handle = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getLong(KEY_HANDLE, 0L)
            if (handle == 0L) return false
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return false
            val job = JobInfo.Builder(RESUME_JOB_ID, ComponentName(context, UpdateCheckJob::class.java))
                .setMinimumLatency(delayMs)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(RESUME_BACKOFF_MS, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .setPersisted(true)
                .build()
            return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
        }

        fun cancel(context: Context) {
            context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
            context.getSystemService(JobScheduler::class.java)?.cancel(RESUME_JOB_ID)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .remove(KEY_HANDLE).apply()
        }
    }
}
