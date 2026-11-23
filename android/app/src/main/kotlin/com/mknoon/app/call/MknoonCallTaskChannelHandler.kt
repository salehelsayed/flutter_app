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
 * (`setCallOwnsBack`), the overlay-priority callback handles Back before
 * Flutter's covered routes can receive it. The callback either requests
 * in-app minimization for the reported call or backgrounds the live task.
 */
internal class MknoonCallTaskChannelHandler(
    private val registerBack: ((() -> Unit) -> (() -> Unit))? = null,
    private val isDeviceUnlocked: () -> Boolean = { false },
    private val onMinimizeCall: (String) -> Unit = {},
    private val moveTaskToBack: () -> Boolean,
) : MethodChannel.MethodCallHandler {
    private sealed interface BackAction {
        object Background : BackAction
        class Minimize(val callId: String) : BackAction
    }

    private var backAction: BackAction? = null
    private var unregisterBack: (() -> Unit)? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDeviceUnlocked" -> {
                if (call.arguments != null) {
                    result.error("bad_args", "isDeviceUnlocked takes no arguments", null)
                    return
                }
                result.success(runCatching { isDeviceUnlocked() }.getOrDefault(false))
            }
            MOVE_TO_BACKGROUND -> {
                if (call.arguments != null) {
                    result.error("bad_args", "moveToBackground takes no arguments", null)
                    return
                }
                result.success(moveToBackground())
            }
            SET_CALL_OWNS_BACK -> {
                val arguments = call.arguments as? Map<*, *>
                val owns = arguments?.get("owns") as? Boolean
                val minimizeCallId = arguments?.get("minimizeCallId") as? String
                if (arguments == null || owns == null ||
                    arguments.keys.any { it != "owns" && it != "minimizeCallId" } ||
                    ("minimizeCallId" in arguments && (!owns || minimizeCallId.isNullOrBlank()))
                ) {
                    result.error("bad_args", "setCallOwnsBack takes owns and an optional minimizeCallId", null)
                    return
                }
                setBackAction(
                    when {
                        !owns -> null
                        minimizeCallId == null -> BackAction.Background
                        else -> BackAction.Minimize(minimizeCallId)
                    },
                )
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** Shared by Activity.onBackPressed and the overlay callback. */
    fun handleBackPressed(): Boolean {
        when (val action = backAction) {
            BackAction.Background -> moveToBackground()
            is BackAction.Minimize -> runCatching { onMinimizeCall(action.callId) }
            null -> return false
        }
        return true
    }

    fun dispose() {
        setBackAction(null)
    }

    private fun setBackAction(action: BackAction?) {
        val wasOwned = backAction != null
        backAction = action
        if (wasOwned == (action != null)) return
        if (action != null) {
            unregisterBack = runCatching {
                registerBack?.invoke { handleBackPressed() }
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
        const val MINIMIZE_CALL = "minimizeCall"

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
