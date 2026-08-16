package com.mknoon.app

import android.app.Notification
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.work.Data
import androidx.work.ForegroundInfo
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.davidmartos96.sqflite_sqlcipher.SqfliteSqlCipherPlugin
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingPlugin
import io.flutter.plugins.pathprovider.PathProviderPlugin
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

internal data class HeadlessCanonicalRecoveryStartSnapshot(
    val reason: String,
    val binding: String,
    val pendingRecovery: DroppedPushRecoveryStore.PendingRecovery?,
)

internal enum class HeadlessCanonicalRecoveryDisposition {
    SUCCEEDED,
    RETRY,
    STALE,
}

internal data class HeadlessCanonicalRecoveryCompletion(
    val disposition: HeadlessCanonicalRecoveryDisposition,
    val databaseClosed: Boolean,
    val leaseReleased: Boolean,
    val failureReason: String? = null,
)

internal data class HeadlessCanonicalRecoveryRunIdentity(
    val nonce: String,
    val reason: String,
    val binding: String,
    val generation: Long?,
)

/** Strictly binds a Dart completion to the one native work invocation. */
internal object HeadlessCanonicalRecoveryCompletionProtocol {
    fun parse(
        arguments: Any?,
        method: String,
        expected: HeadlessCanonicalRecoveryRunIdentity,
    ): HeadlessCanonicalRecoveryCompletion? {
        val values = arguments as? Map<*, *> ?: return null
        if (!values.containsKey("generation")) return null
        val echoedGeneration = values["generation"]
        val generationMatches = if (expected.generation == null) {
            echoedGeneration == null
        } else {
            positiveIntegralLong(echoedGeneration) == expected.generation
        }
        if (
            values["nonce"] != expected.nonce ||
            values["reason"] != expected.reason ||
            values["binding"] != expected.binding ||
            !generationMatches
        ) {
            return null
        }
        val rawDisposition = values["disposition"] as? String
        if (method == "failed" && rawDisposition != "retry") return null
        val disposition = when (rawDisposition) {
            "succeeded" -> HeadlessCanonicalRecoveryDisposition.SUCCEEDED
            "retry" -> HeadlessCanonicalRecoveryDisposition.RETRY
            "stale" -> HeadlessCanonicalRecoveryDisposition.STALE
            else -> return null
        }
        if (method != "complete" && method != "failed") return null
        return HeadlessCanonicalRecoveryCompletion(
            disposition = disposition,
            databaseClosed = values["databaseClosed"] as? Boolean ?: false,
            leaseReleased = values["leaseReleased"] as? Boolean ?: false,
            failureReason = values["failureReason"] as? String,
        )
    }

    private fun positiveIntegralLong(value: Any?): Long? = when (value) {
        null -> null
        is Byte -> value.toLong().takeIf { it > 0L }
        is Short -> value.toLong().takeIf { it > 0L }
        is Int -> value.toLong().takeIf { it > 0L }
        is Long -> value.takeIf { it > 0L }
        else -> null
    }
}

/** Main-looper, exactly-once acceptance gate for one run identity. */
internal class HeadlessCanonicalRecoveryCompletionGate(
    private val expected: HeadlessCanonicalRecoveryRunIdentity,
) {
    private var accepted = false

    fun accept(
        arguments: Any?,
        method: String,
    ): HeadlessCanonicalRecoveryCompletion? {
        if (accepted) return null
        val parsed = HeadlessCanonicalRecoveryCompletionProtocol.parse(
            arguments,
            method,
            expected,
        ) ?: return null
        accepted = true
        return parsed
    }
}

internal object HeadlessCanonicalRecoveryDestructionPolicy {
    fun mayDestroy(
        completion: HeadlessCanonicalRecoveryCompletion?,
        nativeLeaseReleased: Boolean,
        nativeGoReleased: Boolean,
    ): Boolean = completion?.databaseClosed == true &&
        completion.leaseReleased &&
        nativeLeaseReleased &&
        nativeGoReleased
}

internal enum class HeadlessCanonicalRecoveryWorkOutcome {
    SUCCESS,
    RETRY,
}

internal interface HeadlessCanonicalRecoveryAuthority {
    fun recoveryWorkEnabled(): Boolean
    fun currentBinding(): String?
    fun pendingRecovery(): DroppedPushRecoveryStore.PendingRecovery?
}

private class StoreHeadlessCanonicalRecoveryAuthority(
    private val store: DroppedPushRecoveryStore,
) : HeadlessCanonicalRecoveryAuthority {
    override fun recoveryWorkEnabled(): Boolean = store.recoveryWorkEnabled()

    override fun currentBinding(): String? = store.currentBinding()

    override fun pendingRecovery(): DroppedPushRecoveryStore.PendingRecovery? =
        store.pendingRecovery()
}

internal interface HeadlessCanonicalRecoveryEngineRunner {
    suspend fun run(
        snapshot: HeadlessCanonicalRecoveryStartSnapshot,
    ): HeadlessCanonicalRecoveryCompletion

    /** Cooperative only. Cleanup remains owned by [finish]. */
    fun requestStop()

    /** Always invoked from the Worker's `finally` path. */
    suspend fun finish()
}

/**
 * Truthful, testable WorkManager execution policy. Work input is only a wake
 * signal; authority is resnapshotted both before engine creation and after the
 * Dart runtime reports completion.
 */
internal class HeadlessCanonicalRecoveryExecution(
    private val authority: HeadlessCanonicalRecoveryAuthority,
    private val runnerFactory: () -> HeadlessCanonicalRecoveryEngineRunner,
    private val isStopped: () -> Boolean,
    private val timeoutMillis: Long,
) {
    private val lock = Any()
    private val stopRequested = AtomicBoolean(false)
    private var activeRunner: HeadlessCanonicalRecoveryEngineRunner? = null

    init {
        require(timeoutMillis > 0L) { "timeoutMillis must be positive" }
    }

    suspend fun execute(inputData: Data): HeadlessCanonicalRecoveryWorkOutcome {
        if (stopRequested.get() || isStopped()) {
            return HeadlessCanonicalRecoveryWorkOutcome.RETRY
        }
        val snapshot = resolveStartSnapshot(authority, inputData)
            ?: return HeadlessCanonicalRecoveryWorkOutcome.SUCCESS
        val runner = runnerFactory()
        synchronized(lock) { activeRunner = runner }
        val outcome = try {
            if (stopRequested.get() || isStopped()) {
                runner.requestStop()
                HeadlessCanonicalRecoveryWorkOutcome.RETRY
            } else {
                val completion = withTimeout(timeoutMillis) {
                    runner.run(snapshot)
                }
                if (stopRequested.get() || isStopped()) {
                    runner.requestStop()
                    HeadlessCanonicalRecoveryWorkOutcome.RETRY
                } else {
                    classifyCompletion(snapshot, completion)
                }
            }
        } catch (_: TimeoutCancellationException) {
            runner.requestStop()
            HeadlessCanonicalRecoveryWorkOutcome.RETRY
        } catch (_: Throwable) {
            runner.requestStop()
            HeadlessCanonicalRecoveryWorkOutcome.RETRY
        }
        return try {
            withContext(NonCancellable) {
                runner.finish()
            }
            outcome
        } catch (_: Throwable) {
            HeadlessCanonicalRecoveryWorkOutcome.RETRY
        } finally {
            synchronized(lock) {
                if (activeRunner === runner) activeRunner = null
            }
        }
    }

    fun requestStop() {
        stopRequested.set(true)
        synchronized(lock) { activeRunner }?.requestStop()
    }

    private fun classifyCompletion(
        snapshot: HeadlessCanonicalRecoveryStartSnapshot,
        completion: HeadlessCanonicalRecoveryCompletion,
    ): HeadlessCanonicalRecoveryWorkOutcome {
        if (!completion.databaseClosed || !completion.leaseReleased) {
            return HeadlessCanonicalRecoveryWorkOutcome.RETRY
        }
        val currentBinding = authority.currentBinding()
        val pending = authority.pendingRecovery()
        return when (completion.disposition) {
            HeadlessCanonicalRecoveryDisposition.RETRY ->
                HeadlessCanonicalRecoveryWorkOutcome.RETRY

            HeadlessCanonicalRecoveryDisposition.STALE -> {
                if (
                    currentBinding != snapshot.binding ||
                    (snapshot.pendingRecovery != null && pending == null)
                ) {
                    HeadlessCanonicalRecoveryWorkOutcome.SUCCESS
                } else {
                    HeadlessCanonicalRecoveryWorkOutcome.RETRY
                }
            }

            HeadlessCanonicalRecoveryDisposition.SUCCEEDED -> {
                if (currentBinding != snapshot.binding || pending != null) {
                    HeadlessCanonicalRecoveryWorkOutcome.RETRY
                } else {
                    HeadlessCanonicalRecoveryWorkOutcome.SUCCESS
                }
            }
        }
    }

    companion object {
        internal fun resolveStartSnapshot(
            authority: HeadlessCanonicalRecoveryAuthority,
            inputData: Data,
        ): HeadlessCanonicalRecoveryStartSnapshot? {
            val reason = inputData.getString(DroppedPushRecoveryWorkScheduler.INPUT_REASON)
                ?: return null
            if (!authority.recoveryWorkEnabled()) return null
            val binding = authority.currentBinding() ?: return null
            val queuedBindingDigest = inputData.getString(
                DroppedPushRecoveryWorkScheduler.INPUT_BINDING_DIGEST,
            ) ?: return null
            if (
                queuedBindingDigest !=
                DroppedPushRecoveryWorkScheduler.bindingDigest(binding)
            ) {
                return null
            }
            return when (reason) {
                DroppedPushRecoveryWorkScheduler.REASON_DELETED_BATCH -> {
                    if (
                        inputData.getLong(
                            DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION,
                            -1L,
                        ) <= 0L
                    ) {
                        return null
                    }
                    val latest = authority.pendingRecovery() ?: return null
                    HeadlessCanonicalRecoveryStartSnapshot(reason, binding, latest)
                }

                DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP ->
                    HeadlessCanonicalRecoveryStartSnapshot(
                        reason,
                        binding,
                        pendingRecovery = null,
                    )

                else -> null
            }
        }
    }
}

/**
 * Debug-only, one-shot cut point for TC-374-08.
 *
 * The debug receiver arms a private file before invoking the shared production
 * deleted-batch seam. The first matching worker atomically consumes that file
 * and waits, so the device runner can kill its process before any recovery
 * work executes. The restarted worker sees no file and enters production
 * recovery normally. Release builds and unarmed debug work never wait.
 */
internal object Plan374ProcessDeathBarrier {
    internal const val DIRECTORY = "plan374-headless-recovery"
    internal const val FILE_NAME = "first-attempt-barrier"
    internal const val MAX_WAIT_MILLIS = 120_000L

    fun arm(context: Context, runNonce: String): Boolean {
        if (!BuildConfig.DEBUG || runNonce.isBlank()) return false
        val directory = File(context.filesDir, DIRECTORY)
        if (!directory.exists() && !directory.mkdirs()) return false
        return runCatching {
            File(directory, FILE_NAME).apply { writeText(runNonce) }.isFile
        }.getOrDefault(false)
    }

    fun disarm(context: Context) {
        if (!BuildConfig.DEBUG) return
        runCatching { File(File(context.filesDir, DIRECTORY), FILE_NAME).delete() }
    }

    fun consumeAndAwaitProcessDeath(
        context: Context,
        reason: String?,
        isStopped: () -> Boolean,
        onConsumed: () -> Unit,
    ): Boolean {
        if (
            !BuildConfig.DEBUG ||
            reason != DroppedPushRecoveryWorkScheduler.REASON_DELETED_BATCH
        ) {
            return false
        }
        val barrier = File(File(context.filesDir, DIRECTORY), FILE_NAME)
        if (!barrier.delete()) return false
        onConsumed()
        val deadline = SystemClock.elapsedRealtime() + MAX_WAIT_MILLIS
        while (!isStopped() && SystemClock.elapsedRealtime() < deadline) {
            try {
                Thread.sleep(100L)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }
        return true
    }
}

/** WorkManager's production boundary. `onStopped` signals only. */
internal class HeadlessCanonicalRecoveryWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    companion object {
        internal const val FOREGROUND_NOTIFICATION_ID = 330
        internal const val PLAN374_DIAGNOSTIC_TAG = "MknoonPlan374Recovery"
        private const val WORK_TIMEOUT_MILLIS = 8 * 60 * 1000L

        internal fun resolveStartSnapshot(
            store: DroppedPushRecoveryStore,
            inputData: Data,
        ): HeadlessCanonicalRecoveryStartSnapshot? =
            HeadlessCanonicalRecoveryExecution.resolveStartSnapshot(
                StoreHeadlessCanonicalRecoveryAuthority(store),
                inputData,
            )

        internal fun createForegroundInfo(context: Context): ForegroundInfo {
            MknoonFirebaseMessagingService.ensureRecoveryNotificationChannel(context)
            val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(
                    context,
                    MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID,
                )
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = notificationBuilder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(
                    context.getString(R.string.dropped_push_recovery_notification_title),
                )
                .setContentText(context.getString(R.string.dropped_push_recovery_worker_body))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
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
        HeadlessCanonicalRecoveryExecution(
            authority = StoreHeadlessCanonicalRecoveryAuthority(
                DroppedPushRecoveryStore(applicationContext),
            ),
            runnerFactory = {
                FlutterHeadlessCanonicalRecoveryEngineRunner(applicationContext)
            },
            isStopped = { isStopped },
            timeoutMillis = WORK_TIMEOUT_MILLIS,
        )
    }

    override fun getForegroundInfoAsync(): ListenableFuture<ForegroundInfo> =
        Futures.immediateFuture(createForegroundInfo(applicationContext))

    override fun doWork(): Result = runBlocking {
        emitPlan374Diagnostic("start")
        val barrierConsumed = Plan374ProcessDeathBarrier.consumeAndAwaitProcessDeath(
            context = applicationContext,
            reason = inputData.getString(
                DroppedPushRecoveryWorkScheduler.INPUT_REASON,
            ),
            isStopped = { isStopped },
            onConsumed = {
                emitPlan374Diagnostic("process_death_barrier_consumed")
            },
        )
        if (barrierConsumed && isStopped) return@runBlocking Result.retry()
        when (execution.execute(inputData)) {
            HeadlessCanonicalRecoveryWorkOutcome.SUCCESS -> {
                emitPlan374Diagnostic("completion", "SUCCESS")
                Result.success()
            }
            HeadlessCanonicalRecoveryWorkOutcome.RETRY -> {
                emitPlan374Diagnostic("completion", "RETRY")
                Result.retry()
            }
        }
    }

    override fun onStopped() {
        emitPlan374Diagnostic("stopped")
        execution.requestStop()
        super.onStopped()
    }

    /** Privacy-safe device-proof diagnostic; no binding or conversation ID. */
    private fun emitPlan374Diagnostic(phase: String, outcome: String? = null) {
        if (
            (
                applicationContext.applicationInfo.flags and
                    android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE
            ) == 0
        ) {
            return
        }
        val generation = inputData.getLong(
            DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION,
            -1L,
        ).takeIf { it > 0L }
        android.util.Log.i(
            PLAN374_DIAGNOSTIC_TAG,
            JSONObject()
                .put("event", "plan374_headless_worker")
                .put("phase", phase)
                .put("pid", android.os.Process.myPid())
                .put(
                    "reason",
                    inputData.getString(DroppedPushRecoveryWorkScheduler.INPUT_REASON),
                )
                .put("generation", generation)
                .put("runAttemptCount", runAttemptCount)
                .put("outcome", outcome)
                .toString(),
        )
    }
}

/** Prevents a timeout retry from constructing a second engine over a retained owner. */
private object ProcessHeadlessCanonicalRecoveryEngine {
    private val lock = Any()
    private var owner: FlutterHeadlessCanonicalRecoveryEngineRunner? = null

    fun claim(candidate: FlutterHeadlessCanonicalRecoveryEngineRunner): Boolean =
        synchronized(lock) {
            if (owner != null) return@synchronized false
            owner = candidate
            true
        }

    fun release(candidate: FlutterHeadlessCanonicalRecoveryEngineRunner) {
        synchronized(lock) {
            if (owner === candidate) owner = null
        }
    }

    fun isRetained(): Boolean = synchronized(lock) { owner != null }
}

/** Read-only rollback diagnostic; it never claims or releases an engine. */
internal fun isHeadlessCanonicalRecoveryEngineRetained(): Boolean =
    ProcessHeadlessCanonicalRecoveryEngine.isRetained()

/** Minimal, non-UI Flutter engine. All engine lifecycle work stays on main. */
private class FlutterHeadlessCanonicalRecoveryEngineRunner(
    context: Context,
) : HeadlessCanonicalRecoveryEngineRunner {
    companion object {
        private const val CHANNEL_NAME = "mknoon/headless_canonical_recovery"
        private const val CLEANUP_POLL_DELAY_MILLIS = 25L
        private const val MAX_CLEANUP_POLLS = 80
    }

    private val applicationContext = context.applicationContext
    private val completion = CompletableDeferred<HeadlessCanonicalRecoveryCompletion>()
    private val stopRequested = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var resultChannel: MethodChannel? = null
    private var leaseBridge: CanonicalRuntimeLeaseBridge? = null
    private var droppedPushBridge: DroppedPushRecoveryBridge? = null
    private var goBridge: GoBridge? = null
    private var lastCompletion: HeadlessCanonicalRecoveryCompletion? = null
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
        snapshot: HeadlessCanonicalRecoveryStartSnapshot,
    ): HeadlessCanonicalRecoveryCompletion {
        val identity = HeadlessCanonicalRecoveryRunIdentity(
            nonce = UUID.randomUUID().toString(),
            reason = snapshot.reason,
            binding = snapshot.binding,
            generation = snapshot.pendingRecovery?.generation,
        )
        withContext(Dispatchers.Main.immediate) {
            startOnMain(identity)
        }
        return completion.await()
    }

    private fun startOnMain(identity: HeadlessCanonicalRecoveryRunIdentity) {
        check(Looper.myLooper() == Looper.getMainLooper())
        check(engine == null) { "headless canonical engine already started" }
        if (!ProcessHeadlessCanonicalRecoveryEngine.claim(this)) {
            throw IllegalStateException("headless canonical engine is retained")
        }
        claimed = true
        val created = FlutterEngine(applicationContext, null, false)
        engine = created
        registerAllowlistedPlugins(created)
        leaseBridge = CanonicalRuntimeLeaseBridge(
            messenger = created.dartExecutor.binaryMessenger,
            ownerId = "headless-recovery-${System.identityHashCode(created)}",
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
        droppedPushBridge = DroppedPushRecoveryBridge(
            applicationContext,
            created.dartExecutor.binaryMessenger,
        )
        resultChannel = MethodChannel(
            created.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            val completionGate = HeadlessCanonicalRecoveryCompletionGate(identity)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "complete", "failed" -> {
                        val parsed = completionGate.accept(
                            call.arguments,
                            call.method,
                        )
                        if (parsed == null) {
                            result.error(
                                "invalid_completion",
                                "headless recovery returned an invalid or duplicate result",
                                null,
                            )
                        } else {
                            lastCompletion = parsed
                            emitPlan374DartCompletionDiagnostic(parsed)
                            completion.complete(parsed)
                            result.success(null)
                            maybeCleanupRetainedOnMain()
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
        val loader = FlutterInjector.instance().flutterLoader()
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "androidHeadlessCanonicalRecoveryMain",
        )
        created.dartExecutor.executeDartEntrypoint(
            entrypoint,
            listOf(
                identity.reason,
                identity.nonce,
                identity.binding,
                identity.generation?.toString().orEmpty(),
            ),
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

    override suspend fun finish() {
        withContext(Dispatchers.Main.immediate) {
            if (!dartStarted || canDestroyOnMain()) {
                cleanupOnMain()
            }
            // Otherwise retain this exact engine, bridges, and owner. Its Dart
            // completion callback will destroy it only after close/release ack.
        }
    }

    private fun canDestroyOnMain(): Boolean {
        check(Looper.myLooper() == Looper.getMainLooper())
        return HeadlessCanonicalRecoveryDestructionPolicy.mayDestroy(
            completion = lastCompletion,
            nativeLeaseReleased = ProcessCanonicalRuntimeLease.broker.snapshot().state ==
                CanonicalRuntimeLeaseBroker.State.RELEASED,
            nativeGoReleased = ProcessGoRuntimeHost.instance.snapshot().state ==
                GoRuntimeHost.State.RELEASED,
        )
    }

    private fun maybeCleanupRetainedOnMain() {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (cleanedUp) return
        if (canDestroyOnMain()) {
            cleanupOnMain()
            return
        }
        // A safe Dart completion can race the final native StopNode delivery.
        // Retain this exact engine and recheck on main; never infer release from
        // a Dart boolean alone and never construct a successor over it.
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
        } else if (
            reported != null &&
            !cleanupPollScheduled &&
            cleanupPollAttempts >= MAX_CLEANUP_POLLS
        ) {
            emitPlan374EngineDiagnostic(
                phase = "retained_after_cleanup_deadline",
                completion = reported,
            )
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
        droppedPushBridge?.dispose()
        droppedPushBridge = null
        leaseBridge?.dispose()
        leaseBridge = null
        goBridge?.dispose()
        goBridge = null
        engine?.destroy()
        engine = null
        if (claimed) {
            claimed = false
            ProcessHeadlessCanonicalRecoveryEngine.release(this)
        }
        emitPlan374EngineDiagnostic(
            phase = "engine_released",
            completion = lastCompletion,
        )
    }

    /** Privacy-safe debug proof of the exact Dart/native destruction fence. */
    private fun emitPlan374DartCompletionDiagnostic(
        completion: HeadlessCanonicalRecoveryCompletion,
    ) = emitPlan374EngineDiagnostic(
        phase = "dart_completion",
        completion = completion,
    )

    private fun emitPlan374EngineDiagnostic(
        phase: String,
        completion: HeadlessCanonicalRecoveryCompletion?,
    ) {
        if (!BuildConfig.DEBUG) return
        val leaseState = ProcessCanonicalRuntimeLease.broker.snapshot().state
        val goState = ProcessGoRuntimeHost.instance.snapshot().state
        android.util.Log.i(
            HeadlessCanonicalRecoveryWorker.PLAN374_DIAGNOSTIC_TAG,
            JSONObject()
                .put("event", "plan374_headless_engine")
                .put("phase", phase)
                .put("pid", android.os.Process.myPid())
                .put("disposition", completion?.disposition?.name)
                .put("databaseClosed", completion?.databaseClosed)
                .put("leaseReleased", completion?.leaseReleased)
                .put("failureReason", completion?.failureReason)
                .put("nativeLeaseState", leaseState.name)
                .put("nativeGoState", goState.name)
                .put("claimed", claimed)
                .toString(),
        )
    }

    private fun registerAllowlistedPlugins(engine: FlutterEngine) {
        engine.plugins.add(FlutterSecureStoragePlugin())
        engine.plugins.add(SqfliteSqlCipherPlugin())
        engine.plugins.add(FlutterLocalNotificationsPlugin())
        engine.plugins.add(FlutterFirebaseCorePlugin())
        engine.plugins.add(FlutterFirebaseMessagingPlugin())
        engine.plugins.add(PathProviderPlugin())
    }

}
