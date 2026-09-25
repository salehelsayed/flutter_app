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
