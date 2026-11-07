package com.mfficiency.best_todo_2.wear.core

import org.json.JSONArray

/** A watch build on GitHub: release `wear-<phone tag>`, asset `<App>-Watch-<x.y.z>-<build>[-channel].apk`. */
data class WatchRelease(
    val version: String,
    val build: Long,
    val channel: String,
    val tag: String,
    /** The asset's API url (`…/releases/assets/<id>`): downloads public and private alike. */
    val assetUrl: String,
    val size: Long,
)

/**
 * Picks the watch update from the GitHub Releases list (laptop builder,
 * tool/build.ps1 Invoke-WearBuild). The same rule as the phone's updater:
 * the highest build number wins, whatever its version or channel; equal
 * numbers prefer main, then staging, then dev.
 */
object WatchUpdate {
    private val ASSET = Regex("""-Watch-(\d+\.\d+\.\d+)[-+](\d+)(?:-([a-z]+))?\.apk$""")
    private val CHANNELS = listOf("main", "staging", "dev")

    /** Every watch build in [json] (`GET /repos/{repo}/releases`); never drafts. */
    fun releases(json: String, prereleases: Boolean = true): List<WatchRelease> {
        val array = try {
            JSONArray(json)
        } catch (e: Exception) {
            return emptyList()
        }
        val found = mutableListOf<WatchRelease>()
        for (i in 0 until array.length()) {
            val r = array.optJSONObject(i) ?: continue
            val tag = r.optString("tag_name", "")
            if (!tag.startsWith("wear-") || r.optBoolean("draft")) continue
            if (!prereleases && r.optBoolean("prerelease")) continue
            val assets = r.optJSONArray("assets") ?: continue
            for (j in 0 until assets.length()) {
                val a = assets.optJSONObject(j) ?: continue
                val m = ASSET.find(a.optString("name", "")) ?: continue
                val url = a.optString("url", "")
                if (url.isEmpty()) continue
                found.add(
                    WatchRelease(
                        version = m.groupValues[1],
                        build = m.groupValues[2].toLongOrNull() ?: continue,
                        channel = m.groupValues[3].ifEmpty { "main" },
                        tag = tag,
                        assetUrl = url,
                        size = a.optLong("size", 0L),
                    ),
                )
                break
            }
        }
        return found
    }

    /** The build to install over [running] (the running versionCode), or null. */
    fun pick(json: String, running: Long, prereleases: Boolean = true): WatchRelease? =
        releases(json, prereleases)
            .filter { it.build > running }
            .sortedWith(compareByDescending<WatchRelease> { it.build }.thenBy { rank(it.channel) })
            .firstOrNull()

    private fun rank(channel: String): Int = CHANNELS.indexOf(channel).let { if (it < 0) CHANNELS.size else it }
}
