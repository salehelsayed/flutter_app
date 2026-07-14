package com.mknoon.app

import io.flutter.plugin.common.EventChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PictureInPictureExitClassifierTest {
    @Test
    fun `mode false then stop beyond the legacy return window is one system close`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.modeChanged(false)

        // Elapsed time alone is deliberately not an input to the classifier.
        // A late lifecycle callback must therefore remain authoritative instead
        // of a 150 ms timer inventing a return.
        harness.stop()
        harness.stop()
        harness.destroy()
        harness.resume()
        harness.windowFocusChanged(true)
        harness.fallbackTimeout()

        harness.assertSingleTerminal(state = "stopped", reason = "system_close")
    }

    @Test
    fun `mode false then delayed destroy is one system close and never restoring`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.modeChanged(false)
        harness.destroy()
        harness.destroy()
        harness.stop()
        harness.resume()
        harness.windowFocusChanged(true)

        harness.assertSingleTerminal(state = "stopped", reason = "system_close")
    }

    @Test
    fun `mode false then resume and focus is one system return`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.modeChanged(false)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.stop()
        harness.destroy()

        harness.assertSingleTerminal(state = "restoring", reason = "system_return")
    }

    @Test
    fun `mode false then focus and resume reorder is one system return`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.modeChanged(false)
        harness.windowFocusChanged(true)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.resume()
        harness.fallbackTimeout()

        harness.assertSingleTerminal(state = "restoring", reason = "system_return")
    }

    @Test
    fun `resume and focus signals reordered before mode false still return once`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.modeChanged(false)
        harness.modeChanged(false)
        harness.stop()
        harness.destroy()

        harness.assertSingleTerminal(state = "restoring", reason = "system_return")
    }

    @Test
    fun `pause clears stale return evidence and close stays terminal fenced`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.pause()
        harness.modeChanged(false)
        harness.stop()
        harness.windowFocusChanged(true)
        harness.resume()
        harness.modeChanged(false)
        harness.fallbackTimeout()

        harness.assertSingleTerminal(state = "stopped", reason = "system_close")
    }

    @Test
    fun `resume after pause cannot reuse focus from the prior active interval`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.resume()
        harness.windowFocusChanged(true)
        harness.pause()
        harness.modeChanged(false)

        // A fresh resume is only half of the return proof. Focus observed
        // before the intervening pause must not be reused across that boundary.
        harness.resume()
        assertTrue(harness.events.isEmpty())
        assertTrue(harness.decisions.isEmpty())

        harness.stop()
        harness.assertSingleTerminal(state = "stopped", reason = "system_close")
    }

    @Test
    fun `ambiguous exit timeout fails closed as non return exactly once`() {
        val harness = ExitHarness()

        harness.modeChanged(true)
        harness.modeChanged(false)
        assertTrue(harness.events.isEmpty())
        assertTrue(harness.decisions.isEmpty())

        harness.fallbackTimeout()
        harness.fallbackTimeout()
        harness.resume()
        harness.windowFocusChanged(true)
        harness.stop()
        harness.destroy()

        harness.assertSingleTerminal(state = "stopped", reason = "system_close")
    }

    @Test
    fun `unarmed lifecycle noise never produces an exit terminal`() {
        val harness = ExitHarness()

        harness.resume()
        harness.windowFocusChanged(true)
        harness.pause()
        harness.stop()
        harness.destroy()
        harness.fallbackTimeout()

        assertTrue(harness.events.isEmpty())
        assertTrue(harness.decisions.isEmpty())
        assertTrue(harness.registry.snapshot().active)
    }
}

private class ExitHarness {
    val classifier = PictureInPictureExitClassifier()
    val registry = PictureInPictureSessionRegistry(terminalLogger = {})
    val events = mutableListOf<Map<*, *>>()
    val decisions = mutableListOf<String>()

    init {
        registry.setEventSink(
            object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    events += event as Map<*, *>
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) = Unit

                override fun endOfStream() = Unit
            },
        )
        assertTrue(
            registry.begin(
                PictureInPictureSessionRequest(
                    session = SESSION,
                    attachment = ATTACHMENT,
                    path = "/canonical/app_flutter/media/video.mp4",
                    positionMs = 6_139,
                    durationMs = 12_000,
                ),
            ),
        )
    }

    fun modeChanged(inPictureInPicture: Boolean) =
        settle(classifier.onPictureInPictureModeChanged(inPictureInPicture))

    fun resume() = settle(classifier.onResume())

    fun pause() = settle(classifier.onPause())

    fun windowFocusChanged(hasFocus: Boolean) =
        settle(classifier.onWindowFocusChanged(hasFocus))

    fun stop() = settle(classifier.onStop())

    fun destroy() = settle(classifier.onDestroy())

    fun fallbackTimeout() = settle(classifier.onFallbackTimeout())

    fun assertSingleTerminal(state: String, reason: String) {
        assertEquals(listOf(reason), decisions)
        assertEquals(1, events.size)
        assertEquals(state, events.single()["state"])
        assertEquals(reason, events.single()["reason"])
        assertFalse(events.any { it["state"] == "restoring" && reason != "system_return" })
        assertFalse(registry.snapshot().active)
        assertNull(registry.snapshot().session)
    }

    private fun settle(reason: String?) {
        if (reason == null) return
        decisions += reason
        val state = PictureInPictureEventContract.TERMINAL_STATE_BY_REASON[reason]
            ?: error("Classifier returned a reason outside the native terminal contract: $reason")
        registry.terminate(
            session = SESSION,
            attachment = ATTACHMENT,
            state = state,
            reason = reason,
            observedPositionMs = 6_500,
            durationMs = 12_000,
        )
    }

    companion object {
        private const val SESSION = "exit-classifier-session"
        private const val ATTACHMENT = "exit-classifier-attachment"
    }
}
