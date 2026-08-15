package com.mfficiency.best_todo_2

import android.app.Application
import android.os.Process

/**
 * Exists only to timestamp the birth of the app's process.
 *
 * The first field capture of the widget-tap black screen contained a 45-second
 * hole: the user tapped the widget, got a black screen, force-closed, and not
 * one line was written by either side in between. That hole has two very
 * different explanations — the tap never reached the app at all (nothing
 * starts), or a process starts and dies before Flutter can log anything — and
 * `Application.onCreate` is the earliest point the app's own code runs, so a
 * line here separates them. If a black screen shows no `process start` line,
 * the failure is in front of the app; if it shows one with no `onCreate`
 * after it, the failure is between the process and the activity.
 *
 * Plain `android.app.Application`: the v2 embedding (`flutterEmbedding=2` in
 * the manifest) needs no Flutter-specific base class.
 */
class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        DiagLog.write(this, "native", "process start pid=${Process.myPid()}")
    }
}
