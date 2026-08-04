package com.mknoon.app

import android.os.Handler
import android.os.Looper
import bridge.Bridge as GoMknoon
import bridge.EventCallback
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import org.json.JSONObject

/** Small injectable lifecycle boundary around the process-global Go singleton. */
internal interface GoRuntimeLifecycle {
    fun initialize(callback: EventCallback)
    fun stopNode(): Boolean
}

internal fun interface GoRuntimeDeliveryDispatcher {
    fun dispatch(block: () -> Unit)
}

/**
 * Owns the sole process-global Go callback and serializes engine ownership.
 *
 * An owner may admit work only while ACTIVE. Draining rejects new work, waits
 * for admitted JNI calls and every queued result/callback delivery, invokes
 * StopNode only after those calls settle, and releases only after StopNode
 * succeeds. A stop failure deliberately leaves the owner in DRAINING.
 */
internal class GoRuntimeHost(
    private val lifecycle: GoRuntimeLifecycle,
    private val workExecutor: Executor,
    private val deliveryDispatcher: GoRuntimeDeliveryDispatcher,
) : EventCallback {
    enum class State {
        ACTIVE,
        DRAINING,
        RELEASED,
    }

    data class OwnerToken(
        val generation: Long,
        val ownerId: String,
    )

    data class Snapshot(
        val state: State,
        val ownerId: String?,
        val generation: Long?,
        val outstandingDeliveries: Int,
        val initialized: Boolean,
        val initializeCount: Int,
        val stopScheduled: Boolean,
        val stopSucceeded: Boolean,
        val staleCallbackDeliveries: Int,
        val staleResultDeliveries: Int,
    )

    private enum class DeliveryKind {
        CALLBACK,
        RESULT,
    }

    private data class Owner(
        val token: OwnerToken,
        val eventReceiver: (String) -> Unit,
        var deliveriesEnabled: Boolean = true,
    )

    private val lock = Any()
    private var state = State.RELEASED
    private var owner: Owner? = null
    private var nextGeneration = 0L
    private var initialized = false
    private var initializeCount = 0
    private var outstandingDeliveries = 0
    private var stopScheduled = false
    private var stopSucceeded = false
    private var staleCallbackDeliveries = 0
    private var staleResultDeliveries = 0

    fun registerOwner(ownerId: String, eventReceiver: (String) -> Unit): OwnerToken {
        require(ownerId.isNotBlank()) { "ownerId must not be blank" }
        var initializeRequired = false
        val token = synchronized(lock) {
            check(state == State.RELEASED && owner == null) {
                "Go runtime is already owned or draining"
            }
            check(nextGeneration != Long.MAX_VALUE) { "Go runtime generation exhausted" }
            val token = OwnerToken(++nextGeneration, ownerId)
            owner = Owner(token, eventReceiver)
            state = State.ACTIVE
            stopScheduled = false
            stopSucceeded = false
            if (!initialized) {
                initializeCount += 1
                initializeRequired = true
            }
            token
        }
        if (initializeRequired) {
            try {
                // Never hold the ownership monitor across an external JNI
                // boundary. Initialize may synchronously or asynchronously
                // call back into onEvent and must not deadlock host state.
                lifecycle.initialize(this)
                synchronized(lock) {
                    check(owner?.token == token && state == State.ACTIVE) {
                        "Go owner changed while Initialize was in flight"
                    }
                    initialized = true
                }
            } catch (error: Throwable) {
                synchronized(lock) {
                    if (owner?.token == token && !initialized) {
                        owner = null
                        state = State.RELEASED
                    }
                }
                throw error
            }
        }
        return token
    }

    fun <T> execute(
        token: OwnerToken,
        work: () -> T,
        onSuccess: (T) -> Unit,
        onError: (Throwable) -> Unit,
    ): Boolean {
        if (!admit(token, requireActive = true)) return false
        try {
            workExecutor.execute {
                try {
                    val value = work()
                    dispatchAdmitted(token, DeliveryKind.RESULT) { onSuccess(value) }
                } catch (error: Throwable) {
                    dispatchAdmitted(token, DeliveryKind.RESULT) { onError(error) }
                }
            }
        } catch (_: Throwable) {
            completeAdmitted()
            return false
        }
        return true
    }

    /** Queues an owner-generated diagnostic event under the same delivery fence. */
    fun emitOwnerEvent(token: OwnerToken, event: String): Boolean {
        if (!admit(token, requireActive = true)) return false
        dispatchEvent(token, event)
        return true
    }

    /** Begins cooperative drain while allowing already-admitted deliveries. */
    fun requestDrain(token: OwnerToken): Boolean = synchronized(lock) {
        val current = owner ?: return@synchronized false
        if (current.token != token || state == State.RELEASED) return@synchronized false
        if (state == State.ACTIVE) state = State.DRAINING
        maybeScheduleStopLocked()
        true
    }

    /**
     * Detaches an engine immediately, fences its queued deliveries, and then
     * follows the same drain/StopNode/release sequence in the background.
     */
    fun unregister(token: OwnerToken): Boolean = synchronized(lock) {
        val current = owner ?: return@synchronized false
        if (current.token != token || state == State.RELEASED) return@synchronized false
        current.deliveriesEnabled = false
        if (state == State.ACTIVE) state = State.DRAINING
        maybeScheduleStopLocked()
        true
    }

    fun releaseIfDrained(token: OwnerToken): Boolean = synchronized(lock) {
        if (state == State.RELEASED && owner == null) return@synchronized true
        val current = owner ?: return@synchronized false
        if (current.token != token) return@synchronized false
        releaseIfSafeLocked()
    }

    fun snapshot(): Snapshot = synchronized(lock) {
        Snapshot(
            state = state,
            ownerId = owner?.token?.ownerId,
            generation = owner?.token?.generation,
            outstandingDeliveries = outstandingDeliveries,
            initialized = initialized,
            initializeCount = initializeCount,
            stopScheduled = stopScheduled,
            stopSucceeded = stopSucceeded,
            staleCallbackDeliveries = staleCallbackDeliveries,
            staleResultDeliveries = staleResultDeliveries,
        )
    }

    override fun onEvent(jsonString: String?) {
        val event = jsonString ?: return
        val token = synchronized(lock) {
            val current = owner ?: return
            if (state != State.ACTIVE || !current.deliveriesEnabled) return
            outstandingDeliveries += 1
            current.token
        }
        dispatchEvent(token, event)
    }

    private fun admit(token: OwnerToken, requireActive: Boolean): Boolean = synchronized(lock) {
        val current = owner ?: return@synchronized false
        if (
            current.token != token ||
            !current.deliveriesEnabled ||
            state == State.RELEASED ||
            (requireActive && state != State.ACTIVE)
        ) {
            return@synchronized false
        }
        outstandingDeliveries += 1
        true
    }

    private fun dispatchEvent(token: OwnerToken, event: String) {
        dispatchAdmitted(token, DeliveryKind.CALLBACK) {
            val receiver = synchronized(lock) {
                owner
                    ?.takeIf { it.token == token && it.deliveriesEnabled }
                    ?.eventReceiver
            }
            receiver?.invoke(event)
        }
    }

    private fun dispatchAdmitted(
        token: OwnerToken,
        kind: DeliveryKind,
        delivery: () -> Unit,
    ) {
        try {
            deliveryDispatcher.dispatch {
                try {
                    val allowed = synchronized(lock) {
                        val current = owner
                        val isAllowed = current?.token == token &&
                            current.deliveriesEnabled &&
                            state != State.RELEASED
                        if (!isAllowed) {
                            when (kind) {
                                DeliveryKind.CALLBACK -> staleCallbackDeliveries += 1
                                DeliveryKind.RESULT -> staleResultDeliveries += 1
                            }
                        }
                        isAllowed
                    }
                    if (allowed) delivery()
                } finally {
                    completeAdmitted()
                }
            }
        } catch (_: Throwable) {
            completeAdmitted()
        }
    }

    private fun completeAdmitted() {
        synchronized(lock) {
            check(outstandingDeliveries > 0) { "Go runtime accounting underflow" }
            outstandingDeliveries -= 1
            maybeScheduleStopLocked()
            releaseIfSafeLocked()
        }
    }

    private fun maybeScheduleStopLocked() {
        if (
            state != State.DRAINING ||
            outstandingDeliveries != 0 ||
            stopScheduled
        ) {
            return
        }
        stopScheduled = true
        try {
            workExecutor.execute stopTask@{
                val mayStop = synchronized(lock) {
                    if (state != State.DRAINING || outstandingDeliveries != 0) {
                        stopScheduled = false
                        false
                    } else {
                        true
                    }
                }
                if (!mayStop) return@stopTask
                val stopped = runCatching(lifecycle::stopNode).getOrDefault(false)
                synchronized(lock) {
                    stopSucceeded = stopped
                    releaseIfSafeLocked()
                }
            }
        } catch (_: Throwable) {
            stopSucceeded = false
        }
    }

    private fun releaseIfSafeLocked(): Boolean {
        if (
            state != State.DRAINING ||
            outstandingDeliveries != 0 ||
            !stopScheduled ||
            !stopSucceeded
        ) {
            return false
        }
        owner = null
        state = State.RELEASED
        return true
    }
}

private object NativeGoRuntimeLifecycle : GoRuntimeLifecycle {
    override fun initialize(callback: EventCallback) {
        GoMknoon.initialize(callback)
    }

    override fun stopNode(): Boolean = runCatching {
        JSONObject(GoMknoon.stopNode()).optBoolean("ok", false)
    }.getOrDefault(false)
}

private class MainLooperGoRuntimeDeliveryDispatcher : GoRuntimeDeliveryDispatcher {
    private val handler = Handler(Looper.getMainLooper())

    override fun dispatch(block: () -> Unit) {
        check(handler.post(block)) { "Main-looper delivery was rejected" }
    }
}

internal object ProcessGoRuntimeHost {
    val instance: GoRuntimeHost by lazy {
        GoRuntimeHost(
            lifecycle = NativeGoRuntimeLifecycle,
            workExecutor = Executors.newCachedThreadPool { runnable ->
                Thread(runnable, "mknoon-go-runtime").apply { isDaemon = true }
            },
            deliveryDispatcher = MainLooperGoRuntimeDeliveryDispatcher(),
        )
    }
}
