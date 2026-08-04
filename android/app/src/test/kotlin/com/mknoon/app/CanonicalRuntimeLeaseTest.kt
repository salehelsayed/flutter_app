package com.mknoon.app

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CanonicalRuntimeLeaseTest {
    @Test
    fun `foreground worker and fcm ownership matrix permits one writable owner`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val foreground = broker.acquire(
            ownerId = "foreground-engine",
            binding = "installation-a/account-a",
            role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
        )

        assertNotNull(foreground)
        assertNull(
            broker.acquire(
                ownerId = "fcm-engine",
                binding = "installation-a/account-a",
                role = CanonicalRuntimeLeaseBroker.Role.FIREBASE_READ_ONLY,
            ),
        )
        assertNull(
            broker.acquire(
                ownerId = "recovery-engine",
                binding = "installation-a/account-a",
                role = CanonicalRuntimeLeaseBroker.Role.RECOVERY,
            ),
        )
        assertEquals(1, broker.snapshot().maximumConcurrentWritableOwners)
    }

    @Test
    fun `database close fences transfer and close failure retains owner`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val foreground = requireNotNull(
            broker.acquire(
                "foreground-engine",
                "installation-a/account-a",
                CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
            ),
        )

        assertTrue(broker.beginDrain(foreground))
        assertFalse(broker.release(foreground, databaseClosed = false))
        assertEquals(CanonicalRuntimeLeaseBroker.State.DRAINING, broker.snapshot().state)
        assertNull(
            broker.acquire(
                "recovery-engine",
                "installation-a/account-a",
                CanonicalRuntimeLeaseBroker.Role.RECOVERY,
            ),
        )

        assertTrue(broker.release(foreground, databaseClosed = true))
        val recovery = broker.acquire(
            "recovery-engine",
            "installation-a/account-a",
            CanonicalRuntimeLeaseBroker.Role.RECOVERY,
        )
        assertNotNull(recovery)
        assertFalse(broker.release(foreground, databaseClosed = true))
        assertEquals(2L, recovery?.generation)
    }

    @Test
    fun `active owner can rotate opaque account binding without opening a second writer`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val accountA = requireNotNull(
            broker.acquire(
                "foreground-engine",
                "v1:opaque-account-a",
                CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
            ),
        )

        val accountB = requireNotNull(
            broker.rebind(accountA, "v1:opaque-account-b"),
        )

        assertEquals(accountA.generation, accountB.generation)
        assertEquals("v1:opaque-account-b", broker.snapshot().binding)
        assertEquals(1, broker.snapshot().maximumConcurrentWritableOwners)
        assertFalse(broker.beginDrain(accountA))
        assertTrue(broker.beginDrain(accountB))
    }

    @Test
    fun `method channel binds owner identity and requires explicit close acknowledgement`() {
        val broker = CanonicalRuntimeLeaseBroker()
        val bridge = CanonicalRuntimeLeaseBridge(
            messenger = null,
            ownerId = "foreground-engine",
            role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
            broker = broker,
        )

        val acquire = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("acquire", mapOf("binding" to "installation-a/account-a")),
            acquire,
        )
        val token = acquire.value as Map<*, *>
        assertEquals("ACTIVE", token["state"])

        val drain = LeaseCapturingResult()
        bridge.onMethodCall(MethodCall("beginDrain", null), drain)
        assertEquals(true, drain.value)

        val failedClose = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("release", mapOf("databaseClosed" to false)),
            failedClose,
        )
        assertEquals(false, failedClose.value)

        val close = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("release", mapOf("databaseClosed" to true)),
            close,
        )
        assertEquals(true, close.value)
        bridge.dispose()
    }

    @Test
    fun `close failure retry accepts an already quiesced Go runtime`() {
        val broker = CanonicalRuntimeLeaseBroker()
        var runtimeReleased = false
        var drainCalls = 0
        val bridge = CanonicalRuntimeLeaseBridge(
            messenger = null,
            ownerId = "recovery-engine",
            role = CanonicalRuntimeLeaseBroker.Role.RECOVERY,
            broker = broker,
            attachRuntimeOwner = { true },
            beginRuntimeDrain = {
                drainCalls += 1
                true
            },
            isRuntimeReleased = { runtimeReleased },
        )

        val acquire = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("acquire", mapOf("binding" to "v1:opaque")),
            acquire,
        )
        val attach = LeaseCapturingResult()
        bridge.onMethodCall(MethodCall("attachRuntime", null), attach)
        assertEquals(true, attach.value)

        val firstDrain = LeaseCapturingResult()
        bridge.onMethodCall(MethodCall("beginDrain", null), firstDrain)
        assertEquals(true, firstDrain.value)
        assertEquals(1, drainCalls)
        runtimeReleased = true

        val failedClose = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("release", mapOf("databaseClosed" to false)),
            failedClose,
        )
        assertEquals(false, failedClose.value)

        val retryDrain = LeaseCapturingResult()
        bridge.onMethodCall(MethodCall("beginDrain", null), retryDrain)
        assertEquals(true, retryDrain.value)
        assertEquals(1, drainCalls)
        val close = LeaseCapturingResult()
        bridge.onMethodCall(
            MethodCall("release", mapOf("databaseClosed" to true)),
            close,
        )
        assertEquals(true, close.value)
    }
}

private class LeaseCapturingResult : MethodChannel.Result {
    var value: Any? = null

    override fun success(result: Any?) {
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        value = errorCode
    }

    override fun notImplemented() {
        value = "not_implemented"
    }
}
