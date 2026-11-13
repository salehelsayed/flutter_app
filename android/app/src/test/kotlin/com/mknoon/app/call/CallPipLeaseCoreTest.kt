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
            live -= sink
            log += "release $sink"
        }
        override fun setAutoEnter(controls: CallPipControls?) {
            autoEnter = controls
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
        core.onUserLeaving()
        core.onEntered()
        core.onAction("end")
        core.onReturnedWithoutEntry()
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
        // Arm only configures automatic entry; it never enters or attaches by itself.
        assertEquals(listOf("auto true"), platform.log)
    }

    @Test
    fun `entry attaches the remote sink and events follow the lease order`() {
        core.arm(id(1), source, controls)
        core.onAction("mute") // before entered: dropped
        core.onUserLeaving()
        core.onEntered()
        core.onEntered() // duplicate: inert
        core.onAction("mute")
        core.onAction("bogus") // unknown kind: dropped
        core.onExited(restored = true)
        core.onExited(restored = false) // second exit for one entry: dropped
        core.onAction("end") // after exit: dropped
        assertEquals(listOf("1:1:entered", "1:2:action", "1:3:exited"), types())
        assertEquals("mute", events[1]["kind"])
        assertEquals("restored", events[2]["reason"])
        assertEquals(listOf("auto true", "attach sink-1:pc-1", "release sink-1:pc-1"), platform.log)
        assertEquals(emptyList<Any>(), platform.live)
        val first = events.first()
        assertEquals(1, first["version"])
        assertEquals("graph-a", first["instanceId"])
        assertEquals("call-1", first["callId"])
        assertEquals(1L, first["leaseId"])
    }

    @Test
    fun `close keeps the lease armed and reports closed`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onEntered()
        core.onExited(restored = false)
        assertEquals("closed", events.last()["reason"])
        core.onUserLeaving()
        core.onEntered()
        assertEquals(listOf("1:1:entered", "1:2:exited", "1:3:entered"), types())
    }

    @Test
    fun `leaving without entry releases the early sink`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onReturnedWithoutEntry()
        assertEquals(emptyList<Any>(), platform.live)
        assertEquals(emptyList<Map<String, Any>>(), events)
    }

    @Test
    fun `a newer arm retires the old lease and old triples cannot mutate it`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onEntered()
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(2), source, controls))
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertEquals("disarmed", events.last()["reason"])
        assertEquals(emptyList<Any>(), platform.live)
        assertFalse(core.update(id(1), controls))
        assertFalse(core.enter(id(1)))
        assertTrue(core.disarm(id(1))) // idempotent for a retired lease
        assertEquals(mapOf("armed" to false, "reason" to "stale"), core.arm(id(1), source, controls))
        assertTrue(core.update(id(2), controls)) // successor untouched
        assertEquals(controls, platform.autoEnter)
    }

    @Test
    fun `a new graph instance retires the old one for good`() {
        core.arm(id(5, instance = "graph-a"), source, controls)
        assertEquals(mapOf("armed" to true, "reason" to "ok"), core.arm(id(1, instance = "graph-b"), source, controls))
        // Old graph, even with a higher lease id, can never act again.
        assertEquals(mapOf("armed" to false, "reason" to "stale"), core.arm(id(9, instance = "graph-a"), source, controls))
        assertTrue(core.disarm(id(5, instance = "graph-a")))
        assertTrue(core.update(id(1, instance = "graph-b"), controls))
    }

    @Test
    fun `disarm retires before cleanup and emits nothing afterwards`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onEntered()
        assertTrue(core.disarm(id(1)))
        assertEquals(listOf("1:1:entered", "1:2:exited"), types())
        assertEquals("disarmed", events.last()["reason"])
        assertNull(platform.autoEnter)
        assertTrue(platform.log.contains("leave"))
        assertEquals(emptyList<Any>(), platform.live)
        core.onAction("end")
        core.onExited(restored = true)
        core.onEntered()
        assertEquals(2, events.size)
        assertTrue(core.disarm(id(1)))
    }

    @Test
    fun `entry that cannot attach the track fails and retires`() {
        core.arm(id(1), source, controls)
        platform.videoTracks.clear() // remote track replaced or gone
        core.onUserLeaving()
        core.onEntered()
        assertEquals(listOf("1:1:failed"), types())
        assertEquals("trackLost", events.last()["code"])
        assertNull(platform.autoEnter)
        assertTrue(platform.log.contains("leave"))
        core.onAction("end")
        assertEquals(1, events.size)
    }

    @Test
    fun `blocked removes the sink and auto entry even before entry`() {
        core.arm(id(1), source, controls)
        core.onBlocked("userDisabled")
        assertEquals(listOf("1:1:blocked"), types())
        assertEquals("userDisabled", events.last()["reason"])
        assertNull(platform.autoEnter)
        core.onUserLeaving()
        core.onEntered()
        assertEquals(1, events.size)
        assertTrue(core.disarm(id(1)))
    }

    @Test
    fun `blocked while entered leaves PiP and drops later callbacks`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onEntered()
        core.onBlocked("locked")
        assertEquals(listOf("1:1:entered", "1:2:blocked"), types())
        assertTrue(platform.log.contains("leave"))
        assertEquals(emptyList<Any>(), platform.live)
        core.onExited(restored = false)
        assertEquals(2, events.size)
    }

    @Test
    fun `enter is best effort and idempotent`() {
        assertFalse(core.enter(id(1)))
        core.arm(id(1), source, controls)
        platform.enterAllowed = false
        assertFalse(core.enter(id(1)))
        assertEquals(emptyList<Map<String, Any>>(), events) // a late request is not a failure event
        platform.enterAllowed = true
        assertTrue(core.enter(id(1)))
        core.onEntered()
        val requests = platform.log.count { it == "enter" }
        assertTrue(core.enter(id(1)))
        assertEquals(requests, platform.log.count { it == "enter" })
        assertEquals(listOf("1:1:entered"), types())
    }

    @Test
    fun `seq restarts at 1 for each lease`() {
        core.arm(id(1), source, controls)
        core.onUserLeaving()
        core.onEntered()
        core.arm(id(2), source, controls)
        core.onUserLeaving()
        core.onEntered()
        assertEquals(listOf("1:1:entered", "1:2:exited", "2:1:entered"), types())
    }
}
