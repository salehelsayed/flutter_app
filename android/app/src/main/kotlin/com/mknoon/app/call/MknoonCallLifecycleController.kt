package com.mknoon.app.call

import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

internal interface MknoonCallLifecycleStore {
    fun create(payload: CallWakePayload): PendingNativeCallCreateResult

    fun createOutgoing(payload: CallWakePayload): PendingNativeCallCreateResult = create(payload)

    fun append(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): PendingNativeCallAppendResult

    fun snapshot(): PendingNativeCallDescriptor?

    fun acknowledge(
        nativeCallId: UUID,
        highestConsumedSequence: Long,
        acknowledgement: PendingNativeCallAcknowledgement,
    ): Boolean

    fun resolveAcknowledgementReceipt(callHandle: String): UUID? = null
}

internal interface MknoonCallRegistrationCallback {
    fun onRegistered()

    fun onFailure()

    fun onRegistrationAbandoned() {
        onFailure()
    }
}

internal interface MknoonCallPlatform {
    fun registerIncoming(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    )

    fun registerOutgoing(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    ) = registerIncoming(nativeCallId, callback)

    fun showIncoming(nativeCallId: UUID)

    fun startForeground(nativeCallId: UUID)

    fun answer(nativeCallId: UUID)

    fun end(nativeCallId: UUID)

    fun cancelNotification(nativeCallId: UUID)

    fun stopForeground(nativeCallId: UUID)

    fun stopIncomingRinger(nativeCallId: UUID) = Unit

    fun requestAudioFocus(nativeCallId: UUID)

    fun abandonAudioFocus(nativeCallId: UUID)

    fun startEndpointUpdates(nativeCallId: UUID)

    fun stopEndpointUpdates(nativeCallId: UUID)

    fun startMicrophoneService(nativeCallId: UUID)

    fun stopMicrophoneService(nativeCallId: UUID) = Unit

    fun requestRoute(nativeCallId: UUID, route: String): Boolean = false

    fun project(nativeCallId: UUID, state: String): Boolean = false
}

internal interface MknoonCallEventSink {
    fun emit(event: PendingNativeCallEvent)
}

internal enum class MknoonCallLifecycleDiagnostic(
    val transition: String,
    val outcome: String,
) {
    SET_ACTIVE_ACCEPTED_AFTER_DART("set_active", "accepted_after_dart"),
    SET_ACTIVE_BUFFERED_AFTER_ANSWER("set_active", "buffered_after_answer"),
    SET_ACTIVE_REJECTED_UNSOLICITED("set_active", "rejected_unsolicited"),
    DART_ACTIVATE_SKIP_ALREADY_ACTIVE("dart_activate", "skip_already_active"),
    DART_ACTIVATE_SET_ACTIVE_FAILED("dart_activate", "set_active_failed"),
    DART_ACTIVATE_SERVICE_FAILED("dart_activate", "service_failed"),
    DART_ACTIVATE_COMPLETED("dart_activate", "completed"),
}

internal fun interface MknoonCallLifecycleDiagnosticSink {
    fun emit(diagnostic: MknoonCallLifecycleDiagnostic)
}

internal enum class MknoonCallPresentationResult {
    PRESENTED,
    DUPLICATE,
    BUSY,
    DISABLED,
    STALE,
    PERSISTENCE_FAILED,
    PLATFORM_FAILED,
}

internal data class MknoonCallAttachment(
    val descriptor: PendingNativeCallDescriptor,
    val deliverableEvents: List<PendingNativeCallEvent>,
)

internal data class MknoonCallAudioState(
    val active: Boolean,
    val muted: Boolean,
    val route: String,
    val availableRoutes: List<String>,
)

/**
 * Serializes native call ownership around the one durable pending descriptor.
 *
 * No notification, foreground service, Telecom control, or Dart event is
 * allowed to precede the durable transition that authorizes it.
 */
internal class MknoonCallLifecycleController(
    private val store: MknoonCallLifecycleStore,
    private val platform: MknoonCallPlatform,
    private val eventSink: MknoonCallEventSink,
    private val capabilityEnabled: () -> Boolean,
    private val recordAudioPermissionGranted: () -> Boolean,
    private val nowMs: () -> Long,
    private val onPresented: (UUID, Long) -> Unit = { _, _ -> },
    private val onSettled: (UUID) -> Unit = {},
    private val onTerminated: (UUID, Long) -> Boolean = { _, _ -> true },
    private val onCleanupPending: (UUID) -> Unit = {},
    /**
     * Plan 404: a natively declined call with no adopted Dart lifecycle. Asked
     * before native cleanup; a `true` answer means a reply run will release
     * the call foreground service, so cleanup must not stop it (device
     * 2026-09-05 18:46Z: the STOP queued here tore the service down before
     * the reply's admission command behind it was delivered).
     */
    private val onDeclineWithoutOwner: (PendingNativeCallDescriptor) -> Boolean = { false },
    private val diagnosticSink: MknoonCallLifecycleDiagnosticSink =
        MknoonCallLifecycleDiagnosticSink { _ -> },
    private val terminalAckTimeoutMs: Long = TERMINAL_ACK_TIMEOUT_MS,
    private val journalDiagnostic: (String, PendingNativeCallEventType) -> Unit = { _, _ -> },
    private val answerDiagnostic: (String, String, String) -> Unit = { _, _, _ -> },
) : MknoonCallActionHandler {
    private val lock = Any()
    private var attached = false
    private var adoptedCallId: UUID? = null
    private var adoptedState: AdoptedLifecycle? = null
    private var answerRequestedCallId: UUID? = null
    private var telecomActiveCallId: UUID? = null
    private var audioResourcesCallId: UUID? = null
    private var lastMuted: Boolean? = null
    private var lastRoute = "system_default"
    private var availableRoutes = emptyList<String>()
    private var lastAudioActive: Boolean? = null
    private var cleanupState: NativeCleanupState? = null
    private var ownedCallId: UUID? = null
    private var ownedExpiresAtMs: Long? = null
    private var audioTransitionGeneration = 0L
    private var audioTransition: AudioTransition? = null
    private val terminalTombstones = linkedMapOf<UUID, Long>()
    private var terminalAckWaiter: TerminalAckWaiter? = null

    fun present(payload: CallWakePayload): MknoonCallPresentationResult = synchronized(lock) {
        if (!safeBoolean(capabilityEnabled)) return@synchronized MknoonCallPresentationResult.DISABLED
        if (adoptedState != null || cleanupState != null) {
            return@synchronized MknoonCallPresentationResult.BUSY
        }
        val observedNow = safeNow() ?: return@synchronized MknoonCallPresentationResult.STALE
        pruneTerminalTombstones(observedNow)
        if (terminalTombstones[payload.nativeCallId]?.let { it > observedNow } == true) {
            return@synchronized MknoonCallPresentationResult.DUPLICATE
        }
        if (payload.expiresAtMs <= observedNow) {
            return@synchronized MknoonCallPresentationResult.STALE
        }

        val created = try {
            store.create(payload)
        } catch (_: Exception) {
            PendingNativeCallCreateResult.PersistenceFailure
        }
        when (created) {
            is PendingNativeCallCreateResult.Duplicate ->
                return@synchronized MknoonCallPresentationResult.DUPLICATE
            is PendingNativeCallCreateResult.Busy ->
                return@synchronized MknoonCallPresentationResult.BUSY
            PendingNativeCallCreateResult.PersistenceFailure ->
                return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
            is PendingNativeCallCreateResult.Created -> Unit
        }
        ownedCallId = payload.nativeCallId
        ownedExpiresAtMs = payload.expiresAtMs

        if (!registerWithPlatform(payload.nativeCallId, PendingNativeCallDirection.INCOMING)) {
            terminateInternal(
                payload.nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
                endPlatform = true,
            )
            return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
        }

        val presented = append(payload.nativeCallId, PendingNativeCallEventType.PRESENTED)
            ?: run {
                terminateInternal(
                    payload.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
            }
        resetVolatileState()
        runCatching { onPresented(payload.nativeCallId, payload.expiresAtMs) }
            .onFailure {
                terminateInternal(
                    payload.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
            }
        runCatching { platform.showIncoming(payload.nativeCallId) }
            .onFailure {
                terminateInternal(
                    payload.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
            }
        runCatching { platform.startForeground(payload.nativeCallId) }
            .onFailure {
                terminateInternal(
                    payload.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
            }
        emitIfAttached(presented)
        MknoonCallPresentationResult.PRESENTED
    }

    /**
     * Durably owns and registers one authenticated outgoing call before Dart
     * may request media activation. Outgoing registration does not present an
     * incoming-call alert or start the microphone foreground service.
     */
    fun registerOutgoing(payload: CallWakePayload): MknoonCallPresentationResult =
        synchronized(lock) {
            if (!safeBoolean(capabilityEnabled)) {
                return@synchronized MknoonCallPresentationResult.DISABLED
            }
            if (adoptedState != null || cleanupState != null) {
                return@synchronized MknoonCallPresentationResult.BUSY
            }
            val observedNow = safeNow() ?: return@synchronized MknoonCallPresentationResult.STALE
            pruneTerminalTombstones(observedNow)
            if (terminalTombstones[payload.nativeCallId]?.let { it > observedNow } == true) {
                return@synchronized MknoonCallPresentationResult.DUPLICATE
            }
            if (payload.expiresAtMs <= observedNow) {
                return@synchronized MknoonCallPresentationResult.STALE
            }

            val created = try {
                store.createOutgoing(payload)
            } catch (_: Exception) {
                PendingNativeCallCreateResult.PersistenceFailure
            }
            when (created) {
                is PendingNativeCallCreateResult.Duplicate ->
                    return@synchronized MknoonCallPresentationResult.DUPLICATE
                is PendingNativeCallCreateResult.Busy ->
                    return@synchronized MknoonCallPresentationResult.BUSY
                PendingNativeCallCreateResult.PersistenceFailure ->
                    return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
                is PendingNativeCallCreateResult.Created -> Unit
            }
            ownedCallId = payload.nativeCallId
            ownedExpiresAtMs = payload.expiresAtMs

            if (!registerWithPlatform(payload.nativeCallId, PendingNativeCallDirection.OUTGOING)) {
                terminateInternal(
                    payload.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
            }

            val presented = append(payload.nativeCallId, PendingNativeCallEventType.PRESENTED)
                ?: run {
                    terminateInternal(
                        payload.nativeCallId,
                        PendingNativeCallEventType.NATIVE_FAILURE,
                        endPlatform = true,
                    )
                    return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
                }
            resetVolatileState()
            runCatching { onPresented(payload.nativeCallId, payload.expiresAtMs) }
                .onFailure {
                    terminateInternal(
                        payload.nativeCallId,
                        PendingNativeCallEventType.NATIVE_FAILURE,
                        endPlatform = true,
                    )
                    return@synchronized MknoonCallPresentationResult.PLATFORM_FAILED
                }
            emitIfAttached(presented)
            MknoonCallPresentationResult.PRESENTED
        }

    /**
     * Re-registers one already-presented durable call after process recreation.
     * The original PRESENTED event and notification identity are retained; no
     * second presentation event or alert is produced.
     */
    fun reconcilePresented(): Boolean = synchronized(lock) {
        if (!safeBoolean(capabilityEnabled)) return@synchronized false
        if (adoptedState != null || cleanupState != null) return@synchronized false
        val descriptor = snapshotInternal() ?: return@synchronized false
        if (
            descriptor.terminalEvent != null ||
            descriptor.events.none { it.type == PendingNativeCallEventType.PRESENTED }
        ) {
            return@synchronized false
        }
        val observedNow = safeNow() ?: return@synchronized false
        if (descriptor.expiresAtMs <= observedNow) {
            terminateInternal(
                descriptor.nativeCallId,
                PendingNativeCallEventType.EXPIRED,
                endPlatform = false,
            )
            return@synchronized false
        }

        ownedCallId = descriptor.nativeCallId
        ownedExpiresAtMs = descriptor.expiresAtMs
        if (!registerWithPlatform(descriptor.nativeCallId, descriptor.direction)) {
            terminateInternal(
                descriptor.nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
                endPlatform = true,
            )
            return@synchronized false
        }

        resetVolatileState(descriptor)
        val scheduled = runCatching {
            onPresented(descriptor.nativeCallId, descriptor.expiresAtMs)
        }.isSuccess
        val presentationRestored = scheduled &&
            (
                descriptor.direction == PendingNativeCallDirection.OUTGOING ||
                    runCatching { platform.startForeground(descriptor.nativeCallId) }.isSuccess
            )
        if (!presentationRestored) {
            terminateInternal(
                descriptor.nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
                endPlatform = true,
            )
            return@synchronized false
        }
        true
    }

    /** Restores durable adopted custody only long enough to record provider loss. */
    fun reconcileAdoptedJournal(): Boolean = synchronized(lock) {
        if (cleanupState != null || adoptedState != null) return@synchronized false
        val descriptor = snapshotInternal()?.takeIf {
            it.handoffAcknowledgement == PendingNativeCallAcknowledgement.ADOPTED &&
                it.terminalEvent == null
        } ?: return@synchronized false
        adoptedCallId = descriptor.nativeCallId
        adoptedState = AdoptedLifecycle.from(descriptor)
        ownedCallId = descriptor.nativeCallId
        ownedExpiresAtMs = descriptor.expiresAtMs
        terminateInternal(
            descriptor.nativeCallId,
            PendingNativeCallEventType.PROVIDER_REMOVED,
            endPlatform = false,
            audioFocusAlreadyReleased = true,
        )
    }

    /** Blocks terminal attachment/deletion until startup repaired its replay fence. */
    fun reconcileTerminalFence(persisted: Boolean): Boolean = synchronized(lock) {
        val descriptor = snapshotInternal()?.takeIf { it.terminalEvent != null }
            ?: return@synchronized false
        if (persisted) {
            if (cleanupState?.startupFenceOnly == true) {
                cleanupState = null
            }
            return@synchronized cleanupState == null
        }
        cleanupState = NativeCleanupState(
            nativeCallId = descriptor.nativeCallId,
            expiresAtMs = descriptor.expiresAtMs,
            terminalType = descriptor.terminalEvent?.type
                ?: PendingNativeCallEventType.NATIVE_FAILURE,
            terminalEvent = descriptor.terminalEvent,
            terminalPersisted = true,
            tombstoneRecorded = true,
            tombstonePersisted = false,
            settlementNotified = true,
            endComplete = true,
            notificationComplete = true,
            foregroundComplete = true,
            audioFocusComplete = true,
            endpointsComplete = true,
            startupFenceOnly = true,
        )
        false
    }

    override fun answer(nativeCallId: UUID): Boolean =
        answerInternal(
            nativeCallId,
            signalPlatform = true,
            duplicateIsSuccess = false,
        )

    fun answerFromTelecom(nativeCallId: UUID): Boolean =
        answerInternal(
            nativeCallId,
            signalPlatform = false,
            duplicateIsSuccess = true,
        )

    private fun answerInternal(
        nativeCallId: UUID,
        signalPlatform: Boolean,
        duplicateIsSuccess: Boolean,
    ): Boolean {
        var newlyPersisted = false
        val accepted = synchronized(lock) {
            if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) {
                runCatching { answerDiagnostic(nativeCallId.toString(), "rejected", "native_answer_refused") }
                return@synchronized false
            }
            if (answerRequestedCallId == nativeCallId) {
                runCatching { answerDiagnostic(nativeCallId.toString(), "duplicate", "duplicate") }
                return@synchronized duplicateIsSuccess
            }
            val event = append(nativeCallId, PendingNativeCallEventType.ANSWER_REQUESTED)
                ?: run {
                    runCatching { answerDiagnostic(nativeCallId.toString(), "failed", "native_persistence_failed") }
                    return@synchronized false
                }
            answerRequestedCallId = nativeCallId
            emitIfAttached(event)
            newlyPersisted = true
            true
        }
        if (!accepted) return false
        if (newlyPersisted) {
            runCatching { platform.stopIncomingRinger(nativeCallId) }
        }
        if (signalPlatform) {
            try {
                platform.answer(nativeCallId)
                synchronized(lock) {
                    if (cleanupState == null && hasActiveLifecycle(nativeCallId)) {
                        telecomActiveCallId = nativeCallId
                    }
                }
            } catch (_: Exception) {
                runCatching { answerDiagnostic(nativeCallId.toString(), "failed", "native_lifecycle_failed") }
                synchronized(lock) {
                    terminateInternal(
                        nativeCallId,
                        PendingNativeCallEventType.NATIVE_FAILURE,
                        endPlatform = true,
                    )
                }
                return false
            }
        }
        runCatching { answerDiagnostic(nativeCallId.toString(), "ok", "none") }
        return true
    }

    override fun terminate(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): Boolean = synchronized(lock) {
        if (!type.isTerminalLifecycleEvent()) return@synchronized false
        if (
            type == PendingNativeCallEventType.EXPIRED &&
            adoptedState?.let {
                it.nativeCallId == nativeCallId && it.durablyAdopted
            } == true
        ) {
            return@synchronized false
        }
        terminateInternal(nativeCallId, type, endPlatform = true)
    }

    fun endFromDart(nativeCallId: UUID): Boolean = synchronized(lock) {
        terminateInternal(
            nativeCallId,
            PendingNativeCallEventType.END_REQUESTED,
            endPlatform = true,
        )
    }

    fun endFromTelecom(nativeCallId: UUID): Boolean = synchronized(lock) {
        terminateInternal(
            nativeCallId,
            PendingNativeCallEventType.PROVIDER_REMOVED,
            endPlatform = false,
            audioFocusAlreadyReleased = true,
        )
    }

    fun disconnectFromTelecom(nativeCallId: UUID): Boolean =
        terminalizeFromTelecom(nativeCallId)

    fun markAdopted(nativeCallId: UUID): Boolean = synchronized(lock) {
        if (cleanupState != null) return@synchronized false
        adoptedState?.takeIf {
            it.nativeCallId == nativeCallId && !it.terminal
        }?.let {
            adoptedCallId = nativeCallId
            return@synchronized true
        }
        val descriptor = snapshotInternal() ?: return@synchronized false
        if (descriptor.nativeCallId != nativeCallId || descriptor.terminalEvent != null) {
            return@synchronized false
        }
        if (adoptedCallId == nativeCallId) return@synchronized true
        adoptedCallId = nativeCallId
        adoptedState = AdoptedLifecycle.from(descriptor)
        true
    }

    fun activateAudio(nativeCallId: UUID): Boolean =
        activateAudioInternal(
            nativeCallId = nativeCallId,
            requestTelecomTransition = true,
            duplicateIsSuccess = false,
        )

    fun activateAudioFromTelecom(nativeCallId: UUID): Boolean = synchronized(lock) {
        val adopted = adoptedState?.takeIf {
            it.nativeCallId == nativeCallId && it.durablyAdopted && !it.terminal
        }
        val authorized = cleanupState == null &&
            adopted != null &&
            safeBoolean(recordAudioPermissionGranted)
        val alreadyRequested = authorized &&
            audioResourcesCallId == nativeCallId &&
            lastAudioActive == true
        if (alreadyRequested) {
            telecomActiveCallId = nativeCallId
            emitDiagnostic(MknoonCallLifecycleDiagnostic.SET_ACTIVE_ACCEPTED_AFTER_DART)
            return@synchronized true
        }
        val answerAssociated = answerRequestedCallId == nativeCallId ||
            adopted?.answerRequested == true
        val canBuffer = authorized &&
            answerAssociated &&
            audioResourcesCallId == null &&
            audioTransition == null &&
            hasActiveLifecycle(nativeCallId)
        if (canBuffer) {
            telecomActiveCallId = nativeCallId
            emitDiagnostic(MknoonCallLifecycleDiagnostic.SET_ACTIVE_BUFFERED_AFTER_ANSWER)
            return@synchronized true
        }

        emitDiagnostic(MknoonCallLifecycleDiagnostic.SET_ACTIVE_REJECTED_UNSOLICITED)
        if (hasActiveLifecycle(nativeCallId)) {
            terminateInternal(
                nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
                endPlatform = false,
                audioFocusAlreadyReleased = true,
            )
        }
        false
    }

    private fun activateAudioInternal(
        nativeCallId: UUID,
        requestTelecomTransition: Boolean,
        duplicateIsSuccess: Boolean,
    ): Boolean {
        val transition = synchronized(lock) {
            if (cleanupState != null) return false
            if (audioResourcesCallId == nativeCallId) {
                return duplicateIsSuccess
            }
            if (audioTransition != null) return false
            val adopted = adoptedState?.takeIf {
                it.nativeCallId == nativeCallId && it.durablyAdopted && !it.terminal
            }
            val answerAssociated = answerRequestedCallId == nativeCallId ||
                adopted?.answerRequested == true
            if (
                !hasActiveLifecycle(nativeCallId) ||
                adopted == null ||
                !safeBoolean(recordAudioPermissionGranted) ||
                (
                    adopted.direction == PendingNativeCallDirection.INCOMING &&
                        !answerAssociated
                )
            ) {
                return false
            }
            val appended = append(nativeCallId, PendingNativeCallEventType.AUDIO_ACTIVATED)
                ?: return false
            audioResourcesCallId = nativeCallId
            lastAudioActive = true
            val reserved = AudioTransition(
                generation = ++audioTransitionGeneration,
                nativeCallId = nativeCallId,
                activating = true,
                telecomAlreadyActive = telecomActiveCallId == nativeCallId,
            )
            audioTransition = reserved
            emitIfAttached(appended)
            reserved
        }

        val needsTelecomTransition = requestTelecomTransition && !transition.telecomAlreadyActive
        if (requestTelecomTransition && transition.telecomAlreadyActive) {
            emitDiagnostic(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SKIP_ALREADY_ACTIVE)
        }
        if (needsTelecomTransition) {
            try {
                platform.requestAudioFocus(nativeCallId)
            } catch (_: Exception) {
                synchronized(lock) {
                    clearAudioTransition(transition)
                    emitDiagnostic(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SET_ACTIVE_FAILED)
                    terminateInternal(
                        nativeCallId,
                        PendingNativeCallEventType.NATIVE_FAILURE,
                        endPlatform = true,
                    )
                }
                return false
            }
        }

        var compensateFocus = false
        val applied = synchronized(lock) {
            if (
                audioTransition != transition ||
                audioResourcesCallId != nativeCallId ||
                !hasActiveLifecycle(nativeCallId)
            ) {
                compensateFocus = needsTelecomTransition
                clearAudioTransition(transition)
                return@synchronized false
            }
            try {
                platform.startEndpointUpdates(nativeCallId)
                platform.startMicrophoneService(nativeCallId)
            } catch (_: Exception) {
                clearAudioTransition(transition)
                emitDiagnostic(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SERVICE_FAILED)
                terminateInternal(
                    nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
                return@synchronized false
            }
            clearAudioTransition(transition)
            emitDiagnostic(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_COMPLETED)
            true
        }
        if (compensateFocus) runCatching { platform.abandonAudioFocus(nativeCallId) }
        return applied
    }

    fun deactivateAudio(nativeCallId: UUID): Boolean =
        deactivateAudioInternal(
            nativeCallId = nativeCallId,
            requestTelecomTransition = true,
            duplicateIsSuccess = false,
        )

    fun deactivateAudioFromTelecom(nativeCallId: UUID): Boolean =
        terminalizeFromTelecom(nativeCallId)

    private fun terminalizeFromTelecom(nativeCallId: UUID): Boolean {
        val waiter = synchronized(lock) {
            terminalAckWaiter?.takeIf { it.nativeCallId == nativeCallId }
                ?: run {
                    if (cleanupState != null && cleanupState?.nativeCallId != nativeCallId) {
                        return@synchronized null
                    }
                    pruneTerminalTombstones(safeNow() ?: Long.MAX_VALUE)
                    if (
                        cleanupState == null &&
                        snapshotInternal() == null &&
                        terminalTombstones.containsKey(nativeCallId)
                    ) {
                        return true
                    }
                    val terminalized = terminateInternal(
                        nativeCallId,
                        PendingNativeCallEventType.END_REQUESTED,
                        endPlatform = false,
                        audioFocusAlreadyReleased = true,
                    )
                    if (!terminalized && !hasTerminalLifecycleLocked(nativeCallId)) {
                        return@synchronized null
                    }
                    terminalAckWaiter?.takeIf { it.nativeCallId == nativeCallId }
                }
        } ?: return false
        return waiter.await(terminalAckTimeoutMs)
    }

    private fun deactivateAudioInternal(
        nativeCallId: UUID,
        requestTelecomTransition: Boolean,
        duplicateIsSuccess: Boolean,
    ): Boolean {
        val transition = synchronized(lock) {
            if (cleanupState != null) return false
            if (audioResourcesCallId != nativeCallId) {
                return duplicateIsSuccess &&
                    hasActiveLifecycle(nativeCallId) &&
                    lastAudioActive != true
            }
            if (audioTransition != null) return false
            val event = append(nativeCallId, PendingNativeCallEventType.AUDIO_DEACTIVATED)
                ?: return false
            audioResourcesCallId = null
            lastAudioActive = false
            val reserved = AudioTransition(
                generation = ++audioTransitionGeneration,
                nativeCallId = nativeCallId,
                activating = false,
                telecomAlreadyActive = false,
            )
            audioTransition = reserved
            telecomActiveCallId = null
            emitIfAttached(event)
            reserved
        }

        try {
            platform.stopMicrophoneService(nativeCallId)
            if (requestTelecomTransition) platform.abandonAudioFocus(nativeCallId)
            platform.stopEndpointUpdates(nativeCallId)
        } catch (_: Exception) {
            synchronized(lock) {
                clearAudioTransition(transition)
                terminateInternal(
                    nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
            }
            return false
        }
        synchronized(lock) { clearAudioTransition(transition) }
        return true
    }

    fun requestRoute(nativeCallId: UUID, route: String): Boolean = synchronized(lock) {
        if (
            cleanupState != null ||
            !hasActiveLifecycle(nativeCallId) ||
            route !in ROUTES
        ) {
            return@synchronized false
        }
        runCatching { platform.requestRoute(nativeCallId, route) }.getOrDefault(false)
    }

    fun project(nativeCallId: UUID, state: String): Boolean = synchronized(lock) {
        if (
            cleanupState != null ||
            !hasActiveLifecycle(nativeCallId) ||
            state !in PROJECTED_STATES
        ) {
            return@synchronized false
        }
        runCatching { platform.project(nativeCallId, state) }.getOrDefault(false)
    }

    fun onMuteChanged(nativeCallId: UUID, muted: Boolean): Boolean = synchronized(lock) {
        if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) return@synchronized false
        if (lastMuted == muted) return@synchronized false
        val event = append(nativeCallId, PendingNativeCallEventType.MUTE_CHANGED)
            ?: return@synchronized false
        lastMuted = muted
        emitIfAttached(event)
        true
    }

    fun onRouteChanged(nativeCallId: UUID, route: String): Boolean = synchronized(lock) {
        if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) return@synchronized false
        if (route !in ROUTES || lastRoute == route) return@synchronized false
        val event = append(nativeCallId, PendingNativeCallEventType.ROUTE_CHANGED)
            ?: return@synchronized false
        lastRoute = route
        emitIfAttached(event)
        true
    }

    fun onAudioActivationChanged(nativeCallId: UUID, active: Boolean): Boolean =
        synchronized(lock) {
            if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) {
                return@synchronized false
            }
            if (lastAudioActive == active) return@synchronized false
            val type = if (active) {
                PendingNativeCallEventType.AUDIO_ACTIVATED
            } else {
                PendingNativeCallEventType.AUDIO_DEACTIVATED
            }
            val event = append(nativeCallId, type) ?: return@synchronized false
            lastAudioActive = active
            if (!active) telecomActiveCallId = null
            emitIfAttached(event)
            true
        }

    fun onAvailableRoutesChanged(nativeCallId: UUID, routes: List<String>): Boolean =
        synchronized(lock) {
            if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) {
                return@synchronized false
            }
            val normalized = routes.filter { it in ROUTES }.distinct().take(MAX_AVAILABLE_ROUTES)
            if (normalized == availableRoutes) return@synchronized false
            val event = append(nativeCallId, PendingNativeCallEventType.ROUTE_CHANGED)
                ?: return@synchronized false
            availableRoutes = normalized
            // Dart refreshes both the selected route and its inventory from
            // this event, including a headset change that leaves audio on speaker.
            emitIfAttached(event)
            true
        }

    fun attach(): MknoonCallAttachment? = synchronized(lock) {
        attached = true
        if (
            cleanupState?.terminalPersisted == false ||
            cleanupState?.startupFenceOnly == true
        ) {
            return@synchronized null
        }
        val descriptor = snapshotInternal()
            ?: adoptedState?.toDescriptor()
            ?: return@synchronized null
        val deliverable = descriptor.terminalEvent?.let(::listOf)
            ?: descriptor.events.filter { it.type != PendingNativeCallEventType.PRESENTED }
        deliverable.forEach(::emitSafely)
        MknoonCallAttachment(descriptor, deliverable)
    }

    fun detach(): Boolean = synchronized(lock) {
        attached = false
        adoptedState?.takeIf { !it.terminal }?.let { adopted ->
            terminateInternal(
                adopted.nativeCallId,
                PendingNativeCallEventType.PROVIDER_REMOVED,
                endPlatform = true,
            )
        } ?: true
    }

    fun failClosed(): Boolean = synchronized(lock) {
        attached = false
        val nativeCallId = snapshotInternal()?.takeIf { it.terminalEvent == null }?.nativeCallId
            ?: adoptedState?.takeIf { !it.terminal }?.nativeCallId
            ?: cleanupState?.nativeCallId
            ?: return@synchronized true
        terminateInternal(
            nativeCallId,
            PendingNativeCallEventType.NATIVE_FAILURE,
            endPlatform = true,
        )
        cleanupState == null && activeNativeCallId() == null
    }

    fun snapshot(): PendingNativeCallDescriptor? = synchronized(lock) {
        snapshotInternal()
    }

    fun activeNativeCallId(): UUID? = synchronized(lock) {
        snapshotInternal()?.takeIf { it.terminalEvent == null }?.nativeCallId
            ?: adoptedState?.takeIf { !it.terminal }?.nativeCallId
            ?: cleanupState?.nativeCallId
            ?: ownedCallId
    }

    fun hasTerminalLifecycle(nativeCallId: UUID): Boolean = synchronized(lock) {
        hasTerminalLifecycleLocked(nativeCallId)
    }

    fun isCleanupPending(nativeCallId: UUID): Boolean = synchronized(lock) {
        cleanupState?.nativeCallId == nativeCallId
    }

    fun retryCleanup(nativeCallId: UUID): Boolean = synchronized(lock) {
        val cleanup = cleanupState?.takeIf { it.nativeCallId == nativeCallId }
            ?: return@synchronized true
        if (!cleanup.terminalPersisted) {
            val event = append(nativeCallId, cleanup.terminalType)
            if (event != null) {
                terminalAckWaiter?.complete(success = false)
                terminalAckWaiter = TerminalAckWaiter(nativeCallId, event.sequence)
                cleanup.terminalPersisted = true
                cleanup.terminalEvent = event
                emitIfAttached(event)
            }
        }
        performCleanup(cleanup)
        if (cleanup.complete && cleanup.terminalPersisted) {
            val terminalEvent = cleanup.terminalEvent ?: return@synchronized false
            emitIfAttached(terminalEvent)
            cleanupState = null
            true
        } else {
            false
        }
    }

    fun resolveCallHandle(callHandle: String): UUID? = synchronized(lock) {
        snapshotInternal()?.takeIf {
            it.callHandle == callHandle
        }?.nativeCallId ?: adoptedState?.takeIf {
            it.callHandle == callHandle
        }?.nativeCallId ?: runCatching {
            store.resolveAcknowledgementReceipt(callHandle)
        }.getOrNull()
    }

    fun channelDescriptor(event: PendingNativeCallEvent): PendingNativeCallDescriptor? =
        synchronized(lock) {
            snapshotInternal()?.takeIf { it.nativeCallId == event.nativeCallId }
                ?: adoptedState?.takeIf { it.nativeCallId == event.nativeCallId }
                    ?.toDescriptor(listOf(event))
        }

    fun acknowledge(
        nativeCallId: UUID,
        highestConsumedSequence: Long,
        acknowledgement: PendingNativeCallAcknowledgement,
    ): Boolean = synchronized(lock) {
        if (cleanupState?.nativeCallId == nativeCallId) {
            return@synchronized false
        }
        val descriptorBefore = snapshotInternal()
        val durablyAcknowledged = try {
            store.acknowledge(nativeCallId, highestConsumedSequence, acknowledgement)
        } catch (_: Exception) {
            false
        }
        if (durablyAcknowledged) {
            when (acknowledgement) {
                PendingNativeCallAcknowledgement.ADOPTED -> {
                    val adopted = adoptedState?.takeIf { it.nativeCallId == nativeCallId }
                        ?: descriptorBefore?.takeIf { it.nativeCallId == nativeCallId }
                            ?.let(AdoptedLifecycle::from)
                    if (adopted != null) {
                        adopted.durablyAdopted = true
                        adopted.recordAcknowledgement(highestConsumedSequence)
                        adoptedCallId = nativeCallId
                        adoptedState = adopted
                    }
                    notifySettled(nativeCallId)
                }
                PendingNativeCallAcknowledgement.NONE -> {
                    adoptedState?.takeIf { it.nativeCallId == nativeCallId }?.let { adopted ->
                        adopted.recordAcknowledgement(highestConsumedSequence)
                    }
                }
                PendingNativeCallAcknowledgement.TERMINAL -> {
                    completeTerminalAck(nativeCallId, highestConsumedSequence)
                    if (adoptedState?.nativeCallId == nativeCallId) {
                        adoptedCallId = null
                        adoptedState = null
                    }
                }
            }
            return@synchronized true
        }

        false
    }

    fun audioState(): MknoonCallAudioState = synchronized(lock) {
        audioStateLocked()
    }

    fun audioState(nativeCallId: UUID): MknoonCallAudioState? = synchronized(lock) {
        if (!hasActiveLifecycle(nativeCallId)) return@synchronized null
        audioStateLocked()
    }

    private fun audioStateLocked(): MknoonCallAudioState = MknoonCallAudioState(
        active = lastAudioActive == true,
        muted = lastMuted == true,
        route = lastRoute,
        availableRoutes = availableRoutes,
    )

    private fun append(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): PendingNativeCallEvent? {
        val stored = try {
            (store.append(nativeCallId, type) as? PendingNativeCallAppendResult.Appended)?.event
        } catch (_: Exception) {
            null
        }
        if (stored != null) {
            runCatching { journalDiagnostic(nativeCallId.toString(), type) }
            adoptedState?.takeIf { it.nativeCallId == nativeCallId }?.record(stored)
            return stored
        }
        return null
    }

    private fun terminateInternal(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
        endPlatform: Boolean,
        audioFocusAlreadyReleased: Boolean = false,
    ): Boolean {
        val existingPending = cleanupState?.takeIf { it.nativeCallId == nativeCallId }
        val descriptorBefore = snapshotInternal()?.takeIf { it.nativeCallId == nativeCallId }
        val adoptedBefore = adoptedState?.takeIf { it.nativeCallId == nativeCallId }
        val ownedInProcess = ownedCallId == nativeCallId
        if (
            existingPending == null &&
            descriptorBefore == null &&
            adoptedBefore == null &&
            !ownedInProcess
        ) {
            return false
        }
        val alreadyTerminal = descriptorBefore?.terminalEvent != null || adoptedBefore?.terminal == true
        if (alreadyTerminal && existingPending == null) return false

        val event = if (alreadyTerminal) null else append(nativeCallId, type)
        val firstDurableTerminal = event != null
        if (event != null) {
            terminalAckWaiter?.complete(success = false)
            terminalAckWaiter = TerminalAckWaiter(nativeCallId, event.sequence)
        }
        val cleanup = existingPending ?: NativeCleanupState(
            nativeCallId = nativeCallId,
            expiresAtMs = descriptorBefore?.expiresAtMs
                ?: adoptedBefore?.expiresAtMs
                ?: ownedExpiresAtMs
                ?: 0L,
            terminalType = type,
            terminalEvent = event
                ?: descriptorBefore?.terminalEvent
                ?: adoptedBefore?.pendingEvents?.firstOrNull {
                    it.type.isTerminalForAdoptedLifecycle()
                },
            endComplete = !endPlatform,
            audioFocusComplete = audioFocusAlreadyReleased,
        )
        if (!cleanup.tombstoneRecorded) {
            recordTerminalTombstone(nativeCallId, cleanup.expiresAtMs)
            cleanup.tombstoneRecorded = true
        }
        if (!cleanup.tombstonePersisted) {
            cleanup.tombstonePersisted = safeBoolean {
                onTerminated(nativeCallId, cleanup.expiresAtMs)
            }
        }
        if (!cleanup.settlementNotified) {
            notifySettled(nativeCallId)
            cleanup.settlementNotified = true
        }
        cleanup.terminalPersisted = cleanup.terminalPersisted || firstDurableTerminal
        cleanup.endComplete = cleanup.endComplete || !endPlatform
        cleanup.audioFocusComplete = cleanup.audioFocusComplete || audioFocusAlreadyReleased
        if (!cleanup.ringtoneStopAttempted) {
            cleanup.ringtoneStopAttempted = true
            runCatching { platform.stopIncomingRinger(nativeCallId) }
        }
        if (
            type == PendingNativeCallEventType.DECLINE_REQUESTED &&
            firstDurableTerminal &&
            adoptedBefore == null &&
            descriptorBefore != null &&
            !cleanup.foregroundComplete &&
            runCatching { onDeclineWithoutOwner(descriptorBefore) }.getOrDefault(false)
        ) {
            // Plan 404: no Dart lifecycle owns this call, so nobody would send
            // the caller its reject; the headless decline reply does, and it
            // keeps the foreground service until its run is finished.
            cleanup.foregroundComplete = true
        }
        performCleanup(cleanup)
        if (event != null) emitIfAttached(event)

        cleanupState = if (cleanup.complete && cleanup.terminalPersisted) null else cleanup
        if (cleanupState != null) {
            runCatching { onCleanupPending(nativeCallId) }
        }
        val adoptedLifecycle = adoptedState?.nativeCallId == nativeCallId
        audioTransitionGeneration += 1L
        audioTransition = null
        telecomActiveCallId = null
        audioResourcesCallId = null
        if (ownedCallId == nativeCallId) {
            ownedCallId = null
            ownedExpiresAtMs = null
        }
        if (!adoptedLifecycle) {
            adoptedCallId = null
            adoptedState = null
        }
        answerRequestedCallId = null
        lastMuted = null
        lastRoute = "system_default"
        availableRoutes = emptyList()
        lastAudioActive = false
        return firstDurableTerminal && cleanup.complete
    }

    private fun performCleanup(cleanup: NativeCleanupState) {
        val nativeCallId = cleanup.nativeCallId
        if (!cleanup.endpointsComplete) {
            cleanup.endpointsComplete = runCatching {
                platform.stopEndpointUpdates(nativeCallId)
            }.isSuccess
        }
        if (!cleanup.audioFocusComplete) {
            cleanup.audioFocusComplete = runCatching {
                platform.abandonAudioFocus(nativeCallId)
            }.isSuccess
        }
        if (!cleanup.endComplete) {
            cleanup.endComplete = runCatching { platform.end(nativeCallId) }.isSuccess
        }
        if (!cleanup.notificationComplete) {
            cleanup.notificationComplete = runCatching {
                platform.cancelNotification(nativeCallId)
            }.isSuccess
        }
        if (!cleanup.foregroundComplete) {
            cleanup.foregroundComplete = runCatching {
                platform.stopForeground(nativeCallId)
            }.isSuccess
        }
    }

    private fun snapshotInternal(): PendingNativeCallDescriptor? = try {
        store.snapshot()
    } catch (_: Exception) {
        null
    }

    private fun hasActiveLifecycle(nativeCallId: UUID): Boolean {
        if (cleanupState != null) return false
        val descriptor = snapshotInternal()
        if (
            descriptor != null &&
            descriptor.nativeCallId == nativeCallId &&
            descriptor.terminalEvent == null
        ) {
            return true
        }
        return adoptedState?.let {
            it.nativeCallId == nativeCallId && !it.terminal
        } == true
    }

    private fun safeNow(): Long? = try {
        nowMs().takeIf { it >= 0L }
    } catch (_: Exception) {
        null
    }

    private fun safeBoolean(value: () -> Boolean): Boolean = try {
        value()
    } catch (_: Exception) {
        false
    }

    private fun registerWithPlatform(
        nativeCallId: UUID,
        direction: PendingNativeCallDirection,
    ): Boolean {
        var registered = false
        var failed = false
        val callback = object : MknoonCallRegistrationCallback {
            override fun onRegistered() {
                registered = true
            }

            override fun onFailure() {
                failed = true
            }

            override fun onRegistrationAbandoned() {
                failed = true
            }
        }
        try {
            when (direction) {
                PendingNativeCallDirection.INCOMING ->
                    platform.registerIncoming(nativeCallId, callback)
                PendingNativeCallDirection.OUTGOING ->
                    platform.registerOutgoing(nativeCallId, callback)
            }
        } catch (_: Exception) {
            failed = true
        }
        return registered && !failed
    }

    private fun clearAudioTransition(expected: AudioTransition) {
        if (audioTransition == expected) audioTransition = null
    }

    private fun hasTerminalLifecycleLocked(nativeCallId: UUID): Boolean {
        return snapshotInternal()?.let {
            it.nativeCallId == nativeCallId && it.terminalEvent != null
        } == true || adoptedState?.let {
            it.nativeCallId == nativeCallId && it.terminal
        } == true
    }

    private fun completeTerminalAck(nativeCallId: UUID, throughSequence: Long) {
        val waiter = terminalAckWaiter?.takeIf {
            it.nativeCallId == nativeCallId && throughSequence >= it.sequence
        } ?: return
        terminalAckWaiter = null
        waiter.complete(success = true)
    }

    private fun pruneTerminalTombstones(observedNowMs: Long) {
        terminalTombstones.entries.removeAll { it.value <= observedNowMs }
    }

    private fun recordTerminalTombstone(nativeCallId: UUID, expiresAtMs: Long) {
        terminalTombstones[nativeCallId] = expiresAtMs
        while (terminalTombstones.size > MAX_TERMINAL_TOMBSTONES) {
            val oldest = terminalTombstones.minByOrNull { it.value }?.key ?: break
            terminalTombstones.remove(oldest)
        }
    }

    private fun notifySettled(nativeCallId: UUID) {
        runCatching { onSettled(nativeCallId) }
    }

    private fun emitIfAttached(event: PendingNativeCallEvent) {
        if (attached) emitSafely(event)
    }

    private fun emitSafely(event: PendingNativeCallEvent) {
        runCatching { eventSink.emit(event) }
    }

    private fun emitDiagnostic(diagnostic: MknoonCallLifecycleDiagnostic) {
        runCatching { diagnosticSink.emit(diagnostic) }
    }

    private fun resetVolatileState(descriptor: PendingNativeCallDescriptor? = null) {
        adoptedCallId = null
        adoptedState = null
        answerRequestedCallId = descriptor?.takeIf { it.answerRequested }?.nativeCallId
        telecomActiveCallId = null
        audioResourcesCallId = null
        lastMuted = null
        lastRoute = "system_default"
        availableRoutes = emptyList()
        lastAudioActive = null
    }

    private fun PendingNativeCallEventType.isTerminalLifecycleEvent(): Boolean = when (this) {
        PendingNativeCallEventType.DECLINE_REQUESTED,
        PendingNativeCallEventType.END_REQUESTED,
        PendingNativeCallEventType.REMOTE_CANCELLED,
        PendingNativeCallEventType.EXPIRED,
        PendingNativeCallEventType.PROVIDER_REMOVED,
        PendingNativeCallEventType.NATIVE_FAILURE,
        -> true
        else -> false
    }

    private companion object {
        val ROUTES = CANONICAL_NATIVE_CALL_ROUTES
        val PROJECTED_STATES = setOf("ringing", "accepted", "active", "inactive")
        const val MAX_AVAILABLE_ROUTES = 6
        const val MAX_LOCAL_EVENTS = 32
        const val MAX_TERMINAL_TOMBSTONES = 32
        const val TERMINAL_ACK_TIMEOUT_MS = 3_000L
    }

    private data class NativeCleanupState(
        val nativeCallId: UUID,
        val expiresAtMs: Long,
        val terminalType: PendingNativeCallEventType,
        var terminalEvent: PendingNativeCallEvent? = null,
        var terminalPersisted: Boolean = false,
        var tombstoneRecorded: Boolean = false,
        var tombstonePersisted: Boolean = false,
        var settlementNotified: Boolean = false,
        var endComplete: Boolean = false,
        var notificationComplete: Boolean = false,
        var foregroundComplete: Boolean = false,
        var audioFocusComplete: Boolean = false,
        var endpointsComplete: Boolean = false,
        var ringtoneStopAttempted: Boolean = false,
        val startupFenceOnly: Boolean = false,
    ) {
        val complete: Boolean
            get() = tombstonePersisted &&
                endComplete &&
                notificationComplete &&
                foregroundComplete &&
                audioFocusComplete &&
                endpointsComplete
    }

    private data class AudioTransition(
        val generation: Long,
        val nativeCallId: UUID,
        val activating: Boolean,
        val telecomAlreadyActive: Boolean,
    )

    private class TerminalAckWaiter(
        val nativeCallId: UUID,
        val sequence: Long,
    ) {
        private val completed = CountDownLatch(1)
        private val succeeded = AtomicBoolean(false)

        fun complete(success: Boolean) {
            if (success) succeeded.set(true)
            completed.countDown()
        }

        fun await(timeoutMs: Long): Boolean {
            if (timeoutMs <= 0L) return succeeded.get()
            val completedInTime = try {
                completed.await(timeoutMs, TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                false
            }
            return completedInTime && succeeded.get()
        }
    }

    private class AdoptedLifecycle(
        val nativeCallId: UUID,
        val callHandle: String,
        val direction: PendingNativeCallDirection,
        val receivedAtMs: Long,
        val expiresAtMs: Long,
        var nextSequence: Long,
        var terminal: Boolean,
        var terminalSequence: Long?,
        var durablyAdopted: Boolean,
        var acknowledgedSequence: Long,
        var answerRequested: Boolean,
        val pendingEvents: MutableList<PendingNativeCallEvent>,
    ) {
        fun canRecord(type: PendingNativeCallEventType): Boolean =
            pendingEvents.size < MAX_LOCAL_EVENTS || type.isTerminalForAdoptedLifecycle()

        fun record(event: PendingNativeCallEvent) {
            nextSequence = event.sequence + 1L
            if (event.type == PendingNativeCallEventType.ANSWER_REQUESTED) {
                answerRequested = true
            }
            if (event.type.isTerminalForAdoptedLifecycle()) {
                if (pendingEvents.size >= MAX_LOCAL_EVENTS) pendingEvents.clear()
                terminal = true
                terminalSequence = event.sequence
            }
            pendingEvents += event
        }

        fun recordAcknowledgement(highestConsumedSequence: Long) {
            acknowledgedSequence = maxOf(acknowledgedSequence, highestConsumedSequence)
            pendingEvents.removeAll { it.sequence <= highestConsumedSequence }
        }

        fun toDescriptor(
            selectedEvents: List<PendingNativeCallEvent> = pendingEvents,
        ): PendingNativeCallDescriptor = PendingNativeCallDescriptor(
            nativeCallId = nativeCallId,
            callHandle = callHandle,
            wakeHandle = "",
            receivedAtMs = receivedAtMs,
            expiresAtMs = expiresAtMs,
            highestSequence = nextSequence - 1L,
            terminalEvent = selectedEvents.singleOrNull {
                it.type.isTerminalForAdoptedLifecycle()
            } ?: pendingEvents.singleOrNull {
                it.type.isTerminalForAdoptedLifecycle()
            },
            events = selectedEvents.toList(),
            handoffAcknowledgement = if (durablyAdopted) {
                PendingNativeCallAcknowledgement.ADOPTED
            } else {
                PendingNativeCallAcknowledgement.NONE
            },
            phase = if (durablyAdopted) {
                PendingNativeCallPhase.JOURNAL
            } else {
                PendingNativeCallPhase.PRE_START
            },
            answerRequested = answerRequested,
            direction = direction,
        )

        fun acknowledge(
            highestConsumedSequence: Long,
            acknowledgement: PendingNativeCallAcknowledgement,
        ): Boolean {
            if (highestConsumedSequence < 0L) return false
            val highestProducedSequence = nextSequence - 1L
            if (highestConsumedSequence > highestProducedSequence) return false
            if (highestConsumedSequence <= acknowledgedSequence) {
                return acknowledgement == PendingNativeCallAcknowledgement.NONE
            }
            when (acknowledgement) {
                PendingNativeCallAcknowledgement.ADOPTED -> {
                    // The one durable ADOPTED transition already completed;
                    // never report a second handoff as a new success.
                    return false
                }
                PendingNativeCallAcknowledgement.NONE -> {
                    if (terminalSequence?.let { highestConsumedSequence >= it } == true) {
                        return false
                    }
                }
                PendingNativeCallAcknowledgement.TERMINAL -> {
                    val terminalAt = terminalSequence ?: return false
                    if (highestConsumedSequence < terminalAt) return false
                }
            }
            recordAcknowledgement(highestConsumedSequence)
            return true
        }

        companion object {
            fun from(descriptor: PendingNativeCallDescriptor): AdoptedLifecycle =
                AdoptedLifecycle(
                    nativeCallId = descriptor.nativeCallId,
                    callHandle = descriptor.callHandle,
                    direction = descriptor.direction,
                    receivedAtMs = descriptor.receivedAtMs,
                    expiresAtMs = descriptor.expiresAtMs,
                    nextSequence = descriptor.highestSequence + 1L,
                    terminal = descriptor.terminalEvent != null,
                    terminalSequence = descriptor.terminalEvent?.sequence,
                    durablyAdopted = descriptor.handoffAcknowledgement ==
                        PendingNativeCallAcknowledgement.ADOPTED,
                    acknowledgedSequence = descriptor.events.firstOrNull()
                        ?.sequence
                        ?.minus(1L)
                        ?: descriptor.highestSequence,
                    answerRequested = descriptor.answerRequested,
                    pendingEvents = descriptor.events.toMutableList(),
                )
        }
    }
}

private fun PendingNativeCallEventType.isTerminalForAdoptedLifecycle(): Boolean = when (this) {
    PendingNativeCallEventType.DECLINE_REQUESTED,
    PendingNativeCallEventType.END_REQUESTED,
    PendingNativeCallEventType.REMOTE_CANCELLED,
    PendingNativeCallEventType.EXPIRED,
    PendingNativeCallEventType.PROVIDER_REMOVED,
    PendingNativeCallEventType.NATIVE_FAILURE,
    -> true
    else -> false
}
