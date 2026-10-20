package com.mknoon.app.call

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonCallOngoingNotificationHandoverTest {
    @Test
    fun `deferred OS acceptance cannot retire incoming 504 first`() {
        val f = Fixture()
        assertTrue(f.start())
        assertEquals("504 must survive until 505 is accepted", setOf(504), f.accepted)
        assertEquals(listOf(504), f.foregroundCalls)
        f.acceptOngoing()
        f.next()
        assertEquals(setOf(505), f.accepted)
        assertTrue(f.events.indexOf("accepted:505") < f.events.indexOf("autoCancel:504"))
    }

    @Test
    fun `accepted pending record is not a SystemUI drawn-frame acknowledgment`() {
        // Model the AOSP app-active API including enqueued records. A real
        // SystemUI frame is deliberately separate from OS acceptance.
        val f = Fixture().also { it.autoAccept = true }
        assertTrue(f.start())
        assertEquals(setOf(505), f.accepted)
        assertTrue(f.drawn.isEmpty())
        assertEquals(listOf(504, 505), f.foregroundCalls)
    }

    @Test
    fun `missing acceptance expires without retiring incoming or polling forever`() {
        val f = Fixture()
        f.start()
        f.drain()
        assertEquals(setOf(504), f.accepted)
        assertEquals(listOf(504), f.foregroundCalls)
        assertTrue(f.queued.isEmpty())
        f.acceptOngoing()
        f.drain()
        assertTrue(504 in f.accepted)
    }

    @Test
    fun `successor admitted during observation cannot lose its 504`() {
        val f = Fixture().also {
            it.autoAccept = true
            it.onQuery = { it.owner = "successor" }
        }
        f.start()
        assertTrue(504 in f.accepted)
        assertEquals(listOf(504), f.foregroundCalls)
        assertFalse(f.events.any { it.startsWith("cancel:") || it.startsWith("autoCancel:") })
    }

    @Test
    fun `newer same-call mode and destroyed service reject a late acceptance`() {
        for (destroy in listOf(false, true)) {
            val f = Fixture()
            f.start()
            if (destroy) f.closed = true else f.generation += 1
            f.acceptOngoing()
            f.drain()
            assertTrue(504 in f.accepted)
            assertEquals(listOf(504), f.foregroundCalls)
        }
    }

    @Test
    fun `query or owned-commit delay beyond the deadline remains fail closed`() {
        for (delayAtCommit in listOf(false, true)) {
            val f = Fixture().also { it.autoAccept = true }
            f.onQuery = {
                if (delayAtCommit) f.beforeOwnedEffect = { f.now += 10_000 }
                else f.now += 10_000
            }
            f.start()
            f.drain()
            assertTrue(504 in f.accepted)
            assertEquals(listOf(504), f.foregroundCalls)
        }
    }

    @Test
    fun `failed post query or scheduler preserves the configured foreground`() {
        for (failure in listOf("post", "query", "schedule")) {
            val f = Fixture().also { it.failure = failure }
            assertTrue(f.start())
            f.drain()
            assertEquals(setOf(504), f.accepted)
            assertEquals(listOf(504), f.foregroundCalls)
        }
    }

    @Test
    fun `refused initial foreground propagates but refused final switch keeps 504`() {
        val initial = Fixture().also { it.refuseForeground = 504 }
        assertThrows(IllegalStateException::class.java) { initial.start() }
        assertEquals(setOf(504), initial.accepted)
        assertEquals(0, initial.postRequests)
        val finalAttempt = Fixture().also { it.autoAccept = true; it.refuseForeground = 505 }
        assertTrue(finalAttempt.start())
        assertTrue(504 in finalAttempt.accepted)
        assertFalse(finalAttempt.events.any { it.startsWith("cancel:") || it.startsWith("autoCancel:") })
    }

    @Test
    fun `ongoing refresh keeps 505 foreground and retains projected 504 until fresh acceptance`() {
        val f = Fixture(foregroundId = 505)
        f.start()
        assertEquals(listOf(505), f.foregroundCalls)
        assertTrue(504 in f.accepted)
        f.acceptOngoing()
        f.drain()
        assertEquals(setOf(505), f.accepted)
        assertFalse(f.foregroundCalls.contains(504))
    }

    @Test
    fun `inactive owner never configures a stale foreground request`() {
        val f = Fixture().also { it.closed = true }
        assertFalse(f.start())
        assertTrue(f.foregroundCalls.isEmpty())
        assertEquals(0, f.postRequests)
    }

    @Test
    fun `active and inactive calls both use the bounded handover owner`() {
        val source = File("src/main/kotlin/com/mknoon/app/call/MknoonCallAndroidRuntime.kt").readText()
        val active = source.substringAfter("override fun startActive(").substringBefore("override fun startInactive(")
        val inactive = source.substringAfter("override fun startInactive(").substringBefore("private fun beginOngoingNotificationHandover(")
        for ((name, body) in listOf("startActive" to active, "startInactive" to inactive)) {
            assertEquals("$name uses the same handover", 1,
                Regex("beginOngoingNotificationHandover\\(").findAll(body).count())
        }
        assertTrue(active.contains("withMicrophone = true"))
        assertTrue(inactive.contains("withMicrophone = false"))
    }

    private class Fixture(var foregroundId: Int = 504) {
        data class Deferred(val at: Long, val effect: () -> Unit)
        val accepted = mutableSetOf(504).also { if (foregroundId == 505) it += 505 }
        val drawn = accepted.toMutableSet()
        val foregroundCalls = mutableListOf<Int>()
        val events = mutableListOf<String>()
        val queued = mutableListOf<Deferred>()
        var now = 0L
        var owner = "current"
        var generation = 0
        var closed = false
        var autoAccept = false
        var acceptedForRequest = false
        var postRequests = 0
        var failure: String? = null
        var refuseForeground: Int? = null
        var onQuery: (() -> Unit)? = null
        var beforeOwnedEffect: (() -> Unit)? = null

        fun acceptOngoing() {
            check(postRequests > 0)
            acceptedForRequest = true
            accepted += 505
            events += "accepted:505"
        }

        fun start(): Boolean {
            val requestedOwner = owner
            val requestedGeneration = generation
            return handOverToOngoingCallNotification(
                foregroundNotificationId = foregroundId,
                startForeground = { id ->
                    if (refuseForeground == id) error("foreground refused")
                    foregroundCalls += id
                    if (foregroundId != id) {
                        accepted -= foregroundId
                        drawn -= foregroundId
                        events += "autoCancel:$foregroundId"
                    }
                    foregroundId = id
                },
                cancel = { id -> accepted -= id; drawn -= id; events += "cancel:$id" },
                postOngoing = {
                    postRequests += 1
                    if (failure == "post") error("post refused")
                    if (autoAccept) acceptOngoing()
                },
                isOngoingAccepted = {
                    if (failure == "query") error("query unavailable")
                    onQuery?.invoke()
                    acceptedForRequest
                },
                withCurrent = { effect ->
                    if (closed || requestedOwner != owner || requestedGeneration != generation) false
                    else { beforeOwnedEffect?.invoke(); effect(); true }
                },
                scheduleCheck = { delayMs, effect ->
                    if (failure == "schedule") error("scheduler unavailable")
                    queued += Deferred(now + delayMs, effect)
                },
                nowMs = { now },
            )
        }

        fun next() {
            queued.sortBy { it.at }
            val next = queued.removeAt(0)
            now = maxOf(now, next.at)
            next.effect()
        }

        fun drain() {
            var steps = 0
            while (queued.isNotEmpty()) {
                check(steps++ < 100) { "unbounded acceptance observer" }
                next()
            }
        }
    }
}
