package com.mfficiency.best_todo_2.wear.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * The phone's Data Layer payloads (lib/services/wear_sync_service.dart on the
 * phone builds them; keep both sides in step). Pure Kotlin + org.json, unit
 * tested on the JVM.
 */
object Paths {
    const val TODAY = "/todo/today"
    const val ALARMS = "/todo/alarms"
    const val COMPLETE = "/todo/command/complete"
    const val PHONE_CAPABILITY = "todo_phone"
}

data class TaskRow(val id: String, val title: String, val done: Boolean)

/** `/todo/today`: today's list as the phone's task widget shows it + tomorrow. */
data class TodayPayload(
    /** The phone's date when it built the list, `yyyy-MM-dd`. */
    val day: String,
    val today: List<TaskRow>,
    val todayMore: Int,
    val tomorrow: List<TaskRow>,
    val tomorrowMore: Int,
)

data class AlarmRow(
    val id: String,
    val time: String,
    val name: String,
    val sub: String,
    val on: Boolean,
    /** Next ring time (epoch millis), null when off or nothing ahead. */
    val next: Long?,
)

object Payloads {
    /** Null when [json] isn't a today payload. */
    fun parseToday(json: String?): TodayPayload? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            TodayPayload(
                day = o.optString("day", ""),
                today = rows(o.optJSONArray("today")),
                todayMore = o.optInt("todayMore", 0).coerceAtLeast(0),
                tomorrow = rows(o.optJSONArray("tomorrow")),
                tomorrowMore = o.optInt("tomorrowMore", 0).coerceAtLeast(0),
            )
        } catch (e: Exception) {
            null
        }
    }

    /** Null when [json] isn't an alarms payload. */
    fun parseAlarms(json: String?): List<AlarmRow>? {
        if (json.isNullOrBlank()) return null
        return try {
            val list = JSONObject(json).optJSONArray("alarms") ?: return emptyList()
            val out = ArrayList<AlarmRow>()
            for (i in 0 until list.length()) {
                val a = list.optJSONObject(i) ?: continue
                val id = a.optString("id", "")
                if (id.isEmpty()) continue
                out.add(
                    AlarmRow(
                        id = id,
                        time = a.optString("time", ""),
                        name = a.optString("name", "Alarm").ifBlank { "Alarm" },
                        sub = a.optString("sub", ""),
                        on = a.optBoolean("on", true),
                        next = if (a.isNull("next")) null else a.optLong("next", 0L).takeIf { it > 0L },
                    )
                )
            }
            out
        } catch (e: Exception) {
            null
        }
    }

    private fun rows(list: JSONArray?): List<TaskRow> {
        if (list == null) return emptyList()
        val out = ArrayList<TaskRow>()
        for (i in 0 until list.length()) {
            val r = list.optJSONObject(i) ?: continue
            val id = r.optString("id", "")
            if (id.isEmpty()) continue
            out.add(
                TaskRow(
                    id = id,
                    title = r.optString("title", "").ifBlank { "(no title)" },
                    done = r.optBoolean("done", false),
                )
            )
        }
        return out
    }
}
