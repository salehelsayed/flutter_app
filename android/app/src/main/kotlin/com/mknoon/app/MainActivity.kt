package com.mknoon.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.mknoon.app.call.FullScreenCallAccess
import com.mknoon.app.call.MknoonCallBridgeTeardown
import com.mknoon.app.call.MknoonCallNativeBridge
import com.mknoon.app.call.MknoonCallRuntime
import com.mknoon.app.call.MknoonCallTaskChannelHandler
import com.mknoon.app.call.MknoonCallVideoQualityEnvironment
import com.mknoon.app.call.MknoonIncomingCallPresentation
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
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
        private const val LAUNCH_INTENT_CHANNEL = "mknoon/launch_intent"
        private val privateMediaProtectionRegistry =
            PrivateMediaProtectionHandlerRegistry()
        private var retainedCanonicalRuntimeEngine: FlutterEngine? = null
    }

    private class AppVisibilityChannel(val channel: MethodChannel) {
        @Volatile
        var attached = true
            private set

        private val pending = mutableSetOf<MethodChannel.Result>()

        fun <T> deferReply(
            result: MethodChannel.Result,
            encode: (T) -> Map<String, Any?>,
        ): (T?) -> Unit {
            if (!attached) {
                result.success(null)
                return {}
            }
            pending.add(result)
            return { value ->
                if (pending.remove(result)) result.success(value?.let(encode))
            }
        }

        fun close() {
            attached = false
            channel.setMethodCallHandler(null)
            val abandoned = pending.toList()
            pending.clear()
            abandoned.forEach { it.success(null) }
        }
    }

    private var goBridge: GoBridge? = null
    private var permissionResultNormalizer: PermissionResultNormalizer? = null
    private var receivedMediaEgressHandler: ReceivedMediaEgressHandler? = null
    private var stickerClipFrameBridge: StickerClipFrameBridge? = null
    private var stickerCutoutBridge: StickerCutoutBridge? = null
    private var privateMediaProtectionHandler: PrivateMediaProtectionHandler? = null
    private var privateMediaProtectionEngine: FlutterEngine? = null
    private var pictureInPictureHandler: PictureInPictureHandler? = null
    private var callPictureInPictureHandler: com.mknoon.app.call.CallPictureInPictureHandler? = null
    private var callVideoQualityEnvironment: MknoonCallVideoQualityEnvironment? = null
    private var droppedPushRecoveryBridge: DroppedPushRecoveryBridge? = null
    private val contactInviteBridge = ContactInviteBridge(this)
    private var callNativeBridge: MknoonCallNativeBridge? = null
    // F3 (beta 2026-09-25): the bridge's detach ends a live Telecom call
    // without telling Dart. Keep it until Dart's runtime shutdown has ended
    // the call and sent the terminate to the peer.
    private val callBridgeTeardown = MknoonCallBridgeTeardown {
        callNativeBridge?.dispose()
        callNativeBridge = null
    }
    private var callTaskChannel: MethodChannel? = null
    private var callTaskHandler: MknoonCallTaskChannelHandler? = null
    private var androidCallWakeBridge: AndroidCallWakeBridge? = null
    private var incomingCallPresentation: MknoonIncomingCallPresentation? = null
    private var canonicalRuntimeLeaseBridge: CanonicalRuntimeLeaseBridge? = null
    private var updateCheckBackgroundBridge: UpdateCheckBackgroundBridge? = null
    private var canonicalRuntimeShutdownChannel: MethodChannel? = null
    private var pushNotificationSettingsChannel: MethodChannel? = null
    private var appVisibilityChannel: AppVisibilityChannel? = null
    private val appVisibilityOwner = Any()
    private var retainEngineForCanonicalShutdown = false
    private var canonicalRuntimeCleanupFinished = false
    private var canonicalRuntimeShutdownAttempts = 0
    // 180: native jmDNS resolver for the Android-discovers-iOS `.local` wall.
    private var mdnsResolver: MdnsResolver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ordinary activity restoration can precede a call intent, and also
        // needs an exit owner for Android's platform splash. Register before
        // Flutter creates content or allows the first application draw.
        MknoonIncomingCallPresentation.installSplashExit(this)
        com.mknoon.app.diagnostics.MknoonAppDiagnostics.get(this).record("startup", "launch", "started", "bootstrap")
        // Invalidate any stale foreground route before FlutterActivity starts.
        visibilityLifecycleCoordinator().onLaunch(appVisibilityOwner)
        CanonicalRuntimeProbeDiagnostics.recordMainActivityLaunch()
        // 414 (F2): the share plugin reads this intent during super.onCreate
        // and crashes on a shared file the app cannot read. Drop those first.
        intent = ShareIntentReadabilityGuard.sanitize(intent) {
            ShareIntentReadabilityGuard.canRead(contentResolver, it)
        }
        contactInviteBridge.consume(intent, deliver = savedInstanceState == null)
        super.onCreate(savedInstanceState)
        setupPermissionResultNormalizer()
        // This exported entry only displays the exact call. Notification Answer
        // consent is consumed by the private MknoonCallAnswerActivity.
        incomingCallPresentation = MknoonIncomingCallPresentation(this).also {
            it.onIntent(intent, answerFromIntent = false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        contactInviteBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        if (BuildConfig.DEBUG) {
            // A FlutterFire background engine can replace plugin singletons.
            // The debug PCM proof binds the actual canonical foreground engine.
            runCatching {
                Class.forName("com.mknoon.app.call.DebugCallAudioOracleReceiver")
                    .getMethod("bindEngine", FlutterEngine::class.java)
                    .invoke(null, flutterEngine)
            }
        }
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
        setupStickerClipFrameBridge(flutterEngine.dartExecutor.binaryMessenger)
        setupStickerCutoutBridge(flutterEngine.dartExecutor.binaryMessenger)
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
        callPictureInPictureHandler?.dispose()
        callPictureInPictureHandler = com.mknoon.app.call.CallPictureInPictureHandler(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            webRtcPlugin = flutterEngine.plugins.get(FlutterWebRTCPlugin::class.java)
                as? FlutterWebRTCPlugin,
        )
        callVideoQualityEnvironment?.dispose()
        callVideoQualityEnvironment = MknoonCallVideoQualityEnvironment(
            context = applicationContext,
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
                (goBridge != null).also { attached ->
                    if (attached) androidCallWakeBridge?.ownerMayBeReady()
                }
            },
            beginRuntimeDrain = {
                goBridge?.requestRuntimeDrain() ?: true
            },
            isRuntimeReleased = {
                goBridge?.isRuntimeReleased() ?: true
            },
        )
        androidCallWakeBridge = AndroidCallWakeBridge(
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            ownerId = "foreground-${System.identityHashCode(flutterEngine)}",
        )
        // SE-41 T4a: the update-check worker hands its run to this engine only
        // while the lease names this same owner id.
        updateCheckBackgroundBridge = UpdateCheckBackgroundBridge(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
            ownerId = "foreground-${System.identityHashCode(flutterEngine)}",
        )
        droppedPushRecoveryBridge = DroppedPushRecoveryBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            registerProcessSignals = true,
        )
        callNativeBridge = MknoonCallRuntime.get(applicationContext).createBridge(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        val taskHandler = MknoonCallTaskChannelHandler(
            isDeviceUnlocked = {
                val keyguard = getSystemService(android.app.KeyguardManager::class.java)
                keyguard != null && !keyguard.isDeviceLocked && !keyguard.isKeyguardLocked
            },
            moveTaskToBack = { moveTaskToBack(true) },
            registerBack = MknoonCallTaskChannelHandler.overlayBackRegistrar(this),
            onMinimizeCall = { callId ->
                if (incomingCallPresentation?.handleBack() != true) {
                    callTaskChannel?.invokeMethod(MknoonCallTaskChannelHandler.MINIMIZE_CALL, callId)
                }
            },
        )
        callTaskHandler = taskHandler
        callTaskChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MknoonCallTaskChannelHandler.CHANNEL,
        ).also { channel -> channel.setMethodCallHandler(taskHandler) }
        canonicalRuntimeShutdownChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CANONICAL_RUNTIME_SHUTDOWN_CHANNEL,
        )
        // O6: lets Dart draw a first frame at once for a call launch, so the
        // native incoming-call surface is not held back by startup.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCH_INTENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIncomingCallLaunch" -> result.success(
                        MknoonIncomingCallPresentation.isIncomingCallLaunch(intent),
                    )
                    else -> result.notImplemented()
                }
            }
        pushNotificationSettingsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PushNotificationSettingsLauncher.METHOD_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    PushNotificationSettingsLauncher.OPEN_METHOD -> result.success(
                        PushNotificationSettingsLauncher.open(applicationContext),
                    )
                    FullScreenCallAccess.READ_METHOD -> result.success(
                        FullScreenCallAccess.read(applicationContext),
                    )
                    FullScreenCallAccess.OPEN_METHOD -> result.success(
                        FullScreenCallAccess.openSettings(this),
                    )
                    FullScreenCallAccess.DISMISS_METHOD -> result.success(
                        FullScreenCallAccess.dismiss(applicationContext),
                    )
                    else -> result.notImplemented()
                }
            }
        }
        appVisibilityChannel?.close()
        appVisibilityChannel = AppVisibilityChannel(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_VISIBILITY_CHANNEL),
        ).also { binding ->
            binding.channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "readSnapshot" -> {
                        if (call.arguments != null) {
                            result.error(
                                "bad_args",
                                "readSnapshot requires null arguments",
                                null,
                            )
                        } else {
                            visibilityLifecycleCoordinator().readSnapshot(
                                owner = appVisibilityOwner,
                                isAttached = { binding.attached },
                                reply = binding.deferReply(
                                    result,
                                    AppVisibilityReadEnvelope::toChannelMap,
                                ),
                            )
                        }
                    }
                    "publishVisibleConversation" ->
                        handlePublishVisibleConversation(call.arguments, result, binding)
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
        GemmaPreviewChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
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
        incomingCallPresentation?.onIntent(intent, answerFromIntent = false)
        // 414 (F2): same guard as onCreate, before the share plugin's listener.
        ShareIntentReadabilityGuard.sanitize(intent) {
            ShareIntentReadabilityGuard.canRead(contentResolver, it)
        }
        contactInviteBridge.consume(intent)
        super.onNewIntent(intent)
        setIntent(intent)
        droppedPushRecoveryBridge?.onWarmIntent(intent)
    }

    override fun onResume() {
        // Queue the new generation before Flutter can ask to republish its route.
        visibilityLifecycleCoordinator().onResume(appVisibilityOwner)
        super.onResume()
        incomingCallPresentation?.onResume()
        receivedMediaEgressHandler?.onResume()
        callPictureInPictureHandler?.onResume()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        callPictureInPictureHandler?.onUserLeaveHint()
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.S)
    override fun onPictureInPictureUiStateChanged(pipState: android.app.PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(pipState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            callPictureInPictureHandler?.onAutoEnterTransition(pipState.isTransitioningToPip)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callPictureInPictureHandler?.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        callPictureInPictureHandler?.onWindowFocusChanged(hasFocus)
    }

    override fun onPause() {
        // A delayed Dart route write must observe this newer generation and lose.
        visibilityLifecycleCoordinator().onPause(appVisibilityOwner)
        super.onPause()
        callPictureInPictureHandler?.onPause()
    }

    override fun onStop() {
        visibilityLifecycleCoordinator().onStop(appVisibilityOwner)
        super.onStop()
        incomingCallPresentation?.onStop()
        callPictureInPictureHandler?.onStop()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (incomingCallPresentation?.handleBack() == true) return
        if (callTaskHandler?.handleBackPressed() == true) return
        super.onBackPressed()
    }

    private fun setupStickerCutoutBridge(messenger: BinaryMessenger) {
        closeStickerCutoutBridge()
        val context = applicationContext
        stickerCutoutBridge = StickerCutoutBridge(
            messenger = messenger,
            cacheDirectory = cacheDir,
            clientFactory = { MlKitStickerCutoutClient.create(context) },
        )
    }

    private fun closeStickerCutoutBridge() {
        val bridge = stickerCutoutBridge
        stickerCutoutBridge = null
        bridge?.close()
    }

    private fun setupStickerClipFrameBridge(messenger: BinaryMessenger) {
        closeStickerClipFrameBridge()
        stickerClipFrameBridge = StickerClipFrameBridge(messenger, cacheDir)
    }

    private fun closeStickerClipFrameBridge() {
        val bridge = stickerClipFrameBridge
        stickerClipFrameBridge = null
        bridge?.close()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        contactInviteBridge.detach()
        closeStickerClipFrameBridge()
        closeStickerCutoutBridge()
        androidCallWakeBridge?.dispose()
        androidCallWakeBridge = null
        updateCheckBackgroundBridge?.dispose()
        updateCheckBackgroundBridge = null
        Log.i(
            PICTURE_IN_PICTURE_LIFECYCLE_TAG,
            "[MKNOON_PIP] MainActivity.cleanUpFlutterEngine " +
                "reason=flutter_engine_detached",
        )
        PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine()
        pictureInPictureHandler = null
        callVideoQualityEnvironment?.dispose()
        callVideoQualityEnvironment = null
        droppedPushRecoveryBridge?.dispose()
        droppedPushRecoveryBridge = null
        callTaskHandler?.dispose()
        callTaskHandler = null
        callTaskChannel?.setMethodCallHandler(null)
        callTaskChannel = null
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
            // No Dart runtime is left to end a call.
            callBridgeTeardown.onRuntimeShutdownSettled()
            super.cleanUpFlutterEngine(flutterEngine)
            return
        }

        // FlutterActivity would otherwise destroy the engine immediately after
        // this synchronous hook returns. Retain it briefly so Dart can quiesce
        // Go, explicitly close SQLCipher, and acknowledge native lease release.
        retainEngineForCanonicalShutdown = true
        // Dart's shutdown ends a live call first (terminate to the peer, then
        // the native end), so the call bridge must outlive this request.
        callBridgeTeardown.deferUntilRuntimeShutdown()
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
            // Dart had its chance to end the call. The bridge detach now ends
            // anything it could not.
            callBridgeTeardown.onRuntimeShutdownSettled()
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
        appVisibilityChannel?.close()
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
        closePermissionResultNormalizer()
        androidCallWakeBridge?.dispose()
        androidCallWakeBridge = null
        incomingCallPresentation?.dispose()
        incomingCallPresentation = null
        pictureInPictureHandler?.dispose("host_destroyed")
        pictureInPictureHandler = null
        callPictureInPictureHandler?.dispose()
        callPictureInPictureHandler = null
        callVideoQualityEnvironment?.dispose()
        callVideoQualityEnvironment = null
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
        // super.onDestroy runs cleanUpFlutterEngine, which may defer the call
        // bridge until the Dart runtime shutdown settles.
        super.onDestroy()
        callBridgeTeardown.onHostDestroyed()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (receivedMediaEgressHandler?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        val normalized = permissionResultNormalizer?.normalize(requestCode, permissions, grantResults)
        super.onRequestPermissionsResult(
            requestCode,
            normalized?.permissions ?: permissions,
            normalized?.grantResults ?: grantResults,
        )
    }

    private fun setupPermissionResultNormalizer() {
        closePermissionResultNormalizer()
        permissionResultNormalizer = PermissionResultNormalizer(this).also { it.install() }
    }

    private fun closePermissionResultNormalizer() {
        permissionResultNormalizer?.dispose()
        permissionResultNormalizer = null
    }

    private fun visibilityLifecycleCoordinator(): AppVisibilityLifecycleCoordinator =
        AppVisibilityLifecycleCoordinator.get(applicationContext)

    private fun handlePublishVisibleConversation(
        rawArguments: Any?,
        result: MethodChannel.Result,
        binding: AppVisibilityChannel,
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
        visibilityLifecycleCoordinator().publishVisibleConversation(
            visibleConversationDigest = digest,
            lifecycleGeneration = generation,
            owner = appVisibilityOwner,
            isAttached = { binding.attached },
            reply = binding.deferReply(result, AppVisibilityCommitEnvelope::toChannelMap),
        )
    }
}
