package com.mknoon.app.call

import android.app.Activity
import android.os.Build
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps Back from ending a call while the Flutter call surface shows.
 *
 * Back during a call used to close the task, and the teardown ended the call
 * (beta 2026-09-25, F4). While Dart reports that a call surface owns Back
 * (`setCallOwnsBack`), an overlay-priority back callback moves the whole task
 * to the back, like other calling apps, and the call keeps running in its
 * foreground service. It runs before Flutter's own callback, so a predictive
 * swipe never pops the routes hidden under the call. `moveToBackground` is
 * the same action for a Back that still reaches Dart.
 */
internal class MknoonCallTaskChannelHandler(
    private val registerBack: ((() -> Unit) -> (() -> Unit))? = null,
    private val moveTaskToBack: () -> Boolean,
) : MethodChannel.MethodCallHandler {
    private var callOwnsBack = false
    private var unregisterBack: (() -> Unit)? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            MOVE_TO_BACKGROUND -> {
                if (call.arguments != null) {
                    result.error("bad_args", "moveToBackground takes no arguments", null)
                    return
                }
                result.success(moveToBackground())
            }
            SET_CALL_OWNS_BACK -> {
                val arguments = call.arguments as? Map<*, *>
                val owns = arguments?.takeIf { it.keys == setOf("owns") }?.get("owns") as? Boolean
                if (owns == null) {
                    result.error("bad_args", "setCallOwnsBack takes {owns: bool}", null)
                    return
                }
                setCallOwnsBack(owns)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** Back before Android 13 arrives through Activity.onBackPressed. */
    fun handleBackPressed(): Boolean {
        if (!callOwnsBack) return false
        moveToBackground()
        return true
    }

    fun dispose() {
        setCallOwnsBack(false)
    }

    private fun setCallOwnsBack(owns: Boolean) {
        if (owns == callOwnsBack) return
        callOwnsBack = owns
        if (owns) {
            unregisterBack = runCatching {
                registerBack?.invoke { moveToBackground() }
            }.getOrNull()
        } else {
            val release = unregisterBack
            unregisterBack = null
            runCatching { release?.invoke() }
        }
    }

    private fun moveToBackground(): Boolean =
        runCatching { moveTaskToBack() }.getOrDefault(false)

    companion object {
        const val CHANNEL = "mknoon/call_task"
        const val MOVE_TO_BACKGROUND = "moveToBackground"
        const val SET_CALL_OWNS_BACK = "setCallOwnsBack"

        /** Android 13+: Back and predictive swipes reach this before Flutter. */
        fun overlayBackRegistrar(activity: Activity): ((() -> Unit) -> (() -> Unit))? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                { action -> Api33.registerBack(activity, action) }
            } else {
                null
            }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private object Api33 {
        fun registerBack(activity: Activity, action: () -> Unit): () -> Unit {
            val callback = android.window.OnBackInvokedCallback { action() }
            activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_OVERLAY,
                callback,
            )
            return { activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
    }
}
