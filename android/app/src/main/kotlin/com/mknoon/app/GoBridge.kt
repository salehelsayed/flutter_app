package com.mknoon.app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import bridge.Bridge as GoMknoon
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Bridges Flutter MethodChannel/EventChannel to the Go native library.
 *
 * MethodChannel `com.mknoon/go_bridge` handles request/response calls.
 * EventChannel `com.mknoon/go_bridge_events` streams push events from Go.
 */
class GoBridge internal constructor(
    flutterEngine: FlutterEngine,
    context: android.content.Context,
    private val runtimeHost: GoRuntimeHost = ProcessGoRuntimeHost.instance,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val appDiagnostics = com.mknoon.app.diagnostics.MknoonAppDiagnostics.get(context)
    private val appDiagnosticChannel = appDiagnostics.bridge(flutterEngine.dartExecutor.binaryMessenger)

    // FDC-S5 (M1): only emit bridge dispatch queue-wait timing on debuggable
    // builds, so the deferred two-device M1 run can read it while release builds
    // pay nothing. Derived from the app's debuggable flag (BuildConfig is not
    // generated for this module under AGP 8 unless explicitly enabled).
    private val isDebuggable =
        (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private val methodChannel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.mknoon/go_bridge"
    )
    private val eventChannel = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.mknoon/go_bridge_events"
    )
    private var eventSink: EventChannel.EventSink? = null
    private val pendingEvents = ArrayDeque<String>()
    private val pendingEventsLock = Any()
    private val maxPendingEvents = 256
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val disposed = AtomicBoolean(false)
    private val ownerToken = runtimeHost.registerOwner(
        ownerId = "flutter-engine-${System.identityHashCode(flutterEngine)}",
        eventReceiver = ::acceptEvent,
    )

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        appDiagnostics.record("startup", "bridge", "ok", "bootstrap", mapOf("phase" to "bridge_initialized"))
    }

    private fun runOnBackground(work: () -> Any?, result: MethodChannel.Result, method: String = "") {
        // FDC-S5 (M1): stamp when the call was handed to the cached thread pool so
        // the worker can report how long it waited for a thread — the thread-pool
        // serialization signal under concurrent warm/probe work. A cached pool
        // spawns a fresh thread per task, so this should read ~0 unless saturated.
        val receivedAt = if (isDebuggable && method.isNotEmpty()) System.nanoTime() else 0L
        val admitted = runtimeHost.execute(
            ownerToken,
            work = {
                if (receivedAt != 0L) {
                    emitDispatchTiming(method, (System.nanoTime() - receivedAt) / 1_000_000.0)
                }
                work()
            },
            onSuccess = { value ->
                if (!disposed.get()) result.success(value)
            },
            onError = { error ->
                if (!disposed.get()) result.error("GO_ERROR", error.message, null)
            },
        )
        if (!admitted && !disposed.get()) {
            result.error(
                "GO_RUNTIME_NOT_ACTIVE",
                "This Flutter engine does not own the active Go runtime",
                null,
            )
        }
    }

    /// FDC-S5 (M1): surface the bridge dispatch queue-wait on the same EventChannel
    /// Go push events use, so the Dart client (bridge:dispatch_timing raw passthrough)
    /// folds it into FLOW logs alongside BRIDGE_CALL_TIMING {bridgeMs}.
    private fun emitDispatchTiming(method: String, queueWaitMs: Double) {
        val json = org.json.JSONObject()
            .put("event", "bridge:dispatch_timing")
            .put(
                "data",
                org.json.JSONObject()
                    .put("method", method)
                    .put("queueWaitMs", queueWaitMs),
            )
            .toString()
        runtimeHost.emitOwnerEvent(ownerToken, json)
    }

    override fun onMethodCall(call: MethodCall, rawResult: MethodChannel.Result) {
        val result = com.mknoon.app.diagnostics.MknoonAppDiagnosticBridgeResult.wrap(call.method, call.arguments, rawResult,
            { outcome, reason, values, trace -> appDiagnostics.record("runtime", "bridge", outcome, reason, values, trace) })
        if (disposed.get()) {
            result.error("GO_BRIDGE_DISPOSED", "Go bridge is detached", null)
            return
        }
        val args = call.arguments as? String

        when (call.method) {
            // Identity
            "generateIdentity" -> runOnBackground({ GoMknoon.generateIdentity() }, result)
            "restoreIdentity" -> runOnBackground({ GoMknoon.restoreIdentity(args ?: "") }, result)

            // Crypto
            "mlKemKeygen" -> runOnBackground({ GoMknoon.mlKemKeygen() }, result)
            "encryptMessage" -> runOnBackground({ GoMknoon.encryptMessage(args ?: "") }, result)
            "decryptMessage" -> runOnBackground({ GoMknoon.decryptMessage(args ?: "") }, result)
            "signPayload" -> runOnBackground({ GoMknoon.signPayload(args ?: "") }, result)
            "verifyPayload" -> runOnBackground({ GoMknoon.verifyPayload(args ?: "") }, result)
            "encryptContactRequest" -> runOnBackground({ GoMknoon.encryptContactRequest(args ?: "") }, result)
            "decryptContactRequest" -> runOnBackground({ GoMknoon.decryptContactRequest(args ?: "") }, result)
            "migrationSessionEncap" -> runOnBackground({ GoMknoon.migrationSessionEncap(args ?: "") }, result)
            "migrationSessionDecap" -> runOnBackground({ GoMknoon.migrationSessionDecap(args ?: "") }, result)
            "migrationChunkEncrypt" -> runOnBackground({ GoMknoon.migrationChunkEncrypt(args ?: "") }, result)
            "migrationChunkDecrypt" -> runOnBackground({ GoMknoon.migrationChunkDecrypt(args ?: "") }, result)

            // Node lifecycle
            "startNode" -> runOnBackground({ GoMknoon.startNode(args ?: "") }, result)
            "stopNode" -> runOnBackground({ GoMknoon.stopNode() }, result)
            "nodeStatus" -> runOnBackground({ GoMknoon.nodeStatus() }, result, "nodeStatus")

            // Rendezvous
            "rendezvousRegister" -> runOnBackground({ GoMknoon.rendezvousRegister(args ?: "") }, result)
            "rendezvousUnregister" -> runOnBackground({ GoMknoon.rendezvousUnregister(args ?: "") }, result)
            "rendezvousDiscover" -> runOnBackground({ GoMknoon.rendezvousDiscover(args ?: "") }, result, "rendezvousDiscover")

            // Relay
            "relayReconnect" -> runOnBackground({ GoMknoon.relayReconnect() }, result)
            "relayProbe" -> runOnBackground({ GoMknoon.relayProbe(args ?: "") }, result, "relayProbe")
            "relayTurnCredentialsV1" -> runOnBackground({ GoMknoon.turnCredentialsV1() }, result)
            "turnCredentialsWithDiagnosticsV1", "relayTurnCredentialsWithDiagnosticsV1" -> runOnBackground({ GoMknoon.turnCredentialsWithDiagnosticsV1(args ?: "") }, result)
            "callDiagnosticsV1" -> runOnBackground({ GoMknoon.callDiagnosticsV1(args ?: "") }, result)
            "appDiagnosticsV1" -> runOnBackground({ GoMknoon.appDiagnosticsV1(args ?: "") }, result)
            // Presence (FDC-08/09) — Dart case names map to Go presenceGet/presenceSet bindings
            "relayPresenceGet" -> runOnBackground({ GoMknoon.presenceGet(args ?: "") }, result)
            "relayPresenceSet" -> runOnBackground({ GoMknoon.presenceSet(args ?: "") }, result)

            // Dedicated call-control relay and capability authority. These
            // commands never traverse the durable chat inbox/outbox paths.
            "callStoreV1" -> runOnBackground({ GoMknoon.callStoreV1(args ?: "") }, result)
            "callRetrieveV1" -> runOnBackground({ GoMknoon.callRetrieveV1(args ?: "") }, result)
            "callAckV1" -> runOnBackground({ GoMknoon.callAckV1(args ?: "") }, result)
            "callCancelV1" -> runOnBackground({ GoMknoon.callCancelV1(args ?: "") }, result)
            "callEndpointSetV1" -> runOnBackground({ GoMknoon.callEndpointSetV1(args ?: "") }, result)
            "callEndpointGetV1" -> runOnBackground({ GoMknoon.callEndpointGetV1(args ?: "") }, result)
            "callEndpointRevokeV1" -> runOnBackground({ GoMknoon.callEndpointRevokeV1(args ?: "") }, result)
            "callWakeHandleSetV1" -> runOnBackground({ GoMknoon.callWakeHandleSetV1(args ?: "") }, result)
            "callWakeHandleRevokeV1" -> runOnBackground({ GoMknoon.callWakeHandleRevokeV1(args ?: "") }, result)
            "callTokenSetV1" -> runOnBackground({ GoMknoon.callTokenSetV1(args ?: "") }, result)
            "callTokenRevokeV1" -> runOnBackground({ GoMknoon.callTokenRevokeV1(args ?: "") }, result)

            // Peer operations
            "dialPeer" -> runOnBackground({ GoMknoon.dialPeer(args ?: "") }, result, "dialPeer")
            // 183: active-chat keepalive liveness probe (libp2p ping).
            "peerPing" -> runOnBackground({ GoMknoon.peerPing(args ?: "") }, result, "peerPing")
            "disconnectPeer" -> runOnBackground({ GoMknoon.disconnectPeer(args ?: "") }, result)
            "sendMessage" -> runOnBackground({ GoMknoon.sendMessage(args ?: "") }, result, "sendMessage")
            "confirmDirectMessage" -> runOnBackground({ GoMknoon.confirmDirectMessage(args ?: "") }, result)
            // LAN-direct dial (FDC-11)
            "lanPeerFound" -> runOnBackground({ GoMknoon.handleLANPeerFound(args ?: "") }, result)

            // Inbox
            "inboxStore" -> runOnBackground({ GoMknoon.inboxStore(args ?: "") }, result)
            "inboxRetrieve" -> runOnBackground({ GoMknoon.inboxRetrieveWithParams(args ?: "") }, result)
            "inboxRetrievePending" -> runOnBackground({ GoMknoon.inboxRetrievePendingWithParams(args ?: "") }, result)
            "inboxAck" -> runOnBackground({ GoMknoon.inboxAck(args ?: "") }, result)
            "inboxRegisterToken" -> runOnBackground({ GoMknoon.inboxRegisterToken(args ?: "") }, result)
            "inboxUnregisterToken" -> runOnBackground({ GoMknoon.inboxUnregisterToken(args ?: "") }, result)
            // Wake-token registration (FDC-09 §12)
            "inboxRegisterWakeTokens" -> runOnBackground({ GoMknoon.registerWakeTokens(args ?: "") }, result)

            // Media
            "mediaUpload" -> runOnBackground({ GoMknoon.mediaUpload(args ?: "") }, result)
            "mediaDownload" -> runOnBackground({ GoMknoon.mediaDownload(args ?: "") }, result)
            "mediaDelete" -> runOnBackground({ GoMknoon.mediaDelete(args ?: "") }, result)
            "mediaList" -> runOnBackground({ GoMknoon.mediaList(args ?: "") }, result)
            "blobKeygen" -> runOnBackground({ GoMknoon.blobKeygen("") }, result)
            "blobEncrypt" -> runOnBackground({ GoMknoon.blobEncrypt(args ?: "") }, result)
            "blobDecrypt" -> runOnBackground({ GoMknoon.blobDecrypt(args ?: "") }, result)
            // 1:1 media over libp2p LAN (FDC-15) — Dart 'mediaLanSend' maps to Go mediaLANSend
            "mediaLanSend" -> runOnBackground({ GoMknoon.mediaLANSend(args ?: "") }, result)

            // Profile
            "profileUpload" -> runOnBackground({ GoMknoon.profileUpload(args ?: "") }, result)
            "profileDownload" -> runOnBackground({ GoMknoon.profileDownload(args ?: "") }, result)

            // Groups
            "generateGroupKey" -> runOnBackground({ GoMknoon.generateGroupKey() }, result)
            "groupCreate" -> runOnBackground({ GoMknoon.groupCreate(args ?: "") }, result)
            "groupJoinTopic" -> runOnBackground({ GoMknoon.groupJoinTopic(args ?: "") }, result)
            "groupLeaveTopic" -> runOnBackground({ GoMknoon.groupLeaveTopic(args ?: "") }, result)
            "groupPublish" -> runOnBackground({ GoMknoon.groupPublish(args ?: "") }, result)
            "groupSendReliable" -> runOnBackground({ GoMknoon.groupSendReliable(args ?: "") }, result)
            "groupPublishReaction" -> runOnBackground({ GoMknoon.groupPublishReaction(args ?: "") }, result)
            "groupUpdateConfig" -> runOnBackground({ GoMknoon.groupUpdateConfig(args ?: "") }, result)
            "groupGenerateNextKey" -> runOnBackground({ GoMknoon.groupGenerateNextKey(args ?: "") }, result)
            "groupRotateKey" -> runOnBackground({ GoMknoon.groupRotateKey(args ?: "") }, result)
            "groupUpdateKey" -> runOnBackground({ GoMknoon.groupUpdateKey(args ?: "") }, result)
            "groupEncryptMessage" -> runOnBackground({ GoMknoon.groupEncryptMessage(args ?: "") }, result)
            "groupDecryptMessage" -> runOnBackground({ GoMknoon.groupDecryptMessage(args ?: "") }, result)
            "groupInboxStore" -> runOnBackground({ GoMknoon.groupInboxStore(args ?: "") }, result)
            "groupInboxRetrieve" -> runOnBackground({ GoMknoon.groupInboxRetrieve(args ?: "") }, result)
            "groupInboxRetrieveCursor" -> runOnBackground({ GoMknoon.groupInboxRetrieveCursor(args ?: "") }, result)
            "groupAcknowledgeRecovery" -> runOnBackground({ GoMknoon.groupAcknowledgeRecovery() }, result)

            // Background task (no-op on Android)
            "bgBegin" -> result.success("")  // no-op on Android
            "bgEnd" -> result.success(null)  // no-op on Android

            else -> result.notImplemented()
        }
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        android.util.Log.i("GoBridge", "onListen: eventSink registered")
        eventSink = events
        flushPendingEvents()
    }

    override fun onCancel(arguments: Any?) {
        android.util.Log.i("GoBridge", "onCancel: eventSink cleared")
        eventSink = null
    }

    // Stable process callback is owned by GoRuntimeHost; deliveries arrive on main.
    private fun acceptEvent(json: String) {
        if (disposed.get()) return
        val sink = eventSink
        if (sink == null) {
            bufferEvent(json, "no sink")
            return
        }
        sink.success(json)
    }

    private fun bufferEvent(json: String, reason: String) {
        synchronized(pendingEventsLock) {
            if (pendingEvents.size >= maxPendingEvents) {
                pendingEvents.removeFirst()
                android.util.Log.w(
                    "GoBridge",
                    "bufferEvent: dropped oldest buffered event to keep queue <= $maxPendingEvents"
                )
            }
            pendingEvents.addLast(json)
        }
        android.util.Log.w(
            "GoBridge",
            "onEvent: BUFFERED ($reason) eventLength=${json.length}",
        )
    }

    private fun flushPendingEvents() {
        mainHandler.post {
            val sink = eventSink ?: return@post
            val snapshot = synchronized(pendingEventsLock) {
                if (pendingEvents.isEmpty()) {
                    return@synchronized emptyList<String>()
                }
                val events = pendingEvents.toList()
                pendingEvents.clear()
                events
            }
            if (snapshot.isEmpty()) return@post
            android.util.Log.i("GoBridge", "flushPendingEvents: replaying ${snapshot.size} buffered event(s)")
            snapshot.forEach { sink.success(it) }
        }
    }

    /** Starts the host-owned drain; new JNI calls/events are rejected at once. */
    internal fun requestRuntimeDrain(): Boolean = runtimeHost.requestDrain(ownerToken)

    internal fun isRuntimeReleased(): Boolean =
        runtimeHost.snapshot().state == GoRuntimeHost.State.RELEASED

    internal fun runtimeSnapshot(): GoRuntimeHost.Snapshot = runtimeHost.snapshot()

    /**
     * Debug-probe-only boundary seam. The admitted host task invokes the real
     * Go AAR before remaining in flight until the competing engine has tried
     * to acquire the canonical lease. It therefore exercises the production
     * owner/result accounting without adding a Dart-callable production API.
     */
    internal fun admitH0ProbeJniHold(
        release: CountDownLatch,
        onHeld: () -> Unit,
        onSettled: (Boolean) -> Unit,
    ): Boolean {
        if (!isDebuggable || disposed.get()) return false
        return runtimeHost.execute(
            ownerToken,
            work = {
                val status = GoMknoon.nodeStatus()
                onHeld()
                check(release.await(10, TimeUnit.SECONDS)) {
                    "H0 contender did not release admitted Go/JNI work"
                }
                status
            },
            onSuccess = { onSettled(true) },
            onError = { onSettled(false) },
        )
    }

    /** Detaches channels/sink and fences every queued result or callback. */
    fun dispose(): Boolean {
        if (!disposed.compareAndSet(false, true)) return false
        methodChannel.setMethodCallHandler(null)
        appDiagnosticChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        synchronized(pendingEventsLock) {
            pendingEvents.clear()
        }
        runtimeHost.unregister(ownerToken)
        return true
    }
}
