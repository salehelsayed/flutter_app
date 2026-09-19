package com.mknoon.app.call

import android.app.Service
import android.content.Intent
import android.os.Looper
import java.time.Duration
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallForegroundServiceTest {
    @Test
    fun `known terminal wake at cleanup deadline applies foreground then releases without waiting for worker`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime().also {
            it.lifecycleActive = false
            it.terminalCallIds = setOf(callId)
        }
        val service = MknoonCallForegroundService(runtime)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(19_889))
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        assertEquals(listOf("admission", "stop"), runtime.foregroundOperations)
        assertEquals(listOf(callId), runtime.stops)
        assertEquals(listOf(MknoonCallAdmissionEvent.START_APPLIED,
            MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL), runtime.admissionEvents)
        // The observed141 worker took another3087ms; cleanup must not await it.
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(3_087))
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true), 0, 2)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf(callId), runtime.stops)
        assertTrue(MknoonCallAdmissionEvent.TIMEOUT_APPLIED !in runtime.admissionEvents)
    }

    @Test
    fun `terminal check failure retains fresh foreground custody`() {
        val runtime = RecordingForegroundRuntime().also { it.failTerminalLookup = true }
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertEquals(listOf(callId), runtime.admissionStarts)
        assertTrue(runtime.stops.isEmpty())
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId), 0, 2)
        assertEquals(listOf(callId), runtime.ringingStarts)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(21))
        assertTrue(runtime.stops.isEmpty())
    }

    @Test
    fun `explicit decline reply retains custody despite authenticated terminal and ordinary successor wake`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime().also { it.terminalCallIds = setOf(callId) }
        val service = MknoonCallForegroundService(runtime)
        val reply = serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId)
            .putExtra("com.mknoon.app.call.service.extra.ADMISSION_DECLINE_REPLY", true)
        service.onStartCommand(reply, 0, 1)
        val successor = UUID.randomUUID()
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId, successor), 0, 2)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 3)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertEquals(listOf(callId), runtime.admissionStarts)
        assertTrue(runtime.stops.isEmpty())
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId, successor), 0, 4)
        assertEquals(listOf(callId), runtime.stops)
        // The exception belongs only to this custody lifetime.
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId, UUID.randomUUID()), 0, 5)
        assertEquals(listOf(callId, callId), runtime.stops)
    }

    @Test
    fun `old terminal receipt cannot stop new UUID or an upgraded owner`() {
        val oldCall = UUID.fromString(CALL_ID)
        val nextCall = UUID.randomUUID()
        val runtime = RecordingForegroundRuntime().also { it.terminalCallIds = setOf(oldCall) }
        val service = MknoonCallForegroundService(runtime)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, oldCall), 0, 1)
        val nextOwner = UUID.randomUUID()
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, nextCall, nextOwner), 0, 2)
        assertEquals(listOf(oldCall, nextCall), runtime.admissionStarts)
        assertEquals(listOf(oldCall), runtime.stops)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, oldCall), 0, 3)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, oldCall), 0, 4)
        assertEquals(listOf(oldCall), runtime.stops)
        runtime.audioActive = true
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, nextCall), 0, 5)
        runtime.terminalCallIds = setOf(oldCall, nextCall)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, nextCall, nextOwner), 0, 6)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf(oldCall), runtime.stops)
        assertEquals(listOf(nextCall), runtime.activeStarts)
    }

    @Test
    fun `malformed decline marker does not retain known terminal admission`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime().also { it.terminalCallIds = setOf(callId) }
        val service = MknoonCallForegroundService(runtime)
        val malformed = serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId)
            .putExtra("com.mknoon.app.call.service.extra.ADMISSION_DECLINE_REPLY", "true")
        service.onStartCommand(malformed, 0, 1)
        assertEquals(listOf("admission", "stop"), runtime.foregroundOperations)
    }

    @Test
    fun `release diagnostics prove applied terminal cleanup after native stop returns`() {
        val runtime = RecordingForegroundRuntime()
        val events = mutableListOf<Pair<MknoonCallAdmissionEvent, MknoonCallForegroundMode?>>()
        val callId = UUID.fromString(CALL_ID)
        val service = MknoonCallForegroundService(runtime) { event, mode ->
            if (event == MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL) {
                assertEquals(listOf(callId), runtime.stops)
            }
            events += event to mode
        }
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        runtime.lifecycleTerminal = true
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true), 0, 2)
        assertEquals(listOf(
            MknoonCallAdmissionEvent.START_APPLIED to MknoonCallForegroundMode.ADMISSION,
            MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL to MknoonCallForegroundMode.ADMISSION,
        ), events)
        assertEquals(events.map { it.first }, runtime.admissionEvents)
    }

    @Test
    fun `terminal propagation after a deferred worker release still stops before twenty seconds`() {
        val runtime = RecordingForegroundRuntime().also { it.lifecycleActive = false }
        val events = mutableListOf<MknoonCallAdmissionEvent>()
        val service = MknoonCallForegroundService(runtime) { event, _ -> events += event }
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true), 0, 2)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_DEFERRED, events.last())
        assertTrue(runtime.stops.isEmpty())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500))
        runtime.lifecycleTerminal = true
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId), 0, 3)
        assertEquals(MknoonCallAdmissionEvent.STOP_APPLIED, events.last())
        assertEquals(listOf(callId), runtime.stops)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(20))
        assertEquals(listOf(callId), runtime.stops)
        assertTrue(MknoonCallAdmissionEvent.TIMEOUT_APPLIED !in events)
    }

    @Test
    fun `backstop has distinct applied diagnostics and cannot masquerade as immediate release`() {
        val runtime = RecordingForegroundRuntime()
        val events = mutableListOf<MknoonCallAdmissionEvent>()
        val service = MknoonCallForegroundService(runtime) { event, _ -> events += event }
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(20))
        assertEquals(listOf(MknoonCallAdmissionEvent.START_APPLIED), events)
        assertTrue(runtime.stops.isEmpty())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertEquals(MknoonCallAdmissionEvent.TIMEOUT_APPLIED, events.last())
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `failed release never records applied cleanup and diagnostic exceptions cannot block release`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime().also { it.failStop = true }
        val events = mutableListOf<MknoonCallAdmissionEvent>()
        val service = MknoonCallForegroundService(runtime) { event, _ -> events += event }
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 2)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_FAILED, events.last())
        assertTrue(MknoonCallAdmissionEvent.RELEASE_APPLIED_SETTLED !in events)
        runtime.failStop = false
        runtime.failDiagnostic = true
        val recoveredService = MknoonCallForegroundService(runtime) { _, _ -> error("sink failed") }
        recoveredService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        recoveredService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 2)
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `deferred foreground owner retains admission until later authenticated presentation`() {
        val runtime = RecordingForegroundRuntime().also { it.lifecycleActive = false }
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        val deferredRelease = serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true)
        service.onStartCommand(deferredRelease, 0, 2)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertTrue(runtime.stops.isEmpty())
        runtime.lifecycleActive = true
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId), 0, 3)
        assertEquals(listOf(callId), runtime.ringingStarts)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(21))
        assertTrue(runtime.stops.isEmpty())
    }

    @Test
    fun `deferred late terminal wake releases promptly using native terminal evidence`() {
        val runtime = RecordingForegroundRuntime().also { it.lifecycleActive = false }
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        runtime.lifecycleTerminal = true
        service.onStartCommand(
            serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
                .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true),
            0, 2,
        )
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `completed late admission releases its placeholder immediately and exactly once`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId), 0, 1)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId), 0, 2)
        runtime.stops.clear()
        runtime.lifecycleActive = false
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 3)
        val release = serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId)
        service.onStartCommand(release, 0, 4)
        service.onStartCommand(release, 0, 5)
        assertEquals(listOf(callId), runtime.stops)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `prior same-call work and its timeout cannot release a successor admission`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        val successor = UUID.randomUUID()
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(20))
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId, successor), 0, 2)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 3)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, UUID.randomUUID(), successor), 0, 4)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertTrue(runtime.stops.isEmpty())
        assertEquals(listOf(callId), runtime.admissionStarts)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId, successor), 0, 5)
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `old work completion cannot stop a fresh service instance for the same call`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime()
        val oldService = MknoonCallForegroundService(runtime)
        oldService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        oldService.onDestroy()
        val successor = UUID.randomUUID()
        val freshService = MknoonCallForegroundService(runtime)
        freshService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId, successor), 0, 1)
        freshService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 2)
        assertTrue(runtime.stops.isEmpty())
        freshService.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId, successor), 0, 3)
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `admission release and timeout preserve ringing active and inactive upgrades`() {
        for (upgrade in listOf("ringing", "active", "inactive")) {
            val runtime = RecordingForegroundRuntime()
            val service = MknoonCallForegroundService(runtime)
            val callId = UUID.fromString(CALL_ID)
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId), 0, 2)
            if (upgrade != "ringing") {
                runtime.audioActive = true
                service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId), 0, 3)
            }
            if (upgrade == "inactive") {
                runtime.audioActive = false
                service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_INACTIVE, callId), 0, 4)
            }
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 5)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
            assertTrue("upgraded $upgrade service survives worker completion", runtime.stops.isEmpty())
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId), 0, 6)
            assertEquals(listOf(callId), runtime.stops)
        }
    }

    @Test
    fun `authoritative audio activation upgrades admission directly and survives worker completion`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
        runtime.audioActive = true
        val activate = serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId)
        service.onStartCommand(activate, 0, 2)
        service.onStartCommand(activate, 0, 3)
        service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, callId), 0, 4)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf(callId), runtime.activeStarts)
        assertTrue(runtime.stops.isEmpty())
        assertTrue(runtime.startFailures.isEmpty())
    }

    @Test
    fun `admission cannot upgrade microphone without exact authoritative active audio`() {
        for ((audio, lifecycle, sameCall) in listOf(
            Triple(false, true, true), Triple(null, true, true),
            Triple(true, false, true), Triple(true, true, false),
        )) {
            val runtime = RecordingForegroundRuntime()
            val service = MknoonCallForegroundService(runtime)
            val callId = UUID.fromString(CALL_ID)
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId), 0, 1)
            runtime.audioActive = audio
            runtime.lifecycleActive = lifecycle
            service.onStartCommand(serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE,
                if (sameCall) callId else UUID.randomUUID()), 0, 2)
            assertTrue(runtime.activeStarts.isEmpty())
        }
    }

    @Test
    fun `admission entered in the push window upgrades to ringing exactly once`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)
        val admission = serviceIntent(
            MknoonCallForegroundService.ACTION_START_ADMISSION,
            callId,
        )
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(admission, 0, 1))
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(admission, 0, 2))
        assertEquals(listOf(callId), runtime.admissionStarts)
        assertTrue(runtime.ringingStarts.isEmpty())

        val ringing = serviceIntent(
            MknoonCallForegroundService.ACTION_START_RINGING,
            callId,
        )
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(ringing, 0, 3))
        assertEquals(listOf(callId), runtime.ringingStarts)
        // A late admission command for the ringing call is ignored.
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(admission, 0, 4))
        assertEquals(listOf(callId), runtime.admissionStarts)

        val stop = serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId)
        service.onStartCommand(stop, 0, 5)
        assertEquals(listOf(callId), runtime.stops)
        assertTrue(runtime.startFailures.isEmpty())
    }

    @Test
    fun `ringing starts once and cannot implicitly start microphone mode`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)
        val ringing = serviceIntent(
            MknoonCallForegroundService.ACTION_START_RINGING,
            callId,
        )

        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(ringing, 0, 1))
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(ringing, 0, 2))

        assertEquals(listOf(callId), runtime.ringingStarts)
        assertTrue(runtime.activeStarts.isEmpty())

        val active = serviceIntent(
            MknoonCallForegroundService.ACTION_START_ACTIVE,
            callId,
        )
        runtime.audioActive = true
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(active, 0, 3))
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(active, 0, 4))
        assertEquals(listOf(callId), runtime.activeStarts)
    }

    @Test
    fun `delayed active command cannot restore microphone mode after audio deactivation`() {
        listOf(false, true).forEach { previouslyActive ->
            val runtime = RecordingForegroundRuntime()
            val service = MknoonCallForegroundService(runtime = runtime)
            val callId = UUID.fromString(CALL_ID)
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId),
                0,
                1,
            )
            if (previouslyActive) {
                runtime.audioActive = true
                service.onStartCommand(
                    serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId),
                    0,
                    2,
                )
                runtime.audioActive = false
                service.onStartCommand(
                    serviceIntent(MknoonCallForegroundService.ACTION_START_INACTIVE, callId),
                    0,
                    3,
                )
            }
            val activeStartsBefore = runtime.activeStarts.toList()

            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId),
                0,
                4,
            )

            assertEquals(activeStartsBefore, runtime.activeStarts)
            assertEquals(listOf(callId), runtime.startFailures)
        }
    }

    @Test
    fun `answered active to inactive uses ongoing mode without ringing again`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)

        assertEquals(
            Service.START_NOT_STICKY,
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId),
                0,
                1,
            ),
        )
        runtime.audioActive = true
        assertEquals(
            Service.START_NOT_STICKY,
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId),
                0,
                2,
            ),
        )
        runtime.audioActive = false
        assertEquals(
            Service.START_NOT_STICKY,
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId),
                0,
                3,
            ),
        )
        val inactive = serviceIntent(
            MknoonCallForegroundService.ACTION_START_INACTIVE,
            callId,
        )
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(inactive, 0, 4))
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(inactive, 0, 5))

        assertEquals(listOf(callId), runtime.ringingStarts)
        assertEquals(listOf(callId), runtime.activeStarts)
        assertEquals(listOf(callId), runtime.inactiveStarts)
        assertTrue(runtime.startFailures.isEmpty())

        runtime.audioActive = true
        service.onStartCommand(
            serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, callId),
            0,
            6,
        )
        assertEquals(listOf(callId, callId), runtime.activeStarts)
        assertTrue(runtime.startFailures.isEmpty())
    }

    @Test
    fun `cold inactive command restores only the ongoing foreground mode`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)

        assertEquals(
            Service.START_NOT_STICKY,
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_INACTIVE, callId),
                0,
                1,
            ),
        )

        assertEquals(listOf(callId), runtime.inactiveStarts)
        assertTrue(runtime.ringingStarts.isEmpty())
        assertTrue(runtime.activeStarts.isEmpty())
        assertTrue(runtime.startFailures.isEmpty())
    }

    @Test
    fun `terminal stop releases one matching foreground service exactly once`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)
        service.onStartCommand(
            serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId),
            0,
            1,
        )
        val stop = serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId)

        service.onStartCommand(stop, 0, 2)
        service.onStartCommand(stop, 0, 3)

        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `cold ringing command tears down an already audio-active lifecycle`() {
        val callId = UUID.fromString(CALL_ID)
        val runtime = RecordingForegroundRuntime().apply { audioActive = true }
        val service = MknoonCallForegroundService(runtime = runtime)

        assertEquals(
            Service.START_NOT_STICKY,
            service.onStartCommand(
                serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId),
                0,
                1,
            ),
        )

        assertTrue(runtime.ringingStarts.isEmpty())
        assertEquals(listOf(callId), runtime.startFailures)
    }

    @Test
    fun `malformed unknown and mismatched commands have zero runtime side effects`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)

        service.onStartCommand(null, 0, 1)
        service.onStartCommand(Intent("unknown"), 0, 2)
        service.onStartCommand(
            Intent(MknoonCallForegroundService.ACTION_START_RINGING)
                .putExtra(MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID, "not-a-uuid"),
            0,
            3,
        )
        service.onStartCommand(
            serviceIntent(
                MknoonCallForegroundService.ACTION_START_ACTIVE,
                UUID.fromString(OTHER_CALL_ID),
            ),
            0,
            4,
        )
        service.onStartCommand(
            serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId),
            0,
            5,
        )

        assertTrue(runtime.ringingStarts.isEmpty())
        assertTrue(runtime.activeStarts.isEmpty())
        assertTrue(runtime.inactiveStarts.isEmpty())
        assertTrue(runtime.stops.isEmpty())
    }

    // Plan 404 (c): a declined headless call keeps its foreground service for
    // the decline reply. The reply's admission command re-enters admission on
    // the ringing service once the lifecycle is over; the reply worker's STOP
    // then releases it exactly once.
    @Test
    fun `a declined headless call re-enters admission for its reply and stops once`() {
        val runtime = RecordingForegroundRuntime()
        val service = MknoonCallForegroundService(runtime = runtime)
        val callId = UUID.fromString(CALL_ID)
        val admission = serviceIntent(MknoonCallForegroundService.ACTION_START_ADMISSION, callId)
        val ringing = serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, callId)
        val stop = serviceIntent(MknoonCallForegroundService.ACTION_STOP, callId)

        service.onStartCommand(admission, 0, 1)
        service.onStartCommand(ringing, 0, 2)
        assertEquals(listOf(callId), runtime.admissionStarts)
        // Still ringing: a late admission command stays ignored.
        service.onStartCommand(admission, 0, 3)
        assertEquals(listOf(callId), runtime.admissionStarts)

        runtime.lifecycleActive = false
        runtime.lifecycleTerminal = true
        val reply = Intent(admission)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_DECLINE_REPLY, true)
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(reply, 0, 4))
        assertEquals(listOf(callId, callId), runtime.admissionStarts)
        assertTrue(runtime.stops.isEmpty())
        // A second reply command while already in admission does nothing more.
        service.onStartCommand(reply, 0, 5)
        assertEquals(listOf(callId, callId), runtime.admissionStarts)

        service.onStartCommand(stop, 0, 6)
        service.onStartCommand(stop, 0, 7)
        assertEquals(listOf(callId), runtime.stops)
        assertTrue(runtime.startFailures.isEmpty())
    }

    private fun serviceIntent(
        action: String,
        nativeCallId: UUID,
        ownerId: UUID = UUID.fromString("aa112233-4455-6677-8899-aabbccddeeff"),
    ): Intent =
        Intent(action).putExtra(
            MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID,
            nativeCallId.toString(),
        )
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_OWNER_ID, ownerId.toString())
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, false)
}

private class RecordingForegroundRuntime : MknoonCallForegroundRuntime {
    val foregroundOperations = mutableListOf<String>()
    val admissionStarts = mutableListOf<UUID>()
    val ringingStarts = mutableListOf<UUID>()
    val activeStarts = mutableListOf<UUID>()
    val inactiveStarts = mutableListOf<UUID>()
    val stops = mutableListOf<UUID>()
    val startFailures = mutableListOf<UUID>()
    val admissionEvents = mutableListOf<MknoonCallAdmissionEvent>()
    var failStop = false
    var failDiagnostic = false
    var audioActive: Boolean? = false
    var lifecycleActive = true
    var lifecycleTerminal = false
    var terminalCallIds: Set<UUID>? = null
    var failTerminalLookup = false

    override fun isActiveLifecycle(nativeCallId: UUID): Boolean = lifecycleActive

    override fun isAudioActive(nativeCallId: UUID): Boolean? = audioActive

    override fun isTerminalLifecycle(nativeCallId: UUID): Boolean {
        if (failTerminalLookup) error("terminal lookup unavailable")
        return terminalCallIds?.contains(nativeCallId) ?: lifecycleTerminal
    }

    override fun startAdmission(nativeCallId: UUID) {
        foregroundOperations += "admission"
        admissionStarts += nativeCallId
    }

    override fun startRinging(nativeCallId: UUID) {
        ringingStarts += nativeCallId
    }

    override fun startActive(nativeCallId: UUID) {
        activeStarts += nativeCallId
    }

    override fun startInactive(nativeCallId: UUID) {
        inactiveStarts += nativeCallId
    }

    override fun stop(nativeCallId: UUID) {
        if (failStop) error("stop unavailable")
        foregroundOperations += "stop"
        stops += nativeCallId
    }

    override fun onAdmissionEvent(nativeCallId: UUID, event: MknoonCallAdmissionEvent) {
        if (failDiagnostic) error("diagnostic unavailable")
        admissionEvents += event
    }

    override fun onStartFailure(nativeCallId: UUID) {
        startFailures += nativeCallId
    }
}
