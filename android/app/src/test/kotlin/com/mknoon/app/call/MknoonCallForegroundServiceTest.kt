package com.mknoon.app.call

import android.app.Service
import android.content.Intent
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallForegroundServiceTest {
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
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(admission, 0, 4))
        assertEquals(listOf(callId, callId), runtime.admissionStarts)
        assertTrue(runtime.stops.isEmpty())
        // A second reply command while already in admission does nothing more.
        service.onStartCommand(admission, 0, 5)
        assertEquals(listOf(callId, callId), runtime.admissionStarts)

        service.onStartCommand(stop, 0, 6)
        service.onStartCommand(stop, 0, 7)
        assertEquals(listOf(callId), runtime.stops)
        assertTrue(runtime.startFailures.isEmpty())
    }

    private fun serviceIntent(action: String, nativeCallId: UUID): Intent =
        Intent(action).putExtra(
            MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID,
            nativeCallId.toString(),
        )
}

private class RecordingForegroundRuntime : MknoonCallForegroundRuntime {
    val admissionStarts = mutableListOf<UUID>()
    val ringingStarts = mutableListOf<UUID>()
    val activeStarts = mutableListOf<UUID>()
    val inactiveStarts = mutableListOf<UUID>()
    val stops = mutableListOf<UUID>()
    val startFailures = mutableListOf<UUID>()
    var audioActive = false
    var lifecycleActive = true

    override fun isActiveLifecycle(nativeCallId: UUID): Boolean = lifecycleActive

    override fun isAudioActive(nativeCallId: UUID): Boolean = audioActive

    override fun startAdmission(nativeCallId: UUID) {
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
        stops += nativeCallId
    }

    override fun onStartFailure(nativeCallId: UUID) {
        startFailures += nativeCallId
    }
}
