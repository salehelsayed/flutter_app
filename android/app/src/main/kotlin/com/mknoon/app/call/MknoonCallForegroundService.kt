package com.mknoon.app.call

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.util.UUID

internal interface MknoonCallForegroundRuntime {
    fun isActiveLifecycle(nativeCallId: UUID): Boolean = true

    fun isAudioActive(nativeCallId: UUID): Boolean? = null

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
}

/**
 * The service accepts only explicit idempotent commands for one call. Merely
 * ringing can never infer microphone ownership.
 */
internal class MknoonCallForegroundService(
    private val runtime: MknoonCallForegroundRuntime? = null,
) : Service() {
    companion object {
        const val ACTION_START_ADMISSION = "com.mknoon.app.call.service.START_ADMISSION"
        const val ACTION_START_RINGING = "com.mknoon.app.call.service.START_RINGING"
        internal const val ADMISSION_TIMEOUT_MS = 30_000L
        const val ACTION_START_ACTIVE = "com.mknoon.app.call.service.START_ACTIVE"
        const val ACTION_START_INACTIVE = "com.mknoon.app.call.service.START_INACTIVE"
        const val ACTION_STOP = "com.mknoon.app.call.service.STOP"
        const val EXTRA_NATIVE_CALL_ID = "com.mknoon.app.call.service.extra.NATIVE_CALL_ID"
        private val ACTIONS = setOf(
            ACTION_START_ADMISSION,
            ACTION_START_RINGING,
            ACTION_START_ACTIVE,
            ACTION_START_INACTIVE,
            ACTION_STOP,
        )
    }

    private var activeCallId: UUID? = null
    private var mode: Mode? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return rejectStart(startId)
        if (action !in ACTIONS) return rejectStart(startId)
        val rawCallId = intent.extras?.get(EXTRA_NATIVE_CALL_ID) as? String
            ?: return rejectStart(startId)
        val nativeCallId = runCatching { UUID.fromString(rawCallId) }.getOrNull()
            ?: return rejectStart(startId)
        val target by lazy(LazyThreadSafetyMode.NONE) {
            runtime ?: MknoonCallRuntime.get(this).foregroundRuntime(this)
        }

        when (action) {
            ACTION_START_ADMISSION -> {
                if (activeCallId == null) {
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startAdmission(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    activeCallId = nativeCallId
                    mode = Mode.ADMISSION
                    scheduleAdmissionTimeout(nativeCallId, startId)
                }
                // A call that already rings or is active ignores a late
                // admission command.
            }
            ACTION_START_RINGING -> {
                if (activeCallId == null ||
                    (activeCallId == nativeCallId && mode == Mode.ADMISSION)
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
                    mode = Mode.RINGING
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
                    (mode == Mode.RINGING || mode == Mode.INACTIVE)
                ) {
                    if (!reconcilesLifecycle(startId, nativeCallId, target)) {
                        return START_NOT_STICKY
                    }
                    if (!startSafely(startId, nativeCallId, target) {
                            target.startActive(nativeCallId)
                        }) {
                        return START_NOT_STICKY
                    }
                    mode = Mode.ACTIVE
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
                    mode = Mode.ACTIVE
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
                    (mode == Mode.ACTIVE || mode == Mode.RINGING)
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
                    mode = Mode.INACTIVE
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
                    mode = Mode.INACTIVE
                } else if (
                    activeCallId == nativeCallId &&
                    !reconcilesLifecycle(startId, nativeCallId, target)
                ) {
                    return START_NOT_STICKY
                }
            }
            ACTION_STOP -> {
                if (activeCallId == nativeCallId) {
                    activeCallId = null
                    mode = null
                    if (runCatching { target.stop(nativeCallId) }.isFailure) {
                        stopSelfResult(startId)
                    }
                } else if (activeCallId == null) {
                    // A STOP may be the first command delivered to a freshly
                    // created service. End that service promptly without
                    // replaying native cleanup that already completed.
                    stopSelfResult(startId)
                }
            }
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

    /** An admission that is never upgraded or stopped must not hold the
     *  foreground state forever; it ends a little after the worker's budget. */
    private fun scheduleAdmissionTimeout(nativeCallId: UUID, startId: Int) {
        admissionTimeout.postDelayed({
            if (activeCallId == nativeCallId && mode == Mode.ADMISSION) {
                activeCallId = null
                mode = null
                val target = runtime ?: MknoonCallRuntime.get(this).foregroundRuntime(this)
                runCatching { target.stop(nativeCallId) }
                stopSelfResult(startId)
            }
        }, ADMISSION_TIMEOUT_MS)
    }

    override fun onDestroy() {
        admissionTimeout.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun rejectStart(startId: Int): Int {
        stopSelfResult(startId)
        return START_NOT_STICKY
    }

    private enum class Mode {
        ADMISSION,
        RINGING,
        ACTIVE,
        INACTIVE,
    }
}
