package com.mknoon.app.call

import android.content.Context
import android.content.Intent
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallActionReceiverTest {
    private lateinit var context: Context
    private lateinit var handler: RecordingCallActionHandler
    private lateinit var receiver: MknoonCallActionReceiver

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        handler = RecordingCallActionHandler()
        receiver = MknoonCallActionReceiver(handler = handler)
    }

    @Test
    fun `answer decline and end intents route one opaque call ID to lifecycle ownership`() {
        val callId = UUID.fromString(CALL_ID)

        receiver.onReceive(context, actionIntent(MknoonCallActionReceiver.ACTION_ANSWER, callId))
        receiver.onReceive(context, actionIntent(MknoonCallActionReceiver.ACTION_DECLINE, callId))
        receiver.onReceive(context, actionIntent(MknoonCallActionReceiver.ACTION_END, callId))

        assertEquals(listOf(callId), handler.answers)
        assertEquals(
            listOf(
                callId to PendingNativeCallEventType.DECLINE_REQUESTED,
                callId to PendingNativeCallEventType.END_REQUESTED,
            ),
            handler.terminals,
        )
    }

    @Test
    fun `malformed or unknown intents reject without touching lifecycle state`() {
        receiver.onReceive(context, null)
        receiver.onReceive(context, Intent("unknown"))
        receiver.onReceive(context, Intent(MknoonCallActionReceiver.ACTION_ANSWER))
        receiver.onReceive(
            context,
            Intent(MknoonCallActionReceiver.ACTION_ANSWER).putExtra(
                MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID,
                "not-a-uuid",
            ),
        )
        receiver.onReceive(
            context,
            Intent(MknoonCallActionReceiver.ACTION_ANSWER).putExtra(
                MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID,
                401L,
            ),
        )

        assertTrue(handler.answers.isEmpty())
        assertTrue(handler.terminals.isEmpty())
    }

    private fun actionIntent(action: String, nativeCallId: UUID): Intent =
        Intent(context, MknoonCallActionReceiver::class.java)
            .setAction(action)
            .putExtra(
                MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID,
                nativeCallId.toString(),
            )
}

private class RecordingCallActionHandler : MknoonCallActionHandler {
    val answers = mutableListOf<UUID>()
    val terminals = mutableListOf<Pair<UUID, PendingNativeCallEventType>>()

    override fun answer(nativeCallId: UUID): Boolean {
        answers += nativeCallId
        return true
    }

    override fun terminate(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): Boolean {
        terminals += nativeCallId to type
        return true
    }
}
