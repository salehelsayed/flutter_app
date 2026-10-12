package com.mknoon.app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
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
    const val PUSH_WORK_NAME = "mknoon-se41-update-check-push"
    const val PUSH_TOPIC = "update_check"
    const val PUSH_PAYLOAD_TYPE = "update_check"
    const val INPUT_REASON = "reason"
    const val REASON_PERIODIC = "android_periodic"

    /** T4b: one push-triggered check per hour at most. */
    const val REASON_PUSH = "android_push"
    const val PUSH_MIN_INTERVAL_MILLIS = 60 * 60 * 1000L
    private const val PUSH_GATE_PREFS = "se41_update_check_push_gate"
    private const val PUSH_GATE_LAST_MS = "last_push_check_ms"

    /** Takes the hourly slot if free. A clock that went back frees it. */
    fun takePushSlot(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean {
        val prefs = context.getSharedPreferences(PUSH_GATE_PREFS, Context.MODE_PRIVATE)
        synchronized(this) {
            val last = prefs.getLong(PUSH_GATE_LAST_MS, Long.MIN_VALUE)
            val free = last == Long.MIN_VALUE || nowMs < last || nowMs - last >= PUSH_MIN_INTERVAL_MILLIS
            if (free) prefs.edit().putLong(PUSH_GATE_LAST_MS, nowMs).commit()
            return free
        }
    }

    private const val SWITCH_PREFS = "se41_update_check_switch"
    private const val SWITCH_ENABLED = "enabled"

    /** The kill switch as Dart last configured it; false until it has. */
    fun isSwitchEnabled(context: Context): Boolean =
        context.getSharedPreferences(SWITCH_PREFS, Context.MODE_PRIVATE)
            .getBoolean(SWITCH_ENABLED, false)

    fun storeSwitchEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(SWITCH_PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(SWITCH_ENABLED, enabled).commit()
    }

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
    headlessEngineClaimed: Boolean = false,
): UpdateCheckRoute {
    // A headless call-admission or recovery engine exists, maybe before it
    // takes the lease (T4a review F3): never a third engine, never a post
    // while a call may be ringing.
    if (headlessEngineClaimed) return UpdateCheckRoute.DEFER
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
    fun enqueueUniqueOneTime(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    )

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

    override fun enqueueUniqueOneTime(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(uniqueName, policy, request)
    }

    override fun cancelUniqueWork(uniqueName: String) {
        WorkManager.getInstance(applicationContext).cancelUniqueWork(uniqueName)
    }
}

/** FCM topic membership for the T4b check-now push. */
internal fun interface UpdateCheckTopicMembership {
    fun set(subscribed: Boolean)
}

private object FirebaseUpdateCheckTopicMembership : UpdateCheckTopicMembership {
    override fun set(subscribed: Boolean) {
        val messaging = com.google.firebase.messaging.FirebaseMessaging.getInstance()
        if (subscribed) {
            messaging.subscribeToTopic(UpdateCheckBackgroundWork.PUSH_TOPIC)
        } else {
            messaging.unsubscribeFromTopic(UpdateCheckBackgroundWork.PUSH_TOPIC)
        }
    }
}

/** The stored kill switch, so a push can be checked without Dart. */
internal interface UpdateCheckSwitchState {
    var enabled: Boolean
}

internal class InMemoryUpdateCheckSwitchState(override var enabled: Boolean = false) : UpdateCheckSwitchState

private class PrefsUpdateCheckSwitchState(private val context: Context) : UpdateCheckSwitchState {
    override var enabled: Boolean
        get() = UpdateCheckBackgroundWork.isSwitchEnabled(context)
        set(value) = UpdateCheckBackgroundWork.storeSwitchEnabled(context, value)
}

/**
 * Kill switch on: one unique periodic work (KEEP) and the update_check topic.
 * Off: cancel all work and leave the topic. The switch is stored, so a push
 * that still arrives (stale topic membership) is ignored while it is off.
 */
internal class UpdateCheckWorkScheduler(
    private val enqueuer: UpdateCheckWorkEnqueuer,
    private val topic: UpdateCheckTopicMembership = FirebaseUpdateCheckTopicMembership,
    private val takePushSlot: () -> Boolean = { true },
    private val switchState: UpdateCheckSwitchState = InMemoryUpdateCheckSwitchState(),
) {
    constructor(context: Context) : this(
        AndroidXUpdateCheckWorkEnqueuer(context),
        FirebaseUpdateCheckTopicMembership,
        { UpdateCheckBackgroundWork.takePushSlot(context.applicationContext) },
        PrefsUpdateCheckSwitchState(context.applicationContext),
    )

    fun apply(enabled: Boolean) {
        runCatching { switchState.enabled = enabled }
        runCatching { topic.set(enabled) }
        if (!enabled) {
            enqueuer.cancelUniqueWork(UpdateCheckBackgroundWork.UNIQUE_WORK_NAME)
            enqueuer.cancelUniqueWork(UpdateCheckBackgroundWork.PUSH_WORK_NAME)
            return
        }
        enqueuer.enqueueUniquePeriodic(
            UpdateCheckBackgroundWork.UNIQUE_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            buildRequest(),
        )
    }

    /**
     * T4b: a check-now push runs the same worker once (unique, KEEP), at most
     * once per hour. Returns false when the kill switch is off (checked
     * first, so it takes no slot) or the hourly slot is taken.
     */
    fun enqueuePushTriggered(): Boolean {
        if (!switchState.enabled) return false
        if (!takePushSlot()) return false
        enqueuer.enqueueUniqueOneTime(
            UpdateCheckBackgroundWork.PUSH_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            buildPushRequest(),
        )
        return true
    }

    internal fun buildPushRequest(): OneTimeWorkRequest =
        OneTimeWorkRequestBuilder<UpdateCheckWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build(),
            )
            .setInputData(
                Data.Builder()
                    .putString(UpdateCheckBackgroundWork.INPUT_REASON, UpdateCheckBackgroundWork.REASON_PUSH)
                    .build(),
            )
            .build()

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
    private val headlessEngineClaimed: () -> Boolean,
    private val handoffRunner: (UpdateCheckMainEngineHandoff) -> UpdateCheckRunner,
    private val minimalEngineRunner: () -> UpdateCheckRunner,
    private val scheduler: UpdateCheckWorkScheduler,
    private val timeoutMillis: Long = UpdateCheckBackgroundWork.NATIVE_TIMEOUT_MILLIS,
) {
    suspend fun execute(request: UpdateCheckRunRequest): UpdateCheckWorkOutcome {
        val mainEngine = registeredMainEngine()
        val route = routeUpdateCheckRun(
            leaseSnapshot(),
            mainEngine?.ownerId,
            headlessEngineClaimed(),
        )
        val runner = when (route) {
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
            headlessEngineClaimed = ::isHeadlessEngineClaimed,
            handoffRunner = { handoff -> MainEngineUpdateCheckRunner(handoff) },
            minimalEngineRunner = { FlutterUpdateCheckMinimalEngineRunner(applicationContext) },
            scheduler = UpdateCheckWorkScheduler(applicationContext),
        )
        val request = UpdateCheckRunRequest(
            reason = inputData.getString(UpdateCheckBackgroundWork.INPUT_REASON)
                ?.takeIf { it == UpdateCheckBackgroundWork.REASON_PUSH }
                ?: UpdateCheckBackgroundWork.REASON_PERIODIC,
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

internal fun isHeadlessEngineClaimed(): Boolean =
    com.mknoon.app.call.isHeadlessCallAdmissionEngineClaimed() ||
        isHeadlessCanonicalRecoveryEngineClaimed()

/**
 * The minimal engine posts only if, right now, it is still alone: lease free,
 * no main engine (so not in the foreground), no headless engine, no call.
 * Checked again at post time because the run lasts up to 20 s (T4a F3).
 */
internal fun minimalEngineMayPost(
    lease: CanonicalRuntimeLeaseBroker.Snapshot,
    registeredMainEngine: UpdateCheckMainEngineHandoff?,
    headlessEngineClaimed: Boolean,
    inCall: Boolean,
): Boolean =
    lease.state == CanonicalRuntimeLeaseBroker.State.RELEASED &&
        registeredMainEngine == null &&
        !headlessEngineClaimed &&
        !inCall

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
                        "notify" -> {
                            val mayPost = minimalEngineMayPost(
                                lease = ProcessCanonicalRuntimeLease.broker.snapshot(),
                                registeredMainEngine = UpdateCheckMainEngineRegistry.current(),
                                headlessEngineClaimed = isHeadlessEngineClaimed(),
                                inCall = isDeviceInCall(applicationContext),
                            )
                            result.success(
                                mayPost && postFromArguments(applicationContext, call.arguments),
                            )
                        }
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
