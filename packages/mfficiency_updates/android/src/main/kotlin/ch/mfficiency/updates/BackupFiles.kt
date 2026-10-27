package ch.mfficiency.updates

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Full backups in the public Downloads folder (`Download/<folder>/`), where
 * they stay when the app is uninstalled: MediaStore on Android 10+, the
 * plain folder (storage permission) before.
 */
object BackupFiles {
    class NoStorage : Exception()

    /** Copies [source] to `Download/<folder>/<name>`, keeps the newest [keep]; returns that path. */
    fun save(context: Context, source: File, folder: String, name: String, keep: Int): String {
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/$folder"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = context.contentResolver
            val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/gzip")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$relative/")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(collection, values) ?: throw IllegalStateException("insert failed")
            try {
                resolver.openOutputStream(uri)!!.use { out -> source.inputStream().use { it.copyTo(out) } }
                resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            prune(context, "$relative/", keep)
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), folder)
            try {
                dir.mkdirs()
                source.copyTo(File(dir, name), overwrite = true)
            } catch (e: Exception) {
                throw NoStorage()
            }
            dir.listFiles { f -> f.name.endsWith(".tar.gz") }
                ?.sortedByDescending { it.lastModified() }
                ?.drop(keep)
                ?.forEach { it.delete() }
        }
        return "$relative/$name"
    }

    /** Deletes this install's backups in [relative] beyond the newest [keep] (others' aren't visible). */
    private fun prune(context: Context, relative: String, keep: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val ids = mutableListOf<Long>()
        resolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(relative),
            "${MediaStore.MediaColumns.DATE_ADDED} DESC",
        )?.use { c ->
            while (c.moveToNext()) {
                if (c.getString(1)?.endsWith(".tar.gz") == true) ids.add(c.getLong(0))
            }
        }
        for (id in ids.drop(keep)) {
            try {
                resolver.delete(Uri.withAppendedPath(collection, id.toString()), null, null)
            } catch (e: Exception) {
                // Not this install's any more; leave it.
            }
        }
    }

    /** The picker for a backup file, starting in Downloads. */
    fun pickIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = "*/*"
        putExtra(
            Intent.EXTRA_MIME_TYPES,
            arrayOf("application/gzip", "application/x-gzip", "application/x-tar", "application/octet-stream"),
        )
    }

    /** Copies the picked [uri] into the cache; its path. */
    fun copyPicked(context: Context, uri: Uri): String {
        val dir = File(context.cacheDir, "mfficiency_picked").apply { deleteRecursively(); mkdirs() }
        val target = File(dir, "backup.tar.gz")
        context.contentResolver.openInputStream(uri)!!.use { input -> target.outputStream().use { input.copyTo(it) } }
        return target.path
    }

    /** Starts the app's launcher activity in a new task and ends this process. */
    fun restart(context: Context) {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(intent)
        Runtime.getRuntime().exit(0)
    }
}
