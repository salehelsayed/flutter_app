package com.mknoon.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** A payload-free hint to drain the existing authenticated call mailbox.
 *
 * FlutterFire can own a second, read-only engine. Registration order or plugin
 * singletons never establish writable authority: every delivery rechecks the
 * process lease and routes only to that exact ACTIVE FOREGROUND owner.
 */
internal class AndroidCallWakeSignalRegistry(
    private val snapshot: () -> CanonicalRuntimeLeaseBroker.Snapshot = {
        ProcessCanonicalRuntimeLease.broker.snapshot()
    },
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    internal class Registration(
        val ownerId: String,
        val deliver: ((Boolean) -> Unit) -> Unit,
    ) {
        var ready = false
        var inFlight: Any? = null
    }

    private val registrations = mutableMapOf<String, Registration>()
    private var pending = false

    fun register(ownerId: String, deliver: ((Boolean) -> Unit) -> Unit): Registration {
        checkMainThread()
        registrations[ownerId]?.let { if (it.inFlight != null) pending = true }
        return Registration(ownerId, deliver).also { registrations[ownerId] = it }
    }

    fun ready(registration: Registration): Boolean {
        checkMainThread()
        if (registrations[registration.ownerId] !== registration) return false
        registration.ready = true
        flush()
        return true
    }

    fun unregister(registration: Registration): Boolean {
        checkMainThread()
        if (registrations[registration.ownerId] !== registration) return false
        if (registration.inFlight != null) pending = true
        registrations.remove(registration.ownerId)
        return true
    }

    /** Safe from the Firebase worker thread; no call identity crosses here. */
    fun signal() = onMain {
        pending = true
        flush()
    }

    /** Handles listener-before-lease ordering without timers or polling. */
    fun ownerMayBeReady() = onMain { flush() }

    private fun flush() {
        checkMainThread()
        if (!pending) return
        val owner = snapshot()
        if (owner.state != CanonicalRuntimeLeaseBroker.State.ACTIVE ||
            owner.role != CanonicalRuntimeLeaseBroker.Role.FOREGROUND) return
        val registration = registrations[owner.ownerId] ?: return
        if (!registration.ready || registration.inFlight != null) return
        val flight = Any()
        registration.inFlight = flight
        pending = false
        val complete: (Boolean) -> Unit = { accepted ->
            onMain {
                if (registrations[registration.ownerId] === registration &&
                    registration.inFlight === flight) {
                    registration.inFlight = null
                    val current = snapshot()
                    val sameAuthority = current.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
                        current.role == CanonicalRuntimeLeaseBroker.Role.FOREGROUND &&
                        current.ownerId == owner.ownerId && current.generation == owner.generation &&
                        current.binding == owner.binding
                    if (sameAuthority && !accepted) pending = true
                    // Stale replies cannot revive or consume a successor hint.
                    // A refusal waits for another wake/readiness signal, never
                    // a busy loop. A newly coalesced wake follows successful work.
                    if (accepted || !sameAuthority) flush()
                }
            }
        }
        try {
            registration.deliver(complete)
        } catch (_: Exception) {
            complete(false)
        }
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action()
        else mainHandler.post(action)
    }

    private fun checkMainThread() = check(Looper.myLooper() == Looper.getMainLooper())
}

internal object ProcessAndroidCallWakeSignals {
    val registry = AndroidCallWakeSignalRegistry()
}

internal class AndroidCallWakeBridge(
    messenger: BinaryMessenger?,
    ownerId: String,
    private val registry: AndroidCallWakeSignalRegistry = ProcessAndroidCallWakeSignals.registry,
    deliverForTest: (((Boolean) -> Unit) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {
    companion object {
        internal const val CHANNEL_NAME = "mknoon/android_call_wake"
    }

    private val channel = messenger?.let { MethodChannel(it, CHANNEL_NAME) }
    private val registration = registry.register(ownerId, deliverForTest ?: { complete ->
        val target = channel
        if (target == null) complete(false)
        else target.invokeMethod("callWake", null, object : MethodChannel.Result {
            override fun success(result: Any?) = complete(result == true)
            override fun error(code: String, message: String?, details: Any?) = complete(false)
            override fun notImplemented() = complete(false)
        })
    })
    private var disposed = false

    init {
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "ready") {
            result.notImplemented()
            return
        }
        if (call.arguments != null) {
            result.error("bad_args", "ready requires null arguments", null)
            return
        }
        if (!disposed) registry.ready(registration)
        // Dart invokes ready<void>; this signal is never an authority grant.
        result.success(null)
    }

    fun ownerMayBeReady() {
        if (!disposed) registry.ownerMayBeReady()
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        // An old activity on the same retained engine must not clear its
        // successor's MethodChannel handler or registration.
        if (registry.unregister(registration)) channel?.setMethodCallHandler(null)
    }
}
