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
    // API scaffold: behavior lands in the GREEN commit.
    fun availability(): Map<String, Any> = emptyMap()
    fun arm(id: CallPipIdentity, source: CallPipSource, controls: CallPipControls): Map<String, Any> =
        mapOf("armed" to false, "reason" to "unimplemented")
    fun update(id: CallPipIdentity, controls: CallPipControls): Boolean = false
    fun enter(id: CallPipIdentity): Boolean = false
    fun disarm(id: CallPipIdentity): Boolean = false
    fun onUserLeaving() = Unit
    fun onEntered() = Unit
    fun onExited(restored: Boolean) = Unit
    fun onAction(kind: String) = Unit
    fun onBlocked(reason: String) = Unit
    fun onReturnedWithoutEntry() = Unit
}
