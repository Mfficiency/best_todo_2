package com.mfficiency.best_todo_2.wear.update

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.mfficiency.best_todo_2.wear.BuildConfig
import com.mfficiency.best_todo_2.wear.R
import com.mfficiency.best_todo_2.wear.core.WatchRelease
import com.mfficiency.best_todo_2.wear.core.WatchUpdate
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** What the watch shows under "Check for updates". */
enum class UpdateStatus { IDLE, CHECKING, DOWNLOADING, INSTALLING, UP_TO_DATE, NOT_CONFIGURED, NO_PERMISSION, CONFIRM, FAILED }

data class UpdateState(val status: UpdateStatus, val version: String = "", val checkedAt: Long = 0L)

/**
 * The watch updates itself from the repo's GitHub Releases (`wear-…`, built
 * by the laptop with the phone's key): [UpdateWorker] once a day while
 * charging, and "Check for updates" on the screen. Downloads into
 * `cache/updates/`, checks the APK is this app at that build, and installs
 * it with a PackageInstaller session that asks nobody (a self-update with
 * UPDATE_PACKAGES_WITHOUT_USER_ACTION, once the install permission was
 * granted over adb). If Android still wants a confirmation, it is shown at
 * once on the screen, or the next time the app is opened.
 *
 * Token (private repos): the watch's own read-only `watch-<repo>` token,
 * given once over adb ([TokenReceiver]); kept in this app's private
 * preferences, sent only to api.github.com.
 */
object WatchUpdater {
    private const val TAG = "WatchUpdater"
    private const val PREFS = "watch_update"
    private const val KEY_TOKEN = "token"
    private const val KEY_CHECKED = "checked_at"
    private const val KEY_STATUS = "status"
    private const val KEY_VERSION = "version"
    private const val KEY_INSTALLING = "installing_build"
    private const val API = "https://api.github.com"
    const val ACTION_INSTALLED = "com.mfficiency.best_todo_2.wear.update.INSTALL_RESULT"

    private val lock = Mutex()
    private val _state = MutableStateFlow(UpdateState(UpdateStatus.IDLE))
    val state: StateFlow<UpdateState> = _state.asStateFlow()

    /** True while the screen shows: a confirmation is opened right away. */
    @Volatile
    var visible = false

    fun repo(context: Context): String = context.getString(R.string.update_repo).trim()

    /** On every app start: the saved state, and an install that has finished. */
    fun load(context: Context) {
        if (lock.isLocked) return
        val p = prefs(context)
        val installing = p.getLong(KEY_INSTALLING, 0L)
        if (installing in 1..BuildConfig.VERSION_CODE.toLong()) {
            p.edit().remove(KEY_INSTALLING).putString(KEY_STATUS, UpdateStatus.UP_TO_DATE.name).apply()
            downloads(context).deleteRecursively()
        }
        val status = p.getString(KEY_STATUS, null)?.let { s -> UpdateStatus.entries.firstOrNull { it.name == s } }
        val shown = when (status) {
            null, UpdateStatus.CHECKING, UpdateStatus.DOWNLOADING, UpdateStatus.INSTALLING -> UpdateStatus.IDLE
            else -> status
        }
        _state.value = UpdateState(shown, p.getString(KEY_VERSION, "") ?: "", p.getLong(KEY_CHECKED, 0L))
    }

    fun setToken(context: Context, token: String?) {
        val p = prefs(context).edit()
        if (token.isNullOrBlank()) p.remove(KEY_TOKEN) else p.putString(KEY_TOKEN, token.trim())
        p.apply()
    }

    fun hasToken(context: Context): Boolean = !prefs(context).getString(KEY_TOKEN, null).isNullOrEmpty()

    /** Older than [hours]: the app checks when it is opened. */
    fun due(context: Context, hours: Long = 24): Boolean =
        System.currentTimeMillis() - prefs(context).getLong(KEY_CHECKED, 0L) > hours * 3_600_000L

    /**
     * Check, download and install. Never twice at once. Returns false only
     * when it should be tried again later (network, GitHub).
     */
    suspend fun run(context: Context): Boolean {
        val app = context.applicationContext
        if (lock.isLocked) return true
        return lock.withLock { withContext(Dispatchers.IO) { runLocked(app) } }
    }

    private fun runLocked(context: Context): Boolean {
        val repo = repo(context)
        if (repo.isEmpty()) return finish(context, UpdateStatus.NOT_CONFIGURED, checked = false)
        set(context, UpdateStatus.CHECKING)
        val release = try {
            val json = get(context, "$API/repos/$repo/releases?per_page=40").use { it.inputStream.readBytes() }
            WatchUpdate.pick(String(json, Charsets.UTF_8), BuildConfig.VERSION_CODE.toLong(), prereleases(context))
        } catch (e: IOException) {
            Log.w(TAG, "check failed: ${e.javaClass.simpleName} ${e.message}")
            return finish(context, UpdateStatus.FAILED, checked = false, ok = false)
        }
        if (release == null) return finish(context, UpdateStatus.UP_TO_DATE)
        if (!context.packageManager.canRequestPackageInstalls()) {
            return finish(context, UpdateStatus.NO_PERMISSION, version = release.version)
        }
        val apk = try {
            download(context, release)
        } catch (e: IOException) {
            Log.w(TAG, "download failed: ${e.javaClass.simpleName} ${e.message}")
            return finish(context, UpdateStatus.FAILED, version = release.version, ok = false)
        }
        if (!isThisApp(context, apk, release.build)) {
            apk.delete()
            Log.w(TAG, "downloaded APK is not ${context.packageName} build ${release.build}")
            return finish(context, UpdateStatus.FAILED, version = release.version)
        }
        return try {
            install(context, apk, release)
            true
        } catch (e: Exception) {
            Log.w(TAG, "install failed: ${e.javaClass.simpleName} ${e.message}")
            finish(context, UpdateStatus.FAILED, version = release.version)
        }
    }

    private fun download(context: Context, release: WatchRelease): File {
        val dir = downloads(context).apply { mkdirs() }
        val target = File(dir, "${release.build}.apk")
        if (target.exists() && (release.size <= 0 || target.length() == release.size)) return target
        dir.listFiles()?.forEach { it.delete() }
        set(context, UpdateStatus.DOWNLOADING, release.version)
        val part = File(dir, "${release.build}.apk.part")
        get(context, release.assetUrl, accept = "application/octet-stream").use { c ->
            c.inputStream.use { input -> part.outputStream().use { input.copyTo(it) } }
        }
        if (release.size > 0 && part.length() != release.size) throw IOException("incomplete: ${part.length()} of ${release.size}")
        if (!part.renameTo(target)) throw IOException("rename failed")
        return target
    }

    @Suppress("DEPRECATION")
    private fun isThisApp(context: Context, apk: File, build: Long): Boolean {
        val info = context.packageManager.getPackageArchiveInfo(apk.path, 0) ?: return false
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return info.packageName == context.packageName && code == build
    }

    private fun install(context: Context, apk: File, release: WatchRelease) {
        set(context, UpdateStatus.INSTALLING, release.version)
        prefs(context).edit().putLong(KEY_INSTALLING, release.build).apply()
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(context.packageName)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            apk.inputStream().use { input ->
                session.openWrite("base.apk", 0, apk.length()).use { out ->
                    input.copyTo(out)
                    session.fsync(out)
                }
            }
            val intent = Intent(context, InstallResultReceiver::class.java).setAction(ACTION_INSTALLED)
            // Mutable: the installer adds the status (and the confirmation) to it.
            val pending = PendingIntent.getBroadcast(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            // This app is replaced now (the process ends) unless Android asks first.
            session.commit(pending.intentSender)
        }
    }

    /** From [InstallResultReceiver]. */
    internal fun onInstallResult(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                prefs(context).edit().remove(KEY_INSTALLING).apply()
                set(context, UpdateStatus.CONFIRM, state.value.version)
                if (visible && confirm != null) {
                    context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
            PackageInstaller.STATUS_SUCCESS -> set(context, UpdateStatus.UP_TO_DATE)
            else -> {
                Log.w(TAG, "install status $status: ${intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)}")
                prefs(context).edit().remove(KEY_INSTALLING).apply()
                set(context, UpdateStatus.FAILED, state.value.version)
            }
        }
    }

    /** GET with the token (if any). GitHub's asset links redirect to a signed URL: followed without it. */
    private fun get(context: Context, url: String, accept: String = "application/vnd.github+json"): Response {
        var target = URL(url)
        val token = prefs(context).getString(KEY_TOKEN, null)
        repeat(5) {
            val c = (target.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 20_000
                readTimeout = 60_000
                setRequestProperty("Accept", accept)
                setRequestProperty("User-Agent", "${context.packageName}-watch-update")
                if (!token.isNullOrEmpty() && target.host == "api.github.com") {
                    setRequestProperty("Authorization", "Bearer $token")
                }
            }
            when (val code = c.responseCode) {
                in 200..299 -> return Response(c)
                301, 302, 303, 307, 308 -> {
                    val next = c.getHeaderField("Location") ?: throw IOException("redirect without Location")
                    c.disconnect()
                    target = URL(target, next)
                }
                else -> {
                    c.disconnect()
                    throw IOException("HTTP $code for ${target.host}${target.path}")
                }
            }
        }
        throw IOException("too many redirects")
    }

    private class Response(private val c: HttpURLConnection) : AutoCloseable {
        val inputStream get() = c.inputStream
        override fun close() = c.disconnect()
    }

    private fun finish(
        context: Context,
        status: UpdateStatus,
        version: String = "",
        checked: Boolean = true,
        ok: Boolean = true,
    ): Boolean {
        if (checked) prefs(context).edit().putLong(KEY_CHECKED, System.currentTimeMillis()).apply()
        set(context, status, version)
        return ok
    }

    private fun set(context: Context, status: UpdateStatus, version: String = "") {
        val p = prefs(context)
        p.edit().putString(KEY_STATUS, status.name).putString(KEY_VERSION, version).apply()
        _state.value = UpdateState(status, version, p.getLong(KEY_CHECKED, 0L))
    }

    private fun prereleases(context: Context): Boolean = context.resources.getBoolean(R.bool.update_prereleases)

    private fun downloads(context: Context) = File(context.cacheDir, "updates")

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
