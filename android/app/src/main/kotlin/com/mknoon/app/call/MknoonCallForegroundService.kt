package com.mknoon.app.call

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.UUID

internal interface MknoonCallForegroundRuntime {
    fun isActiveLifecycle(nativeCallId: UUID): Boolean = true

    fun isAudioActive(nativeCallId: UUID): Boolean? = null

    fun isTerminalLifecycle(nativeCallId: UUID): Boolean = false

    /**
     * Silent placeholder entered inside the high-priority FCM start window,
     * before the pushed call is authenticated. Ringing then upgrades an
     * already-foreground service, which is allowed after that window closes.
     */
    fun startAdmission(nativeCallId: UUID) = Unit

    fun startRinging(nativeCallId: UUID)

    fun startActive(nativeCallId: UUID)

    fun startInactive(nativeCallId: UUID)

    fun stop(nativeCallId: UUID)

    fun onStartFailure(nativeCallId: UUID) = Unit

    fun onAdmissionEvent(nativeCallId: UUID, event: MknoonCallAdmissionEvent) = Unit
}

/**
 * The service accepts only explicit idempotent commands for one call. Merely
 * ringing can never infer microphone ownership.
 */
internal class MknoonCallForegroundService(
    private val runtime: MknoonCallForegroundRuntime? = null,
    private val settlements: MknoonCallAdmissionSettlementStore = ProcessMknoonCallAdmissionSettlements.store,
    private val diagnostic: (MknoonCallAdmissionEvent, MknoonCallForegroundMode?) -> Unit = { event, mode ->
        android.util.Log.i(MKNOON_CALL_ADMISSION_TAG, formatMknoonCallAdmissionEvent(event, mode))
    },
) : Service() {
    companion object {
        const val ACTION_START_ADMISSION = "com.mknoon.app.call.service.START_ADMISSION"
        const val ACTION_RELEASE_ADMISSION = "com.mknoon.app.call.service.RELEASE_ADMISSION"
        const val ACTION_START_RINGING = "com.mknoon.app.call.service.START_RINGING"
        internal const val ADMISSION_TIMEOUT_MS = 30_000L
        const val ACTION_START_ACTIVE = "com.mknoon.app.call.service.START_ACTIVE"
        const val ACTION_START_INACTIVE = "com.mknoon.app.call.service.START_INACTIVE"
        const val ACTION_STOP = "com.mknoon.app.call.service.STOP"
        const val EXTRA_NATIVE_CALL_ID = "com.mknoon.app.call.service.extra.NATIVE_CALL_ID"
        const val EXTRA_ADMISSION_OWNER_ID = "com.mknoon.app.call.service.extra.ADMISSION_OWNER_ID"
        const val EXTRA_ADMISSION_REQUIRE_TERMINAL = "com.mknoon.app.call.service.extra.ADMISSION_REQUIRE_TERMINAL"
        internal const val EXTRA_ADMISSION_DECLINE_REPLY = "com.mknoon.app.call.service.extra.ADMISSION_DECLINE_REPLY"
        internal const val EXTRA_ADMISSION_EXPIRES_AT_MS = "com.mknoon.app.call.service.extra.ADMISSION_EXPIRES_AT_MS"
        internal const val EXTRA_ADMISSION_WAKE_HANDLE = "com.mknoon.app.call.service.extra.ADMISSION_WAKE_HANDLE"
        internal const val EXTRA_ADMISSION_SETTLED_TOKEN = "com.mknoon.app.call.service.extra.ADMISSION_SETTLED_TOKEN"
        private val ACTIONS = setOf(
            ACTION_START_ADMISSION,
            ACTION_RELEASE_ADMISSION,
            ACTION_START_RINGING,
            ACTION_START_ACTIVE,
            ACTION_START_INACTIVE,
            ACTION_STOP,
        )

        internal fun releaseAdmission(
            context: Context,
            callId: String,
            ownerId: UUID,
            requireTerminal: Boolean = true,
        ) {
            val nativeCallId = runCatching { UUID.fromString(callId) }.getOrNull() ?: return
            val intent = Intent(context, MknoonCallForegroundService::class.java)
                .setAction(ACTION_RELEASE_ADMISSION)
                .putExtra(EXTRA_NATIVE_CALL_ID, nativeCallId.toString())
                .putExtra(EXTRA_ADMISSION_OWNER_ID, ownerId.toString())
                .putExtra(EXTRA_ADMISSION_REQUIRE_TERMINAL, requireTerminal)
            runCatching { context.startService(intent) }
        }

        internal fun releaseSettledAdmission(context: Context, token: MknoonCallAdmissionToken) {
            val intent = Intent(context, MknoonCallForegroundService::class.java)
                .setAction(ACTION_RELEASE_ADMISSION)
                .putExtra(EXTRA_NATIVE_CALL_ID, token.nativeCallId.toString())
                .putExtra(EXTRA_ADMISSION_OWNER_ID, token.ownerId.toString())
                .putExtra(EXTRA_ADMISSION_EXPIRES_AT_MS, token.expiresAtMs)
                .putExtra(EXTRA_ADMISSION_WAKE_HANDLE, token.wakeHandle)
                .putExtra(EXTRA_ADMISSION_SETTLED_TOKEN, true)
                .putExtra(EXTRA_ADMISSION_REQUIRE_TERMINAL, false)
            runCatching { context.startService(intent) }
        }
    }

    private var activeCallId: UUID? = null
    private var mode: MknoonCallForegroundMode? = null
    private var admissionOwnerId: UUID? = null
    private var admissionHoldsDeclineReply = false
    private var admissionToken: MknoonCallAdmissionToken? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return rejectStart(startId)
        if (action !in ACTIONS) return rejectStart(startId)
        val rawCallId = intent.extras?.get(EXTRA_NATIVE_CALL_ID) as? String
            ?: return rejectStart(startId)
        val nativeCallId = runCatching { UUID.fromString(rawCallId) }.getOrNull()
            ?: return rejectStart(startId)
        val ownerId = if (action == ACTION_START_ADMISSION || action == ACTION_RELEASE_ADMISSION) {
            val rawOwner = intent.extras?.get(EXTRA_ADMISSION_OWNER_ID) as? String
                ?: return rejectStart(startId)
            runCatching { UUID.fromString(rawOwner) }.getOrNull() ?: return rejectStart(startId)
        } else null
        val target by lazy(LazyThreadSafetyMode.NONE) {
            runtime ?: MknoonCallRuntime.get(this).foregroundRuntime(this)
        }

        when (action) {
            ACTION_START_ADMISSION -> {
                val declineReply = intent.extras?.get(EXTRA_ADMISSION_DECLINE_REPLY) == true
                val incomingToken = admissionToken(intent, nativeCallId, requireNotNull(ownerId))
                if (activeCallId == nativeCallId && mode == MknoonCallForegroundMode.ADMISSION &&
                    incomingToken != null && settlements.hasSuccessor(incomingToken)) {
                    observe(target, nativeCallId, MknoonCallAdmissionEvent.START_IGNORED_OWNER)
                    return START_NOT_STICKY
                }
                // Plan 404 (c): a ringing call that ended natively re-enters
                // admission for its decline reply; the reply worker's release
                // releases it (or the admission timeout does).
                val replyAfterRinging = activeCallId == nativeCallId &&
                    mode == MknoonCallForegroundMode.RINGING &&
                    runCatching { !target.isActiveLifecycle(nativeCallId) }.getOrDefault(false)
                if (activeCallId == null || replyAfterRinging) {
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startAdmission(nativeCallId)
                        }) {
                        settlements.block(nativeCallId, ownerId)
                        return START_NOT_STICKY
                    }
                    activeCallId = nativeCallId
                    mode = MknoonCallForegroundMode.ADMISSION
                    admissionOwnerId = ownerId
                    admissionToken = admissionToken(intent, nativeCallId, requireNotNull(ownerId))
                    admissionHoldsDeclineReply = declineReply
                    scheduleAdmissionTimeout(nativeCallId, requireNotNull(ownerId), startId)
                    observe(target, nativeCallId, MknoonCallAdmissionEvent.START_APPLIED)
                } else if (activeCallId == nativeCallId && mode == MknoonCallForegroundMode.ADMISSION &&
                    admissionOwnerId != ownerId
                ) {
                    // Same-call work is serialized. A newer queued request keeps
                    // foreground custody when an older request finishes.
                    admissionOwnerId = ownerId
                    admissionToken = admissionToken(intent, nativeCallId, requireNotNull(ownerId))
                    // A later queued ordinary wake must not strip custody from
                    // the decline reply that is still running ahead of it.
                    admissionHoldsDeclineReply = admissionHoldsDeclineReply || declineReply
                    scheduleAdmissionTimeout(nativeCallId, requireNotNull(ownerId), startId)
                    observe(target, nativeCallId, MknoonCallAdmissionEvent.START_REPLACED_OWNER)
                } else if (activeCallId != nativeCallId) {
                    settlements.block(nativeCallId, ownerId)
                    observe(target, nativeCallId, MknoonCallAdmissionEvent.START_IGNORED_OTHER_CALL)
                } else if (mode != MknoonCallForegroundMode.ADMISSION) {
                    settlements.block(nativeCallId, ownerId)
                    observe(target, nativeCallId, MknoonCallAdmissionEvent.START_IGNORED_UPGRADED)
                }
                if (declineReply) settlements.protectDecline(nativeCallId)
                // A call that still rings or is active ignores a late
                // admission command.
                releaseKnownTerminalAdmission(target, nativeCallId, requireNotNull(ownerId), startId)
                releaseSettledAdmission(target, nativeCallId, requireNotNull(ownerId), startId)
            }
            ACTION_START_RINGING -> {
                if (activeCallId == null ||
                    (activeCallId == nativeCallId && mode == MknoonCallForegroundMode.ADMISSION)
                ) {
                    if (!reconcilesLifecycle(startId, nativeCallId, target)) {
                        return START_NOT_STICKY
                    }
                    if (!audioStateMatches(
                            startId,
                            nativeCallId,
                            target,
                            expected = false,
                            requireAuthoritative = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startRinging(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    activeCallId = nativeCallId
                    mode = MknoonCallForegroundMode.RINGING
                    settlements.block(nativeCallId, admissionOwnerId)
                } else if (
                    activeCallId == nativeCallId &&
                    !reconcilesLifecycle(startId, nativeCallId, target)
                ) {
                    return START_NOT_STICKY
                }
            }
            ACTION_START_ACTIVE -> {
                if (
                    activeCallId == nativeCallId &&
                    (mode == MknoonCallForegroundMode.ADMISSION || mode == MknoonCallForegroundMode.RINGING || mode == MknoonCallForegroundMode.INACTIVE)
                ) {
                    if (!reconcilesLifecycle(startId, nativeCallId, target)) {
                        return START_NOT_STICKY
                    }
                    if (!audioStateMatches(
                            startId,
                            nativeCallId,
                            target,
                            expected = true,
                            requireAuthoritative = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startActive(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    mode = MknoonCallForegroundMode.ACTIVE
                } else if (activeCallId == null) {
                    if (!reconcilesLifecycle(
                            startId,
                            nativeCallId,
                            target,
                            failureOnMismatch = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!audioStateMatches(
                            startId,
                            nativeCallId,
                            target,
                            expected = true,
                            requireAuthoritative = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startActive(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    activeCallId = nativeCallId
                    mode = MknoonCallForegroundMode.ACTIVE
                } else if (
                    activeCallId == nativeCallId &&
                    !reconcilesLifecycle(startId, nativeCallId, target)
                ) {
                    return START_NOT_STICKY
                }
            }
            ACTION_START_INACTIVE -> {
                if (
                    activeCallId == nativeCallId &&
                    (mode == MknoonCallForegroundMode.ACTIVE || mode == MknoonCallForegroundMode.RINGING)
                ) {
                    if (!reconcilesLifecycle(startId, nativeCallId, target)) {
                        return START_NOT_STICKY
                    }
                    if (!audioStateMatches(startId, nativeCallId, target, expected = false)) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startInactive(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    mode = MknoonCallForegroundMode.INACTIVE
                } else if (activeCallId == null) {
                    if (!reconcilesLifecycle(
                            startId,
                            nativeCallId,
                            target,
                            failureOnMismatch = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!audioStateMatches(
                            startId,
                            nativeCallId,
                            target,
                            expected = false,
                            requireAuthoritative = true,
                        )) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startInactive(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    activeCallId = nativeCallId
                    mode = MknoonCallForegroundMode.INACTIVE
                } else if (
                    activeCallId == nativeCallId &&
                    !reconcilesLifecycle(startId, nativeCallId, target)
                ) {
                    return START_NOT_STICKY
                }
            }
            ACTION_RELEASE_ADMISSION -> {
                val requireTerminal = intent.getBooleanExtra(EXTRA_ADMISSION_REQUIRE_TERMINAL, true)
                val settlementRelease = intent.getBooleanExtra(EXTRA_ADMISSION_SETTLED_TOKEN, false)
                val token = admissionToken(intent, nativeCallId, requireNotNull(ownerId))
                when {
                    activeCallId == null -> {
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_IDLE)
                        stopSelfResult(startId)
                    }
                    activeCallId != nativeCallId ->
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_IGNORED_CALL)
                    mode != MknoonCallForegroundMode.ADMISSION ->
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_IGNORED_UPGRADED)
                    admissionOwnerId != ownerId ->
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_IGNORED_OWNER)
                    settlementRelease && (admissionHoldsDeclineReply || token == null ||
                        token != admissionToken || !settlements.isSettled(token)) ->
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_DEFERRED)
                    requireTerminal &&
                        !runCatching { target.isTerminalLifecycle(nativeCallId) }.getOrDefault(false) ->
                        observe(target, nativeCallId, MknoonCallAdmissionEvent.RELEASE_DEFERRED)
                    else -> stopOwnedForeground(
                        target, nativeCallId, startId,
                        if (requireTerminal) MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL
                        else MknoonCallAdmissionEvent.RELEASE_APPLIED_SETTLED,
                        MknoonCallAdmissionEvent.RELEASE_FAILED,
                    )
                }
            }
            ACTION_STOP -> {
                if (activeCallId == nativeCallId) {
                    stopOwnedForeground(target, nativeCallId, startId,
                        MknoonCallAdmissionEvent.STOP_APPLIED, MknoonCallAdmissionEvent.STOP_FAILED)
                } else if (activeCallId == null) {
                    // A STOP may be the first command delivered to a freshly
                    // created service. End that service promptly without
                    // replaying native cleanup that already completed.
                    stopSelfResult(startId)
                }
            }
        }
        if (activeCallId == nativeCallId && mode != MknoonCallForegroundMode.ADMISSION) {
            settlements.block(nativeCallId, admissionOwnerId)
        }
        return START_NOT_STICKY
    }

    private fun reconcilesLifecycle(
        startId: Int,
        nativeCallId: UUID,
        target: MknoonCallForegroundRuntime,
        failureOnMismatch: Boolean = false,
    ): Boolean = try {
        if (target.isActiveLifecycle(nativeCallId)) {
            true
        } else {
            if (failureOnMismatch) {
                failStart(startId, nativeCallId, target)
            } else {
                if (activeCallId == nativeCallId) {
                    activeCallId = null
                    mode = null
                }
                stopSelfResult(startId)
            }
            false
        }
    } catch (_: Exception) {
        failStart(startId, nativeCallId, target)
        false
    }

    private inline fun startSafely(
        startId: Int,
        nativeCallId: UUID,
        target: MknoonCallForegroundRuntime,
        start: () -> Unit,
    ): Boolean = try {
        start()
        true
    } catch (_: Exception) {
        failStart(startId, nativeCallId, target)
        false
    }

    private fun audioStateMatches(
        startId: Int,
        nativeCallId: UUID,
        target: MknoonCallForegroundRuntime,
        expected: Boolean,
        requireAuthoritative: Boolean = false,
    ): Boolean = try {
        val actual = target.isAudioActive(nativeCallId)
        if (actual == expected || (actual == null && !requireAuthoritative)) {
            true
        } else {
            failStart(startId, nativeCallId, target)
            false
        }
    } catch (_: Exception) {
        failStart(startId, nativeCallId, target)
        false
    }

    private fun failStart(
        startId: Int,
        nativeCallId: UUID,
        target: MknoonCallForegroundRuntime,
    ) {
        if (activeCallId == nativeCallId) {
            activeCallId = null
            mode = null
        }
        runCatching { target.onStartFailure(nativeCallId) }
        stopSelfResult(startId)
    }

    private val admissionTimeout = Handler(Looper.getMainLooper())

    private fun observe(
        target: MknoonCallForegroundRuntime,
        nativeCallId: UUID,
        event: MknoonCallAdmissionEvent,
        observedMode: MknoonCallForegroundMode? = mode,
    ) {
        runCatching { diagnostic(event, observedMode) }
        runCatching { target.onAdmissionEvent(nativeCallId, event) }
    }

    private fun stopOwnedForeground(
        target: MknoonCallForegroundRuntime,
        nativeCallId: UUID,
        startId: Int,
        appliedEvent: MknoonCallAdmissionEvent,
        failedEvent: MknoonCallAdmissionEvent,
    ) {
        val previousMode = mode
        clearAdmission()
        activeCallId = null
        mode = null
        val applied = runCatching { target.stop(nativeCallId) }.isSuccess
        // "Applied" is emitted only after stopForeground/remove and stopSelf
        // returned. Submission of a worker release intent is not this proof.
        observe(target, nativeCallId, if (applied) appliedEvent else failedEvent, previousMode)
        if (!applied) stopSelfResult(startId)
    }

    private fun releaseKnownTerminalAdmission(
        target: MknoonCallForegroundRuntime,
        nativeCallId: UUID,
        ownerId: UUID,
        startId: Int,
    ) {
        if (activeCallId != nativeCallId || mode != MknoonCallForegroundMode.ADMISSION ||
            admissionOwnerId != ownerId || admissionHoldsDeclineReply
        ) return
        // startAdmission above must satisfy Android's foreground-start
        // obligation first. An authenticated tombstone can then retire this
        // exact placeholder without waiting for a queued headless worker.
        // Unknown or unreadable terminal state keeps fresh admission custody.
        if (!runCatching { target.isTerminalLifecycle(nativeCallId) }.getOrDefault(false)) return
        stopOwnedForeground(target, nativeCallId, startId,
            MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL, MknoonCallAdmissionEvent.RELEASE_FAILED)
    }

    private fun releaseSettledAdmission(target: MknoonCallForegroundRuntime, nativeCallId: UUID,
        ownerId: UUID, startId: Int) {
        val token = admissionToken ?: return
        if (activeCallId != nativeCallId || mode != MknoonCallForegroundMode.ADMISSION ||
            admissionOwnerId != ownerId || admissionHoldsDeclineReply || !settlements.isSettled(token)) return
        stopOwnedForeground(target, nativeCallId, startId,
            MknoonCallAdmissionEvent.RELEASE_APPLIED_SETTLED, MknoonCallAdmissionEvent.RELEASE_FAILED)
    }

    private fun admissionToken(intent: Intent, callId: UUID, ownerId: UUID): MknoonCallAdmissionToken? =
        MknoonCallAdmissionToken.parse(mapOf("nativeCallId" to callId.toString(), "ownerId" to ownerId.toString(),
            "expiresAtMs" to intent.extras?.get(EXTRA_ADMISSION_EXPIRES_AT_MS),
            "wakeHandle" to intent.extras?.get(EXTRA_ADMISSION_WAKE_HANDLE)))

    /** An admission that is never upgraded or stopped must not hold the
     *  foreground state forever; it ends a little after the worker's budget. */
    private fun scheduleAdmissionTimeout(nativeCallId: UUID, ownerId: UUID, startId: Int) {
        admissionTimeout.removeCallbacksAndMessages(null)
        admissionTimeout.postDelayed({
            if (activeCallId == nativeCallId && mode == MknoonCallForegroundMode.ADMISSION &&
                admissionOwnerId == ownerId
            ) {
                val target = runtime ?: MknoonCallRuntime.get(this).foregroundRuntime(this)
                stopOwnedForeground(target, nativeCallId, startId,
                    MknoonCallAdmissionEvent.TIMEOUT_APPLIED, MknoonCallAdmissionEvent.TIMEOUT_FAILED)
                stopSelfResult(startId)
            }
        }, ADMISSION_TIMEOUT_MS)
    }

    private fun clearAdmission() {
        activeCallId?.let { settlements.retire(it, admissionOwnerId) }
        admissionOwnerId = null
        admissionToken = null
        admissionHoldsDeclineReply = false
        admissionTimeout.removeCallbacksAndMessages(null)
    }

    override fun onDestroy() {
        activeCallId?.let { settlements.retire(it, admissionOwnerId) }
        admissionTimeout.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun rejectStart(startId: Int): Int {
        stopSelfResult(startId)
        return START_NOT_STICKY
    }

}
