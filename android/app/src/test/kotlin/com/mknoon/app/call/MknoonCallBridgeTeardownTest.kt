package com.mknoon.app.call

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Beta 2026-09-25 (F3): MainActivity.onDestroy disposed the call bridge before
 * super.onDestroy. The bridge's controller detach ended the Telecom call at
 * 19:34:45.378 (`CALL_ANDROID_DISCONNECT source=explicit_end`) with the Dart
 * sink already detached, so Dart never saw that end. Only afterwards
 * (19:34:45.397) did cleanUpFlutterEngine ask Dart to shut the runtime down.
 * The bridge must stay until that Dart shutdown settles, so Dart ends the call
 * itself and tells the peer.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallBridgeTeardownTest {
    @Test fun `a live call survives host destroy until the Dart runtime shutdown settles`() {
        val rig = adoptedCallRig()
        val bridge = MknoonCallNativeBridge(controller = rig.controller, messenger = null)
        val teardown = MknoonCallBridgeTeardown(bridge::dispose)

        // cleanUpFlutterEngine asks Dart to shut down, then onDestroy finishes.
        teardown.deferUntilRuntimeShutdown()
        teardown.onHostDestroyed()

        assertFalse(rig.operations.contains("platform.end"))
        assertNotNull(rig.controller.activeNativeCallId())

        // Dart's shutdown settled (released or not): the bridge goes now and
        // its detach ends any call Dart could not end.
        teardown.onRuntimeShutdownSettled()
        assertEquals(1, rig.operations.count { it == "platform.end" })
        assertNull(rig.controller.activeNativeCallId())

        teardown.onRuntimeShutdownSettled()
        teardown.onHostDestroyed()
        assertEquals(1, rig.operations.count { it == "platform.end" })
    }

    @Test fun `host destroy with no Dart runtime to shut down releases the bridge at once`() {
        val rig = adoptedCallRig()
        val bridge = MknoonCallNativeBridge(controller = rig.controller, messenger = null)
        val teardown = MknoonCallBridgeTeardown(bridge::dispose)

        teardown.onHostDestroyed()

        assertEquals(1, rig.operations.count { it == "platform.end" })
        assertNull(rig.controller.activeNativeCallId())
        teardown.deferUntilRuntimeShutdown()
        teardown.onRuntimeShutdownSettled()
        assertEquals(1, rig.operations.count { it == "platform.end" })
    }

    @Test fun `MainActivity lets the Dart shutdown end the call before the bridge goes`() {
        val source = mainActivitySource()
        val onDestroy = functionBody(source, "override fun onDestroy()")
        val cleanUp = functionBody(source, "override fun cleanUpFlutterEngine(")
        val request = functionBody(source, "private fun requestCanonicalRuntimeShutdown(")

        // Neither lifecycle hook may end the call before Dart shuts down.
        assertFalse(onDestroy.contains("callNativeBridge?.dispose()"))
        assertFalse(cleanUp.contains("callNativeBridge?.dispose()"))
        assertTrue(cleanUp.contains("callBridgeTeardown.deferUntilRuntimeShutdown()"))
        assertTrue(
            cleanUp.indexOf("callBridgeTeardown.deferUntilRuntimeShutdown()") <
                cleanUp.indexOf("requestCanonicalRuntimeShutdown("),
        )
        assertTrue(
            onDestroy.indexOf("super.onDestroy()") <
                onDestroy.indexOf("callBridgeTeardown.onHostDestroyed()"),
        )
        assertTrue(request.contains("callBridgeTeardown.onRuntimeShutdownSettled()"))
    }

    private fun adoptedCallRig(): LifecycleRig {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        rig.operations.clear()
        return rig
    }

    private fun mainActivitySource(): String {
        val relative = "src/main/kotlin/com/mknoon/app/MainActivity.kt"
        val candidates = listOf(File(relative), File("app/$relative"), File("android/app/$relative"))
        return candidates.first { it.exists() }.readText()
    }

    private fun functionBody(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("missing $signature", start >= 0)
        var depth = 0
        var index = source.indexOf('{', start)
        val open = index
        while (index < source.length) {
            when (source[index]) {
                '{' -> depth += 1
                '}' -> {
                    depth -= 1
                    if (depth == 0) return source.substring(open, index + 1)
                }
            }
            index += 1
        }
        error("unterminated $signature")
    }
}
