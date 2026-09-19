package com.mknoon.app.call

import android.content.Context
import android.content.Intent
import android.os.Looper
import java.time.Duration
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallTerminalTombstonesTest {
    private val preferences = RuntimeEnvironment.getApplication()
        .getSharedPreferences("terminal-retention-test", Context.MODE_PRIVATE)
    private val store = MknoonCallTerminalTombstones(preferences)
    private val callId = UUID.fromString("00000000-0000-4000-8000-000000000601")
    private val ownerId = UUID.fromString("00000000-0000-4000-8000-000000000602")

    @Test
    fun `late deferred wake after invitation expiry releases from durable terminal settlement`() {
        // Candidate139: terminal at36s, invitation expires45s, delayed wake48s.
        assertTrue(store.record(callId, 45_000L, 36_000L))
        val reloaded = MknoonCallTerminalTombstones(preferences)
        val runtime = TerminalRuntime(reloaded, 48_000L)
        val service = MknoonCallForegroundService(runtime)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_START_ADMISSION), 0, 1)
        assertEquals(listOf(callId), runtime.stops)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL, runtime.events.last())
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION), 0, 2)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_IDLE, runtime.events.last())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf(callId), runtime.stops)
        assertFalse(MknoonCallAdmissionEvent.TIMEOUT_APPLIED in runtime.events)
    }

    @Test
    fun `long connected call terminated after invitation expiry retains exact settlement`() {
        assertTrue(store.record(callId, 45_000L, 120_000L))
        assertTrue(MknoonCallTerminalTombstones(preferences).contains(callId, 130_000L))
        assertFalse(store.contains(UUID.randomUUID(), 130_000L))
    }

    @Test
    fun `settlement expires after a bounded wake plus admission horizon without extending invitations`() {
        val terminalAt = 36_000L
        assertTrue(store.record(callId, 45_000L, terminalAt))
        val expiry = terminalAt + MknoonCallTerminalTombstones.RETENTION_MS
        assertTrue(store.contains(callId, expiry - 1))
        assertFalse(store.contains(callId, expiry))
        assertTrue(preferences.all.isEmpty())
        var presented = false
        assertFalse(presentAuthenticatedCall(
            callHandle = callId.toString(), expiresAtMs = 45_000L, observedNowMs = 48_000L,
            capabilityEnabled = true, handleGrammar = Regex("^[0-9a-f-]{36}$"),
            wakeHandle = { "unused" }, present = { presented = true; MknoonCallPresentationResult.PRESENTED },
        ))
        assertFalse(presented)
    }

    @Test
    fun `bounded retention cannot retire fresh unknown admission or a successor owner`() {
        val runtime = TerminalRuntime(store, 48_000L)
        val service = MknoonCallForegroundService(runtime)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_START_ADMISSION), 0, 1)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION), 0, 2)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_DEFERRED, runtime.events.last())
        assertTrue(runtime.stops.isEmpty())
        val successor = UUID.randomUUID()
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_START_ADMISSION, owner = successor), 0, 3)
        // Terminal authority arrives after the successor took fresh custody.
        assertTrue(store.record(callId, 45_000L, 48_000L))
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION), 0, 4)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_IGNORED_OWNER, runtime.events.last())
        assertTrue(runtime.stops.isEmpty())
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, owner = successor), 0, 5)
        assertEquals(listOf(callId), runtime.stops)
    }

    @Test
    fun `old terminal settlement cannot stop another call or upgraded active foreground`() {
        assertTrue(store.record(callId, 45_000L, 36_000L))
        val runtime = TerminalRuntime(store, 48_000L)
        val otherCall = UUID.randomUUID()
        val service = MknoonCallForegroundService(runtime)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_START_ADMISSION, id = otherCall), 0, 1)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION), 0, 2)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_IGNORED_CALL, runtime.events.last())
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_START_ACTIVE, id = otherCall), 0, 3)
        service.onStartCommand(command(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, id = otherCall), 0, 4)
        assertEquals(MknoonCallAdmissionEvent.RELEASE_IGNORED_UPGRADED, runtime.events.last())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertTrue(runtime.stops.isEmpty())
    }

    @Test
    fun `settlement cache is count bounded and preserves unrelated preferences`() {
        preferences.edit().putBoolean("dart_capability_enabled", true).commit()
        val calls = (0..MknoonCallTerminalTombstones.MAX_ENTRIES).map { UUID(0L, it.toLong() + 1) }
        calls.forEachIndexed { index, id -> assertTrue(store.record(id, 45_000L, 120_000L + index)) }
        assertFalse(store.contains(calls.first(), 121_000L))
        assertTrue(store.contains(calls.last(), 121_000L))
        assertEquals(MknoonCallTerminalTombstones.MAX_ENTRIES + 1, preferences.all.size)
        assertTrue(preferences.getBoolean("dart_capability_enabled", false))
    }

    private fun command(action: String, id: UUID = callId, owner: UUID = ownerId) = Intent(action)
        .putExtra(MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID, id.toString())
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_OWNER_ID, owner.toString())
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, true)
}

private class TerminalRuntime(
    private val store: MknoonCallTerminalTombstones,
    private val nowMs: Long,
) : MknoonCallForegroundRuntime {
    val stops = mutableListOf<UUID>()
    val events = mutableListOf<MknoonCallAdmissionEvent>()
    override fun isActiveLifecycle(nativeCallId: UUID) = true
    override fun isAudioActive(nativeCallId: UUID) = true
    override fun isTerminalLifecycle(nativeCallId: UUID) = store.contains(nativeCallId, nowMs)
    override fun startRinging(nativeCallId: UUID) = Unit
    override fun startActive(nativeCallId: UUID) = Unit
    override fun startInactive(nativeCallId: UUID) = Unit
    override fun stop(nativeCallId: UUID) { stops += nativeCallId }
    override fun onAdmissionEvent(nativeCallId: UUID, event: MknoonCallAdmissionEvent) { events += event }
}
