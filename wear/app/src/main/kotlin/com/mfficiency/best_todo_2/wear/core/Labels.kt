package com.mfficiency.best_todo_2.wear.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

/** The connection line at the top of the main list. */
enum class Connection { CHECKING, CONNECTED, UNREACHABLE, NO_APP }

/** Small formatting/decision helpers, kept free of Android for JVM tests. */
object Labels {
    /** `HH:mm` of [millis] in [zone]. */
    fun clock(millis: Long, zone: ZoneId): String {
        val t = Instant.ofEpochMilli(millis).atZone(zone).toLocalTime()
        return String.format(Locale.ROOT, "%02d:%02d", t.hour, t.minute)
    }

    /**
     * When the data was saved, for "saved …": `HH:mm` on the same day as
     * [now], else `EEE HH:mm` (e.g. "Mon 14:32").
     */
    fun savedAt(millis: Long, now: Long, zone: ZoneId, locale: Locale = Locale.getDefault()): String {
        val at = Instant.ofEpochMilli(millis).atZone(zone)
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val time = clock(millis, zone)
        return if (at.toLocalDate() == today) {
            time
        } else {
            at.dayOfWeek.getDisplayName(TextStyle.SHORT, locale) + " " + time
        }
    }

    /**
     * The status line's kind: [Connection.CHECKING] until the first check;
     * then whether a phone with BestToDo's `todo_phone` capability is
     * reachable ([capable]); a connected phone without it ([anyPhone]) has a
     * BestToDo too old for the watch (or none).
     */
    fun connection(capable: Boolean?, anyPhone: Boolean = false): Connection = when {
        capable == null -> Connection.CHECKING
        capable -> Connection.CONNECTED
        anyPhone -> Connection.NO_APP
        else -> Connection.UNREACHABLE
    }

    /**
     * Whether a today list built on [day] (`yyyy-MM-dd`, the phone's date) is
     * from an earlier day than [now] (the list may be out of date then).
     */
    fun isStaleDay(day: String, now: Long, zone: ZoneId): Boolean {
        val built = try {
            LocalDate.parse(day)
        } catch (e: Exception) {
            return false
        }
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        return built.isBefore(today)
    }

    /**
     * An alarm's next ring time: "Today 07:00", "Tomorrow 07:00" or
     * "Tue 07:00"; null when it doesn't ring.
     */
    fun nextRing(
        next: Long?,
        now: Long,
        zone: ZoneId,
        todayWord: String,
        tomorrowWord: String,
        locale: Locale = Locale.getDefault(),
    ): String? {
        if (next == null) return null
        val at = Instant.ofEpochMilli(next).atZone(zone)
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val days = ChronoUnit.DAYS.between(today, at.toLocalDate())
        val time = clock(next, zone)
        return when (days) {
            0L -> "$todayWord $time"
            1L -> "$tomorrowWord $time"
            else -> at.dayOfWeek.getDisplayName(TextStyle.SHORT, locale) + " " + time
        }
    }
}
