package com.mknoon.app

import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaFormat
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.lang.reflect.InvocationTargetException
import java.nio.ByteBuffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowMediaExtractor
import org.robolectric.shadows.util.DataSource

/** Real bridge validation/conversion with controlled framework tracks and pixels. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class StickerClipFrameInputTest {
    @get:Rule
    val temporary = TemporaryFolder()

    @Test
    fun `camera video with muted AAC is accepted for frame-only extraction`() {
        // Pinned CameraX uses withAudioEnabled(initialMuted = true) for
        // enableAudio:false. The source still has an AAC track; this bridge
        // publishes only RGBA frames and never copies a source audio sample.
        withBridge { bridge ->
            validateTracks(bridge, clip("video/avc", "audio/mp4a-latm"))
        }
    }

    @Test
    fun `camera video without audio remains accepted`() {
        withBridge { bridge -> validateTracks(bridge, clip("video/hevc")) }
    }

    @Test
    fun `zero or multiple video tracks remain invalid`() {
        withBridge { bridge ->
            for (source in listOf(clip("audio/mp4a-latm"), clip("video/avc", "video/hevc"))) {
                val error = assertThrows(InvocationTargetException::class.java) {
                    validateTracks(bridge, source)
                }.cause!!
                val code = error.javaClass.getDeclaredField("code").apply { isAccessible = true }
                assertEquals("invalid_clip", code.get(error))
            }
        }
    }

    @Test
    fun `bitmap conversion preserves dark color and writes opaque RGBA`() {
        val frame = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        try {
            for (y in 0 until 512) {
                for (x in 0 until 512) {
                    frame.setPixel(x, y, if (x < 256) Color.rgb(25, 18, 12) else Color.rgb(15, 23, 28))
                }
            }
            val argb = IntArray(512 * 512)
            val rgba = ByteArray(512 * 512 * 4)
            withBridge { bridge ->
                StickerClipFrameBridge::class.java.getDeclaredMethod(
                    "writeFrame", Bitmap::class.java, List::class.java,
                    IntArray::class.java, ByteArray::class.java,
                ).apply { isAccessible = true }.invoke(
                    bridge, frame, listOf(0.0, 0.0, 1.0, 1.0), argb, rgba,
                )
            }
            fun pixel(x: Int): List<Int> =
                (0..3).map { rgba[4 * (256 * 512 + x) + it].toInt() and 0xff }
            assertEquals(listOf(25, 18, 12, 255), pixel(64))
            assertEquals(listOf(15, 23, 28, 255), pixel(448))
        } finally {
            frame.recycle()
        }
    }

    private fun clip(vararg mimes: String): File {
        val file = temporary.newFile()
        val source = DataSource.toDataSource(file.path)
        for (mime in mimes) {
            val format = MediaFormat().apply { setString(MediaFormat.KEY_MIME, mime) }
            ShadowMediaExtractor.addTrack(source, format, byteArrayOf())
        }
        return file
    }

    private fun validateTracks(bridge: StickerClipFrameBridge, clip: File) {
        StickerClipFrameBridge::class.java.getDeclaredMethod("validateTracks", File::class.java)
            .apply { isAccessible = true }.invoke(bridge, clip)
    }

    private fun withBridge(body: (StickerClipFrameBridge) -> Unit) {
        val messenger = object : BinaryMessenger {
            override fun send(channel: String, message: ByteBuffer?) = Unit
            override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
            override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
        }
        StickerClipFrameBridge(messenger, temporary.root).use(body)
    }
}
