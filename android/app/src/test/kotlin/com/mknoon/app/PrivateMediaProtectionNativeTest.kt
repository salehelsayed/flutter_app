package com.mknoon.app

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.view.WindowManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PrivateMediaProtectionNativeTest {
    @Test
    fun `window flag mutation preserves preexisting secure state and multiple owners`() {
        val activity = activity()
        val handler = PrivateMediaProtectionHandler(
            activity = activity,
            messenger = null,
            debugEnabled = true,
        )

        val first = handler.call("enter", owner("first"))
        assertSuccess(first, protectionActive = true)
        assertTrue(activity.isSecure())

        assertSuccess(handler.call("enter", owner("second")), protectionActive = true)
        assertSuccess(handler.call("enter", owner("second")), protectionActive = true)
        assertEquals(2, handler.debugState()["activeOwnerCount"])

        assertSuccess(handler.call("exit", owner("first")), protectionActive = true)
        assertTrue(activity.isSecure())
        assertSuccess(handler.call("exit", owner("second")), protectionActive = false)
        assertFalse(activity.isSecure())

        activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        assertSuccess(handler.call("enter", owner("external-preserved")), protectionActive = true)
        assertSuccess(handler.call("exit", owner("external-preserved")), protectionActive = false)
        assertTrue(activity.isSecure())
    }

    @Test
    fun `detach rebind duplicate unknown and late exits restore only handler ownership`() {
        val firstActivity = activity()
        val secondActivity = activity()
        val handler = PrivateMediaProtectionHandler(
            activity = firstActivity,
            messenger = null,
            debugEnabled = true,
        )

        assertSuccess(handler.call("enter", owner("route")), protectionActive = true)
        assertTrue(firstActivity.isSecure())
        handler.detachActivity(firstActivity)
        assertFalse(firstActivity.isSecure())

        handler.attachActivity(secondActivity)
        assertTrue(secondActivity.isSecure())
        assertSuccess(handler.call("exit", owner("unknown")), protectionActive = true)
        assertTrue(secondActivity.isSecure())
        assertSuccess(handler.call("exit", owner("route")), protectionActive = false)
        assertFalse(secondActivity.isSecure())
        assertSuccess(handler.call("exit", owner("route")), protectionActive = false)

        handler.dispose()
        val late = handler.call("exit", owner("route"))
        assertEquals(1, late.settlements)
        assertEquals("protection_unavailable", late.errorCode)
        assertNull(late.errorDetails)
    }

    @Test
    fun `debug proof methods are gated by BuildConfig DEBUG not runtime app flags`() {
        val activity = activity()
        activity.applicationInfo.flags =
            activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE.inv()
        val handler = PrivateMediaProtectionHandler(
            activity = activity,
            messenger = null,
        )

        val state = handler.call("debugGetState", null)
        if (BuildConfig.DEBUG) {
            assertEquals(
                mapOf("secureApplied" to false, "activeOwnerCount" to 0),
                state.value,
            )
            assertEquals(0, state.notImplementedCount)
        } else {
            assertEquals(1, state.notImplementedCount)
        }
    }

    @Test
    fun `same engine registry rebinds the live owner to the replacement activity`() {
        val firstActivity = activity()
        val secondActivity = activity()
        val engineIdentity = Any()
        val registry = PrivateMediaProtectionHandlerRegistry()

        val first = registry.bind(
            engineIdentity = engineIdentity,
            activity = firstActivity,
            messenger = null,
            debugEnabled = true,
        )
        assertSuccess(first.call("enter", owner("route")), protectionActive = true)
        assertTrue(firstActivity.isSecure())

        val rebound = registry.bind(
            engineIdentity = engineIdentity,
            activity = secondActivity,
            messenger = null,
            debugEnabled = true,
        )
        assertSame(first, rebound)
        assertFalse(firstActivity.isSecure())
        assertTrue(secondActivity.isSecure())
        assertEquals(1, rebound.debugState()["activeOwnerCount"])

        // A late detach from the replaced Activity must not clear the new
        // Activity's secure window.
        registry.detach(
            engineIdentity = engineIdentity,
            activity = firstActivity,
            destroyEngine = false,
        )
        assertTrue(secondActivity.isSecure())
        assertSuccess(rebound.call("exit", owner("route")), protectionActive = false)
        assertFalse(secondActivity.isSecure())

        registry.detach(
            engineIdentity = engineIdentity,
            activity = secondActivity,
            destroyEngine = true,
        )
        assertEquals(
            "protection_unavailable",
            rebound.call("enter", owner("late")).errorCode,
        )
    }

    @Test
    fun `malformed calls complete once and diagnostics and events stay redacted`() {
        val activity = activity()
        val handler = PrivateMediaProtectionHandler(
            activity = activity,
            messenger = null,
            debugEnabled = true,
        )
        val events = mutableListOf<Any?>()
        handler.onListen(null, object : EventChannel.EventSink {
            override fun success(event: Any?) {
                events += event
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
            override fun endOfStream() = Unit
        })

        val secretToken = "owner-secret-value"
        val malformed = handler.call(
            "enter",
            mapOf("ownerToken" to secretToken, "path" to "/private/media.jpg"),
        )
        assertEquals(1, malformed.settlements)
        assertEquals("bad_args", malformed.errorCode)
        assertNull(malformed.errorDetails)
        assertFalse(malformed.toString().contains(secretToken))
        assertFalse(malformed.toString().contains("/private/media.jpg"))
        assertFalse(activity.isSecure())

        assertSuccess(handler.call("enter", owner(secretToken)), protectionActive = true)
        val debug = handler.call("debugGetState", null)
        assertEquals(
            mapOf("secureApplied" to true, "activeOwnerCount" to 1),
            debug.value,
        )
        val injected = handler.call("debugInjectEvent", mapOf("event" to "background"))
        assertEquals(mapOf("ok" to true), injected.value)
        assertEquals(listOf(mapOf("event" to "background")), events)
        assertFalse(events.toString().contains(secretToken))

        val invalidEvent = handler.call("debugInjectEvent", mapOf("event" to "path=/private/media.jpg"))
        assertEquals(1, invalidEvent.settlements)
        assertEquals("bad_args", invalidEvent.errorCode)
        assertNull(invalidEvent.errorDetails)
        assertFalse(invalidEvent.toString().contains("/private/media.jpg"))

        val releaseHandler = PrivateMediaProtectionHandler(
            activity = activity(),
            messenger = null,
            debugEnabled = false,
        )
        assertEquals(1, releaseHandler.call("debugGetState", null).notImplementedCount)
    }

    private fun activity(): Activity = Robolectric.buildActivity(Activity::class.java).setup().get()

    private fun owner(token: String): Map<String, Any> = mapOf("ownerToken" to token)

    private fun PrivateMediaProtectionHandler.call(method: String, arguments: Any?): PrivateProtectionCapturingResult {
        val result = PrivateProtectionCapturingResult()
        onMethodCall(MethodCall(method, arguments), result)
        return result
    }

    private fun Activity.isSecure(): Boolean =
        window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0

    private fun assertSuccess(result: PrivateProtectionCapturingResult, protectionActive: Boolean) {
        assertEquals(1, result.settlements)
        assertEquals(
            mapOf("ok" to true, "protectionActive" to protectionActive),
            result.value,
        )
        assertNull(result.errorCode)
    }
}

private class PrivateProtectionCapturingResult : MethodChannel.Result {
    var settlements = 0
    var value: Any? = null
    var errorCode: String? = null
    var errorMessage: String? = null
    var errorDetails: Any? = null
    var notImplementedCount = 0

    override fun success(result: Any?) {
        settlements++
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        settlements++
        this.errorCode = errorCode
        this.errorMessage = errorMessage
        this.errorDetails = errorDetails
    }

    override fun notImplemented() {
        settlements++
        notImplementedCount++
    }

    override fun toString(): String =
        "PrivateProtectionCapturingResult(settlements=$settlements,errorCode=$errorCode,errorMessage=$errorMessage)"
}
