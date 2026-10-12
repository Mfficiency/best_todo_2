package ch.mfficiency.updates

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Shares a downloaded update APK (cache/updates/, written by the Dart side)
 * with Android's installer app as a read-only content:// URI; file:// URIs
 * are refused since Android 7. A few lines instead of androidx.core's
 * FileProvider, so no extra Gradle dependency.
 */
class ApkProvider : ContentProvider() {
    companion object {
        const val MIME = "application/vnd.android.package-archive"

        fun dir(context: Context) = File(context.cacheDir, "updates")

        fun uriFor(context: Context, file: File): Uri = Uri.Builder()
            .scheme("content")
            .authority("${context.packageName}.mfficiency_updates.apk")
            .appendPath(file.name)
            .build()

        /** True for a plain file directly in cache/updates/, the only ones shared. */
        fun serves(context: Context, file: File): Boolean =
            file.isFile && file.canonicalFile.parentFile == dir(context).canonicalFile
    }

    private fun fileFor(uri: Uri): File {
        val file = File(dir(context!!), uri.lastPathSegment ?: throw FileNotFoundException())
        if (!serves(context!!, file)) throw FileNotFoundException()
        return file
    }

    override fun onCreate() = true

    override fun getType(uri: Uri) = MIME

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)

    /** Name and size, which some installers ask for before reading. */
    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fileFor(uri)
        return MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
            .apply { addRow(arrayOf<Any>(file.name, file.length())) }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
