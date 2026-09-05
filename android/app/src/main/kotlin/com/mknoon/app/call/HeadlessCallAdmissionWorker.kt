package com.mknoon.app.call

import android.app.Notification
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.davidmartos96.sqflite_sqlcipher.SqfliteSqlCipherPlugin
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import com.mknoon.app.CanonicalRuntimeLeaseBridge
import com.mknoon.app.CanonicalRuntimeLeaseBroker
import com.mknoon.app.GoBridge
import com.mknoon.app.MknoonFirebaseMessagingService
import com.mknoon.app.ProcessCanonicalRuntimeLease
import com.mknoon.app.ProcessGoRuntimeHost
import com.mknoon.app.R
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.pathprovider.PathProviderPlugin
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

internal enum class HeadlessCallAdmissionDisposition {
    ADMITTED,
    TERMINAL,
    PERMANENT_REJECT,
    EMPTY_OR_ALREADY_ACKED,
    DEFERRED,
}

/**
 * What one headless run is asked to do. Admission presents an authenticated
 * invite; the decline reply (plan 404) answers a call declined natively while
 * no Dart owner existed to send the caller its reject.
 */
internal enum class HeadlessCallAdmissionMode(val wireName: String) {
    ADMISSION("admission"),
    DECLINE_REPLY("decline_reply"),
    ;

    companion object {
        fun fromWireName(value: String?): HeadlessCallAdmissionMode? =
            entries.firstOrNull { it.wireName == value }
    }
}

internal data class HeadlessCallAdmissionCompletion(
    val nonce: String,
    val callId: String,
    val wakeHandle: String,
    val expiresAtMs: Long,
    val disposition: HeadlessCallAdmissionDisposition,
    val requiredPersistenceComplete: Boolean,
    val databaseClosed: Boolean,
    val leaseReleased: Boolean,
)

internal data class HeadlessCallAdmissionRunIdentity(
    val nonce: String,
    val callId: String,
    val wakeHandle: String,
    val expiresAtMs: Long,
    val mode: HeadlessCallAdmissionMode = HeadlessCallAdmissionMode.ADMISSION,
)

/** Strict, fixed-shape Dart-to-native admission result. */
internal object HeadlessCallAdmissionCompletionProtocol {
    private val RESULT_KEYS = setOf(
        "nonce",
        "callId",
        "wakeHandle",
        "expiresAtMs",
        "disposition",
        "requiredPersistenceComplete",
        "databaseClosed",
        "leaseReleased",
    )

    fun parse(
        method: String,
        arguments: Any?,
        expected: HeadlessCallAdmissionRunIdentity,
    ): HeadlessCallAdmissionCompletion? {
        if (method != "complete") return null
        val values = arguments as? Map<*, *> ?: return null
        if (values.keys != RESULT_KEYS) return null
        val expiresAtMs = positiveIntegralLong(values["expiresAtMs"])
            ?: return null
        if (
            values["nonce"] != expected.nonce ||
            values["callId"] != expected.callId ||
            values["wakeHandle"] != expected.wakeHandle ||
            expiresAtMs != expected.expiresAtMs
        ) {
            return null
        }
        val disposition = when (values["disposition"] as? String) {
            "admitted" -> HeadlessCallAdmissionDisposition.ADMITTED
            "terminal" -> HeadlessCallAdmissionDisposition.TERMINAL
            "permanent_reject" -> HeadlessCallAdmissionDisposition.PERMANENT_REJECT
            "empty_or_already_acked" ->
                HeadlessCallAdmissionDisposition.EMPTY_OR_ALREADY_ACKED
            "deferred" -> HeadlessCallAdmissionDisposition.DEFERRED
            else -> return null
        }
        return HeadlessCallAdmissionCompletion(
            nonce = expected.nonce,
            callId = expected.callId,
            wakeHandle = expected.wakeHandle,
            expiresAtMs = expected.expiresAtMs,
            disposition = disposition,
            requiredPersistenceComplete =
                values["requiredPersistenceComplete"] as? Boolean ?: return null,
            databaseClosed = values["databaseClosed"] as? Boolean ?: return null,
            leaseReleased = values["leaseReleased"] as? Boolean ?: return null,
        )
    }

    private fun positiveIntegralLong(value: Any?): Long? = when (value) {
        is Byte -> value.toLong().takeIf { it > 0L }
        is Short -> value.toLong().takeIf { it > 0L }
        is Int -> value.toLong().takeIf { it > 0L }
        is Long -> value.takeIf { it > 0L }
        else -> null
    }
}

/** Accepts one completion for one random native invocation nonce. */
internal class HeadlessCallAdmissionCompletionGate(
    private val expected: HeadlessCallAdmissionRunIdentity,
) {
    private var accepted = false

    fun accept(
        method: String,
        arguments: Any?,
    ): HeadlessCallAdmissionCompletion? {
        if (accepted) return null
        val parsed = HeadlessCallAdmissionCompletionProtocol.parse(
            method = method,
            arguments = arguments,
            expected = expected,
        ) ?: return null
        accepted = true
        return parsed
    }
}

/**
 * Releases only this headless engine. A newly attached foreground owner may
 * legitimately make the process-wide brokers ACTIVE again after this owner
 * has released, so global RELEASED state alone is not a safe destruction
 * fence.
 */
internal object HeadlessCallAdmissionDestructionPolicy {
    fun mayDestroy(
        completion: HeadlessCallAdmissionCompletion?,
        leaseOwnerId: String?,
        currentLeaseOwnerId: String?,
        goOwnerId: String?,
        currentGoOwnerId: String?,
    ): Boolean = completion?.databaseClosed == true &&
        completion.leaseReleased &&
        leaseOwnerId != null &&
        goOwnerId != null &&
        currentLeaseOwnerId != leaseOwnerId &&
        currentGoOwnerId != goOwnerId
}

internal fun interface HeadlessCallAdmissionWorkEnqueuer {
    fun enqueueUnique(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    )
}

private class AndroidXHeadlessCallAdmissionWorkEnqueuer(
    context: Context,
) : HeadlessCallAdmissionWorkEnqueuer {
    private val applicationContext = context.applicationContext

    override fun enqueueUnique(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(uniqueName, policy, request)
    }
}

/** Turns one already-strict opaque wake into one identity-keyed admission job. */
internal class HeadlessCallAdmissionWorkScheduler(
    context: Context,
    private val enqueuer: HeadlessCallAdmissionWorkEnqueuer =
        AndroidXHeadlessCallAdmissionWorkEnqueuer(context),
    private val nowMs: () -> Long = System::currentTimeMillis,
) {
    companion object {
        internal const val INPUT_CALL_ID = "call_id"
        internal const val INPUT_WAKE_HANDLE = "wake_handle"
        internal const val INPUT_EXPIRES_AT_MS = "expires_at_ms"
        internal const val INPUT_MODE = "mode"
        private const val UNIQUE_PREFIX = "mknoon-headless-call-admission-"
        private const val WORK_TAG = "mknoon-headless-call-admission"

        internal fun uniqueName(callId: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(callId.toByteArray(StandardCharsets.UTF_8))
                .joinToString(separator = "") { byte ->
                    "%02x".format(byte.toInt() and 0xff)
                }
            return UNIQUE_PREFIX + digest.take(32)
        }
    }

    fun enqueue(payload: CallWakePayload): Boolean {
        val observedNow = runCatching(nowMs).getOrNull() ?: return false
        if (!isValidPayload(payload, observedNow)) return false
        val callId = payload.nativeCallId.toString()
        val request = OneTimeWorkRequestBuilder<HeadlessCallAdmissionWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setInputData(
                Data.Builder()
                    .putString(INPUT_CALL_ID, callId)
                    .putString(INPUT_WAKE_HANDLE, payload.wakeHandle)
                    .putLong(INPUT_EXPIRES_AT_MS, payload.expiresAtMs)
                    .build(),
            )
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(WORK_TAG)
            .build()
        return runCatching {
            enqueuer.enqueueUnique(
                uniqueName(callId),
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
            true
        }.getOrDefault(false)
    }

    /**
     * Plan 404: a natively declined call without a Dart owner. One decline-reply
     * run for the same call, serialized behind any admission job of that call
     * (same unique name, APPEND_OR_REPLACE) and carrying the mode as one extra
     * input key plus the descriptor's own wake handle and expiry.
     */
    fun enqueueDeclineReply(descriptor: PendingNativeCallDescriptor): Boolean {
        val observedNow = runCatching(nowMs).getOrNull() ?: return false
        val callId = descriptor.nativeCallId.toString()
        if (
            observedNow < 0L ||
            descriptor.callHandle != callId ||
            !CANONICAL_CALL_HANDLE.matches(callId) ||
            !CALL_RANDOM_ID.matches(descriptor.wakeHandle) ||
            descriptor.expiresAtMs <= observedNow ||
            descriptor.expiresAtMs - observedNow > CallPayloadParser.MAX_FUTURE_SKEW_MS
        ) {
            return false
        }
        val request = OneTimeWorkRequestBuilder<HeadlessCallAdmissionWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setInputData(
                Data.Builder()
                    .putString(INPUT_CALL_ID, callId)
                    .putString(INPUT_WAKE_HANDLE, descriptor.wakeHandle)
                    .putLong(INPUT_EXPIRES_AT_MS, descriptor.expiresAtMs)
                    .putString(INPUT_MODE, HeadlessCallAdmissionMode.DECLINE_REPLY.wireName)
                    .build(),
            )
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(WORK_TAG)
            .build()
        return runCatching {
            enqueuer.enqueueUnique(
                uniqueName(callId),
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                request,
            )
            true
        }.getOrDefault(false)
    }

    private fun isValidPayload(payload: CallWakePayload, observedNow: Long): Boolean {
        if (observedNow < 0L) return false
        val callId = payload.nativeCallId.toString()
        return payload.callHandle == callId &&
            CANONICAL_CALL_HANDLE.matches(callId) &&
            CALL_RANDOM_ID.matches(payload.wakeHandle) &&
            payload.receivedAtMs >= 0L &&
            payload.expiresAtMs > payload.receivedAtMs &&
            payload.expiresAtMs - payload.receivedAtMs <=
                CallPayloadParser.MAX_FUTURE_SKEW_MS &&
            payload.expiresAtMs > observedNow &&
            payload.expiresAtMs - observedNow <= CallPayloadParser.MAX_FUTURE_SKEW_MS
    }
}

internal interface HeadlessCallAdmissionEngineRunner {
    suspend fun run(
        identity: HeadlessCallAdmissionRunIdentity,
    ): HeadlessCallAdmissionCompletion

    fun requestStop()

    /** True only when the engine and both native bridges were safely released. */
    suspend fun finish(): Boolean
}

internal enum class HeadlessCallAdmissionWorkOutcome {
    PRESENTED,
    COMPLETED_WITHOUT_PRESENTATION,
}

/**
 * Mechanical worker policy only: Dart owns authentication and custody; the
 * existing native call runtime remains the sole presentation state machine.
 */
internal class HeadlessCallAdmissionExecution(
    private val runnerFactory: () -> HeadlessCallAdmissionEngineRunner,
    private val isStopped: () -> Boolean,
    private val nowMs: () -> Long,
    private val timeoutMillis: Long,
    private val nonceFactory: () -> String = { UUID.randomUUID().toString() },
    private val presentAuthenticated: suspend (String, Long) -> Boolean,
    private val terminalizeAuthenticated: suspend (String, Long) -> Boolean,
    /**
     * Plan 404 (c): the decline reply runs under the call foreground service
     * started by the native decline; released once the engine is finished,
     * whatever Dart reported.
     */
    private val releaseDeclineReply: suspend (String) -> Unit = {},
) {
    private val lock = Any()
    private val stopRequested = AtomicBoolean(false)
    private var activeRunner: HeadlessCallAdmissionEngineRunner? = null

    init {
        require(timeoutMillis > 0L) { "timeoutMillis must be positive" }
    }

    suspend fun execute(
        inputData: Data,
        runAttemptCount: Int = 0,
    ): HeadlessCallAdmissionWorkOutcome {
        if (runAttemptCount != 0 || stopRequested.get() || isStopped()) {
            return noPresentation()
        }
        val observedNow = runCatching(nowMs).getOrNull() ?: return noPresentation()
        val invocation = parseInput(inputData, observedNow) ?: return noPresentation()
        val nonce = runCatching(nonceFactory).getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: return noPresentation()
        val identity = HeadlessCallAdmissionRunIdentity(
            nonce = nonce,
            callId = invocation.callId,
            wakeHandle = invocation.wakeHandle,
            expiresAtMs = invocation.expiresAtMs,
            mode = invocation.mode,
        )
        val runner = runCatching(runnerFactory).getOrNull() ?: return noPresentation()
        synchronized(lock) { activeRunner = runner }

        var completion: HeadlessCallAdmissionCompletion? = null
        try {
            if (stopRequested.get() || isStopped()) {
                runner.requestStop()
            } else {
                val remainingMillis = invocation.expiresAtMs - observedNow
                completion = withTimeout(minOf(timeoutMillis, remainingMillis)) {
                    runner.run(identity)
                }
            }
        } catch (_: TimeoutCancellationException) {
            runner.requestStop()
        } catch (_: Throwable) {
            runner.requestStop()
        }

        val safelyReleased = try {
            withContext(NonCancellable) { runner.finish() }
        } catch (_: Throwable) {
            false
        } finally {
            synchronized(lock) {
                if (activeRunner === runner) activeRunner = null
            }
        }
        if (identity.mode == HeadlessCallAdmissionMode.DECLINE_REPLY) {
            // The reply run never presents or terminalizes: the native call
            // already ended when the user declined it.
            runCatching { releaseDeclineReply(identity.callId) }
            return noPresentation()
        }
        val authenticated = completion?.takeIf {
            it.nonce == identity.nonce &&
                it.callId == identity.callId &&
                it.wakeHandle == identity.wakeHandle &&
                it.expiresAtMs == identity.expiresAtMs &&
                it.requiredPersistenceComplete &&
                it.databaseClosed &&
                it.leaseReleased
        } ?: return noPresentation()
        if (!safelyReleased || stopRequested.get() || isStopped()) {
            return noPresentation()
        }
        val presentationNow = runCatching(nowMs).getOrNull() ?: return noPresentation()
        if (presentationNow < 0L || authenticated.expiresAtMs <= presentationNow) {
            return noPresentation()
        }

        return when (authenticated.disposition) {
            HeadlessCallAdmissionDisposition.ADMITTED -> {
                val presented = try {
                    presentAuthenticated(authenticated.callId, authenticated.expiresAtMs)
                } catch (_: Throwable) {
                    false
                }
                if (presented) {
                    HeadlessCallAdmissionWorkOutcome.PRESENTED
                } else {
                    noPresentation()
                }
            }

            HeadlessCallAdmissionDisposition.TERMINAL -> {
                try {
                    terminalizeAuthenticated(
                        authenticated.callId,
                        authenticated.expiresAtMs,
                    )
                } catch (_: Throwable) {
                    false
                }
                noPresentation()
            }

            HeadlessCallAdmissionDisposition.PERMANENT_REJECT,
            HeadlessCallAdmissionDisposition.EMPTY_OR_ALREADY_ACKED,
            HeadlessCallAdmissionDisposition.DEFERRED,
            -> noPresentation()
        }
    }

    fun requestStop() {
        stopRequested.set(true)
        synchronized(lock) { activeRunner }?.requestStop()
    }

    private data class Invocation(
        val callId: String,
        val wakeHandle: String,
        val expiresAtMs: Long,
        val mode: HeadlessCallAdmissionMode,
    )

    private fun parseInput(inputData: Data, observedNow: Long): Invocation? {
        val admissionKeys = setOf(
            HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID,
            HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE,
            HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS,
        )
        val mode = when (inputData.keyValueMap.keys) {
            admissionKeys -> HeadlessCallAdmissionMode.ADMISSION
            admissionKeys + HeadlessCallAdmissionWorkScheduler.INPUT_MODE ->
                HeadlessCallAdmissionMode.fromWireName(
                    inputData.getString(HeadlessCallAdmissionWorkScheduler.INPUT_MODE),
                )?.takeIf { it != HeadlessCallAdmissionMode.ADMISSION } ?: return null
            else -> return null
        }
        if (observedNow < 0L) return null
        val callId = inputData.getString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID)
            ?: return null
        val wakeHandle = inputData.getString(
            HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE,
        ) ?: return null
        val expiresAtMs = inputData.keyValueMap[
            HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS
        ] as? Long ?: return null
        if (
            !CANONICAL_CALL_HANDLE.matches(callId) ||
            runCatching { UUID.fromString(callId).toString() }.getOrNull() != callId ||
            !CALL_RANDOM_ID.matches(wakeHandle) ||
            expiresAtMs <= observedNow ||
            expiresAtMs - observedNow > CallPayloadParser.MAX_FUTURE_SKEW_MS
        ) {
            return null
        }
        return Invocation(callId, wakeHandle, expiresAtMs, mode)
    }

    private fun noPresentation() =
        HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION
}

/** WorkManager production boundary; every terminal outcome is fail-closed. */
internal class HeadlessCallAdmissionWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    companion object {
        internal const val FOREGROUND_NOTIFICATION_ID = 331
        private const val WORK_TIMEOUT_MILLIS = 20_000L

        @Suppress("DEPRECATION")
        internal fun createForegroundInfo(context: Context): ForegroundInfo {
            MknoonFirebaseMessagingService.ensureRecoveryNotificationChannel(context)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(
                    context,
                    MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID,
                )
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(
                    context.getString(R.string.dropped_push_recovery_notification_title),
                )
                .setContentText(context.getString(R.string.dropped_push_recovery_worker_body))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setSound(null)
                .setVibrate(null)
                .setDefaults(0)
                .apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setGroup(MknoonFirebaseMessagingService.SILENT_RECOVERY_GROUP_KEY)
                        setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
                    }
                }
                .build()
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ForegroundInfo(
                    FOREGROUND_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                ForegroundInfo(FOREGROUND_NOTIFICATION_ID, notification)
            }
        }
    }

    private val execution by lazy {
        HeadlessCallAdmissionExecution(
            runnerFactory = {
                FlutterHeadlessCallAdmissionEngineRunner(applicationContext)
            },
            isStopped = { isStopped },
            nowMs = System::currentTimeMillis,
            timeoutMillis = WORK_TIMEOUT_MILLIS,
            // The runtime (and its Flutter channel) must be created on main.
            // Presentation itself waits on the Telecom registration callback,
            // which below API 34 arrives on the main looper, so it runs off it.
            presentAuthenticated = { callId, expiresAtMs ->
                val runtime = withContext(Dispatchers.Main.immediate) {
                    MknoonCallRuntime.get(applicationContext)
                }
                withContext(Dispatchers.Default) {
                    runtime.presentAuthenticated(callId, expiresAtMs)
                }
            },
            terminalizeAuthenticated = { callId, expiresAtMs ->
                val runtime = withContext(Dispatchers.Main.immediate) {
                    MknoonCallRuntime.get(applicationContext)
                }
                withContext(Dispatchers.Default) {
                    runtime.terminalizeAuthenticated(callId, expiresAtMs)
                }
            },
            releaseDeclineReply = { callId ->
                withContext(Dispatchers.Main.immediate) {
                    MknoonCallRuntime.get(applicationContext).stopAdmissionForeground(callId)
                }
            },
        )
    }

    override fun getForegroundInfoAsync(): ListenableFuture<ForegroundInfo> =
        Futures.immediateFuture(createForegroundInfo(applicationContext))

    override fun doWork(): Result = runBlocking {
        execution.execute(inputData, runAttemptCount)
        Result.success()
    }

    override fun onStopped() {
        execution.requestStop()
        super.onStopped()
    }
}

/** One retained owner prevents a timeout from starting a successor engine. */
private object ProcessHeadlessCallAdmissionEngine {
    private val lock = Any()
    private var owner: FlutterHeadlessCallAdmissionEngineRunner? = null

    fun claim(candidate: FlutterHeadlessCallAdmissionEngineRunner): Boolean =
        synchronized(lock) {
            if (owner != null) return@synchronized false
            owner = candidate
            true
        }

    fun release(candidate: FlutterHeadlessCallAdmissionEngineRunner) {
        synchronized(lock) {
            if (owner === candidate) owner = null
        }
    }
}

/** Minimal non-UI engine with the canonical lease and Go-runtime custody. */
private class FlutterHeadlessCallAdmissionEngineRunner(
    context: Context,
) : HeadlessCallAdmissionEngineRunner {
    companion object {
        private const val CHANNEL_NAME = "mknoon/headless_call_admission"
        private const val CLEANUP_POLL_DELAY_MILLIS = 25L
        private const val MAX_CLEANUP_POLLS = 80
    }

    private val applicationContext = context.applicationContext
    private val completion = CompletableDeferred<HeadlessCallAdmissionCompletion>()
    private val stopRequested = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var resultChannel: MethodChannel? = null
    private var leaseBridge: CanonicalRuntimeLeaseBridge? = null
    private var goBridge: GoBridge? = null
    private var lastCompletion: HeadlessCallAdmissionCompletion? = null
    private var leaseOwnerId: String? = null
    private var goOwnerId: String? = null
    private var claimed = false
    private var dartStarted = false
    private var cleanedUp = false
    private var cleanupPollScheduled = false
    private var cleanupPollAttempts = 0

    private val cleanupPoll = object : Runnable {
        override fun run() {
            cleanupPollScheduled = false
            maybeCleanupRetainedOnMain()
        }
    }

    override suspend fun run(
        identity: HeadlessCallAdmissionRunIdentity,
    ): HeadlessCallAdmissionCompletion {
        withContext(Dispatchers.Main.immediate) {
            startOnMain(identity)
        }
        return completion.await()
    }

    private fun startOnMain(identity: HeadlessCallAdmissionRunIdentity) {
        check(Looper.myLooper() == Looper.getMainLooper())
        check(engine == null) { "headless call admission engine already started" }
        if (!ProcessHeadlessCallAdmissionEngine.claim(this)) {
            throw IllegalStateException("headless call admission engine is retained")
        }
        claimed = true
        val created = FlutterEngine(applicationContext, null, false)
        engine = created
        val engineIdentity = System.identityHashCode(created)
        leaseOwnerId = "headless-call-admission-$engineIdentity"
        goOwnerId = "flutter-engine-$engineIdentity"
        registerAllowlistedPlugins(created)
        leaseBridge = CanonicalRuntimeLeaseBridge(
            messenger = created.dartExecutor.binaryMessenger,
            ownerId = checkNotNull(leaseOwnerId),
            role = CanonicalRuntimeLeaseBroker.Role.RECOVERY,
            attachRuntimeOwner = {
                if (goBridge == null) {
                    goBridge = runCatching {
                        GoBridge(created, applicationContext)
                    }.getOrNull()
                }
                goBridge != null
            },
            beginRuntimeDrain = { goBridge?.requestRuntimeDrain() ?: true },
            isRuntimeReleased = { goBridge?.isRuntimeReleased() ?: true },
        )
        resultChannel = MethodChannel(
            created.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            val completionGate = HeadlessCallAdmissionCompletionGate(identity)
            channel.setMethodCallHandler { call, result ->
                val parsed = completionGate.accept(call.method, call.arguments)
                if (parsed == null) {
                    result.error(
                        "invalid_completion",
                        "headless call admission returned an invalid or duplicate result",
                        null,
                    )
                } else {
                    lastCompletion = parsed
                    completion.complete(parsed)
                    result.success(null)
                    maybeCleanupRetainedOnMain()
                }
            }
        }
        val loader = FlutterInjector.instance().flutterLoader()
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "androidHeadlessCallAdmissionMain",
        )
        created.dartExecutor.executeDartEntrypoint(
            entrypoint,
            buildList {
                add(identity.nonce)
                add(identity.callId)
                add(identity.wakeHandle)
                add(identity.expiresAtMs.toString())
                if (identity.mode == HeadlessCallAdmissionMode.DECLINE_REPLY) {
                    add(identity.mode.wireName)
                }
            },
        )
        dartStarted = true
        if (stopRequested.get()) postCancelOnMain()
    }

    override fun requestStop() {
        if (!stopRequested.compareAndSet(false, true)) return
        postCancelOnMain()
    }

    private fun postCancelOnMain() {
        mainHandler.post { resultChannel?.invokeMethod("cancel", null) }
    }

    override suspend fun finish(): Boolean = withContext(Dispatchers.Main.immediate) {
        if (!dartStarted || canDestroyOnMain()) {
            cleanupOnMain()
        } else {
            maybeCleanupRetainedOnMain()
        }
        cleanedUp
    }

    private fun canDestroyOnMain(): Boolean {
        check(Looper.myLooper() == Looper.getMainLooper())
        return HeadlessCallAdmissionDestructionPolicy.mayDestroy(
            completion = lastCompletion,
            leaseOwnerId = leaseOwnerId,
            currentLeaseOwnerId = ProcessCanonicalRuntimeLease.broker.snapshot().ownerId,
            goOwnerId = goOwnerId,
            currentGoOwnerId = ProcessGoRuntimeHost.instance.snapshot().ownerId,
        )
    }

    private fun maybeCleanupRetainedOnMain() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (cleanedUp) return
        if (canDestroyOnMain()) {
            cleanupOnMain()
            return
        }
        val reported = lastCompletion
        if (
            reported?.databaseClosed == true &&
            reported.leaseReleased &&
            !cleanupPollScheduled &&
            cleanupPollAttempts < MAX_CLEANUP_POLLS
        ) {
            cleanupPollAttempts += 1
            cleanupPollScheduled = true
            mainHandler.postDelayed(cleanupPoll, CLEANUP_POLL_DELAY_MILLIS)
        }
    }

    private fun cleanupOnMain() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (cleanedUp) return
        cleanedUp = true
        cleanupPollScheduled = false
        mainHandler.removeCallbacks(cleanupPoll)
        resultChannel?.setMethodCallHandler(null)
        resultChannel = null
        leaseBridge?.dispose()
        leaseBridge = null
        goBridge?.dispose()
        goBridge = null
        engine?.destroy()
        engine = null
        leaseOwnerId = null
        goOwnerId = null
        if (claimed) {
            claimed = false
            ProcessHeadlessCallAdmissionEngine.release(this)
        }
    }

    private fun registerAllowlistedPlugins(engine: FlutterEngine) {
        engine.plugins.add(FlutterSecureStoragePlugin())
        engine.plugins.add(SqfliteSqlCipherPlugin())
        engine.plugins.add(PathProviderPlugin())
    }
}
