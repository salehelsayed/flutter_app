package com.mknoon.app.call

import android.content.Intent
import android.os.Looper
import java.time.Duration
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallAdmissionSettlementTest {
    private var now = 1_000L
    private val call = UUID.fromString(CALL_ID)
    private val owner = UUID.fromString("aa112233-4455-4677-8899-aabbccddeeff")
    private fun payload(id: UUID = call) = CallWakePayload(id, id.toString(), "a".repeat(32), now, now + 40_000)

    @Test fun `protected journal failure and every live cleanup owner refuse settlement`() {
        assertTrue(admissionSettlementHasNativeOwner { error("protected record unreadable") })
        for (live in listOf(false, true)) for (cleanup in listOf(false, true)) {
            assertEquals(live || cleanup, admissionSettlementHasNativeOwner {
                MknoonCallJournalObservation(null, live, cleanup)
            })
        }
    }

    @Test fun `read capture has no terminal effect and token diagnostics are redacted`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        assertNull(store.capture(call))
        val token = requireNotNull(store.register(payload(), owner))
        assertEquals(token, store.capture(call))
        assertFalse(store.isSettled(token))
        assertEquals(token, MknoonCallAdmissionToken.parse(token.toMap()))
        assertEquals("MknoonCallAdmissionToken(<redacted>)", token.toString())
    }

    @Test fun `every original owner fact and successor fences the terminal commit`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        var writes = 0
        for (wrong in listOf(token.copy(nativeCallId = UUID.randomUUID()), token.copy(ownerId = UUID.randomUUID()),
            token.copy(expiresAtMs = token.expiresAtMs + 1), token.copy(wakeHandle = "b".repeat(32)))) {
            assertFalse(store.settle(wrong) { writes++; true })
        }
        val successor = requireNotNull(store.register(payload(), UUID.randomUUID()))
        assertFalse(store.settle(token) { writes++; true })
        assertEquals(0, writes)
        assertTrue(store.settle(successor) { writes++; true })
        assertTrue(store.settle(successor) { writes++; true })
        assertEquals(1, writes)
    }

    @Test fun `failed durable terminal receipt retains custody and permits exact retry`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        assertFalse(store.settle(token) { false })
        assertFalse(store.settle(token) { error("private backend failure") })
        assertFalse(store.isSettled(token))
        assertEquals(token, store.capture(call))
        assertTrue(store.settle(token))
    }

    @Test fun `decline reply custody survives ordinary successor and resets only on retirement`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val reply = requireNotNull(store.register(payload(), owner, declineReply = true))
        assertNull(store.capture(call))
        val next = requireNotNull(store.register(payload(), UUID.randomUUID()))
        assertFalse(store.settle(reply))
        assertFalse(store.settle(next))
        store.retire(call, reply.ownerId)
        assertNull(store.capture(call))
        store.retire(call, next.ownerId)
        val fresh = requireNotNull(store.register(payload(), UUID.randomUUID()))
        assertEquals(fresh, store.capture(call))
    }

    @Test fun `bounded retention does not refresh on capture or duplicate registration`() {
        val store = MknoonCallAdmissionSettlementStore({ now }, capacity = 2)
        val firstPayload = payload()
        val first = requireNotNull(store.register(firstPayload, owner))
        now += 74_999
        assertEquals(first, store.register(firstPayload, owner))
        assertEquals(first, store.capture(call))
        now++
        assertNull(store.capture(call))
        assertFalse(store.settle(first))
        now = 100_000
        val second = requireNotNull(store.register(payload(), owner))
        store.register(payload(UUID.randomUUID()), UUID.randomUUID())
        store.register(payload(UUID.randomUUID()), UUID.randomUUID())
        assertNull(store.capture(call))
        assertFalse(store.settle(second))
    }

    @Test fun `clock regression and unavailable clock cannot authorize terminal writes`() {
        var fail = false
        val store = MknoonCallAdmissionSettlementStore({ if (fail) error("clock") else now })
        val token = requireNotNull(store.register(payload(), owner))
        now--
        assertNull(store.capture(call))
        assertFalse(store.settle(token))
        now++
        fail = true
        assertFalse(store.settle(token))
    }

    @Test fun `token parser rejects extra missing ambiguous and malformed fields`() {
        val token = MknoonCallAdmissionToken(call, owner, 41_000, "a".repeat(32))
        for (bad in listOf(token.toMap() + ("unexpected" to true), token.toMap() - "ownerId",
            token.toMap() + ("expiresAtMs" to 41000.0), token.toMap() + ("expiresAtMs" to 0L),
            token.toMap() + ("ownerId" to owner.toString().uppercase()),
            token.toMap() + ("wakeHandle" to "private address"))) assertNull(MknoonCallAdmissionToken.parse(bad))
    }

    @Test fun `terminal ACK before service START foregrounds then retires without the thirty second backstop`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        val runtime = SettlementForegroundRuntime()
        val service = MknoonCallForegroundService(runtime, store)
        assertTrue(store.settle(token))
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, token), 0, 1)
        assertEquals(listOf("admission", "stop"), runtime.operations)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
        assertEquals(listOf("admission", "stop"), runtime.operations)
        // A reordered duplicate START still satisfies Android first, then exits.
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, token), 0, 2)
        assertEquals(listOf("admission", "stop", "admission", "stop"), runtime.operations)
    }

    @Test fun `foreground terminal ACK retires exact deferred placeholder and preserves wrong-owner attempts`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        val runtime = SettlementForegroundRuntime()
        val service = MknoonCallForegroundService(runtime, store)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, token), 0, 1)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, token), 0, 2)
        assertEquals(listOf("admission"), runtime.operations)
        assertTrue(store.settle(token))
        service.onStartCommand(release(token.copy(ownerId = UUID.randomUUID())), 0, 3)
        service.onStartCommand(release(token.copy(wakeHandle = "b".repeat(32))), 0, 4)
        service.onStartCommand(release(token.copy(expiresAtMs = token.expiresAtMs + 1)), 0, 5)
        assertEquals(listOf("admission"), runtime.operations)
        service.onStartCommand(release(token), 0, 6)
        assertEquals(listOf("admission", "stop"), runtime.operations)
    }

    @Test fun `captured token cannot retire a ringing or active native owner`() {
        for (action in listOf(MknoonCallForegroundService.ACTION_START_RINGING, MknoonCallForegroundService.ACTION_START_ACTIVE)) {
            val store = MknoonCallAdmissionSettlementStore({ now })
            val token = requireNotNull(store.register(payload(), owner))
            val runtime = SettlementForegroundRuntime().also { it.audio = action == MknoonCallForegroundService.ACTION_START_ACTIVE }
            val service = MknoonCallForegroundService(runtime, store)
            service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, token), 0, 1)
            service.onStartCommand(intent(action, token), 0, 2)
            var writes = 0
            assertFalse(store.settle(token) { writes++; true })
            service.onStartCommand(release(token), 0, 3)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(31))
            assertEquals(0, writes)
            assertFalse(runtime.operations.contains("stop"))
        }
    }

    @Test fun `runtime commit cannot write terminal receipt for disabled live or superseded ownership`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        var writes = 0
        var releases = 0
        fun commit(capability: Boolean, active: Boolean) = commitAuthenticatedAdmissionSettlement(
            store, token, capability, active, { _, _ -> writes++; true }, { releases++ })
        assertFalse(commit(false, false))
        assertFalse(commit(true, true))
        store.register(payload(), UUID.randomUUID())
        assertFalse(commit(true, false))
        assertEquals(0, writes)
        assertEquals(0, releases)
    }

    @Test fun `authenticated terminal receipt retires a duplicate new work wake but never another call`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val token = requireNotNull(store.register(payload(), owner))
        val terminal = mutableSetOf<UUID>()
        val runtime = SettlementForegroundRuntime().also { it.terminals = terminal }
        val service = MknoonCallForegroundService(runtime, store)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, token), 0, 1)
        assertTrue(commitAuthenticatedAdmissionSettlement(store, token, true, false,
            { id, expiry -> assertEquals(token.expiresAtMs, expiry); terminal += id; true },
            { service.onStartCommand(release(it), 0, 2) }))
        val duplicate = requireNotNull(store.register(payload(), UUID.randomUUID()))
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, duplicate), 0, 3)
        assertEquals(listOf("admission", "stop", "admission", "stop"), runtime.operations)
        val other = requireNotNull(store.register(payload(UUID.randomUUID()), UUID.randomUUID()))
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, other), 0, 4)
        service.onStartCommand(release(token), 0, 5)
        assertEquals(listOf("admission", "stop", "admission", "stop", "admission"), runtime.operations)
        assertEquals(setOf(call), terminal)
    }

    @Test fun `reordered old START cannot steal successor admission and its successful release`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val old = requireNotNull(store.register(payload(), owner))
        val next = requireNotNull(store.register(payload(), UUID.randomUUID()))
        val runtime = SettlementForegroundRuntime()
        val service = MknoonCallForegroundService(runtime, store)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, next), 0, 1)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, old), 0, 2)
        assertFalse(store.settle(old))
        assertTrue(store.settle(next))
        service.onStartCommand(release(next), 0, 3)
        assertEquals(listOf("admission", "stop"), runtime.operations)
    }

    @Test fun `decline reply and ordinary successor prevent runtime terminal write and service release`() {
        val store = MknoonCallAdmissionSettlementStore({ now })
        val reply = requireNotNull(store.register(payload(), owner, declineReply = true))
        val runtime = SettlementForegroundRuntime()
        val service = MknoonCallForegroundService(runtime, store)
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, reply)
            .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_DECLINE_REPLY, true), 0, 1)
        val next = requireNotNull(store.register(payload(), UUID.randomUUID()))
        service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, next), 0, 2)
        var writes = 0
        assertFalse(commitAuthenticatedAdmissionSettlement(store, next, true, false,
            { _, _ -> writes++; true }, { service.onStartCommand(release(it), 0, 3) }))
        service.onStartCommand(release(next), 0, 4)
        assertEquals(0, writes)
        assertEquals(listOf("admission"), runtime.operations)
    }

    @Test fun `ignored admission cannot later gain settlement authority after the live native owner exits`() {
        for (sameCall in listOf(true, false)) {
            val store = MknoonCallAdmissionSettlementStore({ now })
            val first = requireNotNull(store.register(payload(), owner))
            val runtime = SettlementForegroundRuntime()
            val service = MknoonCallForegroundService(runtime, store)
            service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, first), 0, 1)
            service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_RINGING, first), 0, 2)
            val ignored = requireNotNull(store.register(payload(if (sameCall) call else UUID.randomUUID()), UUID.randomUUID()))
            service.onStartCommand(intent(MknoonCallForegroundService.ACTION_START_ADMISSION, ignored), 0, 3)
            service.onStartCommand(intent(MknoonCallForegroundService.ACTION_STOP, first), 0, 4)
            var writes = 0
            assertNull(store.capture(ignored.nativeCallId))
            assertFalse(commitAuthenticatedAdmissionSettlement(store, ignored, true, false,
                { _, _ -> writes++; true }, {}))
            assertEquals(0, writes)
        }
    }

    private fun intent(action: String, token: MknoonCallAdmissionToken) = Intent(action)
        .putExtra(MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID, token.nativeCallId.toString())
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_OWNER_ID, token.ownerId.toString())
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_EXPIRES_AT_MS, token.expiresAtMs)
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_WAKE_HANDLE, token.wakeHandle)
    private fun release(token: MknoonCallAdmissionToken) = intent(MknoonCallForegroundService.ACTION_RELEASE_ADMISSION, token)
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_SETTLED_TOKEN, true)
        .putExtra(MknoonCallForegroundService.EXTRA_ADMISSION_REQUIRE_TERMINAL, false)
}

private class SettlementForegroundRuntime : MknoonCallForegroundRuntime {
    val operations = mutableListOf<String>()
    var audio = false
    var terminals: Set<UUID> = emptySet()
    override fun isTerminalLifecycle(nativeCallId: UUID) = nativeCallId in terminals
    override fun isAudioActive(nativeCallId: UUID) = audio
    override fun startAdmission(nativeCallId: UUID) { operations += "admission" }
    override fun startRinging(nativeCallId: UUID) { operations += "ringing" }
    override fun startActive(nativeCallId: UUID) { operations += "active" }
    override fun startInactive(nativeCallId: UUID) { operations += "inactive" }
    override fun stop(nativeCallId: UUID) { operations += "stop" }
}
