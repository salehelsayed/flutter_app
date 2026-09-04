package com.mknoon.app.call

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.UUID

internal interface MknoonCallActionHandler {
    fun answer(nativeCallId: UUID): Boolean

    fun terminate(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): Boolean
}

/** Explicit, non-exported notification action boundary. */
internal class MknoonCallActionReceiver(
    private val handler: MknoonCallActionHandler? = null,
) : BroadcastReceiver() {
    companion object {
        const val ACTION_ANSWER = "com.mknoon.app.call.action.ANSWER"
        const val ACTION_DECLINE = "com.mknoon.app.call.action.DECLINE"
        const val ACTION_END = "com.mknoon.app.call.action.END"
        const val EXTRA_NATIVE_CALL_ID = "com.mknoon.app.call.extra.NATIVE_CALL_ID"
        private val ACTIONS = setOf(ACTION_ANSWER, ACTION_DECLINE, ACTION_END)
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action !in ACTIONS) return
        val rawCallId = intent.extras?.get(EXTRA_NATIVE_CALL_ID) as? String ?: return
        val nativeCallId = runCatching { UUID.fromString(rawCallId) }.getOrNull() ?: return
        val target = handler ?: MknoonCallRuntime.get(context).controller
        when (action) {
            ACTION_ANSWER -> target.answer(nativeCallId)
            ACTION_DECLINE -> target.terminate(
                nativeCallId,
                PendingNativeCallEventType.DECLINE_REQUESTED,
            )
            ACTION_END -> target.terminate(
                nativeCallId,
                PendingNativeCallEventType.END_REQUESTED,
            )
        }
    }
}
