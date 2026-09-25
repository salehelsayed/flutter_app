package com.mknoon.app.call

/**
 * Orders the call bridge teardown after the Dart runtime shutdown.
 *
 * Disposing [MknoonCallNativeBridge] detaches the lifecycle controller, and
 * that detach ends a live Telecom call without telling Dart (its sink is
 * already gone). MainActivity used to dispose the bridge first in onDestroy,
 * then asked Dart to shut down. Dart then had no call left to end, so the peer
 * never got a terminate (beta 2026-09-25, F3: `CALL_ANDROID_DISCONNECT
 * source=explicit_end` at 19:34:45.378, engine cleanup at 19:34:45.397).
 *
 * Now, while a Dart shutdown is pending, the bridge stays. Dart ends the call
 * through it (terminate to the peer, then native end). Once that shutdown
 * settles, released or not, the bridge goes, and its detach ends any call Dart
 * could not end.
 */
internal class MknoonCallBridgeTeardown(private val disposeBridge: () -> Unit) {
    private var runtimeShutdownPending = false
    private var disposed = false

    /** The engine is kept for a Dart runtime shutdown. Keep the bridge too. */
    fun deferUntilRuntimeShutdown() {
        if (disposed) return
        runtimeShutdownPending = true
    }

    /** The activity is gone. Without a pending Dart shutdown, release now. */
    fun onHostDestroyed() {
        if (!runtimeShutdownPending) dispose()
    }

    /** Dart's shutdown reply or its timeout arrived. */
    fun onRuntimeShutdownSettled() {
        runtimeShutdownPending = false
        dispose()
    }

    private fun dispose() {
        if (disposed) return
        disposed = true
        disposeBridge()
    }
}
