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

    /** Strict observation must not reconcile state or prune acknowledgement receipts. */
    fun observeProtectedJournal(): PendingNativeCallDescriptor? =
        throw UnsupportedOperationException("protected journal observation unavailable")

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
        timeoutMs: Long = MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS,
    )

    fun registerOutgoing(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
        timeoutMs: Long = MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS,
    ) = registerIncoming(nativeCallId, callback, timeoutMs)

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

internal data class MknoonCallJournalObservation(
    val descriptor: PendingNativeCallDescriptor?,
    val liveOwnerPresent: Boolean,
    val cleanupPending: Boolean,
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
    /** True on Android's main thread; nothing in here may wait for Telecom there (B8). */
    private val isMainThread: () -> Boolean = { false },
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
    private var lockedMetadata: Pair<UUID, MknoonLockedCallMetadata>? = null
    private var cleanupState: NativeCleanupState? = null
    private var ownedCallId: UUID? = null
    private var ownedExpiresAtMs: Long? = null
    private var audioTransitionGeneration = 0L
    private var audioTransition: AudioTransition? = null
    private val terminalTombstones = linkedMapOf<UUID, Long>()
    private var terminalAckWaiter: TerminalAckWaiter? = null

    /**
     * B5 (beta 2026-09-25): core-telecom's addCall waits up to 5 s for Telecom,
     * longer on a loaded device. Registration therefore runs without [lock], so
     * main-thread readers never wait for it (some Telecom versions need main to
     * finish a registration). Telecom callbacks for the call wait for [settled],
     * so they still run after the presentation that registered it.
     */
    private class RegistrationInFlight(val nativeCallId: UUID) {
        val settled = CountDownLatch(1)

        /** A main-thread Answer that arrived while registering; applied once presented (B8). */
        @Volatile
        var deferredAnswer = false

        /** False once Telecom itself answered, so the deferred answer must not signal it again. */
        @Volatile
        var deferredAnswerSignalsPlatform = true
    }

    @Volatile
    private var registrationInFlight: RegistrationInFlight? = null

    fun present(payload: CallWakePayload, initialDisplay: MknoonIncomingCallDisplay? = null): MknoonCallPresentationResult {
        val inFlight = RegistrationInFlight(payload.nativeCallId)
        synchronized(lock) {
            admitRegistrationLocked(payload, PendingNativeCallDirection.INCOMING, inFlight)
        }?.let { return it }
        try {
            val registered =
                registerWithPlatform(payload.nativeCallId, PendingNativeCallDirection.INCOMING)
            val result = synchronized(lock) {
                settleRegistrationLocked(payload.nativeCallId, inFlight, registered)
                    ?.let { return@synchronized it }

                val presented = append(payload.nativeCallId, PendingNativeCallEventType.PRESENTED)
                    ?: run {
                        terminateInternal(
                            payload.nativeCallId,
                            PendingNativeCallEventType.NATIVE_FAILURE,
                            endPlatform = true,
                        )
                        return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
                    }
                // The descriptor was newly committed and registered. Seed the first
                // notification/full-screen frame before it can create MainActivity,
                // unless Dart already sent this call's display during registration;
                // duplicates return above and cannot replace foreground metadata.
                if (lockedMetadata?.first != payload.nativeCallId) {
                    initialDisplay?.let { lockedMetadata = payload.nativeCallId to it.toRingingMetadata() }
                }
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
            if (result == MknoonCallPresentationResult.PRESENTED) applyDeferredAnswer(inFlight)
            return result
        } finally {
            releaseRegistration(inFlight)
        }
    }

    /**
     * Durably owns and registers one authenticated outgoing call before Dart
     * may request media activation. Outgoing registration does not present an
     * incoming-call alert or start the microphone foreground service.
     */
    fun registerOutgoing(payload: CallWakePayload): MknoonCallPresentationResult {
        val inFlight = RegistrationInFlight(payload.nativeCallId)
        synchronized(lock) {
            admitRegistrationLocked(payload, PendingNativeCallDirection.OUTGOING, inFlight)
        }?.let { return it }
        try {
            val registered =
                registerWithPlatform(payload.nativeCallId, PendingNativeCallDirection.OUTGOING)
            return synchronized(lock) {
                settleRegistrationLocked(payload.nativeCallId, inFlight, registered)
                    ?.let { return@synchronized it }

                val presented = append(payload.nativeCallId, PendingNativeCallEventType.PRESENTED)
                    ?: run {
                        terminateInternal(
                            payload.nativeCallId,
                            PendingNativeCallEventType.NATIVE_FAILURE,
                            endPlatform = true,
                        )
                        return@synchronized MknoonCallPresentationResult.PERSISTENCE_FAILED
                    }
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
        } finally {
            releaseRegistration(inFlight)
        }
    }

    /**
     * First step of a presentation or outgoing registration, under [lock]:
     * returns a refusal, or null once the call is durably owned and its
     * Telecom registration is marked in flight.
     */
    private fun admitRegistrationLocked(
        payload: CallWakePayload,
        direction: PendingNativeCallDirection,
        inFlight: RegistrationInFlight,
    ): MknoonCallPresentationResult? {
        if (!safeBoolean(capabilityEnabled)) return MknoonCallPresentationResult.DISABLED
        if (adoptedState != null || cleanupState != null || registrationInFlight != null) {
            return MknoonCallPresentationResult.BUSY
        }
        val observedNow = safeNow() ?: return MknoonCallPresentationResult.STALE
        pruneTerminalTombstones(observedNow)
        if (terminalTombstones[payload.nativeCallId]?.let { it > observedNow } == true) {
            return MknoonCallPresentationResult.DUPLICATE
        }
        if (payload.expiresAtMs <= observedNow) return MknoonCallPresentationResult.STALE

        val created = try {
            when (direction) {
                PendingNativeCallDirection.INCOMING -> store.create(payload)
                PendingNativeCallDirection.OUTGOING -> store.createOutgoing(payload)
            }
        } catch (_: Exception) {
            PendingNativeCallCreateResult.PersistenceFailure
        }
        when (created) {
            is PendingNativeCallCreateResult.Duplicate -> return MknoonCallPresentationResult.DUPLICATE
            is PendingNativeCallCreateResult.Busy -> return MknoonCallPresentationResult.BUSY
            PendingNativeCallCreateResult.PersistenceFailure ->
                return MknoonCallPresentationResult.PERSISTENCE_FAILED
            is PendingNativeCallCreateResult.Created -> Unit
        }
        ownedCallId = payload.nativeCallId
        ownedExpiresAtMs = payload.expiresAtMs
        registrationInFlight = inFlight
        // Clear the previous call's volatile state now, not after registration:
        // Dart may already update this call (display, answer) while Telecom registers it.
        resetVolatileState()
        return null
    }

    /**
     * Step after the unlocked Telecom registration, under [lock]. A failed
     * registration fails the call as before. A call that ended meanwhile (a Dart
     * end, fail-closed) is not presented, and its late registration is ended.
     */
    private fun settleRegistrationLocked(
        nativeCallId: UUID,
        inFlight: RegistrationInFlight,
        registered: Boolean,
    ): MknoonCallPresentationResult? {
        if (registrationInFlight === inFlight) registrationInFlight = null
        if (!registered) {
            terminateInternal(
                nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
                endPlatform = true,
            )
            return MknoonCallPresentationResult.PLATFORM_FAILED
        }
        val endedWhileRegistering = ownedCallId != nativeCallId ||
            cleanupState != null ||
            terminalTombstones.containsKey(nativeCallId) ||
            hasTerminalLifecycleLocked(nativeCallId)
        if (endedWhileRegistering) {
            endLateRegistrationLocked(nativeCallId)
            return MknoonCallPresentationResult.STALE
        }
        return null
    }

    /**
     * The call ended while Telecom was still registering it, so the end in its
     * cleanup found no Telecom session. End the late registration now; if that
     * fails, leave an end-only cleanup for the usual retries.
     */
    private fun endLateRegistrationLocked(nativeCallId: UUID) {
        cleanupState?.takeIf { it.nativeCallId == nativeCallId }?.let { pending ->
            pending.endComplete = false
            if (!retryCleanup(nativeCallId)) runCatching { onCleanupPending(nativeCallId) }
            return
        }
        if (runCatching { platform.end(nativeCallId) }.isSuccess) return
        // retryCleanup needs the durable terminal event; without it one attempt is all there is.
        val descriptor = snapshotInternal()?.takeIf { it.nativeCallId == nativeCallId } ?: return
        val terminalEvent = descriptor.terminalEvent ?: return
        cleanupState = NativeCleanupState(
            nativeCallId = nativeCallId,
            expiresAtMs = descriptor.expiresAtMs,
            terminalType = terminalEvent.type,
            terminalEvent = terminalEvent,
            terminalPersisted = true,
            tombstoneRecorded = true,
            tombstonePersisted = true,
            settlementNotified = true,
            notificationComplete = true,
            foregroundComplete = true,
            audioFocusComplete = true,
            endpointsComplete = true,
            ringtoneStopAttempted = true,
        )
        runCatching { onCleanupPending(nativeCallId) }
    }

    private fun releaseRegistration(inFlight: RegistrationInFlight) {
        synchronized(lock) {
            if (registrationInFlight === inFlight) registrationInFlight = null
        }
        inFlight.settled.countDown()
    }

    /** True while this call's Telecom registration runs (B5). */
    fun isRegistrationInFlight(nativeCallId: UUID): Boolean =
        registrationInFlight?.nativeCallId == nativeCallId

    /**
     * B8: a main-thread Answer (notification action, lock-screen view, or a Telecom
     * callback, which below Android 14 arrives on main) for a call still registering
     * is recorded, not waited for, and applied when the registration settles.
     */
    private fun deferAnswerOnMain(nativeCallId: UUID, signalPlatform: Boolean): Boolean {
        if (!safeBoolean(isMainThread)) return false
        return synchronized(lock) {
            val inFlight = registrationInFlight?.takeIf { it.nativeCallId == nativeCallId }
                ?: return@synchronized false
            inFlight.deferredAnswer = true
            if (!signalPlatform) inFlight.deferredAnswerSignalsPlatform = false
            true
        }
    }

    /** Runs after a successful settle, outside [lock], before Telecom callbacks resume. */
    private fun applyDeferredAnswer(inFlight: RegistrationInFlight) {
        if (!inFlight.deferredAnswer) return
        answerInternal(
            inFlight.nativeCallId,
            signalPlatform = inFlight.deferredAnswerSignalsPlatform,
            duplicateIsSuccess = true,
        )
    }

    /**
     * Waits until the presentation that registered this call is settled. Never on
     * main: some Telecom versions need main to finish the registration (B8).
     */
    internal fun awaitRegistrationSettled(nativeCallId: UUID) {
        if (safeBoolean(isMainThread)) return
        val inFlight = registrationInFlight?.takeIf { it.nativeCallId == nativeCallId } ?: return
        try {
            inFlight.settled.await(REGISTRATION_SETTLE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    /**
     * Re-registers one already-presented durable call after process recreation.
     * The original PRESENTED event and notification identity are retained; no
     * second presentation event or alert is produced.
     *
     * B8: the runtime is created on main and restores the call from its
     * constructor. Below Android 14 Telecom needs main to finish a registration,
     * so only the checks run here, under [lock]; the registration runs on the
     * thread [dispatch] provides (the runtime passes a background one) without
     * [lock], like [present]. Returns false when there is nothing to restore,
     * otherwise true (with the default inline [dispatch]: whether it was restored).
     */
    fun reconcilePresented(dispatch: (Runnable) -> Unit = { it.run() }): Boolean {
        val (descriptor, inFlight) = synchronized(lock) { admitRestoreLocked() } ?: return false
        var restored = true
        val handedOff = runCatching {
            dispatch(Runnable { restored = completeRestore(descriptor, inFlight) })
        }.isSuccess
        if (!handedOff) {
            // Never leave the call marked as registering: that would refuse every later call.
            synchronized(lock) {
                if (registrationInFlight === inFlight) registrationInFlight = null
                terminateInternal(
                    descriptor.nativeCallId,
                    PendingNativeCallEventType.NATIVE_FAILURE,
                    endPlatform = true,
                )
            }
            inFlight.settled.countDown()
            return false
        }
        return restored
    }

    private fun admitRestoreLocked(): Pair<PendingNativeCallDescriptor, RegistrationInFlight>? {
        if (!safeBoolean(capabilityEnabled)) return null
        if (adoptedState != null || cleanupState != null || registrationInFlight != null) return null
        val descriptor = snapshotInternal() ?: return null
        if (
            descriptor.terminalEvent != null ||
            descriptor.events.none { it.type == PendingNativeCallEventType.PRESENTED }
        ) {
            return null
        }
        val observedNow = safeNow() ?: return null
        if (descriptor.expiresAtMs <= observedNow) {
            terminateInternal(
                descriptor.nativeCallId,
                PendingNativeCallEventType.EXPIRED,
                endPlatform = false,
            )
            return null
        }
        ownedCallId = descriptor.nativeCallId
        ownedExpiresAtMs = descriptor.expiresAtMs
        val inFlight = RegistrationInFlight(descriptor.nativeCallId)
        registrationInFlight = inFlight
        resetVolatileState(descriptor)
        return descriptor to inFlight
    }

    private fun completeRestore(
        descriptor: PendingNativeCallDescriptor,
        inFlight: RegistrationInFlight,
    ): Boolean {
        try {
            val registered = registerWithPlatform(descriptor.nativeCallId, descriptor.direction)
            val restored = synchronized(lock) {
                if (settleRegistrationLocked(descriptor.nativeCallId, inFlight, registered) != null) {
                    return@synchronized false
                }
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
            if (restored) applyDeferredAnswer(inFlight)
            return restored
        } finally {
            releaseRegistration(inFlight)
        }
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

    override fun answer(nativeCallId: UUID): Boolean {
        // B5/B8: Dart shows Answer before the native presentation, and after a
        // restart the old notification can be tapped while the call re-registers.
        // Off main the answer waits for the registration (the bridge dispatches
        // Dart's off main); on main it is applied when the registration settles.
        if (deferAnswerOnMain(nativeCallId, signalPlatform = true)) return true
        awaitRegistrationSettled(nativeCallId)
        return answerInternal(
            nativeCallId,
            signalPlatform = true,
            duplicateIsSuccess = false,
        )
    }

    fun answerFromTelecom(nativeCallId: UUID): Boolean {
        if (deferAnswerOnMain(nativeCallId, signalPlatform = false)) return true
        awaitRegistrationSettled(nativeCallId)
        return answerInternal(
            nativeCallId,
            signalPlatform = false,
            duplicateIsSuccess = true,
        )
    }

    private fun answerInternal(
        nativeCallId: UUID,
        signalPlatform: Boolean,
        duplicateIsSuccess: Boolean,
    ): Boolean {
        var newlyPersisted = false
        val accepted = synchronized(lock) {
            // Only if the wait in answer() timed out: an answer before Telecom has
            // registered the call would reach Telecom without a session.
            val registering = registrationInFlight?.nativeCallId == nativeCallId
            if (cleanupState != null || registering || !hasActiveLifecycle(nativeCallId)) {
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
        val newlyCompleted = terminateInternal(
            nativeCallId,
            PendingNativeCallEventType.END_REQUESTED,
            endPlatform = true,
        )
        // A canonical terminal snapshot can follow native Decline/End before
        // its journal ACK. Dart needs confirmation that exact cleanup is done,
        // not whether this request appended another terminal event. Retired or
        // unknown UUIDs have no retained lifecycle and remain rejected.
        newlyCompleted || (cleanupState == null && hasTerminalLifecycleLocked(nativeCallId))
    }

    fun endFromTelecom(nativeCallId: UUID): Boolean {
        awaitRegistrationSettled(nativeCallId)
        return synchronized(lock) {
            terminateInternal(
                nativeCallId,
                PendingNativeCallEventType.PROVIDER_REMOVED,
                endPlatform = false,
                audioFocusAlreadyReleased = true,
            )
        }
    }

    fun disconnectFromTelecom(nativeCallId: UUID): Boolean {
        awaitRegistrationSettled(nativeCallId)
        return terminalizeFromTelecom(nativeCallId)
    }

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

    fun activateAudioFromTelecom(nativeCallId: UUID): Boolean {
        awaitRegistrationSettled(nativeCallId)
        return activateAudioFromTelecomAfterRegistration(nativeCallId)
    }

    private fun activateAudioFromTelecomAfterRegistration(nativeCallId: UUID): Boolean = synchronized(lock) {
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

    fun deactivateAudioFromTelecom(nativeCallId: UUID): Boolean {
        awaitRegistrationSettled(nativeCallId)
        return terminalizeFromTelecom(nativeCallId)
    }

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

    /** One protected read with ownership sampled under the same lock; no reconciliation. */
    internal fun observeJournal(): MknoonCallJournalObservation = synchronized(lock) {
        // Unlike snapshotInternal, preserve read errors so observers cannot call them empty.
        val descriptor = store.observeProtectedJournal()
        MknoonCallJournalObservation(
            descriptor = descriptor,
            liveOwnerPresent = descriptor?.terminalEvent == null && descriptor != null ||
                adoptedState?.terminal == false || ownedCallId != null ||
                answerRequestedCallId != null || telecomActiveCallId != null ||
                audioResourcesCallId != null || audioTransition != null,
            cleanupPending = cleanupState != null,
        )
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

    fun updatePresentation(nativeCallId: UUID, metadata: MknoonLockedCallMetadata): Boolean = synchronized(lock) {
        if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) return@synchronized false
        lockedMetadata = nativeCallId to metadata
        true
    }

    fun presentation(nativeCallId: UUID): MknoonLockedCallMetadata? = synchronized(lock) {
        if (cleanupState != null || !hasActiveLifecycle(nativeCallId)) return@synchronized null
        lockedMetadata?.takeIf { it.first == nativeCallId }?.second
    }

    fun audioState(): MknoonCallAudioState = synchronized(lock) {
        audioStateLocked()
    }

    /** Bounded observation under the exact adopted audio owner, without store I/O. */
    internal fun <T> withActiveAudioOwner(
        nativeCallId: UUID,
        otherwise: T,
        observe: (muted: Boolean) -> T,
    ): T = synchronized(lock) {
        if (
            audioResourcesCallId != nativeCallId ||
            lastAudioActive != true ||
            cleanupState != null ||
            adoptedState?.let { it.nativeCallId == nativeCallId && !it.terminal } != true
        ) otherwise else observe(lastMuted == true)
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
        lockedMetadata = null
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
        timeoutMs: Long = MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS,
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
                    platform.registerIncoming(nativeCallId, callback, timeoutMs)
                PendingNativeCallDirection.OUTGOING ->
                    platform.registerOutgoing(nativeCallId, callback, timeoutMs)
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
        lockedMetadata = null
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

        /** Bound for a Telecom callback waiting on an in-flight registration's presentation. */
        const val REGISTRATION_SETTLE_TIMEOUT_MS = MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS + 3_000L
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
