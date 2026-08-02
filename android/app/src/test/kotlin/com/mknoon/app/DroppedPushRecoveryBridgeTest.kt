package com.mknoon.app

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DroppedPushRecoveryBridgeTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
    }

    @Test
    fun `method bridge reads without consuming and compare acknowledges exact generation`() {
        val store = DroppedPushRecoveryStore(context)
        val bridge = DroppedPushRecoveryBridge(context, messenger = null)
        assertEquals(1L, store.recordDeletion())

        val firstRead = CapturingBridgeResult()
        bridge.onMethodCall(MethodCall("pendingGeneration", null), firstRead)
        assertEquals(1L, firstRead.value)
        val secondRead = CapturingBridgeResult()
        bridge.onMethodCall(MethodCall("pendingGeneration", null), secondRead)
        assertEquals(1L, secondRead.value)

        val staleAck = CapturingBridgeResult()
        bridge.onMethodCall(
            MethodCall("acknowledgeGeneration", mapOf("generation" to 99L)),
            staleAck,
        )
        assertEquals(false, staleAck.value)
        assertEquals(1L, store.pendingGeneration())

        val exactAck = CapturingBridgeResult()
        bridge.onMethodCall(
            MethodCall("acknowledgeGeneration", mapOf("generation" to 1L)),
            exactAck,
        )
        assertEquals(true, exactAck.value)
        assertNull(store.pendingGeneration())
    }

    @Test
    fun `warm recovery intent accelerates with current marker and never consumes it`() {
        val signalled = mutableListOf<Long>()
        val bridge = DroppedPushRecoveryBridge(
            context,
            messenger = null,
            recoverySignal = { generation -> signalled.add(generation) },
        )
        val store = DroppedPushRecoveryStore(context)
        assertEquals(1L, store.recordDeletion())

        assertFalse(bridge.onWarmIntent(Intent("unrelated")))
        assertTrue(
            bridge.onWarmIntent(
                Intent(MknoonFirebaseMessagingService.RECOVERY_INTENT_ACTION)
                    .putExtra(MknoonFirebaseMessagingService.RECOVERY_GENERATION_EXTRA, 1L),
            ),
        )

        assertEquals(listOf(1L), signalled)
        assertEquals(1L, store.pendingGeneration())
    }

    @Test
    fun `fractional acknowledgement is rejected without truncating generation`() {
        val store = DroppedPushRecoveryStore(context)
        assertEquals(1L, store.recordDeletion())
        val bridge = DroppedPushRecoveryBridge(context, messenger = null)

        val result = CapturingBridgeResult()
        bridge.onMethodCall(
            MethodCall("acknowledgeGeneration", mapOf("generation" to 1.9)),
            result,
        )

        assertEquals("bad_args", result.value)
        assertEquals(1L, store.pendingGeneration())
    }

    @Test
    fun `bridge initialization cancels only an orphan recovery card`() {
        val cancellations = mutableListOf<String>()
        DroppedPushRecoveryBridge(
            context,
            messenger = null,
            cancelRecoveryNotification = { cancellations += "orphan" },
        )
        assertEquals(listOf("orphan"), cancellations)

        val store = DroppedPushRecoveryStore(context)
        assertEquals(1L, store.recordDeletion())
        DroppedPushRecoveryBridge(
            context,
            messenger = null,
            cancelRecoveryNotification = { cancellations += "pending" },
        )
        assertEquals(listOf("orphan"), cancellations)
    }
}

private class CapturingBridgeResult : MethodChannel.Result {
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
