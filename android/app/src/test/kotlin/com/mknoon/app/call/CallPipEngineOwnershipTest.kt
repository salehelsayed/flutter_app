package com.mknoon.app.call

import android.app.Activity
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.LocalTrack
import io.flutter.plugin.common.BinaryMessenger
import java.nio.ByteBuffer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.webrtc.MediaStreamTrack

/** Multiple engines must not redirect a call's exact remote-track lookup. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class CallPipEngineOwnershipTest {
    private val previousPlugin = FlutterWebRTCPlugin.sharedSingleton
    private val source = CallPipSource("ui-peer", "remote-video")

    private class RecordingPlugin(private val localCollision: Boolean = false) : FlutterWebRTCPlugin() {
        val localReads = mutableListOf<String>()
        val peerReads = mutableListOf<Pair<String, String>>()

        override fun getLocalTrack(trackId: String): LocalTrack? {
            localReads += trackId
            return if (localCollision) LocalTrack(null) else null
        }

        override fun getTrackForId(trackId: String, peerConnectionId: String): MediaStreamTrack? {
            peerReads += trackId to peerConnectionId
            // Missing native track keeps this ownership test independent of EGL/JNI.
            return null
        }
    }

    private class Messenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
    }

    @After
    fun restoreTestOwnedSingleton() {
        FlutterWebRTCPlugin.sharedSingleton = previousPlugin
    }

    @Test
    fun `arm lookup uses UI engine when another plugin already owns the singleton`() {
        val ui = RecordingPlugin()
        val foreign = RecordingPlugin()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val handler = CallPictureInPictureHandler(activity, Messenger(), ui)
        try {
            assertFalse(handler.hasVideoTrack(source))
            assertEquals(listOf("remote-video"), ui.localReads)
            assertEquals(listOf("remote-video" to "ui-peer"), ui.peerReads)
            assertEquals(emptyList<String>(), foreign.localReads)
            assertEquals(emptyList<Pair<String, String>>(), foreign.peerReads)
        } finally {
            handler.dispose()
        }
    }

    @Test
    fun `sink lookup keeps UI engine after a later plugin replaces the singleton`() {
        val ui = RecordingPlugin()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val handler = CallPictureInPictureHandler(activity, Messenger(), ui)
        val foreign = RecordingPlugin()
        try {
            assertNull(handler.attachSink(source))
            assertEquals(listOf("remote-video"), ui.localReads)
            assertEquals(listOf("remote-video" to "ui-peer"), ui.peerReads)
            assertEquals(emptyList<String>(), foreign.localReads)
            assertEquals(emptyList<Pair<String, String>>(), foreign.peerReads)
        } finally {
            handler.dispose()
        }
    }

    @Test
    fun `missing UI plugin never borrows another engine's registry`() {
        FlutterWebRTCPlugin.sharedSingleton = null
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val handler = CallPictureInPictureHandler(activity, Messenger(), null)
        val foreign = RecordingPlugin()
        try {
            assertFalse(handler.hasVideoTrack(source))
            assertNull(handler.attachSink(source))
            assertEquals(emptyList<String>(), foreign.localReads)
            assertEquals(emptyList<Pair<String, String>>(), foreign.peerReads)
        } finally {
            handler.dispose()
        }
    }

    @Test
    fun `two foreground handlers retain their own engine registries`() {
        val first = RecordingPlugin()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val firstHandler = CallPictureInPictureHandler(activity, Messenger(), first)
        val second = RecordingPlugin()
        val secondHandler = CallPictureInPictureHandler(activity, Messenger(), second)
        try {
            assertFalse(firstHandler.hasVideoTrack(source))
            assertFalse(secondHandler.hasVideoTrack(source))
            assertEquals(listOf("remote-video" to "ui-peer"), first.peerReads)
            assertEquals(listOf("remote-video" to "ui-peer"), second.peerReads)
        } finally {
            firstHandler.dispose()
            secondHandler.dispose()
        }
    }

    @Test
    fun `single UI engine preserves exact peer and track arguments`() {
        val ui = RecordingPlugin()
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val handler = CallPictureInPictureHandler(activity, Messenger(), ui)
        try {
            assertFalse(handler.hasVideoTrack(source))
            assertEquals(listOf("remote-video"), ui.localReads)
            assertEquals(listOf("remote-video" to "ui-peer"), ui.peerReads)
        } finally {
            handler.dispose()
        }
    }

    @Test
    fun `local collision is rejected before exact peer lookup`() {
        val ui = RecordingPlugin(localCollision = true)
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val handler = CallPictureInPictureHandler(activity, Messenger(), ui)
        try {
            assertFalse(handler.hasVideoTrack(source))
            assertEquals(listOf("remote-video"), ui.localReads)
            assertEquals(emptyList<Pair<String, String>>(), ui.peerReads)
        } finally {
            handler.dispose()
        }
    }
}
