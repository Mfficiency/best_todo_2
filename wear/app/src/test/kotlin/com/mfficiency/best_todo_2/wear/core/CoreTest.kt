package com.mfficiency.best_todo_2.wear.core

import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PayloadsTest {
    // What lib/services/wear_sync_service.dart's tasksPayload builds.
    private val todayJson = """
        {"v":1,"day":"2026-08-05",
         "today":[{"id":"a","title":"Open today","done":false},
                  {"id":"b","title":"  ","done":true},
                  {"title":"no id"}],
         "todayMore":3,
         "tomorrow":[{"id":"c","title":"Tomorrow","done":false}],
         "tomorrowMore":0}
    """.trimIndent()

    @Test
    fun parsesTheTodayPayload() {
        val p = Payloads.parseToday(todayJson)!!
        assertEquals("2026-08-05", p.day)
        assertEquals(listOf("a", "b"), p.today.map { it.id })
        assertEquals("(no title)", p.today[1].title)
        assertTrue(p.today[1].done)
        assertEquals(3, p.todayMore)
        assertEquals(listOf("Tomorrow"), p.tomorrow.map { it.title })
    }

    @Test
    fun badJsonIsNull() {
        assertNull(Payloads.parseToday(null))
        assertNull(Payloads.parseToday(""))
        assertNull(Payloads.parseToday("not json"))
        assertNull(Payloads.parseAlarms("[1,2"))
    }

    @Test
    fun missingListsAreEmpty() {
        val p = Payloads.parseToday("""{"v":1}""")!!
        assertTrue(p.today.isEmpty())
        assertTrue(p.tomorrow.isEmpty())
        assertEquals(0, p.todayMore)
    }

    @Test
    fun parsesAlarms() {
        val rows = Payloads.parseAlarms(
            """{"v":1,"alarms":[
                {"id":"x","time":"07:00","name":"Wake","sub":"Weekdays","on":true,"next":1754370000000},
                {"id":"y","time":"06:00","name":"","sub":"Once","on":false,"next":null},
                {"time":"no id"}]}"""
        )!!
        assertEquals(listOf("x", "y"), rows.map { it.id })
        assertEquals(1754370000000L, rows[0].next)
        assertEquals("Alarm", rows[1].name)
        assertFalse(rows[1].on)
        assertNull(rows[1].next)
    }
}

class PendingTest {
    private val rows = listOf(
        TaskRow("a", "A", false),
        TaskRow("b", "B", false),
        TaskRow("c", "C", true),
    )

    @Test
    fun pendingRowsShowAsDone() {
        val pending = Pending.add(emptyList(), "a", 100)
        assertEquals(listOf(true, false, true), Pending.applyTo(rows, pending).map { it.done })
    }

    @Test
    fun aRepeatedTapKeepsOneEntry() {
        var list = Pending.add(emptyList(), "a", 100)
        list = Pending.markDelivered(list, "a")
        list = Pending.add(list, "a", 200)
        assertEquals(1, list.size)
        assertEquals(200L, list[0].at)
        assertFalse(list[0].delivered)
    }

    @Test
    fun aNewerPhoneListSettlesDeliveredTapsOnly() {
        var list = Pending.add(emptyList(), "a", 100)
        list = Pending.add(list, "b", 100)
        list = Pending.markDelivered(list, "a")
        // Older list: nothing settles.
        assertEquals(2, Pending.prune(list, 50, 150).size)
        // Newer list: the delivered tap is in it; the undelivered one stays.
        val left = Pending.prune(list, 120, 150)
        assertEquals(listOf("b"), left.map { it.id })
        assertEquals(listOf("b"), Pending.undelivered(left).map { it.id })
    }

    @Test
    fun oldTapsExpire() {
        val list = Pending.add(emptyList(), "a", 0)
        assertTrue(Pending.prune(list, null, Pending.MAX_AGE_MS + 1).isEmpty())
        assertEquals(1, Pending.prune(list, null, 1000).size)
    }

    @Test
    fun jsonRoundTrip() {
        val list = Pending.markDelivered(Pending.add(Pending.add(emptyList(), "a", 1), "b", 2), "b")
        assertEquals(list, Pending.fromJson(Pending.toJson(list)))
        assertTrue(Pending.fromJson("garbage").isEmpty())
        assertTrue(Pending.fromJson(null).isEmpty())
    }
}

class LabelsTest {
    private val zone = ZoneId.of("Europe/Brussels")
    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        ZonedDateTime.of(y, mo, d, h, mi, 0, 0, zone).toInstant().toEpochMilli()

    @Test
    fun clockAndSaved() {
        val now = at(2026, 8, 5, 15, 0)
        assertEquals("14:32", Labels.clock(at(2026, 8, 5, 14, 32), zone))
        assertEquals("14:32", Labels.savedAt(at(2026, 8, 5, 14, 32), now, zone, Locale.ENGLISH))
        assertEquals("Mon 09:05", Labels.savedAt(at(2026, 8, 3, 9, 5), now, zone, Locale.ENGLISH))
    }

    @Test
    fun connection() {
        assertEquals(Connection.CHECKING, Labels.connection(null))
        assertEquals(Connection.CONNECTED, Labels.connection(true))
        assertEquals(Connection.UNREACHABLE, Labels.connection(false))
        assertEquals(Connection.NO_APP, Labels.connection(false, anyPhone = true))
        assertEquals(Connection.CONNECTED, Labels.connection(true, anyPhone = true))
    }

    @Test
    fun staleDay() {
        val now = at(2026, 8, 5, 0, 30)
        assertFalse(Labels.isStaleDay("2026-08-05", now, zone))
        assertTrue(Labels.isStaleDay("2026-08-04", now, zone))
        assertFalse(Labels.isStaleDay("", now, zone))
    }

    @Test
    fun nextRing() {
        val now = at(2026, 8, 5, 22, 0)
        fun ring(next: Long?) = Labels.nextRing(next, now, zone, "Today", "Tomorrow", Locale.ENGLISH)
        assertEquals("Today 23:15", ring(at(2026, 8, 5, 23, 15)))
        assertEquals("Tomorrow 07:00", ring(at(2026, 8, 6, 7, 0)))
        assertEquals("Fri 07:00", ring(at(2026, 8, 7, 7, 0)))
        assertNull(ring(null))
    }
}
