package com.mknoon.app

import android.app.Activity
import android.view.Window
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Route-scoped native protection for direct private media.
 *
 * Owner tokens are deliberately opaque and are never returned, logged, or
 * included in diagnostics. This class owns only window protection state; all
 * media lifecycle and persistence remain in Dart.
 */
internal class PrivateMediaProtectionHandler(
    activity: Activity? = null,
    messenger: BinaryMessenger? = null,
    private val debugEnabled: Boolean = BuildConfig.DEBUG,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "mknoon/private_media_protection"
        const val EVENT_CHANNEL = "mknoon/private_media_protection/events"

        private val DEBUG_EVENTS = setOf(
            "screenshot",
            "captureStarted",
            "captureStopped",
            "inactive",
            "background",
            "foreground",
        )
    }

    private val lock = Any()
    private val activeOwners = linkedSetOf<String>()
    private var activity: Activity? = activity
    private var protectedWindow: Window? = null
    private var ownsSecureFlag = false
    private var eventSink: EventChannel.EventSink? = null
    private var disposed = false
    private val methodChannel = messenger?.let { MethodChannel(it, METHOD_CHANNEL) }
    private val eventChannel = messenger?.let { EventChannel(it, EVENT_CHANNEL) }

    init {
        methodChannel?.setMethodCallHandler(this)
        eventChannel?.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        synchronized(lock) {
            if (disposed) {
                result.error("protection_unavailable", "Private media protection is unavailable", null)
                return
            }
            when (call.method) {
                "enter" -> enter(call.arguments, result)
                "exit" -> exit(call.arguments, result)
                "debugGetState" -> {
                    if (!debugEnabled) {
                        result.notImplemented()
                    } else if (call.arguments != null) {
                        invalidArguments(result)
                    } else {
                        result.success(debugState())
                    }
                }
                "debugInjectEvent" -> {
                    if (!debugEnabled) {
                        result.notImplemented()
                    } else {
                        val event = parseDebugEvent(call.arguments)
                        if (event == null) {
                            invalidArguments(result)
                        } else {
                            emit(event)
                            result.success(mapOf("ok" to true))
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun attachActivity(activity: Activity) {
        synchronized(lock) {
            if (disposed || this.activity === activity) return
            restoreOwnedSecureFlag()
            this.activity = activity
            protectedWindow = null
            if (activeOwners.isNotEmpty()) {
                applySecureFlag(activity.window)
            }
        }
    }

    fun detachActivity(activity: Activity) {
        synchronized(lock) {
            if (this.activity !== activity) return
            restoreOwnedSecureFlag()
            this.activity = null
            protectedWindow = null
        }
    }

    fun dispose() {
        synchronized(lock) {
            if (disposed) return
            disposed = true
            restoreOwnedSecureFlag()
            activeOwners.clear()
            eventSink = null
            methodChannel?.setMethodCallHandler(null)
            eventChannel?.setStreamHandler(null)
            activity = null
            protectedWindow = null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        synchronized(lock) {
            if (!disposed) eventSink = events
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            eventSink = null
        }
    }

    internal fun debugState(): Map<String, Any> = synchronized(lock) {
        mapOf(
            "secureApplied" to isCurrentWindowSecure(),
            "activeOwnerCount" to activeOwners.size,
        )
    }

    private fun enter(arguments: Any?, result: MethodChannel.Result) {
        val token = parseOwner(arguments)
        if (token == null) {
            invalidArguments(result)
            return
        }
        val window = activity?.window
        if (window == null) {
            result.error("protection_unavailable", "Private media protection is unavailable", null)
            return
        }
        try {
            applySecureFlag(window)
            activeOwners += token
            result.success(successEnvelope(protectionActive = true))
        } catch (_: RuntimeException) {
            result.error("protection_unavailable", "Private media protection is unavailable", null)
        }
    }

    private fun exit(arguments: Any?, result: MethodChannel.Result) {
        val token = parseOwner(arguments)
        if (token == null) {
            invalidArguments(result)
            return
        }
        activeOwners -= token
        if (activeOwners.isEmpty()) {
            restoreOwnedSecureFlag()
        } else {
            activity?.window?.let(::applySecureFlag)
        }
        result.success(successEnvelope(protectionActive = activeOwners.isNotEmpty()))
    }

    private fun applySecureFlag(window: Window) {
        if (protectedWindow !== window) {
            restoreOwnedSecureFlag()
            protectedWindow = window
            ownsSecureFlag = false
        }
        val alreadySecure =
            window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0
        if (!alreadySecure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            ownsSecureFlag = true
        }
    }

    private fun restoreOwnedSecureFlag() {
        if (ownsSecureFlag) {
            protectedWindow?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        ownsSecureFlag = false
    }

    private fun isCurrentWindowSecure(): Boolean {
        val window = activity?.window ?: return false
        return window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0
    }

    private fun emit(event: String) {
        eventSink?.success(mapOf("event" to event))
    }

    private fun parseOwner(arguments: Any?): String? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != setOf("ownerToken")) return null
        val token = map["ownerToken"] as? String ?: return null
        if (token.isBlank() || token.length > 128 || token != token.trim()) return null
        if (token.any(Char::isISOControl)) return null
        return token
    }

    private fun parseDebugEvent(arguments: Any?): String? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != setOf("event")) return null
        val event = map["event"] as? String ?: return null
        return event.takeIf(DEBUG_EVENTS::contains)
    }

    private fun invalidArguments(result: MethodChannel.Result) {
        result.error("bad_args", "Invalid private media protection request", null)
    }

    private fun successEnvelope(protectionActive: Boolean): Map<String, Any> = mapOf(
        "ok" to true,
        "protectionActive" to protectionActive,
    )
}

/**
 * Retains one protection owner per Flutter engine while Android replaces the
 * host Activity. The engine identity is deliberately opaque; no route token or
 * media value leaves [PrivateMediaProtectionHandler].
 */
internal class PrivateMediaProtectionHandlerRegistry {
    private val lock = Any()
    private var engineIdentity: Any? = null
    private var handler: PrivateMediaProtectionHandler? = null

    fun bind(
        engineIdentity: Any,
        activity: Activity,
        messenger: BinaryMessenger?,
        debugEnabled: Boolean = BuildConfig.DEBUG,
    ): PrivateMediaProtectionHandler = synchronized(lock) {
        val current = handler
        if (this.engineIdentity === engineIdentity && current != null) {
            current.attachActivity(activity)
            return@synchronized current
        }

        current?.dispose()
        PrivateMediaProtectionHandler(
            activity = activity,
            messenger = messenger,
            debugEnabled = debugEnabled,
        ).also {
            this.engineIdentity = engineIdentity
            handler = it
        }
    }

    fun detach(
        engineIdentity: Any,
        activity: Activity,
        destroyEngine: Boolean,
    ) {
        synchronized(lock) {
            if (this.engineIdentity !== engineIdentity) return
            val current = handler ?: return
            current.detachActivity(activity)
            if (destroyEngine) {
                current.dispose()
                handler = null
                this.engineIdentity = null
            }
        }
    }
}
