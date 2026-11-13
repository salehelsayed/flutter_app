package com.mknoon.app.call

import android.app.Activity
import android.app.PictureInPictureParams
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Guard for Kayan m-69a3dbc5 condition 2: without an arm (video gate off) nothing PiP happens. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CallPictureInPictureHandlerTest {
    class RecordingActivity : Activity() {
        var paramsSet = 0
        var enterRequests = 0
        override fun setPictureInPictureParams(params: PictureInPictureParams) {
            paramsSet++
        }
        override fun enterPictureInPictureMode(params: PictureInPictureParams): Boolean {
            enterRequests++
            return false
        }
    }

    private class Messenger : BinaryMessenger {
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            handlers[channel] = handler
        }

        fun call(method: String, arguments: Any?): Any? {
            val handler = requireNotNull(handlers[CallPictureInPictureHandler.METHOD_CHANNEL])
            val request = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            request.rewind()
            var value: Any? = null
            handler.onMessage(request) { response ->
                response!!.rewind()
                value = StandardMethodCodec.INSTANCE.decodeEnvelope(response)
            }
            return value
        }
    }

    @Test
    fun `no arm means no PiP params, no entry and no events`() {
        val activity = Robolectric.buildActivity(RecordingActivity::class.java).setup().get()
        val messenger = Messenger()
        val handler = CallPictureInPictureHandler(activity, messenger)
        handler.onUserLeaveHint()
        handler.onPictureInPictureModeChanged(true)
        handler.onPictureInPictureModeChanged(false)
        handler.onPause()
        handler.onStop()
        handler.onResume()
        assertEquals(0, activity.paramsSet)
        assertEquals(0, activity.enterRequests)
        handler.dispose()
        assertEquals(null, messenger.handlers[CallPictureInPictureHandler.METHOD_CHANNEL])
    }

    @Test
    fun `malformed calls fail closed without touching PiP`() {
        val activity = Robolectric.buildActivity(RecordingActivity::class.java).setup().get()
        val messenger = Messenger()
        val handler = CallPictureInPictureHandler(activity, messenger)
        val identity = mapOf("version" to 1, "instanceId" to "graph-a", "callId" to "call-1", "leaseId" to 1)
        assertEquals(
            mapOf("supported" to false, "cameraInPip" to false, "reason" to "invalid"),
            messenger.call("availability", mapOf("version" to 2)),
        )
        assertEquals(mapOf("armed" to false, "reason" to "invalid"), messenger.call("arm", identity))
        assertEquals(false, messenger.call("update", identity))
        assertEquals(false, messenger.call("enter", identity))
        assertEquals(false, messenger.call("disarm", identity)) // reason missing
        assertEquals(0, activity.paramsSet)
        assertEquals(0, activity.enterRequests)
        handler.dispose()
    }
}
