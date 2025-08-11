package com.example.best_todo_2

import android.content.Context
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

class TodayWidgetFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var tasks: List<String> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        tasks = loadTasks()
    }

    override fun onDestroy() {}

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.today_widget_list_item)
        rv.setTextViewText(R.id.widget_item_text, tasks[position])
        return rv
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun loadTasks(): List<String> {
        val file = File(context.filesDir, "tasks.json")
        if (!file.exists()) return emptyList()
        return try {
            val json = JSONArray(file.readText())
            val today = LocalDate.now()
            val result = mutableListOf<String>()
            for (i in 0 until json.length()) {
                val obj = json.getJSONObject(i)
                val dueDateStr = obj.optString("dueDate", null)
                if (dueDateStr != null) {
                    val zdt = ZonedDateTime.parse(dueDateStr)
                    val date = zdt.withZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
                    if (!date.isAfter(today)) {
                        result.add(obj.getString("title"))
                    }
                }
            }
            result
        } catch (e: Exception) {
            emptyList()
        }
    }
}
