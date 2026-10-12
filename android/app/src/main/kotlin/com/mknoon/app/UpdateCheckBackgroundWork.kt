package com.mknoon.app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.pathprovider.PathProviderPlugin
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * SE-41 T4a: the periodic background update check on Android.
 *
 * The worker never decides anything itself. It routes one run to the Dart
 * entry `UpdateCheckBackgroundRunner` under the D1 lease rules:
 * - The main engine holds the canonical runtime lease (ACTIVE, FOREGROUND)
 *   and is registered here: hand off over `mknoon/update_check_background`.
 * - The lease is RELEASED and no main engine is registered: start a minimal
 *   engine (`androidUpdateCheckMinimalMain`). It never takes the lease.
 * - Anything else (another owner, DRAINING, a main engine that has not taken
 *   the lease yet or is tearing down): defer.
 * "Main engine alive" comes from the lease plus the engine registration done
 * in configureFlutterEngine/cleanUpFlutterEngine, never from Activity state:
 * MainActivity can keep its engine after the Activity is gone (PiP teardown,
 * MainActivity.cleanUpFlutterEngine).
 *
 * Limits (docs/release/se41-update-check-background.md): Doze, App Standby
 * and OEM battery savers can delay the work; the 6 h gate of the foreground
 * check also applies here.
 */
internal object UpdateCheckBackgroundWork {
    const val CHANNEL_NAME = "mknoon/update_check_background"
    const val UNIQUE_WORK_NAME = "mknoon-se41-update-check"
    const val MINIMAL_ENTRYPOINT = "androidUpdateCheckMinimalMain"
    const val REPEAT_HOURS = 12L
    const val BACKOFF_MINUTES = 30L

    /** The Dart run's own budget; native waits [NATIVE_TIMEOUT_MILLIS]. */
    const val DART_BUDGET_MILLIS = 18_000L
    const val NATIVE_TIMEOUT_MILLIS = 20_000L
}

internal enum class UpdateCheckRoute {
    HANDOFF,
    MINIMAL_ENGINE,
    DEFER,
}

internal fun routeUpdateCheckRun(
    lease: CanonicalRuntimeLeaseBroker.Snapshot,
    registeredMainEngineOwnerId: String?,
): UpdateCheckRoute {
    if (
        lease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
        lease.role == CanonicalRuntimeLeaseBroker.Role.FOREGROUND &&
        registeredMainEngineOwnerId != null &&
        lease.ownerId == registeredMainEngineOwnerId
    ) {
        return UpdateCheckRoute.HANDOFF
    }
    if (
        lease.state == CanonicalRuntimeLeaseBroker.State.RELEASED &&
        registeredMainEngineOwnerId == null
    ) {
        return UpdateCheckRoute.MINIMAL_ENGINE
    }
    return UpdateCheckRoute.DEFER
}

/** One run's input, the same for the handoff and the minimal engine. */
internal data class UpdateCheckRunRequest(
    val reason: String,
    val budgetMillis: Long,
    val installedBuildNumber: String,
    val inCall: Boolean,
) {
    fun toChannelArguments(): Map<String, Any?> = mapOf(
        "reason" to reason,
        "budgetMs" to budgetMillis.toInt(),
        "inCall" to inCall,
    )

    fun toEntrypointArguments(): List<String> = listOf(
        reason,
        budgetMillis.toString(),
        installedBuildNumber,
        inCall.toString(),
    )
}

internal fun interface UpdateCheckRunner {
    /** Returns the Dart result map, or null when the run failed to report. */
    suspend fun run(request: UpdateCheckRunRequest): Map<*, *>?
}

/** A registered main engine that can take a run. */
internal interface UpdateCheckMainEngineHandoff {
    val ownerId: String

    fun run(request: UpdateCheckRunRequest, callback: (Map<*, *>?) -> Unit)
}

internal object UpdateCheckMainEngineRegistry {
    @Volatile
    private var current: UpdateCheckMainEngineHandoff? = null

    fun register(handoff: UpdateCheckMainEngineHandoff) {
        synchronized(this) { current = handoff }
    }

    fun unregister(handoff: UpdateCheckMainEngineHandoff) {
        synchronized(this) {
            if (current === handoff) current = null
        }
    }

    fun current(): UpdateCheckMainEngineHandoff? = current
}

internal interface UpdateCheckWorkEnqueuer {
    fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    )

    fun cancelUniqueWork(uniqueName: String)
}

private class AndroidXUpdateCheckWorkEnqueuer(context: Context) : UpdateCheckWorkEnqueuer {
    private val applicationContext = context.applicationContext

    override fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    ) {
        WorkManager.getInstance(applicationContext)
            .enqueueUniquePeriodicWork(uniqueName, policy, request)
    }

    override fun cancelUniqueWork(uniqueName: String) {
        WorkManager.getInstance(applicationContext).cancelUniqueWork(uniqueName)
    }
}

/** Kill switch on: one unique periodic work (KEEP). Off: cancel it. */
internal class UpdateCheckWorkScheduler(
    private val enqueuer: UpdateCheckWorkEnqueuer,
) {
    constructor(context: Context) : this(AndroidXUpdateCheckWorkEnqueuer(context))

    fun apply(enabled: Boolean) {
        if (!enabled) {
            enqueuer.cancelUniqueWork(UpdateCheckBackgroundWork.UNIQUE_WORK_NAME)
            return
        }
        enqueuer.enqueueUniquePeriodic(
            UpdateCheckBackgroundWork.UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            buildRequest(),
        )
    }

    internal fun buildRequest(): PeriodicWorkRequest =
        PeriodicWorkRequestBuilder<UpdateCheckWorker>(
            UpdateCheckBackgroundWork.REPEAT_HOURS,
            TimeUnit.HOURS,
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setBackoffCriteria(
                BackoffPolicy.LINEAR,
                UpdateCheckBackgroundWork.BACKOFF_MINUTES,
                TimeUnit.MINUTES,
            )
            .build()
}

internal enum class UpdateCheckWorkOutcome {
    /** The run finished; the kill switch is on. */
    COMPLETED,

    /** Dart reported the kill switch off; the schedule was cancelled. */
    DISABLED,

    /** The lease is held by another owner: retry after the backoff. */
    DEFERRED,

    /** No answer within the budget. The next period tries again. */
    TIMED_OUT,
}

internal class UpdateCheckWorkExecution(
    private val leaseSnapshot: () -> CanonicalRuntimeLeaseBroker.Snapshot,
    private val registeredMainEngine: () -> UpdateCheckMainEngineHandoff?,
    private val handoffRunner: (UpdateCheckMainEngineHandoff) -> UpdateCheckRunner,
    private val minimalEngineRunner: () -> UpdateCheckRunner,
    private val scheduler: UpdateCheckWorkScheduler,
    private val timeoutMillis: Long = UpdateCheckBackgroundWork.NATIVE_TIMEOUT_MILLIS,
) {
    suspend fun execute(request: UpdateCheckRunRequest): UpdateCheckWorkOutcome {
        val mainEngine = registeredMainEngine()
        val runner = when (routeUpdateCheckRun(leaseSnapshot(), mainEngine?.ownerId)) {
            UpdateCheckRoute.HANDOFF -> handoffRunner(mainEngine!!)
            UpdateCheckRoute.MINIMAL_ENGINE -> minimalEngineRunner()
            UpdateCheckRoute.DEFER -> return UpdateCheckWorkOutcome.DEFERRED
        }
        val result = withTimeoutOrNull(timeoutMillis) { runner.run(request) }
            ?: return UpdateCheckWorkOutcome.TIMED_OUT
        if (result["enabled"] == false) {
            scheduler.apply(false)
            return UpdateCheckWorkOutcome.DISABLED
        }
        return UpdateCheckWorkOutcome.COMPLETED
    }
}

internal class UpdateCheckWorker(
    appContext: Context,
    params: WorkerParameters,
) : Worker(appContext, params) {
    override fun doWork(): Result = runBlocking {
        val execution = UpdateCheckWorkExecution(
            leaseSnapshot = { ProcessCanonicalRuntimeLease.broker.snapshot() },
            registeredMainEngine = { UpdateCheckMainEngineRegistry.current() },
            handoffRunner = { handoff -> MainEngineUpdateCheckRunner(handoff) },
            minimalEngineRunner = { FlutterUpdateCheckMinimalEngineRunner(applicationContext) },
            scheduler = UpdateCheckWorkScheduler(applicationContext),
        )
        val request = UpdateCheckRunRequest(
            reason = "android_periodic",
            budgetMillis = UpdateCheckBackgroundWork.DART_BUDGET_MILLIS,
            installedBuildNumber = installedBuildNumber(applicationContext),
            inCall = isDeviceInCall(applicationContext),
        )
        when (execution.execute(request)) {
            UpdateCheckWorkOutcome.DEFERRED -> Result.retry()
            UpdateCheckWorkOutcome.COMPLETED,
            UpdateCheckWorkOutcome.DISABLED,
            UpdateCheckWorkOutcome.TIMED_OUT,
            -> Result.success()
        }
    }
}

/** The same number package_info_plus reports as the build number. */
internal fun installedBuildNumber(context: Context): String = runCatching {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        info.longVersionCode.toString()
    } else {
        @Suppress("DEPRECATION")
        info.versionCode.toString()
    }
}.getOrDefault("")

/**
 * A call is ringing or active, ours (WebRTC uses MODE_IN_COMMUNICATION and the
 * call service rings with MODE_RINGTONE) or a phone call. Needs no permission.
 */
internal fun isDeviceInCall(context: Context): Boolean {
    val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
    return when (audio.mode) {
        AudioManager.MODE_IN_CALL,
        AudioManager.MODE_IN_COMMUNICATION,
        AudioManager.MODE_RINGTONE,
        -> true
        else -> false
    }
}

private class MainEngineUpdateCheckRunner(
    private val handoff: UpdateCheckMainEngineHandoff,
) : UpdateCheckRunner {
    override suspend fun run(request: UpdateCheckRunRequest): Map<*, *>? {
        val reply = CompletableDeferred<Map<*, *>?>()
        withContext(Dispatchers.Main.immediate) {
            handoff.run(request) { reply.complete(it) }
        }
        return reply.await()
    }
}

/**
 * Main-engine side: created in MainActivity.configureFlutterEngine. Handles
 * `configure` (schedule or cancel) and `notify`, and takes worker handoffs.
 */
internal class UpdateCheckBackgroundBridge(
    context: Context,
    messenger: BinaryMessenger,
    override val ownerId: String,
    private val scheduler: UpdateCheckWorkScheduler = UpdateCheckWorkScheduler(context),
    private val registry: UpdateCheckMainEngineRegistry = UpdateCheckMainEngineRegistry,
) : UpdateCheckMainEngineHandoff, MethodChannel.MethodCallHandler {
    private val applicationContext = context.applicationContext
    private val channel = MethodChannel(messenger, UpdateCheckBackgroundWork.CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
        registry.register(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> {
                val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                if (enabled == null) {
                    result.error("bad_args", "enabled is required", null)
                    return
                }
                runCatching { scheduler.apply(enabled) }
                result.success(null)
            }
            "notify" -> result.success(postFromArguments(applicationContext, call.arguments))
            else -> result.notImplemented()
        }
    }

    override fun run(request: UpdateCheckRunRequest, callback: (Map<*, *>?) -> Unit) {
        channel.invokeMethod(
            "run",
            request.toChannelArguments(),
            object : MethodChannel.Result {
                override fun success(result: Any?) = callback(result as? Map<*, *>)

                override fun error(code: String, message: String?, details: Any?) = callback(null)

                override fun notImplemented() = callback(null)
            },
        )
    }

    fun dispose() {
        registry.unregister(this)
        channel.setMethodCallHandler(null)
    }
}

internal fun postFromArguments(context: Context, arguments: Any?): Boolean {
    val map = arguments as? Map<*, *> ?: return false
    val kind = map["kind"] as? String ?: return false
    val title = map["title"] as? String ?: return false
    val body = map["body"] as? String ?: return false
    return UpdateCheckNotificationPoster.post(context, kind, title, body)
}

/**
 * Starts the minimal engine, waits for `complete`, then destroys it. Only the
 * path_provider plugin is registered: no lease bridge, no Go bridge, no
 * SQLCipher and no Firebase plugin exist on this engine.
 */
private class FlutterUpdateCheckMinimalEngineRunner(
    context: Context,
) : UpdateCheckRunner {
    private val applicationContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    override suspend fun run(request: UpdateCheckRunRequest): Map<*, *>? {
        val completion = CompletableDeferred<Map<*, *>?>()
        var engine: FlutterEngine? = null
        try {
            withContext(Dispatchers.Main.immediate) {
                val created = FlutterEngine(applicationContext, null, false)
                engine = created
                created.plugins.add(PathProviderPlugin())
                MethodChannel(
                    created.dartExecutor.binaryMessenger,
                    UpdateCheckBackgroundWork.CHANNEL_NAME,
                ).setMethodCallHandler { call, result ->
                    when (call.method) {
                        "notify" -> result.success(postFromArguments(applicationContext, call.arguments))
                        "complete" -> {
                            result.success(null)
                            completion.complete(call.arguments as? Map<*, *>)
                        }
                        else -> result.notImplemented()
                    }
                }
                val loader = FlutterInjector.instance().flutterLoader()
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        UpdateCheckBackgroundWork.MINIMAL_ENTRYPOINT,
                    ),
                    request.toEntrypointArguments(),
                )
            }
            return completion.await()
        } finally {
            val started = engine
            if (started != null) mainHandler.post { started.destroy() }
        }
    }
}
