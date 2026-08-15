package com.mknoon.app

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PICTURE_IN_PICTURE_LIFECYCLE_TAG = "MknoonPiP"
        private const val CANONICAL_RUNTIME_SHUTDOWN_CHANNEL =
            "mknoon/canonical_runtime_shutdown"
        private const val CANONICAL_RUNTIME_SHUTDOWN_TIMEOUT_MS = 5_000L
        private const val CANONICAL_RUNTIME_SHUTDOWN_RETRY_MS = 500L
        private const val CANONICAL_RUNTIME_SHUTDOWN_MAX_ATTEMPTS = 3
        private const val APP_VISIBILITY_CHANNEL = "mknoon/app_visibility"
        private val privateMediaProtectionRegistry =
            PrivateMediaProtectionHandlerRegistry()
        private var retainedCanonicalRuntimeEngine: FlutterEngine? = null
    }

    private var goBridge: GoBridge? = null
    private var receivedMediaEgressHandler: ReceivedMediaEgressHandler? = null
    private var privateMediaProtectionHandler: PrivateMediaProtectionHandler? = null
    private var privateMediaProtectionEngine: FlutterEngine? = null
    private var pictureInPictureHandler: PictureInPictureHandler? = null
    private var droppedPushRecoveryBridge: DroppedPushRecoveryBridge? = null
    private var canonicalRuntimeLeaseBridge: CanonicalRuntimeLeaseBridge? = null
    private var canonicalRuntimeShutdownChannel: MethodChannel? = null
    private var pushNotificationSettingsChannel: MethodChannel? = null
    private var appVisibilityChannel: MethodChannel? = null
    private var appVisibilitySnapshotStore: AppVisibilitySnapshotStore? = null
    private var appVisibilityLifecycleCoordinator: AppVisibilityLifecycleCoordinator? = null
    private var retainEngineForCanonicalShutdown = false
    private var canonicalRuntimeCleanupFinished = false
    private var canonicalRuntimeShutdownAttempts = 0
    // 180: native jmDNS resolver for the Android-discovers-iOS `.local` wall.
    private var mdnsResolver: MdnsResolver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // N04: commit launch invalidation before FlutterActivity can expose a
        // stale foreground route to Dart. Failure remains fail-notify inside the
        // one process-scoped store; lifecycle startup itself must stay total.
        visibilityLifecycleCoordinator().onLaunch()
        CanonicalRuntimeProbeDiagnostics.recordMainActivityLaunch()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (BuildConfig.ENABLE_GROUP_EXIT_RELEASE_DIAGNOSTICS_PROOF) {
            val proofPlugin = Class.forName(
                "dev.flutter.plugins.integration_test.IntegrationTestPlugin",
            ).getDeclaredConstructor().newInstance()
            check(proofPlugin is FlutterPlugin) {
                "PB266 release integration plugin has an invalid type."
            }
            flutterEngine.plugins.add(proofPlugin)
            Log.i(
                "PB266ReleaseProof",
                "IntegrationTestPlugin registered in release engine",
            )
        }
        receivedMediaEgressHandler = ReceivedMediaEgressHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        privateMediaProtectionEngine = flutterEngine
        privateMediaProtectionHandler = privateMediaProtectionRegistry.bind(
            engineIdentity = flutterEngine,
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        pictureInPictureHandler = PictureInPictureHandler(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        canonicalRuntimeLeaseBridge = CanonicalRuntimeLeaseBridge(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            ownerId = "foreground-${System.identityHashCode(flutterEngine)}",
            role = CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
            attachRuntimeOwner = {
                if (goBridge == null) {
                    goBridge = runCatching {
                        GoBridge(flutterEngine, applicationContext)
                    }.getOrNull()
                }
                goBridge != null
            },
            beginRuntimeDrain = {
                goBridge?.requestRuntimeDrain() ?: true
            },
            isRuntimeReleased = {
                goBridge?.isRuntimeReleased() ?: true
            },
        )
        droppedPushRecoveryBridge = DroppedPushRecoveryBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        canonicalRuntimeShutdownChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CANONICAL_RUNTIME_SHUTDOWN_CHANNEL,
        )
        pushNotificationSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PushNotificationSettingsLauncher.METHOD_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    PushNotificationSettingsLauncher.OPEN_METHOD -> result.success(
                        PushNotificationSettingsLauncher.open(applicationContext),
                    )
                    else -> result.notImplemented()
                }
            }
        }
        appVisibilityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_VISIBILITY_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "readSnapshot" -> {
                        if (call.arguments != null) {
                            result.error(
                                "bad_args",
                                "readSnapshot requires null arguments",
                                null,
                            )
                        } else {
                            result.success(visibilitySnapshotStore().readSnapshot()?.toChannelMap())
                        }
                    }
                    "publishVisibleConversation" ->
                        handlePublishVisibleConversation(call.arguments, result)
                    else -> result.notImplemented()
                }
            }
        }
        // Move Account transfer keep-alive: Dart holds/releases a dataSync
        // foreground service so backgrounding mid-transfer cannot freeze the
        // segment upload or the local receiver (audit gap G7).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mknoon/migration_keepalive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    MigrationKeepAliveService.start(this)
                    result.success(null)
                }
                "stop" -> {
                    MigrationKeepAliveService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mknoon/disk_space",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAvailableBytes" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(StatFs(path).availableBytes)
                    } catch (error: Exception) {
                        result.error(
                            "disk_space_unavailable",
                            error.message ?: "disk space unavailable",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
        // 180: native jmDNS mDNS resolver — MethodChannel start/stop + an
        // EventChannel streaming resolved peers. Android-only; the Dart side
        // (BonsoirDiscoveryService) gates it off on iOS and behind the
        // MKNOON_ENABLE_NATIVE_MDNS flag.
        val resolver = MdnsResolver(applicationContext)
        mdnsResolver = resolver
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mknoon/mdns_resolver",
        ).setMethodCallHandler { call, result ->
            resolver.onMethodCall(
                call.method,
                call.argument<String>("serviceType"),
                result,
            )
        }
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mknoon/mdns_resolver/events",
        ).setStreamHandler(resolver)
    }

    /**
     * Required for `flutter_local_notifications` on `singleTask` apps.
     *
     * On Android, when `launchMode="singleTask"` (see `AndroidManifest.xml`),
     * a notification-tap PendingIntent is delivered to `onNewIntent` on the
     * existing MainActivity instance instead of starting a fresh Activity.
     * The default `FlutterActivity.onNewIntent` does NOT call
     * `setIntent(intent)`, so the new intent's extras (including the
     * `flutter_local_notifications` plugin's notification-response payload)
     * are silently dropped before the plugin's
     * `onDidReceiveNotificationResponse` dispatcher can see them.
     *
     * Calling `setIntent(intent)` here makes the new intent visible to the
     * Flutter embedding's plugin pipeline, which then dispatches
     * `didReceiveNotificationResponse` to the Dart side and the
     * `NOTIFICATION_TAPPED` flow event finally fires.
     *
     * Diagnosed in the Pixel ↔ iOS-sim hardware soak on 2026-05-05; see
     * `Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md`
     * (section "2026-05-05 hardware-soak finding"). Standing Rule 2.1 in the
     * same document requires a real-device hardware soak to verify — that is
     * the runtime regression catcher; the matching Dart pin test
     * (`test/core/notifications/main_activity_onnewintent_pin_test.dart`) is
     * the static catcher.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        droppedPushRecoveryBridge?.onWarmIntent(intent)
    }

    override fun onResume() {
        // Persist FOREGROUND_ACTIVE + null before super can deliver resume to
        // Flutter. Dart republishes the top route only against this generation.
        visibilityLifecycleCoordinator().onResume()
        super.onResume()
        receivedMediaEgressHandler?.onResume()
    }

    override fun onPause() {
        // A delayed Dart route write must observe this newer generation and lose.
        visibilityLifecycleCoordinator().onPause()
        super.onPause()
    }

    override fun onStop() {
        visibilityLifecycleCoordinator().onStop()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Log.i(
            PICTURE_IN_PICTURE_LIFECYCLE_TAG,
            "[MKNOON_PIP] MainActivity.cleanUpFlutterEngine " +
                "reason=flutter_engine_detached",
        )
        PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine()
        pictureInPictureHandler = null
        droppedPushRecoveryBridge?.dispose()
        droppedPushRecoveryBridge = null
        val destroyEngineWithHost = super.shouldDestroyEngineWithHost()
        privateMediaProtectionRegistry.detach(
            engineIdentity = flutterEngine,
            activity = this,
            destroyEngine = false,
        )
        privateMediaProtectionHandler = null
        privateMediaProtectionEngine = null

        val leaseState = ProcessCanonicalRuntimeLease.broker.snapshot().state
        if (leaseState == CanonicalRuntimeLeaseBroker.State.RELEASED) {
            finishCanonicalRuntimeEngineCleanup(
                flutterEngine = flutterEngine,
                destroyRetainedEngine = false,
                reason = "already_released",
            )
            super.cleanUpFlutterEngine(flutterEngine)
            return
        }

        // FlutterActivity would otherwise destroy the engine immediately after
        // this synchronous hook returns. Retain it briefly so Dart can quiesce
        // Go, explicitly close SQLCipher, and acknowledge native lease release.
        retainEngineForCanonicalShutdown = true
        requestCanonicalRuntimeShutdown(
            flutterEngine = flutterEngine,
            destroyRetainedEngine = destroyEngineWithHost,
        )
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun shouldDestroyEngineWithHost(): Boolean =
        if (retainEngineForCanonicalShutdown) {
            false
        } else {
            super.shouldDestroyEngineWithHost()
        }

    private fun requestCanonicalRuntimeShutdown(
        flutterEngine: FlutterEngine,
        destroyRetainedEngine: Boolean,
    ) {
        canonicalRuntimeShutdownAttempts += 1
        val mainHandler = Handler(Looper.getMainLooper())
        var settled = false
        fun settle(released: Boolean, reason: String) {
            if (settled) return
            settled = true
            if (released) {
                finishCanonicalRuntimeEngineCleanup(
                    flutterEngine = flutterEngine,
                    destroyRetainedEngine = destroyRetainedEngine,
                    reason = reason,
                )
            } else {
                retainCanonicalRuntimeEngineAfterFailedShutdown(
                    flutterEngine = flutterEngine,
                    destroyRetainedEngine = destroyRetainedEngine,
                    reason = reason,
                )
            }
        }
        val timeout = Runnable {
            settle(released = false, reason = "shutdown_timeout_retained")
        }
        mainHandler.postDelayed(timeout, CANONICAL_RUNTIME_SHUTDOWN_TIMEOUT_MS)
        val channel = canonicalRuntimeShutdownChannel
        if (channel == null) {
            mainHandler.removeCallbacks(timeout)
            settle(
                released = false,
                reason = "shutdown_channel_missing_retained",
            )
            return
        }
        channel.invokeMethod(
            "shutdown",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    mainHandler.post {
                        mainHandler.removeCallbacks(timeout)
                        val reply = result as? Map<*, *>
                        val released = reply?.get("released") == true &&
                            reply["databaseClosed"] == true &&
                            reply["leaseState"] == "released" &&
                            ProcessCanonicalRuntimeLease.broker.snapshot().state ==
                            CanonicalRuntimeLeaseBroker.State.RELEASED
                        settle(
                            released = released,
                            reason = if (released) {
                                "dart_close_acknowledged"
                            } else {
                                "dart_close_rejected_retained"
                            },
                        )
                    }
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    mainHandler.post {
                        mainHandler.removeCallbacks(timeout)
                        settle(
                            released = false,
                            reason = "dart_shutdown_error_retained:$errorCode",
                        )
                    }
                }

                override fun notImplemented() {
                    mainHandler.post {
                        mainHandler.removeCallbacks(timeout)
                        settle(
                            released = false,
                            reason = "dart_shutdown_missing_retained",
                        )
                    }
                }
            },
        )
    }

    private fun retainCanonicalRuntimeEngineAfterFailedShutdown(
        flutterEngine: FlutterEngine,
        destroyRetainedEngine: Boolean,
        reason: String,
    ) {
        check(Looper.myLooper() == Looper.getMainLooper())
        retainedCanonicalRuntimeEngine = flutterEngine
        retainEngineForCanonicalShutdown = true
        Log.w(
            "CanonicalRuntime",
            "foreground_engine_retained reason=$reason " +
                "attempt=$canonicalRuntimeShutdownAttempts",
        )
        if (
            canonicalRuntimeShutdownAttempts <
            CANONICAL_RUNTIME_SHUTDOWN_MAX_ATTEMPTS
        ) {
            Handler(Looper.getMainLooper()).postDelayed(
                {
                    requestCanonicalRuntimeShutdown(
                        flutterEngine = flutterEngine,
                        destroyRetainedEngine = destroyRetainedEngine,
                    )
                },
                CANONICAL_RUNTIME_SHUTDOWN_RETRY_MS,
            )
        }
    }

    private fun finishCanonicalRuntimeEngineCleanup(
        flutterEngine: FlutterEngine,
        destroyRetainedEngine: Boolean,
        reason: String,
    ) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (canonicalRuntimeCleanupFinished) return
        canonicalRuntimeCleanupFinished = true
        Log.i("CanonicalRuntime", "foreground_engine_cleanup reason=$reason")
        retainedCanonicalRuntimeEngine = null
        canonicalRuntimeShutdownChannel = null
        pushNotificationSettingsChannel?.setMethodCallHandler(null)
        pushNotificationSettingsChannel = null
        appVisibilityChannel?.setMethodCallHandler(null)
        appVisibilityChannel = null
        goBridge?.dispose()
        goBridge = null
        canonicalRuntimeLeaseBridge?.dispose()
        canonicalRuntimeLeaseBridge = null
        if (retainEngineForCanonicalShutdown && destroyRetainedEngine) {
            privateMediaProtectionRegistry.detach(
                engineIdentity = flutterEngine,
                activity = this,
                destroyEngine = true,
            )
            flutterEngine.destroy()
        }
        retainEngineForCanonicalShutdown = false
    }

    override fun onDestroy() {
        pictureInPictureHandler?.dispose("host_destroyed")
        pictureInPictureHandler = null
        val engine = privateMediaProtectionEngine
        if (engine != null) {
            privateMediaProtectionRegistry.detach(
                engineIdentity = engine,
                activity = this,
                destroyEngine = false,
            )
        } else {
            privateMediaProtectionHandler?.detachActivity(this)
        }
        privateMediaProtectionHandler = null
        privateMediaProtectionEngine = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (receivedMediaEgressHandler?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun visibilitySnapshotStore(): AppVisibilitySnapshotStore =
        appVisibilitySnapshotStore ?: AppVisibilitySnapshotStore(applicationContext).also {
            appVisibilitySnapshotStore = it
        }

    private fun visibilityLifecycleCoordinator(): AppVisibilityLifecycleCoordinator =
        appVisibilityLifecycleCoordinator ?: AppVisibilityLifecycleCoordinator(
            visibilitySnapshotStore(),
        ).also {
            appVisibilityLifecycleCoordinator = it
        }

    private fun handlePublishVisibleConversation(
        rawArguments: Any?,
        result: MethodChannel.Result,
    ) {
        val arguments = rawArguments as? Map<*, *>
        if (
            arguments == null ||
            !arguments.containsKey("visibleConversationDigest") ||
            !arguments.containsKey("lifecycleGeneration") ||
            arguments.keys.any {
                it != "visibleConversationDigest" && it != "lifecycleGeneration"
            }
        ) {
            result.error(
                "bad_args",
                "publishVisibleConversation requires exactly " +
                    "visibleConversationDigest and lifecycleGeneration",
                null,
            )
            return
        }
        val digestValue = arguments["visibleConversationDigest"]
        val digest = when (digestValue) {
            null -> null
            is String -> digestValue
            else -> {
                result.error(
                    "bad_args",
                    "visibleConversationDigest must be a String or null",
                    null,
                )
                return
            }
        }
        val generation = when (val value = arguments["lifecycleGeneration"]) {
            is Byte -> value.toLong()
            is Short -> value.toLong()
            is Int -> value.toLong()
            is Long -> value
            else -> null
        }
        if (generation == null || generation <= 0L) {
            result.error(
                "bad_args",
                "lifecycleGeneration must be a positive integer",
                null,
            )
            return
        }
        result.success(
            visibilitySnapshotStore().publishVisibleConversation(
                visibleConversationDigest = digest,
                lifecycleGeneration = generation,
            ).toChannelMap(),
        )
    }
}
