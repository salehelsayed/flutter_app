package com.mknoon.app.call

import android.annotation.TargetApi
import android.app.Activity
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Rational
import com.mknoon.app.PictureInPictureExitClassifier
import com.mknoon.app.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Android side of the live-call PiP bridge (contract v1). MainActivity forwards
 * its lifecycle; [CallPipLeaseCore] owns lease rules. Until Dart arms a lease
 * (never while the video gate is off) no PiP params are set and nothing enters.
 */
internal class CallPictureInPictureHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : CallPipPlatform, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, METHOD_CHANNEL)
    private val events = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private val core = CallPipLeaseCore(this) { eventSink?.success(it) }
    private val main = Handler(Looper.getMainLooper())
    private val liveSinks = mutableSetOf<CallPipRemoteSink>()
    private var controls: CallPipControls? = null
    private var exit: PictureInPictureExitClassifier? = null
    private var armedLease: CallPipIdentity? = null
    private var receiverRegistered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_CONTROL -> {
                    val kind = intent.getStringExtra(EXTRA_KIND) ?: return
                    val id = CallPipIdentity(
                        intent.getStringExtra(EXTRA_INSTANCE) ?: return,
                        intent.getStringExtra(EXTRA_CALL) ?: return,
                        intent.getLongExtra(EXTRA_LEASE, 0L),
                    )
                    core.onAction(id, kind)
                }
                // Lock retires an armed lease even before entry (PIP-NATIVE-5).
                Intent.ACTION_SCREEN_OFF -> core.onBlocked("locked")
            }
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        // Retire the lease and turn auto entry off before the channels go.
        core.shutdown()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        setReceiver(false)
        liveSinks.toList().forEach { runCatching { releaseSink(it) } }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val id = CallPipIdentity.parse(args)
        when (call.method) {
            "availability" -> result.success(
                if (id == null) mapOf("supported" to false, "cameraInPip" to false, "reason" to "invalid")
                else core.availability(),
            )
            "arm" -> {
                val source = args?.let { CallPipSource.parse(it) }
                val wanted = args?.let { CallPipControls.parse(it) }
                result.success(
                    if (id == null || source == null || wanted == null) {
                        mapOf("armed" to false, "reason" to "invalid")
                    } else {
                        core.arm(id, source, wanted)
                    },
                )
            }
            "update" -> {
                val wanted = args?.let { CallPipControls.parse(it) }
                result.success(id != null && wanted != null && core.update(id, wanted))
            }
            "enter" -> result.success(id != null && core.enter(id))
            "disarm" -> result.success(id != null && args?.get("reason") is String && core.disarm(id))
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MainActivity lifecycle forwarding.
    fun onUserLeaveHint() {
        core.beginEntry() ?: return
        val wanted = controls ?: return
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S && !enter(wanted)) {
            core.osEntryFailed()
        }
    }

    fun onPictureInPictureModeChanged(inPictureInPicture: Boolean) {
        if (inPictureInPicture) {
            exit = PictureInPictureExitClassifier().also { it.onPictureInPictureModeChanged(true) }
            // Never attribute a completion to whatever lease is current now.
            if (!core.osEntered()) leavePip()
            return
        }
        val classifier = exit ?: return
        settle(classifier.onPictureInPictureModeChanged(false))
        main.postDelayed({ if (exit === classifier) settle(classifier.onFallbackTimeout()) }, EXIT_FALLBACK_MS)
    }

    fun onResume() {
        val classifier = exit
        if (classifier != null) {
            settle(classifier.onResume())
        } else {
            core.osReturnedWithoutEntry(settled = true)
        }
        if (controls != null && !pipAllowed()) core.onBlocked("userDisabled")
    }

    fun onPause() {
        exit?.onPause()
    }

    fun onWindowFocusChanged(hasFocus: Boolean) {
        exit?.let { settle(it.onWindowFocusChanged(hasFocus)) }
    }

    fun onStop() {
        exit?.let { settle(it.onStop()) }
    }

    private fun settle(reason: String?) {
        when (reason) {
            "system_return" -> core.osExited(restored = true)
            "system_close" -> core.osExited(restored = false)
            else -> return
        }
        exit = null
    }

    // CallPipPlatform.
    override fun supported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE) &&
            pipAllowed()

    override fun hasVideoTrack(source: CallPipSource): Boolean =
        CallPipRemoteSink.videoTrack(source) != null

    override fun attachSink(source: CallPipSource): Any? =
        CallPipRemoteSink.attach(activity, source)?.also { liveSinks += it }

    override fun releaseSink(sink: Any) {
        val remote = sink as? CallPipRemoteSink ?: return
        remote.release() // throws on failure; the sink stays owned
        liveSinks -= remote
    }

    override fun setAutoEnter(lease: CallPipIdentity?, controls: CallPipControls?) {
        this.controls = controls
        armedLease = lease
        setReceiver(controls != null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.setPictureInPictureParams(params(controls))
        }
    }

    override fun requestEnter(): Boolean {
        val wanted = controls ?: return false
        return enter(wanted)
    }

    override fun leavePip() {
        // Closing the PiP window keeps the call; the task just goes to the background.
        if (inPip()) activity.moveTaskToBack(false)
    }

    private fun enter(wanted: CallPipControls): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            activity.enterPictureInPictureMode(params(wanted))
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun inPip(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode

    private fun pipAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val ops = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        @Suppress("DEPRECATION")
        val mode = ops.checkOpNoThrow(
            AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
            Process.myUid(),
            activity.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun params(wanted: CallPipControls?): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(9, 16))
            .setActions(if (wanted == null) emptyList() else actions(wanted))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(wanted != null)
        }
        return builder.build()
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun actions(wanted: CallPipControls): List<RemoteAction> = listOf(
        action(
            "mute",
            android.R.drawable.ic_btn_speak_now,
            if (wanted.muted) R.string.call_screen_unmute else R.string.call_screen_mute,
            enabled = true,
        ),
        action(
            "camera",
            android.R.drawable.ic_menu_camera,
            if (wanted.cameraOn) R.string.call_pip_camera_off else R.string.call_pip_camera_on,
            enabled = wanted.cameraEnabled,
        ),
        action(
            "end",
            android.R.drawable.ic_menu_close_clear_cancel,
            R.string.call_notification_end,
            enabled = true,
        ),
    )

    @TargetApi(Build.VERSION_CODES.O)
    private fun action(kind: String, icon: Int, title: Int, enabled: Boolean): RemoteAction {
        val lease = armedLease
        val intent = Intent(ACTION_CONTROL).setPackage(activity.packageName)
            .putExtra(EXTRA_KIND, kind)
            .putExtra(EXTRA_INSTANCE, lease?.instanceId)
            .putExtra(EXTRA_CALL, lease?.callId)
            .putExtra(EXTRA_LEASE, lease?.leaseId ?: 0L)
        // Distinct per lease: an old control can never be rewritten to a successor.
        val pending = PendingIntent.getBroadcast(
            activity,
            "$kind/${lease?.instanceId}/${lease?.leaseId}".hashCode(),
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val text = activity.getString(title)
        return RemoteAction(Icon.createWithResource(activity, icon), text, text, pending).apply {
            isEnabled = enabled
        }
    }

    private fun setReceiver(on: Boolean) {
        if (on == receiverRegistered) return
        receiverRegistered = on
        if (on) {
            val filter = IntentFilter(ACTION_CONTROL).apply { addAction(Intent.ACTION_SCREEN_OFF) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
        } else {
            runCatching { activity.unregisterReceiver(receiver) }
        }
    }

    companion object {
        const val METHOD_CHANNEL = "mknoon/call_pip"
        const val EVENT_CHANNEL = "mknoon/call_pip/events"
        private const val ACTION_CONTROL = "com.mknoon.app.call.PIP_CONTROL"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_INSTANCE = "instanceId"
        private const val EXTRA_CALL = "callId"
        private const val EXTRA_LEASE = "leaseId"
        private const val EXIT_FALLBACK_MS = 1500L
    }
}
