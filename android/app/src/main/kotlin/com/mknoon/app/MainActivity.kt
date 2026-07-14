package com.mknoon.app

import android.content.Intent
import android.os.StatFs
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PICTURE_IN_PICTURE_LIFECYCLE_TAG = "MknoonPiP"
        private val privateMediaProtectionRegistry =
            PrivateMediaProtectionHandlerRegistry()
    }

    private var goBridge: GoBridge? = null
    private var receivedMediaEgressHandler: ReceivedMediaEgressHandler? = null
    private var privateMediaProtectionHandler: PrivateMediaProtectionHandler? = null
    private var privateMediaProtectionEngine: FlutterEngine? = null
    private var pictureInPictureHandler: PictureInPictureHandler? = null
    // 180: native jmDNS resolver for the Android-discovers-iOS `.local` wall.
    private var mdnsResolver: MdnsResolver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
        goBridge = GoBridge(flutterEngine, applicationContext)
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
    }

    override fun onResume() {
        super.onResume()
        receivedMediaEgressHandler?.onResume()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Log.i(
            PICTURE_IN_PICTURE_LIFECYCLE_TAG,
            "[MKNOON_PIP] MainActivity.cleanUpFlutterEngine " +
                "reason=flutter_engine_detached",
        )
        PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine()
        pictureInPictureHandler = null
        privateMediaProtectionRegistry.detach(
            engineIdentity = flutterEngine,
            activity = this,
            destroyEngine = shouldDestroyEngineWithHost(),
        )
        privateMediaProtectionHandler = null
        privateMediaProtectionEngine = null
        super.cleanUpFlutterEngine(flutterEngine)
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
}
