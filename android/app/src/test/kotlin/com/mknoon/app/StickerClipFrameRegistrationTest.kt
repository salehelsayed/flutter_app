package com.mknoon.app

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Calls MainActivity's actual narrow registration methods, without running
 * FlutterActivity.create(), engine initialization or Go native loading.
 * The messenger observes the unchanged real StickerClipFrameBridge.
 * Wiring into configure/cleanUp is checked separately by the host contract.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class StickerClipFrameRegistrationTest {
    @Test
    fun `replacement removes the old handler before installing on the same messenger`() {
        val activity = activity()
        val events = mutableListOf<String>()
        val messenger = RecordingMessenger("engine", events)
        try {
            attach(activity, messenger)
            messenger.assertCancelReplies()
            attach(activity, messenger)

            assertEquals(listOf("engine.attach", "engine.remove", "engine.attach"), events)
            // Close-after-create would erase the newly installed handler.
            messenger.assertCancelReplies()
        } finally {
            detach(activity)
        }
    }

    @Test
    fun `replacing an engine releases its messenger before attaching the successor`() {
        val activity = activity()
        val events = mutableListOf<String>()
        val old = RecordingMessenger("old", events)
        val next = RecordingMessenger("next", events)
        try {
            attach(activity, old)
            attach(activity, next)

            assertEquals(listOf("old.attach", "old.remove", "next.attach"), events)
            assertNull(old.handler)
            next.assertCancelReplies()
        } finally {
            detach(activity)
        }
        assertEquals("next.remove", events.last())
    }

    @Test
    fun `detach removes the handler immediately without a runtime shutdown callback`() {
        val activity = activity()
        val events = mutableListOf<String>()
        val messenger = RecordingMessenger("engine", events)
        attach(activity, messenger)
        messenger.assertCancelReplies()

        // Deliberately do not settle callBridgeTeardown or a Dart/Go runtime.
        detach(activity)
        assertNull(messenger.handler)
        assertEquals(listOf("engine.attach", "engine.remove"), events)

        detach(activity)
        assertEquals(listOf("engine.attach", "engine.remove"), events)
    }

    @Test
    fun `detach before setup and a fresh attachment after detach remain usable`() {
        val activity = activity()
        val events = mutableListOf<String>()
        val messenger = RecordingMessenger("engine", events)
        try {
            detach(activity)
            attach(activity, messenger)
            detach(activity)
            attach(activity, messenger)
            messenger.assertCancelReplies()
            assertEquals(listOf("engine.attach", "engine.remove", "engine.attach"), events)
        } finally {
            detach(activity)
        }
    }

    private fun activity(): MainActivity =
        Robolectric.buildActivity(MainActivity::class.java).get()

    private fun attach(activity: MainActivity, messenger: BinaryMessenger) {
        MainActivity::class.java
            .getDeclaredMethod("setupStickerClipFrameBridge", BinaryMessenger::class.java)
            .apply { isAccessible = true }
            .invoke(activity, messenger)
    }

    private fun detach(activity: MainActivity) {
        MainActivity::class.java
            .getDeclaredMethod("closeStickerClipFrameBridge")
            .apply { isAccessible = true }
            .invoke(activity)
    }

    private class RecordingMessenger(
        private val name: String,
        private val events: MutableList<String>,
    ) : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
            private set

        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) = Unit

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {
            assertEquals("mknoon/custom_sticker_clip_frames", channel)
            events.add("$name.${if (handler == null) "remove" else "attach"}")
            this.handler = handler
        }

        fun assertCancelReplies() {
            val active = handler
            assertNotNull("the current helper must retain its channel handler", active)
            val codec = StandardMethodCodec.INSTANCE
            val request = codec.encodeMethodCall(MethodCall("cancel", mapOf("jobId" to "probe")))
            request.rewind()
            var response: ByteBuffer? = null
            var replies = 0
            active!!.onMessage(request) {
                response = it
                replies += 1
            }
            assertEquals(1, replies)
            assertNotNull(response)
            response!!.rewind()
            assertNull(codec.decodeEnvelope(response!!))
        }
    }
}
