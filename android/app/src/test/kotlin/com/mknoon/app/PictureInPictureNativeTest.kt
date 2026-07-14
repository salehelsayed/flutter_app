package com.mknoon.app

import android.app.Activity
import android.content.Intent
import android.media.AudioManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLog
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PictureInPictureNativeTest {
    @Test
    fun `owned path authority is canonical app documents media only`() {
        val sandbox = Files.createTempDirectory("pip-owned-path").toFile()
        val dataRoot = File(sandbox, "data").apply { mkdirs() }
        val documentsRoot = File(dataRoot, "app_flutter").apply { mkdirs() }
        val mediaRoot = File(documentsRoot, "media").apply { mkdirs() }
        val owned = File(mediaRoot, "received.mp4").apply { writeText("fixture") }
        val filesMedia = File(dataRoot, "files/media").apply { mkdirs() }
        val legacy = File(filesMedia, "received.mp4").apply { writeText("fixture") }
        val outside = File(sandbox, "outside.mp4").apply { writeText("fixture") }
        try {
            assertEquals(
                owned.canonicalFile,
                PictureInPictureHandler.resolveOwnedPath(dataRoot.path, owned.path),
            )
            assertNull(PictureInPictureHandler.resolveOwnedPath(dataRoot.path, legacy.path))
            assertNull(PictureInPictureHandler.resolveOwnedPath(dataRoot.path, outside.path))
            assertNull(
                PictureInPictureHandler.resolveOwnedPath(
                    dataRoot.path,
                    File(mediaRoot, "missing.mp4").path,
                ),
            )
        } finally {
            sandbox.deleteRecursively()
        }
    }

    @Test
    fun `capability and channel methods fail closed and accept exact schemas only`() {
        val activity = activity()
        val registry = PictureInPictureSessionRegistry()
        val launches = mutableListOf<Intent>()
        val handler = PictureInPictureHandler(
            activity = activity,
            messenger = null,
            registry = registry,
            sdkInt = 34,
            hasPictureInPictureFeature = { true },
            resolveOwnedVideo = { File("/canonical/app_flutter/media/video.mp4") },
            launchActivity = launches::add,
        )

        assertEquals(
            mapOf("supported" to true),
            handler.call("capability", null).value,
        )
        assertEquals(
            "bad_args",
            handler.call("capability", emptyMap<String, Any>()).errorCode,
        )

        val request = startArguments()
        val extra = handler.call("start", request + ("message" to "forbidden"))
        assertEquals("bad_args", extra.errorCode)
        assertFalse(registry.snapshot().active)

        val started = handler.call("start", request)
        assertEquals(mapOf("accepted" to true), started.value)
        assertEquals(1, launches.size)
        assertEquals(
            "session-1",
            launches.single().getStringExtra(PictureInPictureHandler.SESSION_EXTRA),
        )
        assertFalse(launches.single().hasExtra("path"))
        assertFalse(launches.single().hasExtra("attachment"))

        val malformedFence = handler.call(
            "stop",
            mapOf("session" to "session-1", "attachment" to "attachment-1", "reason" to "forbidden"),
        )
        assertEquals("bad_args", malformedFence.errorCode)

        handler.dispose("flutter_engine_detached")
        assertFalse(registry.snapshot().active)
        assertEquals("pip_unavailable", handler.call("capability", null).errorCode)
    }

    @Test
    fun `api and feature capability hide unsupported devices without launch`() {
        assertFalse(PictureInPictureHandler.isSupported(25, true))
        assertFalse(PictureInPictureHandler.isSupported(26, false))
        assertTrue(PictureInPictureHandler.isSupported(26, true))

        val launches = mutableListOf<Intent>()
        val handler = PictureInPictureHandler(
            activity = activity(),
            messenger = null,
            registry = PictureInPictureSessionRegistry(),
            sdkInt = 25,
            hasPictureInPictureFeature = { true },
            resolveOwnedVideo = { File("/should/not/be/resolved") },
            launchActivity = launches::add,
        )
        assertEquals(mapOf("supported" to false), handler.call("capability", null).value)
        assertEquals("unsupported", handler.call("start", startArguments()).errorCode)
        assertTrue(launches.isEmpty())
    }

    @Test
    fun `registry fences events keeps monotonic checkpoint and settles once`() {
        val registry = PictureInPictureSessionRegistry()
        val events = mutableListOf<Map<*, *>>()
        registry.setEventSink(capturingSink(events))
        assertTrue(registry.begin(request(positionMs = 3_900, durationMs = 12_000)))
        assertFalse(registry.begin(request(positionMs = 0, durationMs = null)))

        assertTrue(registry.nativeReady("session-1", "attachment-1", 3_900, 12_000))
        assertTrue(registry.active("session-1", "attachment-1"))
        assertFalse(registry.checkpoint("stale", "attachment-1", 9_000, 12_000))
        assertTrue(registry.checkpoint("session-1", "attachment-1", 6_139, 12_000))
        assertFalse(
            registry.terminate(
                session = "session-1",
                attachment = "attachment-1",
                state = "restoring",
                reason = "system_close",
                observedPositionMs = 0,
                durationMs = 12_000,
            ),
        )
        assertTrue(
            registry.terminate(
                session = "session-1",
                attachment = "attachment-1",
                state = "stopped",
                reason = "system_close",
                observedPositionMs = 0,
                durationMs = 12_000,
            ),
        )
        assertFalse(
            registry.terminate(
                session = "session-1",
                attachment = "attachment-1",
                state = "restoring",
                reason = "system_return",
                observedPositionMs = 8_000,
                durationMs = 12_000,
            ),
        )

        assertEquals(
            listOf("nativeReady", "active", "checkpoint", "stopped"),
            events.map { it["state"] },
        )
        assertEquals(6_139, events.last()["positionMs"])
        assertEquals("system_close", events.last()["reason"])
        assertTrue(
            events.all {
                it.keys == setOf(
                    "session",
                    "attachment",
                    "state",
                    "positionMs",
                    "durationMs",
                    "reason",
                )
            },
        )
        assertEquals(
            PictureInPictureSessionSnapshot(false, null, null, null, null),
            registry.snapshot(),
        )
    }

    @Test
    fun `terminal state reason compatibility matches Dart exactly`() {
        assertEquals(
            mapOf(
                "system_return" to "restoring",
                "system_close" to "stopped",
                "explicit_stop" to "stopped",
                "interrupted" to "stopped",
                "completed" to "completed",
                "activity_destroyed" to "stopped",
                "flutter_engine_detached" to "stopped",
                "host_destroyed" to "stopped",
                "playback_error" to "failed",
            ),
            PictureInPictureEventContract.TERMINAL_STATE_BY_REASON,
        )
        assertFalse(PictureInPictureEventContract.isTerminalCompatible("failed", "system_close"))
        assertFalse(PictureInPictureEventContract.isTerminalCompatible("stopped", "system_return"))
    }

    @Test
    fun `completion resets zero and engine detach has one terminal`() {
        val registry = PictureInPictureSessionRegistry()
        val events = mutableListOf<Map<*, *>>()
        registry.setEventSink(capturingSink(events))
        assertTrue(registry.begin(request(positionMs = 400, durationMs = null)))
        assertTrue(
            registry.terminate(
                session = "session-1",
                attachment = "attachment-1",
                state = "completed",
                reason = "completed",
                observedPositionMs = 9_999,
                durationMs = 12_000,
            ),
        )
        assertEquals(0, events.single()["positionMs"])
        assertEquals("completed", events.single()["state"])

        events.clear()
        ShadowLog.clear()
        assertTrue(registry.begin(request(positionMs = 5_220, durationMs = 12_000)))
        assertTrue(registry.stopCurrent("flutter_engine_detached"))
        assertFalse(registry.stopCurrent("host_destroyed"))
        assertEquals(1, events.size)
        assertEquals("stopped", events.single()["state"])
        assertEquals("flutter_engine_detached", events.single()["reason"])
        assertEquals(5_220, events.single()["positionMs"])
        val terminalLogs = ShadowLog.getLogsForTag("MknoonPiP")
            .map { it.msg }
            .filter { it.startsWith("[MKNOON_PIP] TERMINAL") }
        assertEquals(
            listOf(
                "[MKNOON_PIP] TERMINAL " +
                    "state=stopped reason=flutter_engine_detached",
            ),
            terminalLogs,
        )
        assertFalse(terminalLogs.single().contains("session-1"))
        assertFalse(terminalLogs.single().contains("attachment-1"))
    }

    @Test
    fun `audio focus loss and transient loss each settle interrupted exactly once`() {
        for (
            focusChange in listOf(
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            )
        ) {
            val events = mutableListOf<Map<*, *>>()
            ShadowLog.clear()
            val (activity, listener) = focusActivity(events)

            listener.onAudioFocusChange(focusChange)
            listener.onAudioFocusChange(focusChange)

            assertEquals(1, events.size)
            assertEquals("stopped", events.single()["state"])
            assertEquals("interrupted", events.single()["reason"])
            assertFalse(PictureInPictureProcessRegistry.registry.snapshot().active)
            val terminals = ShadowLog.getLogsForTag("MknoonPiP")
                .map { it.msg }
                .filter { it.startsWith("[MKNOON_PIP] TERMINAL") }
            assertEquals(
                listOf(
                    "[MKNOON_PIP] TERMINAL state=stopped reason=interrupted",
                ),
                terminals,
            )
            assertTrue(activity.isFinishing)
        }
    }

    @Test
    fun `audio focus gain and duck never settle while later loss still settles once`() {
        val events = mutableListOf<Map<*, *>>()
        ShadowLog.clear()
        val (_, listener) = focusActivity(events)

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_GAIN)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK)

        assertTrue(PictureInPictureProcessRegistry.registry.snapshot().active)
        assertTrue(events.isEmpty())
        assertTrue(
            ShadowLog.getLogsForTag("MknoonPiP")
                .none { it.msg.startsWith("[MKNOON_PIP] TERMINAL") },
        )

        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        listener.onAudioFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        assertEquals(1, events.size)
        assertEquals("stopped", events.single()["state"])
        assertEquals("interrupted", events.single()["reason"])
        assertEquals(
            1,
            ShadowLog.getLogsForTag("MknoonPiP")
                .count { it.msg.startsWith("[MKNOON_PIP] TERMINAL") },
        )
    }

    @Test
    fun `engine cleanup coordinator is weak bound idempotent and delivers the real callback`() {
        val callbackOwners = mutableListOf<Any>()
        val binding = PictureInPictureEngineCleanupBinding<Any>(callbackOwners::add)
        val owner = Any()
        binding.bind(owner)
        assertTrue(binding.cleanUpFlutterEngine())
        assertFalse(binding.cleanUpFlutterEngine())
        assertEquals(listOf(owner), callbackOwners)

        val registry = PictureInPictureSessionRegistry()
        val events = mutableListOf<Map<*, *>>()
        registry.setEventSink(capturingSink(events))
        val handler = PictureInPictureHandler(
            activity = activity(),
            messenger = null,
            registry = registry,
            sdkInt = 34,
            hasPictureInPictureFeature = { true },
            resolveOwnedVideo = { File("/canonical/app_flutter/media/video.mp4") },
            launchActivity = {},
        )
        assertTrue(registry.begin(request(positionMs = 5_220, durationMs = 12_000)))

        assertTrue(PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine())
        assertFalse(PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine())
        assertEquals(1, events.size)
        assertEquals("stopped", events.single()["state"])
        assertEquals("flutter_engine_detached", events.single()["reason"])
        assertEquals("pip_unavailable", handler.call("capability", null).errorCode)
    }

    private fun activity(): Activity =
        Robolectric.buildActivity(Activity::class.java).setup().get()

    private fun focusActivity(
        events: MutableList<Map<*, *>>,
    ): Pair<ReceivedVideoPictureInPictureActivity, AudioManager.OnAudioFocusChangeListener> {
        val registry = PictureInPictureProcessRegistry.registry
        assertFalse(registry.snapshot().active)
        registry.setEventSink(capturingSink(events))
        val current = request(positionMs = 4_000, durationMs = 72_000)
        assertTrue(registry.begin(current))
        val activity = Robolectric
            .buildActivity(ReceivedVideoPictureInPictureActivity::class.java)
            .get()
        ReceivedVideoPictureInPictureActivity::class.java
            .getDeclaredField("request")
            .apply { isAccessible = true }
            .set(activity, current)
        val listener = ReceivedVideoPictureInPictureActivity::class.java
            .getDeclaredField("audioFocusListener")
            .apply { isAccessible = true }
            .get(activity) as AudioManager.OnAudioFocusChangeListener
        return activity to listener
    }

    private fun request(
        positionMs: Int,
        durationMs: Int?,
    ): PictureInPictureSessionRequest = PictureInPictureSessionRequest(
        session = "session-1",
        attachment = "attachment-1",
        path = "/canonical/app_flutter/media/video.mp4",
        positionMs = positionMs,
        durationMs = durationMs,
    )

    private fun startArguments(): Map<String, Any?> = mapOf(
        "session" to "session-1",
        "attachment" to "attachment-1",
        "path" to "/canonical/app_flutter/media/video.mp4",
        "positionMs" to 3_900,
        "durationMs" to 12_000,
    )

    private fun PictureInPictureHandler.call(
        method: String,
        arguments: Any?,
    ): PictureInPictureCapturingResult {
        val result = PictureInPictureCapturingResult()
        onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private fun capturingSink(events: MutableList<Map<*, *>>): EventChannel.EventSink =
        object : EventChannel.EventSink {
            override fun success(event: Any?) {
                events += event as Map<*, *>
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
            override fun endOfStream() = Unit
        }
}

private class PictureInPictureCapturingResult : MethodChannel.Result {
    var settlements = 0
    var value: Any? = null
    var errorCode: String? = null
    var errorDetails: Any? = null
    var notImplementedCount = 0

    override fun success(result: Any?) {
        settlements++
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        settlements++
        this.errorCode = errorCode
        this.errorDetails = errorDetails
    }

    override fun notImplemented() {
        settlements++
        notImplementedCount++
    }
}
