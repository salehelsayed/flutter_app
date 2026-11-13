package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CallPipLeaseCoreTest {
    private class FakePlatform : CallPipPlatform {
        var supported = true
        val videoTracks = mutableSetOf(CallPipSource("pc-1", "remote-v"))
        var enterAllowed = true
        val log = mutableListOf<String>()
        val live = mutableListOf<Any>()
        var autoEnter: CallPipControls? = null
        var autoLease: CallPipIdentity? = null
        var failRelease = false
        private var next = 0

        override fun supported() = supported
        override fun hasVideoTrack(source: CallPipSource) = source in videoTracks
        override fun attachSink(source: CallPipSource): Any? {
            if (source !in videoTracks) return null
            val sink = "sink-${++next}:${source.peerConnectionId}"
            live += sink
            log += "attach $sink"
            return sink
        }
        override fun releaseSink(sink: Any) {
            if (failRelease) throw IllegalStateException("release failed")
            live -= sink
            log += "release $sink"
        }
        override fun setAutoEnter(lease: CallPipIdentity?, controls: CallPipControls?) {
            autoEnter = controls
            autoLease = lease
            log += "auto ${controls != null}"
        }
        override fun requestEnter(): Boolean {
            log += "enter"
            return enterAllowed
        }
        override fun leavePip() {
            log += "leave"
        }
    }

    private val platform = FakePlatform()
    private val events = mutableListOf<Map<String, Any>>()
    private val core = CallPipLeaseCore(platform) { events += it }

    private fun id(lease: Long, instance: String = "graph-a", call: String = "call-1") =
        CallPipIdentity(instance, call, lease)
    private val source = CallPipSource("pc-1", "remote-v")
    private val controls = CallPipControls(muted = false, cameraOn = false, cameraEnabled = false)
    private fun types() = events.map { "${it["leaseId"]}:${it["seq"]}:${it["type"]}" }

    @Test
    fun `parse accepts only the exact v1 schema`() {
        val args = mapOf(
            "version" to 1, "instanceId" to "graph-a", "callId" to "call-1", "leaseId" to 3,
            "negotiationId" to "n", "mediaRevision" to 0, "rendererEpoch" to 2,
            "peerConnectionId" to "pc-1", "remoteTrackId" to "remote-v",
            "muted" to true, "cameraOn" to false, "cameraEnabled" to false,
        )
        assertEquals(id(3), CallPipIdentity.parse(args))
        assertEquals(source, CallPipSource.parse(args))
        assertEquals(CallPipControls(true, false, false), CallPipControls.parse(args))
        assertNull(CallPipIdentity.parse(args + ("version" to 2)))
        assertNull(CallPipIdentity.parse(args + ("leaseId" to 0)))
        assertNull(CallPipIdentity.parse(args + ("instanceId" to "")))
        assertNull(CallPipSource.parse(args - "peerConnectionId"))
        assertNull(CallPipSource.parse(args + ("rendererEpoch" to -1)))
        assertNull(CallPipControls.parse(args - "cameraEnabled"))
    }

    @Test
    fun `without an arm nothing is requested (gate off)`() {
        assertNull(core.beginEntry())
        core.onEntered(id(1))
        core.onAction(id(1), "end")
        core.onReturnedWithoutEntry(id(1))
        core.onBlocked("locked")
        core.shutdown()
        assertEquals(emptyList<String>(), platform.log)
        assertEquals(emptyList<Map<String, Any>>(), events)
    }

    @Test
    fun `availability never claims camera in PiP`() {
        assertEquals(mapOf("supported" to true, "cameraInPip" to false, "reason" to "ok"), core.availability())
        platform.supported = false
        assertEquals(mapOf("supported" to false, "cameraInPip" to false, "reason" to "os"), core.availability())
    }

    @Test
    fun `remote lookup rejects a local id collision and a wrong peer`() {
        val peers = mapOf(("remote-v" to "pc-1") to "remote-track")
        fun resolve(source: CallPipSource, locals: Set<String>) = resolveExactRemoteTrack(
            source,
            localTrack = { if (it in locals) "local-camera" else null },
            peerTrack = { track, peer -> peers[track to peer] },
        )
        assertEquals("remote-track", resolve(source, emptySet()))
        assertNull(resolve(source, setOf("remote-v"))) // local collision never wins
        assertNull(resolve(CallPipSource("pc-old", "remote-v"), emptySet())) // no global fallback
    }

    @Test
    fun `arm binds only the exact peer and video track and fails closed`() {
        assertEquals(
            mapOf("armed" to false, "reason" to "trackNotFound"),
            core.arm(id(1), CallPipSource("pc-old", "remote-v"), controls),
        )
        assertNull(platform.autoEnter)
        platform.supported = false
        assertEquals(mapOf("armed" to false, "reason" to "unsupported"), core.arm(id(2), source, controls))
        platform.supported = true
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(3), source, controls))
        assertEquals(controls, platform.autoEnter)
        assertEquals(id(3), platform.autoLease) // controls carry the exact triple
        assertEquals(listOf("auto true"), platform.log)
    }

    @Test
    fun `one entry and one exit per lease, then the lease is retired`() {
        core.arm(id(1), source, controls)
        core.onAction(id(1), "mute") // before entered: dropped
        assertEquals(id(1), core.beginEntry())
        core.onEntered(id(1))
        core.onEntered(id(1)) // duplicate: inert
        core.onAction(id(1), "mute")
        core.onAction(id(1), "bogus")
        core.onExited(id(1), restored = true)
        core.onExited(id(1), restored = false) // second exit: dropped
        core.onEntered(id(1)) // re-entry of a retired lease: dropped
        core.onAction(id(1), "end")
        assertEquals(listOf("1:1:entered", "1:2:action", "1:3:exited"), types())
        assertEquals("restored", events[2]["reason"])
        assertNull(platform.autoEnter) // auto entry off until a fresh arm
        assertEquals(emptyList<Any>(), platform.live)
        assertFalse(core.update(id(1), controls))
        assertEquals(1, events.first()["version"])
        assertEquals("graph-a", events.first()["instanceId"])
        assertEquals("call-1", events.first()["callId"])
        assertEquals(1L, events.first()["leaseId"])
    }

    @Test
    fun `close reports closed and another entry needs a fresh arm`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        core.onExited(id(1), restored = false)
        assertEquals("closed", events.last()["reason"])
        assertNull(core.beginEntry())
        core.arm(id(2), source, controls)
        core.beginEntry()
        core.onEntered(id(2))
        assertEquals(listOf("1:1:entered", "1:2:exited", "2:1:entered"), types())
    }

    @Test
    fun `old controls and old OS callbacks never touch a successor`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        core.arm(id(2), source, controls) // retires 1 (exited disarmed)
        core.onAction(id(1), "end")
        core.onEntered(id(1))
        core.onExited(id(1), restored = false)
        core.onEntryFailed(id(1))
        core.onReturnedWithoutEntry(id(1))
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertEquals(controls, platform.autoEnter)
        assertEquals(id(2), platform.autoLease)
        core.osExited(restored = false) // lease 1's own terminal OS callback
        assertEquals(2, events.size)
        assertEquals(id(2), core.beginEntry())
        core.onAction(id(2), "end") // successor not entered yet: dropped
        assertEquals(listOf("sink-2:pc-1"), platform.live)
        assertEquals(2, events.size)
    }

    @Test
    fun `leaving without entry releases the early sink and keeps the lease`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onReturnedWithoutEntry(id(1))
        assertEquals(emptyList<Any>(), platform.live)
        assertEquals(emptyList<Map<String, Any>>(), events)
        assertTrue(core.update(id(1), controls))
    }

    @Test
    fun `a newer arm retires the old lease and old triples cannot mutate it`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(2), source, controls))
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertEquals("disarmed", events.last()["reason"])
        assertEquals(emptyList<Any>(), platform.live)
        assertFalse(core.update(id(1), controls))
        assertFalse(core.enter(id(1)))
        assertTrue(core.disarm(id(1)))
        assertEquals(mapOf("armed" to false, "reason" to "stale"), core.arm(id(1), source, controls))
        assertTrue(core.update(id(2), controls))
    }

    @Test
    fun `a new graph instance retires the old one for good`() {
        core.arm(id(5, instance = "graph-a"), source, controls)
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(1, instance = "graph-b"), source, controls))
        assertEquals(mapOf("armed" to false, "reason" to "stale"), core.arm(id(9, instance = "graph-a"), source, controls))
        assertTrue(core.disarm(id(5, instance = "graph-a")))
        assertTrue(core.update(id(1, instance = "graph-b"), controls))
    }

    @Test
    fun `disarm retires before cleanup and emits nothing afterwards`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        assertTrue(core.disarm(id(1)))
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertNull(platform.autoEnter)
        assertTrue(platform.log.contains("leave"))
        assertEquals(emptyList<Any>(), platform.live)
        core.onAction(id(1), "end")
        core.onExited(id(1), restored = true)
        assertEquals(2, events.size)
        assertTrue(core.disarm(id(1)))
    }

    @Test
    fun `failed cleanup stays owned and a later disarm retries it`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        platform.failRelease = true
        assertFalse(core.disarm(id(1))) // retired, but its sink is still owned
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertNull(platform.autoEnter)
        assertEquals(listOf("sink-1:pc-1"), platform.live)
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(2), source, controls))
        assertFalse(core.disarm(id(1)))
        assertEquals(controls, platform.autoEnter) // retry never touches the successor
        platform.failRelease = false
        assertTrue(core.disarm(id(1)))
        assertEquals(emptyList<Any>(), platform.live)
        assertTrue(core.update(id(2), controls))
    }

    @Test
    fun `shutdown retires an armed lease and turns auto entry off`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        core.shutdown()
        assertNull(platform.autoEnter)
        assertTrue(platform.log.contains("leave"))
        assertEquals(emptyList<Any>(), platform.live)
        assertEquals(listOf("1:1:entered"), types())
        assertFalse(core.update(id(1), controls))
    }

    @Test
    fun `entry that cannot attach the track fails and retires`() {
        core.arm(id(1), source, controls)
        platform.videoTracks.clear()
        assertEquals(id(1), core.beginEntry())
        core.onEntered(id(1))
        assertEquals(listOf("1:1:failed"), types())
        assertEquals("trackLost", events.last()["code"])
        assertNull(platform.autoEnter)
        assertTrue(platform.log.contains("leave"))
    }

    @Test
    fun `an asynchronous start failure reports enterRejected and retires`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntryFailed(id(1))
        assertEquals(listOf("1:1:failed"), types())
        assertEquals("enterRejected", events.last()["code"])
        assertNull(platform.autoEnter)
        assertEquals(emptyList<Any>(), platform.live)
        core.onEntered(id(1))
        assertEquals(1, events.size)
    }

    @Test
    fun `lock retires an armed lease even before entry`() {
        core.arm(id(1), source, controls)
        core.onBlocked("locked")
        assertEquals(listOf("1:1:blocked"), types())
        assertEquals("locked", events.last()["reason"])
        assertNull(platform.autoEnter)
        assertNull(core.beginEntry())
        assertTrue(core.disarm(id(1)))
    }

    @Test
    fun `blocked while entered leaves PiP and drops later callbacks`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        core.onBlocked("userDisabled")
        assertEquals(listOf("1:1:entered", "1:2:blocked"), types())
        assertTrue(platform.log.contains("leave"))
        assertEquals(emptyList<Any>(), platform.live)
        core.onExited(id(1), restored = false)
        assertEquals(2, events.size)
    }

    @Test
    fun `enter is best effort and idempotent`() {
        assertFalse(core.enter(id(1)))
        core.arm(id(1), source, controls)
        platform.enterAllowed = false
        assertFalse(core.enter(id(1)))
        assertEquals(emptyList<Map<String, Any>>(), events)
        platform.enterAllowed = true
        assertTrue(core.enter(id(1)))
        core.onEntered(id(1))
        val requests = platform.log.count { it == "enter" }
        assertTrue(core.enter(id(1)))
        assertEquals(requests, platform.log.count { it == "enter" })
        assertEquals(listOf("1:1:entered"), types())
    }

    @Test
    fun `seq restarts at 1 for each lease`() {
        core.arm(id(1), source, controls)
        core.beginEntry()
        core.onEntered(id(1))
        core.arm(id(2), source, controls)
        core.beginEntry()
        core.onEntered(id(2))
        assertEquals(listOf("1:1:entered", "1:2:exited", "2:1:entered"), types())
    }

    @Test
    fun `a late OS completion for an explicit enter is never credited to a successor`() {
        core.arm(id(1), source, controls)
        assertTrue(core.enter(id(1))) // explicit request captures lease 1
        core.arm(id(2), source, controls) // replaces 1 before the OS answers
        assertFalse(core.osEntered()) // delayed completion: rejected, adapter leaves PiP
        assertEquals(emptyList<Map<String, Any>>(), events)
        assertEquals(emptyList<Any>(), platform.live) // successor sink never attached
        assertEquals(controls, platform.autoEnter)
        core.osExited(restored = false)
        assertEquals(emptyList<Map<String, Any>>(), events)
        // The successor still enters through its own captured user leave.
        assertEquals(id(2), core.beginEntry())
        assertTrue(core.osEntered())
        assertEquals(listOf("2:1:entered"), types())
    }

    @Test
    fun `an OS completion with no captured entry is rejected`() {
        core.arm(id(1), source, controls)
        assertFalse(core.osEntered())
        core.osEntryFailed()
        core.osExited(restored = true)
        assertEquals(emptyList<Map<String, Any>>(), events)
        assertEquals(emptyList<Any>(), platform.live)
    }

    @Test
    fun `OS callbacks follow the captured entry through exit and failure`() {
        core.arm(id(1), source, controls)
        assertTrue(core.enter(id(1)))
        assertEquals(id(1), core.beginEntry()) // user leave during the request keeps it
        assertTrue(core.osEntered())
        core.osExited(restored = true)
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        core.arm(id(2), source, controls)
        core.beginEntry()
        core.osEntryFailed()
        assertEquals("enterRejected", events.last()["code"])
        assertFalse(core.osEntered())
    }

    @Test
    fun `a too-late explicit enter leaves no capture behind`() {
        core.arm(id(1), source, controls)
        platform.enterAllowed = false
        assertFalse(core.enter(id(1)))
        assertFalse(core.osEntered())
        assertEquals(emptyList<Map<String, Any>>(), events)
    }

    @Test
    fun `a successor start waits until the retired lease's OS start settles`() {
        core.arm(id(1), source, controls)
        assertTrue(core.enter(id(1)))
        core.arm(id(2), source, controls)
        assertFalse(core.enter(id(2))) // old start outstanding: refused, not overwritten
        assertNull(core.beginEntry())
        assertFalse(core.osEntered()) // A's delayed completion
        assertEquals(emptyList<Map<String, Any>>(), events)
        assertEquals(emptyList<Any>(), platform.live)
        core.osExited(restored = false) // A's terminal callback settles the capture
        assertTrue(core.enter(id(2)))
        assertEquals(id(2), core.beginEntry())
        assertTrue(core.osEntered())
        assertEquals(listOf("2:1:entered"), types())
    }

    @Test
    fun `a stale capture also settles when the app returns without PiP`() {
        core.arm(id(1), source, controls)
        assertTrue(core.enter(id(1)))
        core.arm(id(2), source, controls)
        core.osReturnedWithoutEntry(settled = false)
        assertEquals(id(2), core.beginEntry())
    }
}
