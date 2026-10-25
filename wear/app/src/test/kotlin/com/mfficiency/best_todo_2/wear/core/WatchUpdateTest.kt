package com.mfficiency.best_todo_2.wear.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WatchUpdateTest {
    private fun release(tag: String, asset: String, prerelease: Boolean = true, draft: Boolean = false, id: Int = 1) = """
        {"tag_name":"$tag","draft":$draft,"prerelease":$prerelease,
         "assets":[{"name":"notes.txt","url":"x"},
                   {"name":"$asset","size":2314471,"url":"https://api.github.com/repos/o/r/releases/assets/$id"}]}
    """

    private val json = "[" + listOf(
        release("v0.37.3-3584514-dev", "HallyRemote-0.37.3-3584514-dev.apk"),
        release("wear-v0.37.3-3584514-dev", "HallyRemote-Watch-0.37.3-3584514-dev.apk", id = 3),
        release("wear-v0.37.2-3583983", "HallyRemote-Watch-0.37.2-3583983.apk", prerelease = false, id = 2),
        release("wear-v0.38.0-3590000-dev", "HallyRemote-Watch-0.38.0-3590000-dev.apk", draft = true, id = 9),
        release("wear-vesta-immo-v0.1.30-b3583969-dev", "VestaImmo-Watch-0.1.30-3583969-dev.apk", id = 4),
    ).joinToString(",") + "]"

    @Test
    fun readsOnlyWatchReleasesAndNeverDrafts() {
        val all = WatchUpdate.releases(json)
        assertEquals(listOf(3584514L, 3583983L, 3583969L), all.map { it.build })
        assertEquals("dev", all[0].channel)
        assertEquals("main", all[1].channel)
        assertEquals("0.37.3", all[0].version)
        assertEquals(2314471L, all[0].size)
        assertTrue(all[0].assetUrl.endsWith("/assets/3"))
    }

    @Test
    fun picksTheHighestBuildAboveTheRunningOne() {
        assertEquals(3584514L, WatchUpdate.pick(json, 3583983L)!!.build)
        assertNull(WatchUpdate.pick(json, 3584514L))
        assertEquals(3583983L, WatchUpdate.pick(json, 1L, prereleases = false)!!.build)
    }

    @Test
    fun equalBuildsPreferMain() {
        val same = "[" + release("wear-v1.0.0-500-dev", "A-Watch-1.0.0-500-dev.apk", id = 1) + "," +
            release("wear-v1.0.0-500", "A-Watch-1.0.0-500.apk", prerelease = false, id = 2) + "]"
        assertEquals("main", WatchUpdate.pick(same, 1L)!!.channel)
    }

    @Test
    fun readsBestToDoWatchReleases() {
        // Real names of this repo's releases (tool/build.ps1 Invoke-WearBuild).
        val real = "[" + listOf(
            release("v0.2.118-3583933-dev", "best_todo_0.2.118.apk", id = 7),
            release("wear-v0.2.118-3583933-dev", "BestToDo-Watch-0.2.118-3583933-dev.apk", id = 8),
            release("wear-v0.2.117-3582419-dev", "BestToDo-Watch-0.2.117-3582419-dev.apk", id = 6),
            release("music-v1.0.0-3500000", "BestMusic-1.0.0.apk", prerelease = false, id = 5),
        ).joinToString(",") + "]"
        val pick = WatchUpdate.pick(real, 3582419L)!!
        assertEquals("0.2.118", pick.version)
        assertEquals(3583933L, pick.build)
        assertEquals("dev", pick.channel)
        assertEquals("wear-v0.2.118-3583933-dev", pick.tag)
        assertTrue(pick.assetUrl.endsWith("/assets/8"))
        assertEquals(2, WatchUpdate.releases(real).size)
    }

    @Test
    fun toleratesGarbage() {
        assertTrue(WatchUpdate.releases("not json").isEmpty())
        assertTrue(WatchUpdate.releases("{}").isEmpty())
        assertNull(WatchUpdate.pick("[{\"tag_name\":\"wear-v1\"}]", 0L))
    }
}
