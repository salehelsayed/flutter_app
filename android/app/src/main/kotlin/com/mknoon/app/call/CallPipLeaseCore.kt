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

/** Platform effects. A sink is an opaque native renderer bound to one track. */
interface CallPipPlatform {
    fun supported(): Boolean
    fun hasVideoTrack(source: CallPipSource): Boolean
    fun attachSink(source: CallPipSource): Any?
    fun releaseSink(sink: Any)
    fun setAutoEnter(controls: CallPipControls?)
    fun requestEnter(): Boolean
    fun leavePip()
}

class CallPipLeaseCore(
    private val platform: CallPipPlatform,
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

    fun availability(): Map<String, Any> {
        val supported = platform.supported()
        // Unit 3 never enables same-session background capture.
        return mapOf("supported" to supported, "cameraInPip" to false, "reason" to (if (supported) "ok" else "os"))
    }

    fun arm(id: CallPipIdentity, source: CallPipSource, controls: CallPipControls): Map<String, Any> {
        if (!accepts(id)) return mapOf("armed" to false, "reason" to "stale")
        if (id.instanceId != instance) {
            instance?.let { retiredInstances += it }
            instance = id.instanceId
        }
        highestLease = id.leaseId
        retire("disarmed")
        if (!platform.supported()) return mapOf("armed" to false, "reason" to "unsupported")
        if (!platform.hasVideoTrack(source)) return mapOf("armed" to false, "reason" to "trackNotFound")
        lease = Lease(id, source)
        platform.setAutoEnter(controls)
        return mapOf("armed" to true, "reason" to "ok")
    }

    fun update(id: CallPipIdentity, controls: CallPipControls): Boolean {
        if (lease?.id != id) return false
        platform.setAutoEnter(controls)
        return true
    }

    fun enter(id: CallPipIdentity): Boolean {
        val current = lease ?: return false
        if (current.id != id) return false
        return current.entered || platform.requestEnter()
    }

    /** Idempotent: a retired or unknown triple is already clean and never touches a successor. */
    fun disarm(id: CallPipIdentity): Boolean {
        if (lease?.id == id) retire("disarmed")
        return true
    }

    fun onUserLeaving() {
        val current = lease ?: return
        if (current.sink == null) current.sink = platform.attachSink(current.source)
    }

    fun onEntered() {
        val current = lease ?: return
        if (current.entered) return
        if (current.sink == null) current.sink = platform.attachSink(current.source)
        if (current.sink == null) {
            send(current, "failed", "code" to "trackLost")
            drop(current)
            platform.leavePip()
            return
        }
        current.entered = true
        send(current, "entered")
    }

    fun onExited(restored: Boolean) {
        val current = lease ?: return
        if (!current.entered) return
        current.entered = false
        current.sink?.let(platform::releaseSink)
        current.sink = null
        send(current, "exited", "reason" to (if (restored) "restored" else "closed"))
    }

    fun onAction(kind: String) {
        val current = lease ?: return
        if (!current.entered || kind !in ACTIONS) return
        send(current, "action", "kind" to kind)
    }

    fun onBlocked(reason: String) {
        val current = lease ?: return
        if (reason !in BLOCKED) return
        val wasEntered = current.entered
        drop(current)
        if (wasEntered) platform.leavePip()
        send(current, "blocked", "reason" to reason)
    }

    fun onReturnedWithoutEntry() {
        val current = lease ?: return
        if (current.entered) return
        current.sink?.let(platform::releaseSink)
        current.sink = null
    }

    private fun accepts(id: CallPipIdentity): Boolean {
        if (id.instanceId in retiredInstances) return false
        return id.instanceId != instance || id.leaseId > highestLease
    }

    private fun retire(reason: String) {
        val current = lease ?: return
        val wasEntered = current.entered
        drop(current)
        if (wasEntered) {
            platform.leavePip()
            send(current, "exited", "reason" to reason)
        }
    }

    /** Retire first, then clean up: no callback can reach this lease afterwards. */
    private fun drop(current: Lease) {
        lease = null
        current.entered = false
        platform.setAutoEnter(null)
        current.sink?.let(platform::releaseSink)
        current.sink = null
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
