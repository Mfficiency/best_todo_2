package com.mfficiency.best_todo_2

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Trampoline behind the app's share-sheet entry: receives ACTION_SEND text
 * (links, selected text, email addresses, ...) and forwards it to
 * [MainActivity] in the app's own task, then finishes immediately.
 *
 * Deliberately NOT a FlutterActivity and not MainActivity itself: the share
 * sheet starts its target inside the *sharing* app's task, and a second
 * MainActivity there means a second Flutter engine — the known
 * black-screen failure mode the manifest comments on MainActivity warn
 * about. Launching MainActivity explicitly with NEW_TASK re-fronts the one
 * existing app task (or cold-starts it) instead, and singleTop delivers the
 * text via onNewIntent.
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val shared = extractSharedText(intent)
        if (shared != null) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = ACTION_SHARED_TEXT
                    putExtra(EXTRA_SHARED_TEXT, shared)
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

    companion object {
        const val ACTION_SHARED_TEXT = "com.mfficiency.best_todo_2.SHARED_TEXT"
        const val EXTRA_SHARED_TEXT = "shared_text"
    }
}
