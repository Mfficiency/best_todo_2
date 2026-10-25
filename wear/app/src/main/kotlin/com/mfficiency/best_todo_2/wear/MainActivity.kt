package com.mfficiency.best_todo_2.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.mfficiency.best_todo_2.wear.update.UpdateStatus
import com.mfficiency.best_todo_2.wear.update.UpdateWorker
import com.mfficiency.best_todo_2.wear.update.WatchUpdater
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The watch's only activity. Syncs only while started; also keeps the daily
 * update check scheduled, and checks when opened if the last check is a day
 * old (or an update waits for a tap). README.md › Updates.
 */
class MainActivity : ComponentActivity() {
    private val viewModel: TodoViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WatchUpdater.load(applicationContext)
        UpdateWorker.schedule(applicationContext)
        setContent { TodoWearApp(viewModel, onCheckUpdates = ::checkUpdates) }
        // Data Layer listener + a connection check every 30 s, only while the
        // activity is started (screen on, app in front). Nothing runs after.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.onStart()
                try {
                    while (true) {
                        delay(CHECK_EVERY_MS)
                        viewModel.checkConnection()
                    }
                } finally {
                    viewModel.onStop()
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        WatchUpdater.visible = true
        val waiting = WatchUpdater.state.value.status == UpdateStatus.CONFIRM
        if (waiting || WatchUpdater.due(applicationContext)) checkUpdates()
    }

    override fun onStop() {
        WatchUpdater.visible = false
        super.onStop()
    }

    private fun checkUpdates() {
        lifecycleScope.launch { WatchUpdater.run(applicationContext) }
    }

    private companion object {
        const val CHECK_EVERY_MS = 30_000L
    }
}
