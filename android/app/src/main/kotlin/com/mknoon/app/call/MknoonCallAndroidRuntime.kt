package com.mknoon.app.call

import android.Manifest
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.telecom.DisconnectCause
import androidx.core.content.ContextCompat
import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallControlScope
import androidx.core.telecom.CallControlResult
import androidx.core.telecom.CallEndpointCompat
import androidx.core.telecom.CallsManager
import com.mknoon.app.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

internal val CANONICAL_NATIVE_CALL_ROUTES = setOf(
    "system_default",
    "earpiece",
    "speaker",
    "wired_headset",
    "bluetooth",
)

internal const val MKNOON_CALL_LIFECYCLE_DIAGNOSTIC_TAG = "MknoonCallLifecycle"
internal const val MKNOON_CALL_LIFECYCLE_DIAGNOSTIC_PREFIX = "CALL_ANDROID_LIFECYCLE"
internal const val MKNOON_TELECOM_DISCONNECT_DIAGNOSTIC_TAG = "MknoonCallDisconnect"
internal const val MKNOON_TELECOM_DISCONNECT_DIAGNOSTIC_PREFIX = "CALL_ANDROID_DISCONNECT"
internal const val MKNOON_CALL_RINGTONE_DIAGNOSTIC_TAG = "MknoonCallRingtone"
internal const val MKNOON_CALL_PRESENTATION_DIAGNOSTIC_TAG = "MknoonCallPresentation"
internal const val MKNOON_CALL_RINGTONE_DIAGNOSTIC_PREFIX = "MKNOON_CALL_RINGTONE_DIAG"

internal enum class MknoonTelecomDisconnectSource(
    val source: String,
    val stage: String,
) {
    EXPLICIT_END("explicit_end", "requested"),
    LATE_REGISTRATION("late_registration", "requested"),
    SET_ACTIVE_REJECTED("set_active", "rejected_disconnect"),
    SET_INACTIVE("set_inactive", "requested"),
    TELECOM_CALLBACK_LOCAL("telecom_callback", "ignored_local"),
    TELECOM_CALLBACK_REMOTE("telecom_callback", "forwarded_remote"),
}

internal fun formatMknoonTelecomDisconnectDiagnostic(
    diagnostic: MknoonTelecomDisconnectSource,
): String =
    "$MKNOON_TELECOM_DISCONNECT_DIAGNOSTIC_PREFIX " +
        "source=${diagnostic.source} stage=${diagnostic.stage}"

private fun emitMknoonTelecomDisconnectDiagnostic(
    diagnostic: MknoonTelecomDisconnectSource,
) {
    android.util.Log.i(
        MKNOON_TELECOM_DISCONNECT_DIAGNOSTIC_TAG,
        formatMknoonTelecomDisconnectDiagnostic(diagnostic),
    )
}

internal fun formatMknoonCallRingtoneDiagnostic(stage: String, result: String): String =
    "$MKNOON_CALL_RINGTONE_DIAGNOSTIC_PREFIX stage=$stage result=$result"

internal fun isIncomingRingtoneEligible(
    descriptor: PendingNativeCallDescriptor?,
    nativeCallId: UUID,
    observedNowMs: Long,
): Boolean =
    descriptor?.nativeCallId == nativeCallId &&
        descriptor.direction == PendingNativeCallDirection.INCOMING &&
        descriptor.terminalEvent == null &&
        descriptor.expiresAtMs > observedNowMs &&
        !descriptor.answerRequested

internal enum class MknoonIncomingRingtoneStartResult(val wireValue: String) {
    PLAYING("playing"),
    INELIGIBLE("ineligible"),
    UNAVAILABLE("unavailable"),
}

internal fun coordinateIncomingRingtoneStart(
    nativeCallId: UUID,
    snapshot: () -> PendingNativeCallDescriptor?,
    observedNowMs: () -> Long,
    start: (UUID) -> Boolean,
    stop: (UUID, String) -> Unit,
): MknoonIncomingRingtoneStartResult {
    if (!isIncomingRingtoneEligible(snapshot(), nativeCallId, observedNowMs())) {
        stop(nativeCallId, "ineligible")
        return MknoonIncomingRingtoneStartResult.INELIGIBLE
    }
    if (!start(nativeCallId)) {
        return MknoonIncomingRingtoneStartResult.UNAVAILABLE
    }
    if (!isIncomingRingtoneEligible(snapshot(), nativeCallId, observedNowMs())) {
        stop(nativeCallId, "start_race")
        return MknoonIncomingRingtoneStartResult.INELIGIBLE
    }
    return MknoonIncomingRingtoneStartResult.PLAYING
}

internal fun shouldAutoDeleteExpiredPersistedCallAtStartup(
    descriptor: PendingNativeCallDescriptor,
    observedNowMs: Long,
): Boolean = descriptor.expiresAtMs <= observedNowMs

internal fun formatMknoonCallLifecycleDiagnostic(
    diagnostic: MknoonCallLifecycleDiagnostic,
): String =
    "$MKNOON_CALL_LIFECYCLE_DIAGNOSTIC_PREFIX " +
        "transition=${diagnostic.transition} outcome=${diagnostic.outcome}"

private object AndroidMknoonCallLifecycleDiagnosticSink : MknoonCallLifecycleDiagnosticSink {
    override fun emit(diagnostic: MknoonCallLifecycleDiagnostic) {
        android.util.Log.i(
            MKNOON_CALL_LIFECYCLE_DIAGNOSTIC_TAG,
            formatMknoonCallLifecycleDiagnostic(diagnostic),
        )
    }
}

/** Process singleton shared by FCM, notification actions, service, and Flutter. */
internal class MknoonCallRuntime private constructor(context: Context) {
    companion object {
        private const val PREFERENCES = "mknoon_android_call_capability_v1"
        private const val CAPABILITY_KEY = "dart_capability_enabled"
        private const val TERMINAL_TOMBSTONE_PREFIX = "terminal_tombstone_"
        private const val MAX_TERMINAL_TOMBSTONES = 32
        private const val STARTUP_CONVERGENCE_ATTEMPTS = 16
        private const val STARTUP_CONVERGENCE_RETRY_MS = 250L
        private const val CLEANUP_RETRY_ATTEMPTS = 8
        private const val CLEANUP_RETRY_MS = 250L
        private val AUTHENTICATED_HANDLE = Regex(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        )

        @Volatile
        private var instance: MknoonCallRuntime? = null

        fun get(context: Context): MknoonCallRuntime =
            instance ?: synchronized(this) {
                instance ?: MknoonCallRuntime(context.applicationContext).also {
                    instance = it
                }
            }
    }

    private val applicationContext = context.applicationContext
    private val incomingCallRinger = MknoonIncomingCallRinger(
        AndroidMknoonCallRingtoneStarter(applicationContext),
    )
    private val outgoingRingback = MknoonOutgoingCallRingback(
        AndroidMknoonCallRingbackToneStarter(),
    )
    private val preferences = applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val runtimeScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /**
     * Telecom registration waits on the platform callback. Below API 34
     * core-telecom delivers that callback on the main looper, so the wait
     * must never run there; bridge registrations use this thread instead.
     */
    private val registrationExecutor: Executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "mknoon-call-registration").apply { isDaemon = true }
    }
    private val expiryJobs = ConcurrentHashMap<UUID, Job>()
    private val cleanupJobs = ConcurrentHashMap<UUID, Job>()
    private val authenticatedIngressLock = Any()
    private val terminalTombstoneLock = Any()
    internal val eventRelay = MknoonCallEventRelay()
    private lateinit var androidPlatform: AndroidMknoonCallPlatform

    val controller: MknoonCallLifecycleController

    init {
        androidPlatform = AndroidMknoonCallPlatform(
            context = applicationContext,
            controller = { controller },
            stopIncomingRinger = { nativeCallId ->
                stopIncomingRingtone(nativeCallId, "lifecycle")
                stopOutgoingRingbackFromLifecycle()
            },
        )
        controller = MknoonCallLifecycleController(
            store = PendingNativeCallStore(applicationContext),
            platform = androidPlatform,
            eventSink = eventRelay,
            capabilityEnabled = ::isCapabilityEnabled,
            recordAudioPermissionGranted = {
                ContextCompat.checkSelfPermission(
                    applicationContext,
                    Manifest.permission.RECORD_AUDIO,
                ) == PackageManager.PERMISSION_GRANTED
            },
            nowMs = { System.currentTimeMillis() },
            onPresented = ::scheduleExpiry,
            onSettled = ::cancelExpiry,
            onTerminated = ::recordTerminalTombstone,
            onCleanupPending = ::scheduleCleanupRetry,
            onDeclineWithoutOwner = ::scheduleHeadlessDeclineReply,
            diagnosticSink = AndroidMknoonCallLifecycleDiagnosticSink,
        )
        reconcilePersistedDescriptor()
    }

    /** Plan 404: a natively declined call with no Dart owner answers the caller headlessly. */
    private fun scheduleHeadlessDeclineReply(descriptor: PendingNativeCallDescriptor) {
        HeadlessCallAdmissionWorkScheduler(applicationContext).enqueueDeclineReply(descriptor)
    }

    fun setCapabilityEnabled(enabled: Boolean): Boolean {
        if (
            enabled &&
            (!BuildConfig.ENABLE_ANDROID_NATIVE_CALLS || Build.VERSION.SDK_INT < Build.VERSION_CODES.O)
        ) {
            preferences.edit().putBoolean(CAPABILITY_KEY, false).commit()
            cleanupActiveLifecycle()
            return false
        }
        val committed = preferences.edit().putBoolean(CAPABILITY_KEY, enabled).commit()
        if (!enabled) {
            val disabled = committed && !preferences.getBoolean(CAPABILITY_KEY, true)
            val cleaned = cleanupActiveLifecycle()
            return disabled && cleaned
        }
        return committed && preferences.getBoolean(CAPABILITY_KEY, false)
    }

    fun failClosed(): Boolean = executeFailClosed(
        persistDisable = {
            preferences.edit().putBoolean(CAPABILITY_KEY, false).commit() &&
                !preferences.getBoolean(CAPABILITY_KEY, true)
        },
        cleanup = {
            controller.failClosed() && controller.activeNativeCallId() == null
        },
    )

    fun isCapabilityEnabled(): Boolean =
        BuildConfig.ENABLE_ANDROID_NATIVE_CALLS &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            preferences.getBoolean(CAPABILITY_KEY, false)

    fun present(payload: CallWakePayload): MknoonCallPresentationResult =
        synchronized(authenticatedIngressLock) {
            if (
                isCapabilityEnabled() &&
                hasTerminalTombstone(payload.nativeCallId, System.currentTimeMillis())
            ) {
                return@synchronized MknoonCallPresentationResult.DUPLICATE
            }
            controller.snapshot()?.takeIf {
                it.nativeCallId == payload.nativeCallId &&
                    it.callHandle == payload.callHandle &&
                    it.expiresAtMs == payload.expiresAtMs &&
                    it.terminalEvent == null
            }?.let {
                return@synchronized MknoonCallPresentationResult.DUPLICATE
            }
            controller.present(payload).also { result ->
                android.util.Log.i(
                    MKNOON_CALL_PRESENTATION_DIAGNOSTIC_TAG,
                    "MKNOON_CALL_PRESENTATION_DIAG result=" + result.name,
                )
            }
        }

    fun presentAuthenticated(callHandle: String, expiresAtMs: Long): Boolean {
        val observedNow = System.currentTimeMillis()
        return presentAuthenticatedCall(
            callHandle = callHandle,
            expiresAtMs = expiresAtMs,
            observedNowMs = observedNow,
            capabilityEnabled = isCapabilityEnabled(),
            handleGrammar = AUTHENTICATED_HANDLE,
            wakeHandle = { UUID.randomUUID().toString() },
            present = ::present,
        )
    }

    fun terminalizeAuthenticated(callHandle: String, expiresAtMs: Long): Boolean {
        val observedNow = System.currentTimeMillis()
        return terminalizeAuthenticatedCall(
            callHandle = callHandle,
            expiresAtMs = expiresAtMs,
            observedNowMs = observedNow,
            capabilityEnabled = isCapabilityEnabled(),
            handleGrammar = AUTHENTICATED_HANDLE,
            terminalize = { nativeCallId, terminalExpiryMs ->
                synchronized(authenticatedIngressLock) {
                    val current = controller.snapshot()
                    if (
                        current?.nativeCallId == nativeCallId &&
                        current.terminalEvent == null
                    ) {
                        controller.terminate(
                            nativeCallId,
                            PendingNativeCallEventType.REMOTE_CANCELLED,
                        )
                        val afterTermination = controller.snapshot()
                        if (
                            afterTermination?.nativeCallId == nativeCallId &&
                            afterTermination.terminalEvent == null
                        ) {
                            return@synchronized false
                        }
                    }
                    recordTerminalTombstone(nativeCallId, terminalExpiryMs)
                }
            },
        )
    }

    fun registerOutgoingAuthenticated(callHandle: String, expiresAtMs: Long): Boolean {
        val observedNow = System.currentTimeMillis()
        return presentAuthenticatedCall(
            callHandle = callHandle,
            expiresAtMs = expiresAtMs,
            observedNowMs = observedNow,
            capabilityEnabled = isCapabilityEnabled(),
            handleGrammar = AUTHENTICATED_HANDLE,
            wakeHandle = { UUID.randomUUID().toString() },
            present = controller::registerOutgoing,
        )
    }

    fun createBridge(messenger: BinaryMessenger): MknoonCallNativeBridge =
        MknoonCallNativeBridge(
            controller = controller,
            messenger = messenger,
            relay = eventRelay,
            capabilitySetter = ::setCapabilityEnabled,
            capabilityGetter = ::isCapabilityEnabled,
            failCloser = ::failClosed,
            beforeAttach = ::settleUnconsumableTerminalBeforeAttach,
            authenticatedPresenter = ::presentAuthenticated,
            authenticatedOutgoingRegistrar = ::registerOutgoingAuthenticated,
            ringbackStarter = ::startOutgoingRingback,
            ringbackStopper = ::stopOutgoingRingback,
            registrationExecutor = registrationExecutor,
        )

    fun foregroundRuntime(service: Service): MknoonCallForegroundRuntime =
        AndroidMknoonCallForegroundRuntime(service)

    private fun startOutgoingRingback(callHandle: String): Boolean {
        val started = outgoingRingback.start(callHandle)
        logRingback(stage = "start", result = if (started) "playing" else "unavailable")
        return started
    }

    private fun stopOutgoingRingback(callHandle: String): Boolean {
        val stopped = outgoingRingback.stop(callHandle)
        if (stopped) logRingback(stage = "stop", result = "stopped")
        return stopped
    }

    /** Native answer/terminal paths silence ringback even if Dart never asks. */
    private fun stopOutgoingRingbackFromLifecycle() {
        if (outgoingRingback.stopAll()) logRingback(stage = "lifecycle", result = "stopped")
    }

    private fun logRingback(stage: String, result: String) {
        android.util.Log.i(
            MKNOON_CALL_RINGBACK_DIAGNOSTIC_TAG,
            "ringback stage=$stage result=$result",
        )
    }

    private fun stopIncomingRingtone(nativeCallId: UUID, stage: String) {
        if (incomingCallRinger.stop(nativeCallId)) {
            logIncomingRingtone(stage = stage, result = "stopped")
        }
    }

    private fun logIncomingRingtone(stage: String, result: String) {
        android.util.Log.i(
            MKNOON_CALL_RINGTONE_DIAGNOSTIC_TAG,
            formatMknoonCallRingtoneDiagnostic(stage, result),
        )
    }

    private fun reconcilePersistedDescriptor() {
        val descriptor = controller.snapshot() ?: return
        val observedNow = System.currentTimeMillis()
        if (shouldAutoDeleteExpiredPersistedCallAtStartup(descriptor, observedNow)) {
            reconcileExpiredDescriptor(descriptor)
            return
        }
        if (descriptor.terminalEvent != null) {
            // Crash repair: terminal custody is the protected source of truth.
            // Backfill the replay fence before Flutter can attach/ack/delete it.
            val fenced = recordTerminalTombstone(
                descriptor.nativeCallId,
                descriptor.expiresAtMs,
            )
            controller.reconcileTerminalFence(fenced)
            if (!fenced) scheduleStartupConvergence(descriptor.nativeCallId, autoDeleteExpired = false)
            return
        }
        if (hasTerminalTombstone(descriptor.nativeCallId, observedNow)) {
            if (!controller.terminate(descriptor.nativeCallId, PendingNativeCallEventType.NATIVE_FAILURE)) {
                scheduleStartupConvergence(descriptor.nativeCallId, autoDeleteExpired = false)
            }
            return
        }
        if (descriptor.handoffAcknowledgement == PendingNativeCallAcknowledgement.ADOPTED) {
            controller.reconcileAdoptedJournal()
            return
        }
        if (descriptor.events.any { it.type == PendingNativeCallEventType.PRESENTED }) {
            controller.reconcilePresented()
            return
        }
        controller.terminate(descriptor.nativeCallId, PendingNativeCallEventType.NATIVE_FAILURE)
    }

    /**
     * A terminal record that reaches a fresh Flutter attachment has no Dart
     * call to end: the call ended natively (decline, expiry) before or without
     * a Dart binding while this process stayed alive. Replaying it would wedge
     * the adapter on a sequence it can never acknowledge (or fail it closed on
     * an expired descriptor), which disables native calling until the process
     * restarts. Settle it here instead, exactly as startup repair does.
     */
    private fun settleUnconsumableTerminalBeforeAttach() {
        val descriptor = controller.snapshot() ?: return
        if (descriptor.terminalEvent == null) return
        if (descriptor.handoffAcknowledgement == PendingNativeCallAcknowledgement.TERMINAL) return
        reconcileExpiredDescriptor(descriptor)
    }

    private fun reconcileExpiredDescriptor(descriptor: PendingNativeCallDescriptor) {
        if (descriptor.terminalEvent == null) {
            controller.terminate(descriptor.nativeCallId, PendingNativeCallEventType.EXPIRED)
        } else {
            val fenced = recordTerminalTombstone(
                descriptor.nativeCallId,
                descriptor.expiresAtMs,
            )
            controller.reconcileTerminalFence(fenced)
        }
        val terminal = controller.snapshot()?.takeIf {
            it.nativeCallId == descriptor.nativeCallId && it.terminalEvent != null
        }
        if (
            terminal == null ||
            !controller.acknowledge(
                terminal.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            )
        ) {
            scheduleStartupConvergence(descriptor.nativeCallId, autoDeleteExpired = true)
        }
    }

    private fun scheduleStartupConvergence(
        nativeCallId: UUID,
        autoDeleteExpired: Boolean,
    ) {
        runtimeScope.launch {
            repeat(STARTUP_CONVERGENCE_ATTEMPTS) {
                delay(STARTUP_CONVERGENCE_RETRY_MS)
                val current = controller.snapshot()?.takeIf { it.nativeCallId == nativeCallId }
                    ?: return@launch
                if (current.terminalEvent == null) {
                    controller.terminate(nativeCallId, PendingNativeCallEventType.NATIVE_FAILURE)
                    return@repeat
                }
                // A prior terminal append may still have incomplete native cleanup.
                controller.terminate(nativeCallId, PendingNativeCallEventType.NATIVE_FAILURE)
                val fenced = recordTerminalTombstone(nativeCallId, current.expiresAtMs)
                controller.reconcileTerminalFence(fenced)
                if (!fenced) return@repeat
                if (autoDeleteExpired) {
                    controller.acknowledge(
                        nativeCallId,
                        current.highestSequence,
                        PendingNativeCallAcknowledgement.TERMINAL,
                    )
                }
                return@launch
            }
        }
    }

    private fun scheduleExpiry(nativeCallId: UUID, expiresAtMs: Long) {
        expiryJobs.remove(nativeCallId)?.cancel()
        expiryJobs[nativeCallId] = runtimeScope.launch {
            delay((expiresAtMs - System.currentTimeMillis()).coerceAtLeast(1L))
            controller.terminate(nativeCallId, PendingNativeCallEventType.EXPIRED)
            expiryJobs.remove(nativeCallId)
        }
    }

    private fun cancelExpiry(nativeCallId: UUID) {
        expiryJobs.remove(nativeCallId)?.cancel()
    }

    private fun scheduleCleanupRetry(nativeCallId: UUID) {
        val existing = cleanupJobs[nativeCallId]
        if (existing?.isActive == true) return
        lateinit var retryJob: Job
        retryJob = runtimeScope.launch(start = CoroutineStart.LAZY) {
            try {
                repeat(CLEANUP_RETRY_ATTEMPTS) {
                    delay(CLEANUP_RETRY_MS)
                    if (controller.retryCleanup(nativeCallId)) return@launch
                }
            } finally {
                cleanupJobs.remove(nativeCallId, retryJob)
            }
        }
        val winner = cleanupJobs.putIfAbsent(nativeCallId, retryJob)
        if (winner == null) retryJob.start() else retryJob.cancel()
    }

    private fun cleanupActiveLifecycle(): Boolean {
        val nativeCallId = controller.activeNativeCallId() ?: return true
        controller.terminate(
            nativeCallId,
            PendingNativeCallEventType.NATIVE_FAILURE,
        )
        return controller.activeNativeCallId() != nativeCallId
    }

    private fun recordTerminalTombstone(nativeCallId: UUID, expiresAtMs: Long): Boolean =
        synchronized(terminalTombstoneLock) {
            val observedNow = System.currentTimeMillis()
            val editor = preferences.edit()
            val retained = preferences.all.entries
                .mapNotNull { (key, value) ->
                    if (!key.startsWith(TERMINAL_TOMBSTONE_PREFIX)) return@mapNotNull null
                    val expiry = value as? Long ?: return@mapNotNull null
                    if (expiry <= observedNow) {
                        editor.remove(key)
                        return@mapNotNull null
                    }
                    key to expiry
                }
                .sortedBy { it.second }
                .toMutableList()
            val key = TERMINAL_TOMBSTONE_PREFIX + nativeCallId
            retained.removeAll { it.first == key }
            if (expiresAtMs > observedNow) {
                while (retained.size >= MAX_TERMINAL_TOMBSTONES) {
                    editor.remove(retained.removeAt(0).first)
                }
                editor.putLong(key, expiresAtMs)
            } else {
                editor.remove(key)
            }
            editor.commit()
        }

    private fun hasTerminalTombstone(nativeCallId: UUID, observedNow: Long): Boolean =
        synchronized(terminalTombstoneLock) {
            val key = TERMINAL_TOMBSTONE_PREFIX + nativeCallId
            val expiresAtMs = preferences.all[key] as? Long ?: 0L
            if (expiresAtMs <= observedNow) {
                if (expiresAtMs != 0L) preferences.edit().remove(key).apply()
                false
            } else {
                true
            }
        }

    private inner class AndroidMknoonCallForegroundRuntime(
        private val service: Service,
    ) : MknoonCallForegroundRuntime {
        private val notifications = MknoonCallNotificationFactory(service)

        override fun isActiveLifecycle(nativeCallId: UUID): Boolean =
            controller.activeNativeCallId() == nativeCallId

        override fun isAudioActive(nativeCallId: UUID): Boolean =
            controller.activeNativeCallId() == nativeCallId && controller.audioState().active

        override fun startAdmission(nativeCallId: UUID) {
            val notification = notifications.createAdmission(nativeCallId)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            } else {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                )
            }
        }

        override fun startRinging(nativeCallId: UUID) {
            val notification = notifications.createIncoming(
                nativeCallId = nativeCallId,
                fullScreenAllowed = false,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            } else {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                )
            }
            val ringtoneResult = coordinateIncomingRingtoneStart(
                nativeCallId = nativeCallId,
                snapshot = controller::snapshot,
                observedNowMs = System::currentTimeMillis,
                start = incomingCallRinger::start,
                stop = ::stopIncomingRingtone,
            )
            logIncomingRingtone(stage = "start", result = ringtoneResult.wireValue)
        }

        override fun startActive(nativeCallId: UUID) {
            stopIncomingRingtone(nativeCallId, "active")
            val notification = notifications.createOngoing(nativeCallId)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                )
            }
        }

        override fun startInactive(nativeCallId: UUID) {
            stopIncomingRingtone(nativeCallId, "inactive")
            val notification = notifications.createOngoing(nativeCallId)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL,
                )
            } else {
                service.startForeground(
                    MknoonCallNotificationFactory.NOTIFICATION_ID,
                    notification,
                )
            }
        }

        override fun stop(nativeCallId: UUID) {
            stopIncomingRingtone(nativeCallId, "stop")
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
            service.stopSelf()
        }

        override fun onStartFailure(nativeCallId: UUID) {
            stopIncomingRingtone(nativeCallId, "start_failure")
            controller.terminate(
                nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
            )
        }

    }
}

/** Actual Core-Telecom and Android system boundary. */
private class AndroidMknoonCallPlatform(
    context: Context,
    private val controller: () -> MknoonCallLifecycleController,
    private val stopIncomingRinger: (UUID) -> Unit,
) : MknoonCallPlatform {
    private val applicationContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val callsManager = CallsManager(applicationContext)
    private val notificationManager =
        applicationContext.getSystemService(NotificationManager::class.java)
    private val notificationFactory = MknoonCallNotificationFactory(applicationContext)
    private val sessions = ConcurrentHashMap<UUID, CallControlScope>()
    private val endpointJobs = ConcurrentHashMap<UUID, Job>()
    private val availableEndpoints = ConcurrentHashMap<UUID, List<CallEndpointCompat>>()
    private val locallyDisconnecting = ConcurrentHashMap.newKeySet<UUID>()
    private val registered = AtomicBoolean(false)

    override fun registerIncoming(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    ) = register(nativeCallId, PendingNativeCallDirection.INCOMING, callback)

    override fun registerOutgoing(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    ) = register(nativeCallId, PendingNativeCallDirection.OUTGOING, callback)

    private fun register(
        nativeCallId: UUID,
        direction: PendingNativeCallDirection,
        callback: MknoonCallRegistrationCallback,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            callback.onFailure()
            return
        }
        if (registered.compareAndSet(false, true)) {
            try {
                callsManager.registerAppWithTelecom(
                    CallsManager.CAPABILITY_BASELINE,
                    Build.VERSION_CODES.TIRAMISU,
                )
            } catch (_: Exception) {
                registered.set(false)
                callback.onFailure()
                return
            }
        }

        val completion = MknoonCallRegistrationWinner()
        val registration = CountDownLatch(1)
        val registeredScope = AtomicReference<CallControlScope?>(null)
        scope.launch {
            try {
                callsManager.addCall(
                    callAttributes(direction),
                    onAnswer = {
                        check(controller().answerFromTelecom(nativeCallId)) {
                            "native answer transition rejected"
                        }
                    },
                    onDisconnect = {
                        if (locallyDisconnecting.contains(nativeCallId)) {
                            emitMknoonTelecomDisconnectDiagnostic(
                                MknoonTelecomDisconnectSource.TELECOM_CALLBACK_LOCAL,
                            )
                        } else {
                            emitMknoonTelecomDisconnectDiagnostic(
                                MknoonTelecomDisconnectSource.TELECOM_CALLBACK_REMOTE,
                            )
                            check(controller().disconnectFromTelecom(nativeCallId)) {
                                "native disconnect transition rejected"
                            }
                        }
                    },
                    onSetActive = {
                        val applied = controller().activateAudioFromTelecom(nativeCallId)
                        if (!applied) {
                            disconnectCallbackScope(
                                nativeCallId,
                                registeredScope.get(),
                                MknoonTelecomDisconnectSource.SET_ACTIVE_REJECTED,
                            )
                        }
                        check(applied) {
                            "native active transition rejected"
                        }
                    },
                    onSetInactive = {
                        val applied = controller().deactivateAudioFromTelecom(nativeCallId)
                        val released = disconnectCallbackScope(
                            nativeCallId,
                            registeredScope.get(),
                            MknoonTelecomDisconnectSource.SET_INACTIVE,
                        )
                        check(applied && released) {
                            "native inactive transition rejected"
                        }
                    },
                ) registered@{
                    if (!completion.claimReady {
                            registeredScope.set(this)
                            sessions[nativeCallId] = this
                        }) {
                        emitMknoonTelecomDisconnectDiagnostic(
                            MknoonTelecomDisconnectSource.LATE_REGISTRATION,
                        )
                        runBlocking {
                            releaseLateTelecomScope {
                                disconnect(
                                    DisconnectCause(DisconnectCause.LOCAL),
                                ) is CallControlResult.Success
                            }
                        }
                        registration.countDown()
                        return@registered
                    }
                    registration.countDown()
                }
            } catch (_: Exception) {
                completion.claimFailure()
                registration.countDown()
            } finally {
                val exactScope = registeredScope.get()
                exactScope?.let {
                    sessions.remove(nativeCallId, exactScope)
                }
                locallyDisconnecting.remove(nativeCallId)
                stopEndpointUpdates(nativeCallId)
                if (exactScope != null && !controller().hasTerminalLifecycle(nativeCallId)) {
                    controller().endFromTelecom(nativeCallId)
                }
            }
        }
        awaitAndDispatchTelecomRegistration(
            completion = completion,
            registration = registration,
            timeoutMs = REGISTRATION_TIMEOUT_MS,
            callback = callback,
        )
    }

    override fun showIncoming(nativeCallId: UUID) {
        val fullScreenAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            notificationManager.canUseFullScreenIntent()
        } else {
            true
        }
        notificationManager.notify(
            MknoonCallNotificationFactory.NOTIFICATION_ID,
            notificationFactory.createIncoming(nativeCallId, fullScreenAllowed),
        )
    }

    private suspend fun disconnectCallbackScope(
        nativeCallId: UUID,
        callScope: CallControlScope?,
        source: MknoonTelecomDisconnectSource,
    ): Boolean {
        emitMknoonTelecomDisconnectDiagnostic(source)
        locallyDisconnecting.add(nativeCallId)
        val released = releaseTelecomCallbackSession {
            callScope?.disconnect(
                DisconnectCause(DisconnectCause.LOCAL),
            ) is CallControlResult.Success
        }
        if (!released) locallyDisconnecting.remove(nativeCallId)
        return released
    }

    override fun startForeground(nativeCallId: UUID) {
        checkNotNull(
            ContextCompat.startForegroundService(
                applicationContext,
                serviceIntent(MknoonCallForegroundService.ACTION_START_RINGING, nativeCallId),
            ),
        )
    }

    override fun answer(nativeCallId: UUID) {
        val session = sessions[nativeCallId] ?: error("call session unavailable")
        val outcome = runBlocking {
            withTimeout(CONTROL_TIMEOUT_MS) {
                session.answer(CallAttributesCompat.CALL_TYPE_AUDIO_CALL)
            }
        }
        check(outcome is CallControlResult.Success) { "Telecom answer rejected" }
    }

    override fun end(nativeCallId: UUID) {
        val session = sessions[nativeCallId] ?: return
        emitMknoonTelecomDisconnectDiagnostic(MknoonTelecomDisconnectSource.EXPLICIT_END)
        locallyDisconnecting.add(nativeCallId)
        val outcome = try {
            runBlocking {
                withTimeout(CONTROL_TIMEOUT_MS) {
                    session.disconnect(DisconnectCause(DisconnectCause.LOCAL))
                }
            }
        } catch (error: Exception) {
            locallyDisconnecting.remove(nativeCallId)
            throw error
        }
        if (outcome !is CallControlResult.Success) {
            locallyDisconnecting.remove(nativeCallId)
            error("Telecom disconnect rejected")
        }
    }

    override fun cancelNotification(nativeCallId: UUID) {
        notificationManager.cancel(MknoonCallNotificationFactory.NOTIFICATION_ID)
    }

    override fun stopForeground(nativeCallId: UUID) {
        checkNotNull(
            applicationContext.startService(
                serviceIntent(MknoonCallForegroundService.ACTION_STOP, nativeCallId),
            ),
        )
    }

    override fun stopIncomingRinger(nativeCallId: UUID) {
        stopIncomingRinger.invoke(nativeCallId)
    }

    override fun requestAudioFocus(nativeCallId: UUID) {
        val session = sessions[nativeCallId] ?: error("call session unavailable")
        val outcome = runBlocking {
            withTimeout(CONTROL_TIMEOUT_MS) { session.setActive() }
        }
        check(outcome is CallControlResult.Success) { "Telecom activation rejected" }
    }

    override fun abandonAudioFocus(nativeCallId: UUID) {
        if (
            controller().hasTerminalLifecycle(nativeCallId) ||
            controller().isCleanupPending(nativeCallId)
        ) {
            return
        }
        val session = sessions[nativeCallId] ?: return
        val outcome = runBlocking {
            withTimeout(CONTROL_TIMEOUT_MS) { session.setInactive() }
        }
        check(outcome is CallControlResult.Success) { "Telecom inactivation rejected" }
    }

    override fun startEndpointUpdates(nativeCallId: UUID) {
        val session = sessions[nativeCallId] ?: return
        endpointJobs.computeIfAbsent(nativeCallId) {
            scope.launch {
                coroutineScope {
                    launch {
                        session.isMuted.collectLatest { muted ->
                            controller().onMuteChanged(nativeCallId, muted)
                        }
                    }
                    launch {
                        session.currentCallEndpoint.collectLatest { endpoint ->
                            controller().onRouteChanged(nativeCallId, endpoint.routeName())
                        }
                    }
                    launch {
                        session.availableEndpoints.collectLatest { endpoints ->
                            availableEndpoints[nativeCallId] = endpoints
                            controller().onAvailableRoutesChanged(
                                nativeCallId,
                                endpoints.map { it.routeName() },
                            )
                        }
                    }
                }
            }
        }
    }

    override fun stopEndpointUpdates(nativeCallId: UUID) {
        endpointJobs.remove(nativeCallId)?.cancel()
        availableEndpoints.remove(nativeCallId)
    }

    override fun startMicrophoneService(nativeCallId: UUID) {
        checkNotNull(
            ContextCompat.startForegroundService(
                applicationContext,
                serviceIntent(MknoonCallForegroundService.ACTION_START_ACTIVE, nativeCallId),
            ),
        )
    }

    override fun stopMicrophoneService(nativeCallId: UUID) {
        checkNotNull(
            applicationContext.startService(
                serviceIntent(MknoonCallForegroundService.ACTION_START_INACTIVE, nativeCallId),
            ),
        )
    }

    override fun requestRoute(nativeCallId: UUID, route: String): Boolean {
        val session = sessions[nativeCallId] ?: return false
        val endpoint = selectCallEndpointForRoute(
            availableEndpoints[nativeCallId],
            route,
        ) { it.type }
            ?: return false
        val outcome = try {
            runBlocking {
                withTimeout(CONTROL_TIMEOUT_MS) { session.requestEndpointChange(endpoint) }
            }
        } catch (_: Exception) {
            return false
        }
        if (outcome !is CallControlResult.Success) return false
        controller().onRouteChanged(nativeCallId, route)
        return true
    }

    override fun project(nativeCallId: UUID, state: String): Boolean {
        val notification = when (state) {
            "ringing" -> notificationFactory.createIncoming(nativeCallId, fullScreenAllowed = false)
            "accepted", "active", "inactive" -> notificationFactory.createOngoing(nativeCallId)
            else -> return false
        }
        notificationManager.notify(MknoonCallNotificationFactory.NOTIFICATION_ID, notification)
        return true
    }

    private fun callAttributes(
        direction: PendingNativeCallDirection,
    ): CallAttributesCompat = CallAttributesCompat(
        displayName = "MKnoon call",
        address = Uri.parse("sip:mknoon"),
        direction = coreTelecomDirection(direction),
        callType = CallAttributesCompat.CALL_TYPE_AUDIO_CALL,
        callCapabilities = CallAttributesCompat.SUPPORTS_SET_INACTIVE,
        preferredStartingCallEndpoint = null,
        isLogExcluded = true,
    )

    private fun serviceIntent(action: String, nativeCallId: UUID): Intent =
        Intent(applicationContext, MknoonCallForegroundService::class.java)
            .setAction(action)
            .putExtra(
                MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID,
                nativeCallId.toString(),
            )

    private fun CallEndpointCompat.routeName(): String = canonicalCallRoute(type)

    private companion object {
        const val REGISTRATION_TIMEOUT_MS = 4_000L
        const val CONTROL_TIMEOUT_MS = 4_000L
    }

}

internal fun coreTelecomDirection(direction: PendingNativeCallDirection): Int =
    when (direction) {
        PendingNativeCallDirection.INCOMING -> CallAttributesCompat.DIRECTION_INCOMING
        PendingNativeCallDirection.OUTGOING -> CallAttributesCompat.DIRECTION_OUTGOING
    }

internal fun canonicalCallRoute(endpointType: Int): String = when (endpointType) {
    CallEndpointCompat.TYPE_EARPIECE -> "earpiece"
    CallEndpointCompat.TYPE_BLUETOOTH -> "bluetooth"
    CallEndpointCompat.TYPE_WIRED_HEADSET -> "wired_headset"
    CallEndpointCompat.TYPE_SPEAKER -> "speaker"
    CallEndpointCompat.TYPE_STREAMING -> "system_default"
    else -> "system_default"
}

internal fun <T> selectCallEndpointForRoute(
    endpoints: List<T>?,
    route: String,
    endpointType: (T) -> Int,
): T? {
    if (route !in CANONICAL_NATIVE_CALL_ROUTES) return null
    return endpoints?.firstOrNull { canonicalCallRoute(endpointType(it)) == route }
}

internal class MknoonCallRegistrationWinner {
    private val winner = AtomicReference<Outcome?>(null)

    fun claimReady(): Boolean = claimReady {}

    fun claimReady(publish: () -> Unit): Boolean = synchronized(winner) {
        if (winner.get() != null) return@synchronized false
        publish()
        winner.set(Outcome.READY)
        true
    }

    fun claimTimeout(): Boolean = synchronized(winner) {
        if (winner.get() != null) return@synchronized false
        winner.set(Outcome.TIMED_OUT)
        true
    }

    fun claimFailure(): Boolean = synchronized(winner) {
        if (winner.get() != null) return@synchronized false
        winner.set(Outcome.FAILED)
        true
    }

    fun outcome(): Outcome? = winner.get()

    internal enum class Outcome {
        READY,
        TIMED_OUT,
        FAILED,
    }
}

internal fun awaitAndDispatchTelecomRegistration(
    completion: MknoonCallRegistrationWinner,
    registration: CountDownLatch,
    timeoutMs: Long,
    callback: MknoonCallRegistrationCallback,
): MknoonCallRegistrationWinner.Outcome {
    val signaled = try {
        registration.await(timeoutMs, TimeUnit.MILLISECONDS)
    } catch (_: InterruptedException) {
        Thread.currentThread().interrupt()
        false
    }
    if (!signaled) completion.claimTimeout()
    val outcome = checkNotNull(completion.outcome()) {
        "registration signal observed without a terminal outcome"
    }
    when (outcome) {
        MknoonCallRegistrationWinner.Outcome.READY -> callback.onRegistered()
        MknoonCallRegistrationWinner.Outcome.TIMED_OUT,
        MknoonCallRegistrationWinner.Outcome.FAILED,
        -> callback.onRegistrationAbandoned()
    }
    return outcome
}

internal suspend fun releaseTelecomCallbackSession(
    attempts: Int = 1,
    disconnect: suspend () -> Boolean,
): Boolean {
    if (attempts !in 1..3) return false
    repeat(attempts) { attempt ->
        val released = try {
            // Keep the terminal-ACK wait plus provider release below Telecom's
            // 5s callback budget. Durable terminal custody survives failure.
            withTimeout(750L) { disconnect() }
        } catch (_: Throwable) {
            false
        }
        if (released) return true
        if (attempt + 1 < attempts) delay(50L)
    }
    return false
}

internal suspend fun releaseLateTelecomScope(
    disconnect: suspend () -> Boolean,
) {
    check(
        releaseTelecomCallbackSession(
            attempts = 3,
            disconnect = disconnect,
        ),
    ) { "late Telecom scope release rejected" }
}

internal fun presentAuthenticatedCall(
    callHandle: String,
    expiresAtMs: Long,
    observedNowMs: Long,
    capabilityEnabled: Boolean,
    handleGrammar: Regex,
    wakeHandle: () -> String,
    present: (CallWakePayload) -> MknoonCallPresentationResult,
): Boolean {
    if (
        !capabilityEnabled ||
        observedNowMs < 0L ||
        expiresAtMs <= observedNowMs ||
        expiresAtMs - observedNowMs > CallPayloadParser.MAX_FUTURE_SKEW_MS ||
        !handleGrammar.matches(callHandle)
    ) {
        return false
    }
    val nativeCallId = runCatching { UUID.fromString(callHandle) }.getOrNull()
        ?: return false
    val generatedWakeHandle = runCatching(wakeHandle).getOrNull()
        ?.takeIf(CALL_RANDOM_ID::matches)
        ?: return false
    return when (
        present(
            CallWakePayload(
                nativeCallId = nativeCallId,
                callHandle = callHandle,
                wakeHandle = generatedWakeHandle,
                receivedAtMs = observedNowMs,
                expiresAtMs = expiresAtMs,
            ),
        )
    ) {
        MknoonCallPresentationResult.PRESENTED,
        MknoonCallPresentationResult.DUPLICATE,
        -> true
        else -> false
    }
}

internal fun terminalizeAuthenticatedCall(
    callHandle: String,
    expiresAtMs: Long,
    observedNowMs: Long,
    capabilityEnabled: Boolean,
    handleGrammar: Regex,
    terminalize: (UUID, Long) -> Boolean,
): Boolean {
    if (
        !capabilityEnabled ||
        observedNowMs < 0L ||
        expiresAtMs <= observedNowMs ||
        expiresAtMs - observedNowMs > CallPayloadParser.MAX_FUTURE_SKEW_MS ||
        !handleGrammar.matches(callHandle)
    ) {
        return false
    }
    val nativeCallId = runCatching { UUID.fromString(callHandle) }.getOrNull()
        ?.takeIf { it.toString() == callHandle }
        ?: return false
    return runCatching { terminalize(nativeCallId, expiresAtMs) }.getOrDefault(false)
}

internal fun executeFailClosed(
    persistDisable: () -> Boolean,
    cleanup: () -> Boolean,
): Boolean {
    val disabled = runCatching(persistDisable).getOrDefault(false)
    val cleaned = runCatching(cleanup).getOrDefault(false)
    return disabled && cleaned
}
