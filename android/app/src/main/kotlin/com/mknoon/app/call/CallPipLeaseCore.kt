package com.mknoon.app.call

/**
 * Live-call PiP lease state (bridge contract v1, bl16-pip-bridge-contract.md).
 * Pure Kotlin: identity, lease order, seq and event rules only. All calls come
 * from the main thread. Platform effects go through [CallPipPlatform].
 * Native never starts, stops or switches a camera and never ends a call.
 */
data class CallPipIdentity(val instanceId: String, val callId: String, val leaseId: Long) {
    companion object {
        fun parse(args: Map<*, *>?): CallPipIdentity? {
            if (args == null || (args["version"] as? Number)?.toInt() != 1) return null
            val instance = args["instanceId"] as? String
            val call = args["callId"] as? String
            val lease = (args["leaseId"] as? Number)?.toLong()
            if (instance.isNullOrEmpty() || call.isNullOrEmpty()) return null
            if (lease == null || lease <= 0) return null
            return CallPipIdentity(instance, call, lease)
        }
    }
}

data class CallPipSource(val peerConnectionId: String, val remoteTrackId: String) {
    companion object {
        fun parse(args: Map<*, *>): CallPipSource? {
            val pc = args["peerConnectionId"] as? String
            val track = args["remoteTrackId"] as? String
            val negotiation = args["negotiationId"] as? String
            val revision = (args["mediaRevision"] as? Number)?.toLong()
            val epoch = (args["rendererEpoch"] as? Number)?.toLong()
            if (pc.isNullOrEmpty() || track.isNullOrEmpty() || negotiation.isNullOrEmpty()) return null
            if (revision == null || revision < 0 || epoch == null || epoch < 0) return null
            return CallPipSource(pc, track)
        }
    }
}

data class CallPipControls(val muted: Boolean, val cameraOn: Boolean, val cameraEnabled: Boolean) {
    companion object {
        fun parse(args: Map<*, *>): CallPipControls? {
            val muted = args["muted"] as? Boolean ?: return null
            val on = args["cameraOn"] as? Boolean ?: return null
            val enabled = args["cameraEnabled"] as? Boolean ?: return null
            return CallPipControls(muted, on, enabled)
        }
    }
}

/**
 * Exact remote lookup (PIP-NATIVE-1). The pinned plugin's peer lookup checks
 * local tracks first, so a local id collision is rejected before asking the
 * exact peer; there is never a global fallback.
 */
internal fun <T : Any> resolveExactRemoteTrack(
    source: CallPipSource,
    localTrack: (String) -> Any?,
    peerTrack: (trackId: String, peerConnectionId: String) -> T?,
): T? {
    if (localTrack(source.remoteTrackId) != null) return null
    return peerTrack(source.remoteTrackId, source.peerConnectionId)
}

/** Platform effects. A sink is an opaque native renderer bound to one track.
 * releaseSink and setAutoEnter throw when the platform cleanup fails. */
interface CallPipPlatform {
    fun supported(): Boolean
    fun hasVideoTrack(source: CallPipSource): Boolean
    fun attachSink(source: CallPipSource): Any?
    fun releaseSink(sink: Any)
    /** Lease-qualified so platform controls can carry the exact triple. */
    fun setAutoEnter(lease: CallPipIdentity?, controls: CallPipControls?)
    fun requestEnter(): Boolean
    fun leavePip()
}

/**
 * Every OS callback and control carries the triple captured when it began
 * (PIP-NATIVE-2); a stale triple never touches the current lease. One entry
 * and one exit per lease: exit retires it (PIP-NATIVE-3). Failed cleanup stays
 * owned until a disarm retries it (PIP-NATIVE-4).
 */
class CallPipLeaseCore(
    private val platform: CallPipPlatform,
    private val debugTrace: ((String) -> Unit)? = null,
    private val emit: (Map<String, Any>) -> Unit,
) {
    private class Lease(val id: CallPipIdentity, val source: CallPipSource) {
        var seq = 0L
        var sink: Any? = null
        var entered = false
    }

    private var lease: Lease? = null
    private var instance: String? = null
    private var highestLease = 0L
    private val retiredInstances = mutableSetOf<String>()
    private val pendingSinks = mutableMapOf<CallPipIdentity, Any>()
    private var pendingAutoOff: CallPipIdentity? = null
    // The lease an in-flight OS entry belongs to, captured when it began
    // (explicit enter or user leave); never resolved from the current lease
    // at completion time.
    private var pendingEntry: CallPipIdentity? = null

    internal fun traceState(event: String) {
        debugTrace?.invoke(
            "$event current=${lease?.id?.leaseId ?: 0} pending=${pendingEntry?.leaseId ?: 0}" +
                " entered=${lease?.entered == true} sink=${lease?.sink != null}",
        )
    }

    fun availability(): Map<String, Any> {
        val supported = platform.supported()
        // Unit 3 never enables same-session background capture.
        return mapOf("supported" to supported, "cameraInPip" to false, "reason" to (if (supported) "ok" else "os"))
    }

    fun arm(id: CallPipIdentity, source: CallPipSource, controls: CallPipControls): Map<String, Any> {
        traceState("arm requested=${id.leaseId}")
        if (!accepts(id)) {
            traceState("arm response armed=false reason=stale")
            return mapOf("armed" to false, "reason" to "stale")
        }
        if (id.instanceId != instance) {
            instance?.let { retiredInstances += it }
            instance = id.instanceId
        }
        highestLease = id.leaseId
        retire("disarmed")
        if (!platform.supported()) {
            traceState("arm response armed=false reason=unsupported")
            return mapOf("armed" to false, "reason" to "unsupported")
        }
        if (!platform.hasVideoTrack(source)) {
            traceState("arm response armed=false reason=trackNotFound")
            return mapOf("armed" to false, "reason" to "trackNotFound")
        }
        lease = Lease(id, source)
        platform.setAutoEnter(id, controls)
        pendingAutoOff = null
        traceState("arm response armed=true reason=ok")
        return mapOf("armed" to true, "reason" to "ok")
    }

    fun update(id: CallPipIdentity, controls: CallPipControls): Boolean {
        current(id) ?: return false
        platform.setAutoEnter(id, controls)
        return true
    }

    fun enter(id: CallPipIdentity): Boolean {
        traceState("enter requested=${id.leaseId}")
        val target = current(id) ?: return false
        if (target.entered) return true
        // A retired lease's OS start is still outstanding: refuse, never overwrite.
        if (pendingEntry != null && pendingEntry != id) return false
        val previous = pendingEntry
        pendingEntry = id
        if (platform.requestEnter()) return true
        pendingEntry = previous
        return false
    }

    /** Retires a current triple, then retries any cleanup it still owns. True
     * once nothing of that lease is left; never touches a successor. */
    fun disarm(id: CallPipIdentity): Boolean {
        traceState("disarm requested=${id.leaseId}")
        if (lease?.id == id) retire("disarmed")
        return retryCleanup(id)
    }

    /** OS pre-entry UI notification, distinct from its eventual completion. */
    fun onAutoEnterTransition(transitioningToPip: Boolean) {
        traceState("onAutoEnterTransition value=$transitioningToPip")
        if (transitioningToPip) beginEntry()
    }

    /** OS entry is starting: attach the remote sink early and return the triple
     * the adapter must pass to every later entry/exit callback. */
    fun beginEntry(): CallPipIdentity? {
        traceState("beginEntry before")
        val target = lease ?: return null
        // An outstanding capture keeps its identity; a retired lease's capture
        // blocks the successor until its own terminal callback settles it.
        val owner = pendingEntry ?: target.id
        if (owner != target.id) return null
        pendingEntry = owner
        if (target.sink == null) target.sink = platform.attachSink(target.source)
        traceState("beginEntry accepted=${owner.leaseId}")
        return owner
    }

    // OS-level callbacks: attributed only to the captured in-flight entry.

    /** False when the completion has no captured entry or a stale one; the
     * adapter must then leave PiP so no unbound window stays visible. */
    fun osEntered(): Boolean {
        traceState("osEntered before")
        val owner = pendingEntry ?: run {
            traceState("osEntered accepted=false reason=noPendingEntry")
            return false
        }
        onEntered(owner)
        return (lease?.let { it.id == owner && it.entered } == true).also {
            traceState("osEntered accepted=$it")
        }
    }

    fun osExited(restored: Boolean) {
        traceState("osExited restored=$restored")
        pendingEntry?.let { onExited(it, restored) }
        pendingEntry = null
    }

    fun osEntryFailed() {
        traceState("osEntryFailed")
        pendingEntry?.let(::onEntryFailed)
        pendingEntry = null
    }

    /** [settled] false keeps a current capture (iOS can report active before
     * stop); a retired lease's capture is always settled here. */
    fun osReturnedWithoutEntry(settled: Boolean) {
        traceState("osReturnedWithoutEntry settled=$settled")
        val owner = pendingEntry ?: return
        onReturnedWithoutEntry(owner)
        if (settled || lease?.id != owner) pendingEntry = null
    }

    fun onEntered(id: CallPipIdentity) {
        val target = current(id) ?: return
        if (target.entered) return
        if (target.sink == null) target.sink = platform.attachSink(target.source)
        if (target.sink == null) {
            send(target, "failed", "code" to "trackLost")
            drop(target)
            traceState("leave reason=trackLost")
            platform.leavePip()
            return
        }
        target.entered = true
        send(target, "entered")
    }

    fun onExited(id: CallPipIdentity, restored: Boolean) {
        val target = current(id) ?: return
        if (!target.entered) return
        send(target, "exited", "reason" to (if (restored) "restored" else "closed"))
        drop(target)
    }

    /** OS entry failed after it began (iOS start error, Android refusal). */
    fun onEntryFailed(id: CallPipIdentity) {
        val target = current(id) ?: return
        if (target.entered) return
        send(target, "failed", "code" to "enterRejected")
        drop(target)
    }

    fun onReturnedWithoutEntry(id: CallPipIdentity) {
        val target = current(id) ?: return
        if (target.entered) return
        val sink = target.sink ?: return
        target.sink = null
        releaseOwned(target.id, sink)
    }

    fun onAction(id: CallPipIdentity, kind: String) {
        val target = current(id) ?: return
        if (!target.entered || kind !in ACTIONS) return
        send(target, "action", "kind" to kind)
    }

    /** Lock or user-disabled: retires the current lease even before entry. */
    fun onBlocked(reason: String) {
        traceState("onBlocked")
        val target = lease ?: return
        if (reason !in BLOCKED) return
        val wasEntered = target.entered
        drop(target)
        if (wasEntered) platform.leavePip()
        send(target, "blocked", "reason" to reason)
    }

    /** Host going away (engine detach): retire without events. */
    fun shutdown() {
        traceState("shutdown")
        val target = lease ?: return
        val wasEntered = target.entered
        drop(target)
        if (wasEntered) platform.leavePip()
    }

    private fun current(id: CallPipIdentity): Lease? = lease?.takeIf { it.id == id }

    private fun accepts(id: CallPipIdentity): Boolean {
        if (id.instanceId in retiredInstances) return false
        return id.instanceId != instance || id.leaseId > highestLease
    }

    private fun retire(reason: String) {
        traceState("retire reason=$reason")
        val target = lease ?: return
        val wasEntered = target.entered
        drop(target)
        if (wasEntered) {
            platform.leavePip()
            send(target, "exited", "reason" to reason)
        }
    }

    /** Retire first, then clean up; failed cleanup stays owned by this triple. */
    private fun drop(target: Lease) {
        lease = null
        target.entered = false
        try {
            platform.setAutoEnter(null, null)
        } catch (_: Exception) {
            pendingAutoOff = target.id
        }
        val sink = target.sink ?: return
        target.sink = null
        releaseOwned(target.id, sink)
    }

    private fun releaseOwned(id: CallPipIdentity, sink: Any) {
        try {
            platform.releaseSink(sink)
        } catch (_: Exception) {
            pendingSinks[id] = sink
        }
    }

    private fun retryCleanup(id: CallPipIdentity): Boolean {
        if (pendingAutoOff == id && lease == null) {
            try {
                platform.setAutoEnter(null, null)
                pendingAutoOff = null
            } catch (_: Exception) {
                return false
            }
        }
        val sink = pendingSinks[id] ?: return pendingAutoOff != id
        return try {
            platform.releaseSink(sink)
            pendingSinks.remove(id)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun send(target: Lease, type: String, vararg extra: Pair<String, Any>) {
        target.seq += 1
        emit(
            mapOf(
                "version" to 1,
                "instanceId" to target.id.instanceId,
                "callId" to target.id.callId,
                "leaseId" to target.id.leaseId,
                "seq" to target.seq,
                "type" to type,
            ) + extra,
        )
    }

    companion object {
        private val ACTIONS = setOf("mute", "camera", "end")
        private val BLOCKED = setOf("locked", "userDisabled")
    }
}
