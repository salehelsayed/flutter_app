package com.mknoon.app.call

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import java.util.concurrent.Executor

internal class MknoonCallEventRelay(
    private val onDeliveryClaimed: (() -> Unit)? = null,
) : MknoonCallEventSink {
    private val ownerLock = ReentrantLock()
    private val ownerIdle = ownerLock.newCondition()
    @Volatile
    private var binding: RelayBinding? = null
    private var mutationInProgress = false
    private var generation = 0L

    override fun emit(event: PendingNativeCallEvent) {
        val current = ownerLock.withLock {
            val observed = binding ?: return
            if (!observed.valid) return
            observed.inFlight += 1
            observed
        }
        try {
            onDeliveryClaimed?.invoke()
            runCatching { current.target(event) }
        } finally {
            ownerLock.withLock {
                current.inFlight -= 1
                ownerIdle.signalAll()
            }
        }
    }

    fun bind(target: (PendingNativeCallEvent) -> Unit): Long = ownerLock.withLock {
        awaitOwnerIdle()
        binding?.let { previous ->
            previous.valid = false
            awaitDeliveries(previous)
        }
        generation += 1L
        binding = RelayBinding(target, generation)
        generation
    }

    fun isCurrent(
        target: (PendingNativeCallEvent) -> Unit,
        expectedGeneration: Long,
    ): Boolean {
        val current = binding
        return current != null &&
            current.valid &&
            current.target === target &&
            current.generation == expectedGeneration
    }

    fun <T> withCurrent(
        target: (PendingNativeCallEvent) -> Unit,
        expectedGeneration: Long,
        staleResult: T,
        action: () -> T,
    ): T = mutateCurrent(
        target = target,
        expectedGeneration = expectedGeneration,
        staleResult = staleResult,
        invalidate = false,
        action = action,
    )

    fun <T> withCurrentAndInvalidate(
        target: (PendingNativeCallEvent) -> Unit,
        expectedGeneration: Long,
        staleResult: T,
        action: () -> T,
    ): T = mutateCurrent(
        target = target,
        expectedGeneration = expectedGeneration,
        staleResult = staleResult,
        invalidate = true,
        action = action,
    )

    private fun <T> mutateCurrent(
        target: (PendingNativeCallEvent) -> Unit,
        expectedGeneration: Long,
        staleResult: T,
        invalidate: Boolean,
        action: () -> T,
    ): T {
        val claimed = ownerLock.withLock {
            awaitOwnerIdle()
            val current = binding
            if (
                current == null ||
                !current.valid ||
                current.target !== target ||
                current.generation != expectedGeneration
            ) {
                return staleResult
            }
            mutationInProgress = true
            current
        }
        return try {
            action()
        } finally {
            ownerLock.withLock {
                if (invalidate && binding === claimed) {
                    claimed.valid = false
                    awaitDeliveries(claimed)
                    binding = null
                    generation += 1L
                }
                mutationInProgress = false
                ownerIdle.signalAll()
            }
        }
    }

    private fun awaitOwnerIdle() {
        while (mutationInProgress) ownerIdle.awaitUninterruptibly()
    }

    private fun awaitDeliveries(claimed: RelayBinding) {
        while (claimed.inFlight > 0) ownerIdle.awaitUninterruptibly()
    }

    private class RelayBinding(
        val target: (PendingNativeCallEvent) -> Unit,
        val generation: Long,
    ) {
        @Volatile
        var valid = true
        var inFlight = 0
    }
}

/** Strict MethodChannel/EventChannel boundary for the native call mailbox. */
internal class MknoonCallNativeBridge(
    private val controller: MknoonCallLifecycleController,
    messenger: BinaryMessenger?,
    private val relay: MknoonCallEventRelay? = null,
    private val capabilitySetter: ((Boolean) -> Boolean)? = null,
    private val capabilityGetter: (() -> Boolean)? = null,
    private val failCloser: (() -> Boolean)? = null,
    private val beforeAttach: (() -> Unit)? = null,
    private val authenticatedPresenter: ((String, Long) -> Boolean)? = null,
    private val authenticatedOutgoingRegistrar: ((String, Long) -> Boolean)? = null,
    private val ringbackStarter: ((String) -> Boolean)? = null,
    private val ringbackStopper: ((String) -> Boolean)? = null,
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
    private val registrationExecutor: Executor? = null,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "mknoon/android_call_lifecycle"
        const val EVENT_CHANNEL = "mknoon/android_call_lifecycle/events"
        private const val VERSION = 1
    }

    private val methodChannel = messenger?.let { MethodChannel(it, METHOD_CHANNEL) }
    private val eventChannel = messenger?.let { EventChannel(it, EVENT_CHANNEL) }
    private val sinkLock = Any()
    private val localOwnershipLock = Any()
    private var locallyCurrent = true
    private var eventSink: EventChannel.EventSink? = null
    private var sinkGeneration = 0L
    private val attachLock = Any()
    private var attaching = false
    private val eventsBufferedDuringAttach = mutableListOf<PendingNativeCallEvent>()
    private val relayListener: (PendingNativeCallEvent) -> Unit = ::emitEvent
    private val relayGeneration: Long

    init {
        methodChannel?.setMethodCallHandler(this)
        eventChannel?.setStreamHandler(this)
        relayGeneration = relay?.bind(relayListener) ?: 0L
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "attach" -> attach(call.arguments, result)
            "detach" -> detach(call.arguments, result)
            "acknowledge" -> acknowledge(call.arguments, result)
            "markAdopted" -> withLegacyCallId(call.arguments, result, controller::markAdopted)
            "adopt" -> withDartCallHandle(call.arguments, result, controller::markAdopted)
            "activateAudio" -> withEitherCallIdentity(
                call.arguments,
                result,
                controller::activateAudio,
            )
            "deactivateAudio" -> withDartCallHandle(
                call.arguments,
                result,
                controller::deactivateAudio,
            )
            "end" -> withEitherCallIdentity(call.arguments, result, controller::endFromDart)
            "requestRoute" -> requestRoute(call.arguments, result)
            "readAudioState" -> readAudioState(call.arguments, result)
            "project" -> project(call.arguments, result)
            "presentAuthenticated" -> presentAuthenticated(call.arguments, result)
            "registerOutgoingAuthenticated" ->
                registerOutgoingAuthenticated(call.arguments, result)
            "setCapability" -> setCapabilityEnabled(call.arguments, result)
            "setCapabilityEnabled" -> setCapabilityEnabled(call.arguments, result)
            "readCapability" -> readCapability(call.arguments, result)
            "failClosed" -> failClosed(call.arguments, result)
            "startRingback" -> withRingbackHandle(call.arguments, result, ringbackStarter)
            "stopRingback" -> withRingbackHandle(call.arguments, result, ringbackStopper)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (arguments != null) {
            events.error("bad_args", "event subscription requires null arguments", null)
            return
        }
        synchronized(sinkLock) {
            sinkGeneration += 1L
            eventSink = events
        }
    }

    override fun onCancel(arguments: Any?) {
        // EventChannel cancellation is transient during a Flutter hot restart.
        // Keep this bridge's relay generation current so the restarted Dart
        // subscription can attach and replay native actions. Permanent bridge
        // teardown still invalidates ownership in dispose().
        detachControllerIfOwned(invalidate = false)
        synchronized(sinkLock) {
            sinkGeneration += 1L
            eventSink = null
        }
    }

    fun dispose() {
        detachControllerIfOwned(invalidate = true)
        synchronized(sinkLock) {
            sinkGeneration += 1L
            eventSink = null
        }
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
    }

    private fun attach(arguments: Any?, result: MethodChannel.Result) {
        if (!nullOrVersionOnly(arguments)) return badArguments(result)
        val attachCurrent = {
            performAttach(result)
            true
        }
        val attached = relay?.withCurrent(
            relayListener,
            relayGeneration,
            staleResult = false,
            action = attachCurrent,
        ) ?: synchronized(localOwnershipLock) {
            if (!locallyCurrent) false else attachCurrent()
        }
        if (!attached) result.success(null.toEnvelope())
    }

    private fun performAttach(result: MethodChannel.Result) {
        // Controller attach replays pending events for non-channel consumers.
        // Suppress that synchronous relay copy because this response carries
        // the complete ordered snapshot; live events resume immediately after.
        synchronized(attachLock) {
            attaching = true
            eventsBufferedDuringAttach.clear()
        }
        var highestSnapshotSequence = 0L
        try {
            beforeAttach?.invoke()
            val descriptor = controller.attach()?.descriptor
            highestSnapshotSequence = descriptor?.highestSequence ?: 0L
            result.success(descriptor.toEnvelope())
        } finally {
            val liveEvents = synchronized(attachLock) {
                attaching = false
                eventsBufferedDuringAttach
                    .filter { it.sequence > highestSnapshotSequence }
                    .also { eventsBufferedDuringAttach.clear() }
            }
            liveEvents.forEach(::emitEvent)
        }
    }

    private fun detach(arguments: Any?, result: MethodChannel.Result) {
        if (!nullOrVersionOnly(arguments)) return badArguments(result)
        val detached = detachControllerIfOwned(invalidate = true)
        synchronized(sinkLock) {
            sinkGeneration += 1L
            eventSink = null
        }
        result.success(detached)
    }

    private fun detachControllerIfOwned(invalidate: Boolean): Boolean {
        val targetRelay = relay
        if (targetRelay != null) {
            return if (invalidate) {
                targetRelay.withCurrentAndInvalidate(
                    relayListener,
                    relayGeneration,
                    staleResult = false,
                    action = controller::detach,
                )
            } else {
                targetRelay.withCurrent(
                    relayListener,
                    relayGeneration,
                    staleResult = false,
                    action = controller::detach,
                )
            }
        }
        return synchronized(localOwnershipLock) {
            if (!locallyCurrent) return@synchronized false
            val detached = controller.detach()
            if (invalidate) locallyCurrent = false
            detached
        }
    }

    private fun failClosed(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version") || !validVersion(map["version"])) {
            return badArguments(result)
        }
        val close = { failCloser?.invoke() ?: controller.failClosed() }
        val closed = relay?.withCurrentAndInvalidate(
            relayListener,
            relayGeneration,
            staleResult = false,
            action = close,
        ) ?: synchronized(localOwnershipLock) {
            if (!locallyCurrent) {
                false
            } else {
                try {
                    close()
                } finally {
                    locallyCurrent = false
                }
            }
        }
        synchronized(sinkLock) {
            sinkGeneration += 1L
            eventSink = null
        }
        result.success(closed)
    }

    private fun acknowledge(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        val legacyKeys = setOf(
            "nativeCallId",
            "highestConsumedSequence",
            "acknowledgement",
        )
        val dartKeys = setOf("version", "callHandle", "throughSequence", "disposition")
        val parsed = when (map.keys) {
            legacyKeys -> {
                val nativeCallId = parseUuid(map["nativeCallId"]) ?: return badArguments(result)
                val sequence = parseLong(map["highestConsumedSequence"])
                    ?: return badArguments(result)
                val acknowledgement = parseAcknowledgement(map["acknowledgement"])
                    ?: return badArguments(result)
                Triple(nativeCallId, sequence, acknowledgement)
            }
            dartKeys -> {
                if (!validVersion(map["version"])) return badArguments(result)
                val nativeCallId = resolveCallHandle(map["callHandle"])
                    ?: return badArguments(result)
                val sequence = parseLong(map["throughSequence"])
                    ?: return badArguments(result)
                val acknowledgement = parseAcknowledgement(map["disposition"])
                    ?: return badArguments(result)
                Triple(nativeCallId, sequence, acknowledgement)
            }
            else -> return badArguments(result)
        }
        result.success(controller.acknowledge(parsed.first, parsed.second, parsed.third))
    }

    private fun requestRoute(arguments: Any?, result: MethodChannel.Result) {
        val map = dartIdentityMap(arguments, setOf("route")) ?: return badArguments(result)
        val nativeCallId = resolveCallHandle(map["callHandle"])
            ?: return badArguments(result)
        val route = map["route"] as? String ?: return badArguments(result)
        result.success(controller.requestRoute(nativeCallId, route))
    }

    private fun readAudioState(arguments: Any?, result: MethodChannel.Result) {
        val map = dartIdentityMap(arguments) ?: return badArguments(result)
        val nativeCallId = resolveCallHandle(map["callHandle"]) ?: return badArguments(result)
        val state = controller.audioState(nativeCallId) ?: return badArguments(result)
        result.success(
            mapOf(
                "version" to VERSION,
                "active" to state.active,
                "muted" to state.muted,
                "route" to state.route,
                "availableRoutes" to state.availableRoutes,
            ),
        )
    }

    private fun project(arguments: Any?, result: MethodChannel.Result) {
        val map = dartIdentityMap(arguments, setOf("state")) ?: return badArguments(result)
        val nativeCallId = resolveCallHandle(map["callHandle"])
            ?: return badArguments(result)
        val state = map["state"] as? String ?: return badArguments(result)
        result.success(controller.project(nativeCallId, state))
    }

    private fun presentAuthenticated(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version", "callHandle", "expiresAtMs")) {
            return badArguments(result)
        }
        if (!validVersion(map["version"])) return badArguments(result)
        val callHandle = map["callHandle"] as? String ?: return badArguments(result)
        val expiresAtMs = parseLong(map["expiresAtMs"]) ?: return badArguments(result)
        val descriptor = controller.snapshot()
        val alreadyPresented = descriptor != null &&
                descriptor.callHandle == callHandle &&
                descriptor.expiresAtMs == expiresAtMs &&
                descriptor.terminalEvent == null
        if (alreadyPresented) return result.success(true)
        dispatchRegistration(result) {
            authenticatedPresenter?.invoke(callHandle, expiresAtMs) == true
        }
    }

    /**
     * Telecom registration blocks on the platform callback for up to the
     * registration timeout. Below API 34 core-telecom delivers that callback
     * on the main looper, so waiting on the main thread can only time out.
     * Run the wait on the registration executor and answer on main.
     */
    private fun dispatchRegistration(result: MethodChannel.Result, register: () -> Boolean) {
        val executor = registrationExecutor
        if (executor == null || Looper.myLooper() != Looper.getMainLooper()) {
            result.success(runCatching(register).getOrDefault(false))
            return
        }
        executor.execute {
            val registered = runCatching(register).getOrDefault(false)
            mainHandler.post { result.success(registered) }
        }
    }

    private fun registerOutgoingAuthenticated(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version", "callHandle", "expiresAtMs")) {
            return badArguments(result)
        }
        if (!validVersion(map["version"])) return badArguments(result)
        val callHandle = map["callHandle"] as? String ?: return badArguments(result)
        val expiresAtMs = parseLong(map["expiresAtMs"]) ?: return badArguments(result)
        val descriptor = controller.snapshot()
        val alreadyRegistered = descriptor != null &&
            descriptor.direction == PendingNativeCallDirection.OUTGOING &&
            descriptor.callHandle == callHandle &&
            descriptor.expiresAtMs == expiresAtMs &&
            descriptor.terminalEvent == null &&
            descriptor.events.any { it.type == PendingNativeCallEventType.PRESENTED }
        if (alreadyRegistered) return result.success(true)
        dispatchRegistration(result) {
            authenticatedOutgoingRegistrar?.invoke(callHandle, expiresAtMs) == true
        }
    }

    private fun setCapabilityEnabled(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version", "enabled") || !validVersion(map["version"])) {
            return badArguments(result)
        }
        val enabled = map["enabled"] as? Boolean ?: return badArguments(result)
        val setter = capabilitySetter ?: return result.success(false)
        result.success(setter(enabled))
    }

    private fun readCapability(arguments: Any?, result: MethodChannel.Result) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version") || !validVersion(map["version"])) {
            return badArguments(result)
        }
        result.success(
            mapOf(
                "version" to VERSION,
                "enabled" to (capabilityGetter?.invoke() == true),
            ),
        )
    }

    private fun withLegacyCallId(
        arguments: Any?,
        result: MethodChannel.Result,
        operation: (UUID) -> Boolean,
    ) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("nativeCallId")) return badArguments(result)
        val nativeCallId = parseUuid(map["nativeCallId"]) ?: return badArguments(result)
        result.success(operation(nativeCallId))
    }

    private fun withDartCallHandle(
        arguments: Any?,
        result: MethodChannel.Result,
        operation: (UUID) -> Boolean,
    ) {
        val map = dartIdentityMap(arguments) ?: return badArguments(result)
        val nativeCallId = resolveCallHandle(map["callHandle"])
            ?: return badArguments(result)
        result.success(operation(nativeCallId))
    }

    private fun withEitherCallIdentity(
        arguments: Any?,
        result: MethodChannel.Result,
        operation: (UUID) -> Boolean,
    ) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        when (map.keys) {
            setOf("nativeCallId") -> {
                val nativeCallId = parseUuid(map["nativeCallId"])
                    ?: return badArguments(result)
                result.success(operation(nativeCallId))
            }
            setOf("version", "callHandle") -> {
                if (!validVersion(map["version"])) return badArguments(result)
                val nativeCallId = resolveCallHandle(map["callHandle"])
                    ?: return badArguments(result)
                result.success(operation(nativeCallId))
            }
            else -> badArguments(result)
        }
    }

    private fun dartIdentityMap(
        arguments: Any?,
        extraKeys: Set<String> = emptySet(),
    ): Map<*, *>? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != setOf("version", "callHandle") + extraKeys) return null
        if (!validVersion(map["version"])) return null
        if (map["callHandle"] !is String) return null
        return map
    }

    private fun resolveCallHandle(value: Any?): UUID? {
        val callHandle = value as? String ?: return null
        return controller.resolveCallHandle(callHandle)
    }

    private fun emitEvent(event: PendingNativeCallEvent) {
        synchronized(attachLock) {
            if (attaching) {
                eventsBufferedDuringAttach += event
                return
            }
        }
        val descriptor = controller.channelDescriptor(event) ?: return
        val envelope = descriptor.toEnvelope(listOf(event))
        val delivery = synchronized(sinkLock) {
            val sink = eventSink ?: return
            PendingSinkDelivery(sink, sinkGeneration, envelope)
        }
        val deliver = Runnable {
            val stillCurrent = synchronized(sinkLock) {
                eventSink === delivery.sink &&
                    sinkGeneration == delivery.generation &&
                    (relay == null || relay.isCurrent(relayListener, relayGeneration))
            }
            if (stillCurrent) runCatching { delivery.sink.success(delivery.envelope) }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            deliver.run()
        } else {
            mainHandler.post(deliver)
        }
    }

    private fun PendingNativeCallDescriptor?.toEnvelope(
        selectedEvents: List<PendingNativeCallEvent>? = null,
    ): Map<String, Any?> {
        val descriptor = this
            ?: return mapOf(
                "version" to VERSION,
                "descriptor" to null,
                "events" to emptyList<Map<String, Any?>>(),
                "nativeCallId" to null,
                "highestSequence" to 0L,
            )
        val events = selectedEvents ?: descriptor.events
        return mapOf(
            "version" to VERSION,
            "descriptor" to mapOf(
                "callHandle" to descriptor.callHandle,
                "expiresAtMs" to descriptor.expiresAtMs,
                "direction" to when (descriptor.direction) {
                    PendingNativeCallDirection.INCOMING -> "incoming"
                    PendingNativeCallDirection.OUTGOING -> "outgoing"
                },
                "phase" to when (descriptor.phase) {
                    PendingNativeCallPhase.PRE_START -> "preStart"
                    PendingNativeCallPhase.JOURNAL -> "journal"
                },
                "presented" to (
                    descriptor.handoffAcknowledgement ==
                        PendingNativeCallAcknowledgement.ADOPTED ||
                        descriptor.events.any {
                            it.type == PendingNativeCallEventType.PRESENTED
                        }
                ),
            ),
            "events" to events.map { event ->
                mapOf(
                    "callHandle" to descriptor.callHandle,
                    "sequence" to event.sequence,
                    "eventId" to event.eventId.toString(),
                    "type" to event.type.dartName(),
                    "occurredAtMs" to descriptor.receivedAtMs,
                )
            },
            // Compatibility for the frozen native bridge contract. Dart treats
            // these as the only permitted compatibility keys.
            "nativeCallId" to descriptor.nativeCallId.toString(),
            "highestSequence" to (
                selectedEvents?.maxOfOrNull { it.sequence } ?: descriptor.highestSequence
            ),
        )
    }

    private data class PendingSinkDelivery(
        val sink: EventChannel.EventSink,
        val generation: Long,
        val envelope: Map<String, Any?>,
    )

    private fun PendingNativeCallEventType.dartName(): String = when (this) {
        PendingNativeCallEventType.PRESENTED -> "presented"
        PendingNativeCallEventType.ANSWER_REQUESTED -> "answer"
        PendingNativeCallEventType.DECLINE_REQUESTED -> "decline"
        PendingNativeCallEventType.END_REQUESTED -> "end"
        PendingNativeCallEventType.REMOTE_CANCELLED -> "remoteCancelled"
        PendingNativeCallEventType.EXPIRED -> "expired"
        PendingNativeCallEventType.PROVIDER_REMOVED -> "providerRemoved"
        PendingNativeCallEventType.MUTE_CHANGED -> "muteChanged"
        PendingNativeCallEventType.ROUTE_CHANGED -> "routeChanged"
        PendingNativeCallEventType.AUDIO_ACTIVATED -> "audioActivated"
        PendingNativeCallEventType.AUDIO_DEACTIVATED -> "audioDeactivated"
        PendingNativeCallEventType.NATIVE_FAILURE -> "nativeFailure"
    }

    private fun parseUuid(value: Any?): UUID? =
        (value as? String)?.let { runCatching { UUID.fromString(it) }.getOrNull() }

    private fun parseLong(value: Any?): Long? = when (value) {
        is Byte -> value.toLong()
        is Short -> value.toLong()
        is Int -> value.toLong()
        is Long -> value
        else -> null
    }

    private fun parseAcknowledgement(value: Any?): PendingNativeCallAcknowledgement? =
        (value as? String)?.let { text ->
            PendingNativeCallAcknowledgement.entries.singleOrNull { it.name == text }
        }

    /**
     * Ringback (the caller-side ringing tone) is keyed by the Dart call handle
     * rather than a native call id: the tone must work even when no Telecom
     * connection exists, and a stale stop must never silence a later call.
     */
    private fun withRingbackHandle(
        arguments: Any?,
        result: MethodChannel.Result,
        operation: ((String) -> Boolean)?,
    ) {
        val map = arguments as? Map<*, *> ?: return badArguments(result)
        if (map.keys != setOf("version", "callHandle") || !validVersion(map["version"])) {
            return badArguments(result)
        }
        val callHandle = map["callHandle"] as? String ?: return badArguments(result)
        if (callHandle.length != 36 || runCatching { UUID.fromString(callHandle) }.isFailure) {
            return badArguments(result)
        }
        result.success(operation?.invoke(callHandle) == true)
    }

    private fun validVersion(value: Any?): Boolean = parseLong(value) == VERSION.toLong()

    private fun nullOrVersionOnly(arguments: Any?): Boolean {
        if (arguments == null) return true
        val map = arguments as? Map<*, *> ?: return false
        return map.keys == setOf("version") && validVersion(map["version"])
    }

    private fun badArguments(result: MethodChannel.Result) {
        result.error("bad_args", "invalid native call arguments", null)
    }
}
