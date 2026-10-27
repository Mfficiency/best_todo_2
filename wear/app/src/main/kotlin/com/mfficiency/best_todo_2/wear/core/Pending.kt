package com.mfficiency.best_todo_2.wear.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * A "done" tap on the watch that the phone's list doesn't show yet. The row
 * shows as done until the phone publishes a list newer than the tap (then the
 * phone's state wins). Not delivered (phone not reachable) = sent again on
 * the next refresh; completing is idempotent on the phone, so a repeat is
 * harmless.
 */
data class PendingDone(val id: String, val at: Long, val delivered: Boolean)

object Pending {
    /** Taps older than this are dropped, delivered or not. */
    const val MAX_AGE_MS = 24L * 60 * 60 * 1000

    fun add(list: List<PendingDone>, id: String, now: Long): List<PendingDone> =
        list.filter { it.id != id } + PendingDone(id, now, delivered = false)

    fun markDelivered(list: List<PendingDone>, id: String): List<PendingDone> =
        list.map { if (it.id == id) it.copy(delivered = true) else it }

    /**
     * What is still pending after the phone published a list at [publishedAt]
     * (null = no list yet): delivered taps older than that list are settled
     * (the list already reflects them), and anything older than [MAX_AGE_MS].
     */
    fun prune(list: List<PendingDone>, publishedAt: Long?, now: Long): List<PendingDone> =
        list.filter { p ->
            now - p.at < MAX_AGE_MS &&
                !(p.delivered && publishedAt != null && publishedAt > p.at)
        }

    fun undelivered(list: List<PendingDone>): List<PendingDone> = list.filter { !it.delivered }

    /** [rows] with every pending id shown as done. */
    fun applyTo(rows: List<TaskRow>, list: List<PendingDone>): List<TaskRow> {
        if (list.isEmpty()) return rows
        val ids = list.map { it.id }.toSet()
        return rows.map { if (!it.done && it.id in ids) it.copy(done = true) else it }
    }

    fun toJson(list: List<PendingDone>): String {
        val a = JSONArray()
        for (p in list) {
            val o = JSONObject()
            o.put("id", p.id)
            o.put("at", p.at)
            o.put("delivered", p.delivered)
            a.put(o)
        }
        return a.toString()
    }

    fun fromJson(json: String?): List<PendingDone> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val a = JSONArray(json)
            val out = ArrayList<PendingDone>()
            for (i in 0 until a.length()) {
                val o = a.optJSONObject(i) ?: continue
                val id = o.optString("id", "")
                if (id.isEmpty()) continue
                out.add(PendingDone(id, o.optLong("at", 0L), o.optBoolean("delivered", false)))
            }
            out
        } catch (e: Exception) {
            emptyList()
        }
    }
}
