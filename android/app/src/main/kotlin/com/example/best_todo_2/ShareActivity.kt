package com.mfficiency.best_todo_2

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID

/**
 * Trampoline behind the app's share-sheet entry: receives an ACTION_SEND(_MULTIPLE)
 * intent (text/links/email addresses, images, PDFs) and forwards it to
 * [MainActivity] in the app's own task, then finishes immediately.
 *
 * Any shared file is copied into this app's cache dir before forwarding: the
 * `content://` URI's read grant is scoped to *this* activity, and dies the
 * moment it finishes — passing the URI itself to MainActivity would leave it
 * unreadable by the time the Dart side gets to it.
 *
 * Deliberately NOT a FlutterActivity and not MainActivity itself: the share
 * sheet starts its target inside the *sharing* app's task, and a second
 * MainActivity there would mean a second Flutter engine. Launching
 * MainActivity explicitly with NEW_TASK re-fronts the one existing app task
 * (or cold-starts it) instead, and singleTop delivers the content via
 * onNewIntent.
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = extractSharedText(intent)
        val files = extractSharedFiles(intent)
        if (text != null || files.isNotEmpty()) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = ACTION_SHARED_CONTENT
                    putExtra(EXTRA_SHARED_TEXT, text)
                    putStringArrayListExtra(EXTRA_SHARED_FILE_PATHS, ArrayList(files.map { it.first }))
                    putStringArrayListExtra(EXTRA_SHARED_FILE_MIME_TYPES, ArrayList(files.map { it.second }))
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
        finish()
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
        // Browsers put the page title in EXTRA_SUBJECT and the URL in
        // EXTRA_TEXT; keep both when the subject adds information.
        val combined = when {
            text.isEmpty() -> subject
            subject.isEmpty() || text.contains(subject) -> text
            else -> "$subject\n$text"
        }
        return combined.ifEmpty { null }
    }

    // Copies every EXTRA_STREAM uri (single SEND or SEND_MULTIPLE) into
    // cacheDir/shared_incoming/, returning (absolute path, mime type) pairs.
    // Best-effort per file: one unreadable stream doesn't drop the rest.
    @Suppress("DEPRECATION")
    private fun extractSharedFiles(intent: Intent?): List<Pair<String, String>> {
        val uris: List<Uri> = when (intent?.action) {
            Intent.ACTION_SEND ->
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { listOf(it) } ?: emptyList()
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            else -> emptyList()
        }
        if (uris.isEmpty()) return emptyList()
        val dir = File(cacheDir, "shared_incoming").apply { mkdirs() }
        return uris.mapNotNull { uri -> copyToCache(uri, dir) }
    }

    private fun copyToCache(uri: Uri, dir: File): Pair<String, String>? {
        return try {
            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
                ?: displayName(uri)?.substringAfterLast('.', "")
                ?: ""
            val name = displayName(uri) ?: "${UUID.randomUUID()}${if (ext.isEmpty()) "" else ".$ext"}"
            val dest = File(dir, "${UUID.randomUUID()}_$name")
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            dest.absolutePath to mimeType
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else null
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        const val ACTION_SHARED_CONTENT = "com.mfficiency.best_todo_2.SHARED_CONTENT"
        const val EXTRA_SHARED_TEXT = "shared_text"
        const val EXTRA_SHARED_FILE_PATHS = "shared_file_paths"
        const val EXTRA_SHARED_FILE_MIME_TYPES = "shared_file_mime_types"
    }
}
