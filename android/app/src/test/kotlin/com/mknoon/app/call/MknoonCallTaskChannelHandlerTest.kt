package com.mknoon.app.call

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Beta 2026-09-25 (F4): Back during a call must send the app to the
 * background (like other calling apps) instead of closing the task.
 */
class MknoonCallTaskChannelHandlerTest {
    @Test fun `device unlock probe reflects locked unlocked and unavailable without moving the task`() {
        for (unlocked in listOf(false, true)) {
            val result = TaskResult()
            MknoonCallTaskChannelHandler(isDeviceUnlocked = { unlocked }, moveTaskToBack = { error("must not move") })
                .onMethodCall(MethodCall("isDeviceUnlocked", null), result)
            assertEquals(unlocked, result.value)
        }
        val unavailable = TaskResult()
        MknoonCallTaskChannelHandler(isDeviceUnlocked = { error("unavailable") }, moveTaskToBack = { true })
            .onMethodCall(MethodCall("isDeviceUnlocked", null), unavailable)
        assertEquals(false, unavailable.value)
    }
    @Test fun `device unlock probe fails closed when no activity probe exists`() {
        val result = TaskResult()
        MknoonCallTaskChannelHandler { true }
            .onMethodCall(MethodCall("isDeviceUnlocked", null), result)
        assertEquals(false, result.value)
    }
    @Test fun `moveToBackground moves the whole task to the back`() {
        var moves = 0
        val handler = MknoonCallTaskChannelHandler { moves += 1; true }
        val result = TaskResult()

        handler.onMethodCall(MethodCall("moveToBackground", null), result)

        assertEquals(1, moves)
        assertEquals(true, result.value)
        assertEquals(null, result.errorCode)
        assertEquals("mknoon/call_task", MknoonCallTaskChannelHandler.CHANNEL)
    }

    @Test fun `a refused or failing move reports false and never throws`() {
        val refused = TaskResult()
        MknoonCallTaskChannelHandler { false }
            .onMethodCall(MethodCall("moveToBackground", null), refused)
        assertEquals(false, refused.value)

        val failing = TaskResult()
        MknoonCallTaskChannelHandler { error("activity gone") }
            .onMethodCall(MethodCall("moveToBackground", null), failing)
        assertEquals(false, failing.value)
    }

    @Test fun `unexpected arguments or methods do not move the task`() {
        var moves = 0
        val handler = MknoonCallTaskChannelHandler { moves += 1; true }

        val badArgs = TaskResult()
        handler.onMethodCall(MethodCall("moveToBackground", mapOf("x" to 1)), badArgs)
        assertEquals("bad_args", badArgs.errorCode)

        val unknown = TaskResult()
        handler.onMethodCall(MethodCall("finish", null), unknown)
        assertTrue(unknown.notImplemented)

        assertEquals(0, moves)
        assertFalse(badArgs.notImplemented)
    }

    @Test fun `while a call owns Back an overlay back callback moves the task to the back`() {
        var moves = 0
        val registered = mutableListOf<() -> Unit>()
        var unregistered = 0
        val handler = MknoonCallTaskChannelHandler(
            moveTaskToBack = { moves += 1; true },
            registerBack = { action ->
                registered += action
                ({ unregistered += 1 })
            },
        )
        fun owns(value: Any?) = TaskResult().also {
            handler.onMethodCall(MethodCall("setCallOwnsBack", mapOf("owns" to value)), it)
        }

        assertEquals(true, owns(true).value)
        assertEquals(true, owns(true).value)
        assertEquals(1, registered.size)

        // A predictive swipe or the Back key reaches the overlay callback
        // before Flutter's own callback, so no hidden route is popped.
        registered.single().invoke()
        assertEquals(1, moves)

        assertEquals(true, owns(false).value)
        assertEquals(1, unregistered)
        assertEquals(true, owns(false).value)
        assertEquals(1, unregistered)

        assertEquals("bad_args", owns("yes").errorCode)
        val missing = TaskResult()
        handler.onMethodCall(MethodCall("setCallOwnsBack", null), missing)
        assertEquals("bad_args", missing.errorCode)
    }

    @Test fun `onBackPressed moves the task only while a call owns Back`() {
        var moves = 0
        val handler = MknoonCallTaskChannelHandler(moveTaskToBack = { moves += 1; true })

        assertFalse(handler.handleBackPressed())
        handler.onMethodCall(MethodCall("setCallOwnsBack", mapOf("owns" to true)), TaskResult())
        assertTrue(handler.handleBackPressed())
        assertEquals(1, moves)
        handler.onMethodCall(MethodCall("setCallOwnsBack", mapOf("owns" to false)), TaskResult())
        assertFalse(handler.handleBackPressed())
        assertEquals(1, moves)
    }

    @Test fun `BL65 expanded back ownership does not move the task`() {
        var moves = 0
        val callbacks = mutableListOf<() -> Unit>()
        val handler = MknoonCallTaskChannelHandler(
            registerBack = { action ->
                callbacks += action
                ({})
            },
            moveTaskToBack = { moves += 1; true },
        )
        val result = TaskResult()
        handler.onMethodCall(
            MethodCall(
                "setCallOwnsBack",
                mapOf("owns" to true, "minimizeCallId" to "33333333-3333-4333-8333-333333333333"),
            ),
            result,
        )

        assertEquals(true, result.value)
        assertTrue(handler.handleBackPressed())
        callbacks.single().invoke()
        assertEquals(0, moves)
    }

    @Test fun `BL65 the registered Back follows the current call and action`() {
        val firstCall = "33333333-3333-4333-8333-333333333333"
        val nextCall = "44444444-4444-4444-8444-444444444444"
        val minimizeRequests = mutableListOf<String>()
        val callbacks = mutableListOf<() -> Unit>()
        var moves = 0
        var releases = 0
        val handler = MknoonCallTaskChannelHandler(
            registerBack = { action ->
                callbacks += action
                ({ releases += 1 })
            },
            onMinimizeCall = { minimizeRequests += it },
            moveTaskToBack = { moves += 1; true },
        )
        fun publish(owns: Boolean, callId: String? = null) {
            val arguments = mutableMapOf<String, Any>("owns" to owns)
            if (callId != null) arguments["minimizeCallId"] = callId
            val result = TaskResult()
            handler.onMethodCall(MethodCall("setCallOwnsBack", arguments), result)
            assertEquals(true, result.value)
        }

        publish(true, firstCall)
        assertTrue(handler.handleBackPressed())
        publish(true, nextCall)
        callbacks.single().invoke()
        assertEquals(listOf(firstCall, nextCall), minimizeRequests)
        assertEquals(0, moves)

        publish(true)
        callbacks.single().invoke()
        assertEquals(1, moves)
        assertEquals(0, releases)
        publish(false)
        assertFalse(handler.handleBackPressed())
        callbacks.single().invoke()
        assertEquals(1, moves)
        assertEquals(1, releases)
        assertEquals(listOf(firstCall, nextCall), minimizeRequests)
    }

    @Test fun `dispose releases the overlay back callback`() {
        var unregistered = 0
        val handler = MknoonCallTaskChannelHandler(
            moveTaskToBack = { true },
            registerBack = { { unregistered += 1 } },
        )
        handler.onMethodCall(MethodCall("setCallOwnsBack", mapOf("owns" to true)), TaskResult())

        handler.dispose()
        handler.dispose()

        assertEquals(1, unregistered)
        assertFalse(handler.handleBackPressed())
    }

    private class TaskResult : MethodChannel.Result {
        var value: Any? = null
        var errorCode: String? = null
        var notImplemented = false

        override fun success(result: Any?) { value = result }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
        }

        override fun notImplemented() { notImplemented = true }
    }
}
