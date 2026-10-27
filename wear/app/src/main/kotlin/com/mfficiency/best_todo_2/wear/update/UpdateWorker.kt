package com.mfficiency.best_todo_2.wear.update

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * The daily update check: only while the watch charges and is online
 * (overnight, on the charger), so it costs no battery during the day.
 */
class UpdateWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        WatchUpdater.load(applicationContext)
        return if (WatchUpdater.run(applicationContext)) Result.success() else Result.retry()
    }

    companion object {
        private const val DAILY = "watch_update_daily"
        private const val NOW = "watch_update_now"

        private val constraints = Constraints.Builder()
            .setRequiresCharging(true)
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        /** Every app start; keeps an existing schedule. */
        fun schedule(context: Context) {
            if (WatchUpdater.repo(context).isEmpty()) return
            val request = PeriodicWorkRequestBuilder<UpdateWorker>(1, TimeUnit.DAYS)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(DAILY, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        /** Once, as soon as the watch is online (a new token). */
        fun runSoon(context: Context) {
            val request = OneTimeWorkRequestBuilder<UpdateWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.REPLACE, request)
        }
    }
}

/** The PackageInstaller session's answer (not exported). */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == WatchUpdater.ACTION_INSTALLED) WatchUpdater.onInstallResult(context, intent)
    }
}

/**
 * Sets the watch's GitHub token, once, over adb (wear/README.md › Updates).
 * Guarded by android.permission.DUMP, which only the shell and the system
 * hold: no app on the watch can send it.
 *
 *     adb shell am broadcast -n <applicationId>/<applicationId>.wear.update.TokenReceiver --es token github_pat_…
 *
 * An empty token removes it.
 */
class TokenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra("token")
        WatchUpdater.setToken(context, token)
        Log.i("WatchUpdater", if (token.isNullOrBlank()) "token removed" else "token saved")
        resultData = if (token.isNullOrBlank()) "token removed" else "token saved, checking for updates"
        UpdateWorker.schedule(context)
        UpdateWorker.runSoon(context)
    }
}
