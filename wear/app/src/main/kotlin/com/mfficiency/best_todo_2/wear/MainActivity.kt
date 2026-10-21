package com.mfficiency.best_todo_2.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val viewModel: TodoViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TodoWearApp(viewModel) }
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

    private companion object {
        const val CHECK_EVERY_MS = 30_000L
    }
}
