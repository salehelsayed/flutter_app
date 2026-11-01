package com.mknoon.app

import android.app.ActivityManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class GemmaPreviewChannelTest {
    @Test
    fun `capability uses total kernel-visible RAM while memory exposes current low-memory pressure`() {
        val context = RuntimeEnvironment.getApplication() as Context
        val manager = requireNotNull(context.getSystemService(ActivityManager::class.java))
        val info = ActivityManager.MemoryInfo().apply {
            totalMem = 54 * (1L shl 30) / 10
            availMem = 3L shl 30
            lowMemory = true
        }
        shadowOf(manager).setMemoryInfo(info)
        val messenger = IncomingMessenger()
        GemmaPreviewChannel.register(messenger, context)

        val capability = messenger.invoke("deviceCapabilities")
        assertEquals(info.totalMem, capability["physicalMemoryBytes"])
        assertEquals(30, capability["sdkInt"])
        val memory = messenger.invoke("memory")
        assertEquals(info.availMem, memory["availableBytes"])
        assertEquals(true, memory["lowMemory"])

        info.availMem = 4L shl 30
        info.lowMemory = false
        shadowOf(manager).setMemoryInfo(info)
        val recovered = messenger.invoke("memory")
        assertEquals(info.availMem, recovered["availableBytes"])
        assertEquals(false, recovered["lowMemory"])
    }

    private class IncomingMessenger : BinaryMessenger {
        private var handler: BinaryMessenger.BinaryMessageHandler? = null

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
            assertEquals("mknoon/gemma_preview", channel)
            this.handler = handler
        }

        fun invoke(method: String): Map<*, *> {
            val codec = StandardMethodCodec.INSTANCE
            val request = codec.encodeMethodCall(MethodCall(method, null))
            request.rewind()
            var response: ByteBuffer? = null
            handler!!.onMessage(request) { response = it }
            response!!.rewind()
            return codec.decodeEnvelope(response!!) as Map<*, *>
        }
    }
}
