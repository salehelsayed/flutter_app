package com.mknoon.app

import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [24, 34])
@LooperMode(LooperMode.Mode.PAUSED)
class AndroidCallWakeBridgeTest {
    @Test
    fun `coalesced wake waits for Dart ready and current foreground owner without acquiring recovery lease`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        var foregroundCalls = 0
        var readOnlyCalls = 0
        val foreground = AndroidCallWakeBridge(null, "foreground-1", registry) { complete ->
            foregroundCalls += 1
            complete(true)
        }
        val readOnly = AndroidCallWakeBridge(null, "firebase-read-only", registry) { complete ->
            readOnlyCalls += 1
            complete(true)
        }
        registry.signal()
        registry.signal()
        ready(foreground)
        ready(readOnly)
        assertEquals(0, foregroundCalls)
        val token = requireNotNull(broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND))
        assertNull(broker.acquire("recovery", "binding", CanonicalRuntimeLeaseBroker.Role.RECOVERY))
        foreground.ownerMayBeReady()
        assertEquals(1, foregroundCalls)
        assertEquals(0, readOnlyCalls)
        assertEquals(token.ownerId, broker.snapshot().ownerId)
        assertEquals(1, broker.snapshot().maximumConcurrentWritableOwners)
        foreground.dispose()
        readOnly.dispose()
    }

    @Test
    fun `ready is strict and a worker-thread wake only invokes Dart on main`() {
        val broker = CanonicalRuntimeLeaseBroker()
        broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        val threads = mutableListOf<Looper?>()
        val bridge = AndroidCallWakeBridge(null, "foreground-1", registry) { complete ->
            threads += Looper.myLooper()
            complete(true)
        }
        val malformed = Result()
        bridge.onMethodCall(MethodCall("ready", mapOf("callHandle" to "untrusted")), malformed)
        assertEquals("bad_args", malformed.error)
        Thread { registry.signal() }.apply { start(); join() }
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue(threads.isEmpty())
        ready(bridge)
        assertEquals(listOf(Looper.getMainLooper()), threads)
        bridge.dispose()
    }

    @Test
    fun `last registration never steals another canonical engine and draining owner cannot receive`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val firstToken = requireNotNull(broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND))
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        var first = 0
        var successor = 0
        val a = AndroidCallWakeBridge(null, "foreground-1", registry) { complete -> first++; complete(true) }
        val b = AndroidCallWakeBridge(null, "foreground-2", registry) { complete -> successor++; complete(true) }
        ready(a); ready(b)
        registry.signal()
        assertEquals(1, first)
        assertEquals(0, successor)
        assertTrue(broker.beginDrain(firstToken))
        registry.signal()
        assertEquals(1, first)
        assertTrue(broker.release(firstToken, databaseClosed = true))
        broker.acquire("foreground-2", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        b.ownerMayBeReady()
        assertEquals(1, successor)
        a.dispose()
        registry.signal()
        assertEquals(2, successor)
        assertEquals(1, first)
        b.dispose()
    }

    @Test
    fun `superseded registration disposal and readiness cannot disable same-engine successor`() {
        val broker = CanonicalRuntimeLeaseBroker()
        broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        var oldCalls = 0
        var newCalls = 0
        val old = AndroidCallWakeBridge(null, "foreground-1", registry) { complete -> oldCalls++; complete(true) }
        ready(old)
        val current = AndroidCallWakeBridge(null, "foreground-1", registry) { complete -> newCalls++; complete(true) }
        old.dispose()
        ready(old)
        registry.signal()
        assertEquals(0, newCalls)
        ready(current)
        assertEquals(0, oldCalls)
        assertEquals(1, newCalls)
        current.dispose()
        registry.signal()
        ready(current)
        assertEquals(1, newCalls)
    }

    @Test
    fun `signals during drain coalesce and a refused callback waits for a new signal`() {
        val broker = CanonicalRuntimeLeaseBroker()
        broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        val completions = mutableListOf<(Boolean) -> Unit>()
        val bridge = AndroidCallWakeBridge(null, "foreground-1", registry) { completions += it }
        ready(bridge)
        registry.signal()
        registry.signal()
        registry.signal()
        assertEquals(1, completions.size)
        completions[0](true)
        assertEquals(2, completions.size)
        completions[1](false)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(2, completions.size)
        registry.signal()
        assertEquals(3, completions.size)
        completions[2](true)
        bridge.dispose()
    }

    @Test
    fun `late refusal from released owner cannot create a wake for its successor`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val token = requireNotNull(broker.acquire("foreground-1", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND))
        val registry = AndroidCallWakeSignalRegistry(broker::snapshot)
        var reply: ((Boolean) -> Unit)? = null
        var calls = 0
        val old = AndroidCallWakeBridge(null, "foreground-1", registry) { reply = it }
        val current = AndroidCallWakeBridge(null, "foreground-2", registry) { complete -> calls++; complete(true) }
        ready(old); ready(current)
        registry.signal()
        broker.beginDrain(token)
        broker.release(token, databaseClosed = true)
        broker.acquire("foreground-2", "binding", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        requireNotNull(reply)(false)
        current.ownerMayBeReady()
        assertEquals(0, calls)
        registry.signal()
        assertEquals(1, calls)
        old.dispose(); current.dispose()
    }

    private fun ready(bridge: AndroidCallWakeBridge) {
        val result = Result()
        bridge.onMethodCall(MethodCall("ready", null), result)
        assertTrue(result.success)
        assertNull(result.value)
    }

    private class Result : MethodChannel.Result {
        var success = false
        var value: Any? = "not completed"
        var error: String? = null
        override fun success(result: Any?) { success = true; value = result }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() { error = "not_implemented" }
    }
}
