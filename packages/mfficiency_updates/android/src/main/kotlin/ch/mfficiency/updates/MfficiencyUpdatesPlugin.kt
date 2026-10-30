package ch.mfficiency.updates

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * The native side of in-app updates (channel `mfficiency_updates`):
 * installs a downloaded APK through [ApkInstaller], the one-time "install
 * unknown apps" switch, when this build was installed, and the files of the
 * full backups ([BackupFiles]). The app's MainActivity needs nothing for it.
 */
class MfficiencyUpdatesPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var pickResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mfficiency_updates")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attach(binding)

    override fun onDetachedFromActivityForConfigChanges() = detach()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attach(binding)

    override fun onDetachedFromActivity() = detach()

    private fun attach(b: ActivityPluginBinding) {
        activity = b.activity
        binding = b
        b.addActivityResultListener(this)
    }

    private fun detach() {
        binding?.removeActivityResultListener(this)
        binding = null
        activity = null
    }

    /** The backup file picked in [pickFile], copied into the cache. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST) return false
        val result = pickResult ?: return true
        pickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        Thread {
            val path = try {
                BackupFiles.copyPicked(context, uri)
            } catch (e: Exception) {
                Log.w("BackupFiles", "copy failed", e)
                null
            }
            main.post { result.success(path) }
        }.start()
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "installApk" -> installApk(call.argument<String>("path")!!, result)
                "canInstallApks" -> result.success(canInstallApks())
                "openInstallSettings" -> result.success(openInstallSettings())
                "installTime" -> result.success(installTime())
                "appId" -> result.success(context.packageName)
                "packageInfo" -> result.success(packageInfo(call.argument<String>("id")!!))
                "launchApp" -> result.success(launchApp(call.argument<String>("id")!!))
                "saveToDownloads" -> saveToDownloads(call, result)
                "pickFile" -> pickFile(result)
                "restartApp" -> {
                    result.success(null)
                    main.postDelayed({ BackupFiles.restart(context) }, 150)
                }
                "openUrl" -> result.success(
                    start(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!))),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("native_error", e.javaClass.simpleName, null)
        }
    }

    /**
     * Installs a downloaded update APK. Android's installer app asks "Update
     * this app?" and, when done, shows "App updated" with Open, so the user
     * can go straight back into the app ([openInstaller]). Where no installer
     * app takes it, a PackageInstaller session ([ApkInstaller]) asks the same
     * question without the Open step. Without the one-time "install unknown
     * apps" permission it opens that switch for this app instead and answers
     * "needs-permission".
     */
    private fun installApk(path: String, result: MethodChannel.Result) {
        if (!canInstallApks()) {
            openInstallSettings()
            result.success("needs-permission")
            return
        }
        if (openInstaller(File(path))) {
            result.success("ok")
            return
        }
        Thread {
            val outcome = try {
                ApkInstaller.install(context, File(path))
                "ok"
            } catch (e: Exception) {
                Log.w("ApkInstaller", "install failed", e)
                "failed"
            }
            main.post { result.success(outcome) }
        }.start()
    }

    /**
     * Hands the APK to Android's installer app (the one that handles
     * ACTION_INSTALL_PACKAGE, addressed directly, so never a chooser, a file
     * manager or a browser) through [ApkProvider]. False when there is none
     * or the file isn't in cache/updates/; the caller then uses a session.
     */
    private fun openInstaller(file: File): Boolean {
        if (!ApkProvider.serves(context, file)) return false
        @Suppress("DEPRECATION")
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE)
            .setDataAndType(ApkProvider.uriFor(context, file), ApkProvider.MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val installer = intent.resolveActivity(context.packageManager) ?: return false
        intent.component = installer
        return start(intent)
    }

    /** Copies a finished backup to Downloads, off the main thread. */
    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")!!
        val folder = call.argument<String>("folder")!!
        val name = call.argument<String>("name")!!
        val keep = call.argument<Int>("keep") ?: 10
        Thread {
            try {
                val where = BackupFiles.save(context, File(path), folder, name, keep)
                main.post { result.success(where) }
            } catch (e: BackupFiles.NoStorage) {
                main.post { result.error("no-storage", "storage permission needed", null) }
            } catch (e: Exception) {
                Log.w("BackupFiles", "save failed", e)
                main.post { result.error("failed", e.javaClass.simpleName, null) }
            }
        }.start()
    }

    /** Android's file picker; answers the copied file's path, or null. */
    private fun pickFile(result: MethodChannel.Result) {
        val a = activity
        if (a == null) {
            result.success(null)
            return
        }
        pickResult?.success(null)
        pickResult = result
        try {
            a.startActivityForResult(BackupFiles.pickIntent(), PICK_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pickResult = null
            result.success(null)
        }
    }

    /** True once the one-time "install unknown apps" switch is on for this app. */
    private fun canInstallApks(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    /** The "install unknown apps" switch of this app. */
    private fun openInstallSettings(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            start(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))

    /** When this version was installed or last updated (ms since epoch). */
    private fun installTime(): Long {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION") pm.getPackageInfo(context.packageName, 0)
        }
        return info.lastUpdateTime
    }

    /**
     * Another app's installed version ({versionName, versionCode}), or null
     * when it isn't installed. Android 11+ only answers for the packages the
     * manifest's <queries> lists (the Mfficiency apps, for "Other apps").
     */
    private fun packageInfo(id: String): Map<String, Any?>? = try {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(id, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION") pm.getPackageInfo(id, 0)
        }
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION") info.versionCode.toLong()
        }
        mapOf("versionName" to info.versionName, "versionCode" to code)
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    /** Opens another installed app; false when it has no launcher screen. */
    private fun launchApp(id: String): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(id) ?: return false
        return start(intent)
    }

    /** Starts an activity from the app, or as a new task without one. */
    private fun start(intent: Intent): Boolean = try {
        val a = activity
        if (a != null) {
            a.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    private companion object {
        const val PICK_REQUEST = 0x6d62
    }
}
