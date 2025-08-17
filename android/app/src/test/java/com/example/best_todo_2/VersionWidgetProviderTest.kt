package com.example.best_todo_2

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class VersionWidgetProviderTest {
    private lateinit var context: Context

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
    }

    @Test
    fun loadDueTasks_readsFromFallbackLocation() {
        val appFlutter = context.getDir("app_flutter", Context.MODE_PRIVATE)
        File(appFlutter, "tasks.json").delete()

        val file = File(context.filesDir, "tasks.json")
        file.writeText(
            "[{\"title\":\"Test\",\"dueDate\":\"2000-01-01T00:00:00.000\",\"isDone\":false}]"
        )

        val provider = VersionWidgetProvider()
        val result = provider.loadDueTasks(context)

        assertTrue(result.contains("Test"))
    }
}
