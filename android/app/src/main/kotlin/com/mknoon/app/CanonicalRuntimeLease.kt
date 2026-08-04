package com.mknoon.app

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Process-wide writable-runtime lease; read-only FlutterFire never acquires it. */
internal class CanonicalRuntimeLeaseBroker {
    enum class State {
        ACTIVE,
        DRAINING,
        RELEASED,
    }

    enum class Role {
        FOREGROUND,
        RECOVERY,
        FIREBASE_READ_ONLY,
    }

    data class Token(
        val generation: Long,
        val ownerId: String,
        val binding: String,
        val role: Role,
    )

    data class Snapshot(
        val state: State,
        val generation: Long?,
        val ownerId: String?,
        val binding: String?,
        val role: Role?,
        val maximumConcurrentWritableOwners: Int,
    )

    private val lock = Any()
    private var state = State.RELEASED
    private var token: Token? = null
    private var nextGeneration = 0L
    private var maximumConcurrentWritableOwners = 0

    fun acquire(ownerId: String, binding: String, role: Role): Token? = synchronized(lock) {
        if (
            ownerId.isBlank() ||
            binding.isBlank() ||
            role == Role.FIREBASE_READ_ONLY
        ) {
            return@synchronized null
        }
        val current = token
        if (
            state == State.ACTIVE &&
            current?.ownerId == ownerId &&
            current.binding == binding &&
            current.role == role
        ) {
            return@synchronized current
        }
        if (state != State.RELEASED || current != null || nextGeneration == Long.MAX_VALUE) {
            return@synchronized null
        }
        val acquired = Token(++nextGeneration, ownerId, binding, role)
        token = acquired
        state = State.ACTIVE
        maximumConcurrentWritableOwners = maxOf(maximumConcurrentWritableOwners, 1)
        acquired
    }

    fun beginDrain(expected: Token): Boolean = synchronized(lock) {
        if (token != expected || state == State.RELEASED) return@synchronized false
        state = State.DRAINING
        true
    }

    /** Rotates only the ACTIVE owner's opaque account binding in-place. */
    fun rebind(expected: Token, binding: String): Token? = synchronized(lock) {
        val normalized = binding.trim().takeIf { it.isNotEmpty() }
            ?: return@synchronized null
        if (token != expected || state != State.ACTIVE) return@synchronized null
        val rebound = expected.copy(binding = normalized)
        token = rebound
        rebound
    }

    /** A failed/omitted DB close retains DRAINING ownership and fails closed. */
    fun release(expected: Token, databaseClosed: Boolean): Boolean = synchronized(lock) {
        if (token != expected || state != State.DRAINING || !databaseClosed) {
            return@synchronized false
        }
        token = null
        state = State.RELEASED
        true
    }

    fun snapshot(): Snapshot = synchronized(lock) {
        Snapshot(
            state = state,
            generation = token?.generation,
            ownerId = token?.ownerId,
            binding = token?.binding,
            role = token?.role,
            maximumConcurrentWritableOwners = maximumConcurrentWritableOwners,
        )
    }
}

internal object ProcessCanonicalRuntimeLease {
    val broker = CanonicalRuntimeLeaseBroker()
}

/** Engine-bound MethodChannel API; callers cannot spoof another owner ID/role. */
internal class CanonicalRuntimeLeaseBridge(
    messenger: BinaryMessenger?,
    private val ownerId: String,
    private val role: CanonicalRuntimeLeaseBroker.Role,
    private val broker: CanonicalRuntimeLeaseBroker = ProcessCanonicalRuntimeLease.broker,
    private val attachRuntimeOwner: (() -> Boolean)? = null,
    private val beginRuntimeDrain: (() -> Boolean)? = null,
    private val isRuntimeReleased: (() -> Boolean)? = null,
) : MethodChannel.MethodCallHandler {
    companion object {
        internal const val CHANNEL_NAME = "mknoon/canonical_runtime_lease"
    }

    private val channel = messenger?.let { MethodChannel(it, CHANNEL_NAME) }
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private var token: CanonicalRuntimeLeaseBroker.Token? = null
    private var runtimeAttached = false

    init {
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquire" -> acquire(call, result)
            "attachRuntime" -> attachRuntime(result)
            "rebind" -> rebind(call, result)
            "beginDrain" -> beginDrain(result)
            "quiesceRuntime" -> quiesceRuntime(result)
            "release" -> release(call, result)
            "status" -> result.success(snapshotMap())
            else -> result.notImplemented()
        }
    }

    private fun rebind(call: MethodCall, result: MethodChannel.Result) {
        val binding = (call.arguments as? Map<*, *>)
            ?.get("binding")
            ?.let { it as? String }
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (binding == null) {
            result.error("bad_args", "binding is required", null)
            return
        }
        val current = token
        val rebound = current?.let { broker.rebind(it, binding) }
        if (rebound == null) {
            result.error(
                "lease_not_active",
                "only the active canonical owner can rotate binding",
                snapshotMap(),
            )
            return
        }
        token = rebound
        result.success(tokenMap(rebound, CanonicalRuntimeLeaseBroker.State.ACTIVE))
    }

    private fun acquire(call: MethodCall, result: MethodChannel.Result) {
        val binding = (call.arguments as? Map<*, *>)
            ?.get("binding")
            ?.let { it as? String }
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (binding == null) {
            result.error("bad_args", "binding is required", null)
            return
        }
        val acquired = broker.acquire(ownerId, binding, role)
        if (acquired == null) {
            result.error("lease_unavailable", "canonical writable runtime is owned", snapshotMap())
            return
        }
        token = acquired
        result.success(tokenMap(acquired, CanonicalRuntimeLeaseBroker.State.ACTIVE))
    }

    /** Called only after Dart has opened SQLCipher under the acquired lease. */
    private fun attachRuntime(result: MethodChannel.Result) {
        val current = token
        if (current == null || broker.snapshot().state != CanonicalRuntimeLeaseBroker.State.ACTIVE) {
            result.success(false)
            return
        }
        if (runtimeAttached) {
            result.success(true)
            return
        }
        runtimeAttached = runCatching {
            attachRuntimeOwner?.invoke() ?: true
        }.getOrDefault(false)
        result.success(runtimeAttached)
    }

    private fun beginDrain(result: MethodChannel.Result) {
        val current = token
        if (current == null || !broker.beginDrain(current)) {
            result.success(false)
            return
        }
        val runtimeAlreadyReleased = !runtimeAttached || runCatching {
            isRuntimeReleased?.invoke() ?: false
        }.getOrDefault(false)
        val runtimeDrainStarted = runtimeAlreadyReleased || runCatching {
            beginRuntimeDrain?.invoke() ?: true
        }.getOrDefault(false)
        result.success(runtimeDrainStarted)
    }

    private fun quiesceRuntime(result: MethodChannel.Result) {
        val released = isRuntimeReleased
        if (!runtimeAttached || released == null) {
            result.success(true)
            return
        }
        val deadline = SystemClock.uptimeMillis() + 2_000L
        fun poll() {
            if (runCatching(released).getOrDefault(false)) {
                result.success(true)
                return
            }
            if (SystemClock.uptimeMillis() >= deadline) {
                result.success(false)
                return
            }
            mainHandler.postDelayed(::poll, 10L)
        }
        poll()
    }

    private fun release(call: MethodCall, result: MethodChannel.Result) {
        val databaseClosed = (call.arguments as? Map<*, *>)?.get("databaseClosed") as? Boolean
        if (databaseClosed == null) {
            result.error("bad_args", "databaseClosed is required", null)
            return
        }
        val current = token
        val runtimeIsReleased = runCatching {
            isRuntimeReleased?.invoke() ?: true
        }.getOrDefault(false)
        val released = current != null &&
            runtimeIsReleased &&
            broker.release(current, databaseClosed)
        if (released) {
            token = null
            runtimeAttached = false
        }
        result.success(released)
    }

    private fun snapshotMap(): Map<String, Any?> {
        val snapshot = broker.snapshot()
        return mapOf(
            "state" to snapshot.state.name,
            "generation" to snapshot.generation,
            "ownerId" to snapshot.ownerId,
            "binding" to snapshot.binding,
            "role" to snapshot.role?.name,
            "maximumConcurrentWritableOwners" to snapshot.maximumConcurrentWritableOwners,
        )
    }

    private fun tokenMap(
        value: CanonicalRuntimeLeaseBroker.Token,
        state: CanonicalRuntimeLeaseBroker.State,
    ): Map<String, Any?> = mapOf(
        "state" to state.name,
        "generation" to value.generation,
        "binding" to value.binding,
        "role" to value.role.name,
        "maximumConcurrentWritableOwners" to broker.snapshot().maximumConcurrentWritableOwners,
    )

    /** Detach never pretends the database closed; it only enters DRAINING. */
    fun dispose() {
        channel?.setMethodCallHandler(null)
        token?.let { current ->
            if (broker.beginDrain(current) && runtimeAttached) {
                runCatching { beginRuntimeDrain?.invoke() }
            }
        }
    }
}
