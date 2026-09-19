package com.mknoon.app.call

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.cloudwebrtc.webrtc.audio.AudioProcessingController
import com.mknoon.app.CanonicalRuntimeLeaseBroker
import com.mknoon.app.ProcessCanonicalRuntimeLease
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import java.util.WeakHashMap

/** Shell-authorized, debug-only bounded synthetic signal proof on an existing call. */
class DebugCallAudioOracleReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION = "com.mknoon.app.debug.CALL_AUDIO_ORACLE"
        private val handler = Handler(Looper.getMainLooper())
        private var session: Session? = null
        private var latest: JSONObject? = null
        private val foregroundEngines = WeakHashMap<FlutterEngine, Boolean>()

        /** Called only by MainActivity's debug reflection hook, after plugin registration. */
        @JvmStatic
        fun bindEngine(engine: FlutterEngine) {
            check(Looper.myLooper() == Looper.getMainLooper())
            foregroundEngines[engine] = true
        }

        private fun publish(context: Context, value: JSONObject) {
            latest = value
            val directory = File(context.filesDir, "debug-call-audio-oracle").apply { mkdirs() }
            val temporary = File(directory, "latest.json.tmp")
            temporary.writeText(value.toString())
            check(temporary.renameTo(File(directory, "latest.json")))
        }

        private fun stop(context: Context, reason: String): JSONObject {
            val current = session ?: return latest ?: JSONObject().put("status", "idle")
            session = null
            if (!current.ownerValid()) current.ownerLost = true
            current.enabled = false
            current.processing.capturePostProcessing.removeProcessor(current.capture)
            current.processing.renderPreProcessing.removeProcessor(current.render)
            val result = current.result(reason)
            publish(context, result)
            return result
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        var response = JSONObject().put("status", "rejected")
        var starting: Session? = null
        var failureStage = "invalid_request"
        try {
            check(intent.action == ACTION)
            when (intent.getStringExtra("operation")) {
                "expiry_arm", "expiry_snapshot" -> {
                    check(intent.extras?.keySet() == setOf("operation", "nonce"))
                    val nonce = intent.getStringExtra("nonce").orEmpty()
                    val observation = MknoonCallRuntime.existingInstance()?.controller?.observeJournal()
                    response = JSONObject(if (intent.getStringExtra("operation") == "expiry_arm")
                        DebugCallLifecycleObservation.recorder.arm(nonce, checkNotNull(observation))
                    else DebugCallLifecycleObservation.recorder.snapshot(nonce, observation))
                }
                "history_snapshot" -> {
                    requestHistory(intent)
                    return
                }
                "journal_snapshot" -> {
                    // No get(context), publish, session changes, reconciliation, or ACK.
                    response = JSONObject(debugCallJournalSnapshot(
                        intent.getStringExtra("nonce").orEmpty(),
                    ) { MknoonCallRuntime.existingInstance()?.controller?.observeJournal() })
                }
                "start" -> {
                    check(session == null)
                    check(intent.getBooleanExtra("testSignal", false))
                    val nonce = intent.getStringExtra("nonce").orEmpty()
                    check(Regex("^[0-9a-f]{16,64}$").matches(nonce))
                    val role = intent.getStringExtra("role")
                    check(role == "caller" || role == "callee")
                    val duration = intent.getIntExtra("durationMs", 12000)
                    check(duration in 5000..30000)
                    val controller = MknoonCallRuntime.get(context).controller
                    failureStage = "no_current_native_call"
                    val call = checkNotNull(controller.activeNativeCallId())
                    failureStage = "no_exact_adopted_audio_owner"
                    check(controller.withActiveAudioOwner(call, false) { true })
                    failureStage = "canonical_foreground_engine_unavailable"
                    val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
                    check(lease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
                        lease.role == CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
                    val engine = foregroundEngines.keys.singleOrNull {
                        lease.ownerId == "foreground-${System.identityHashCode(it)}"
                    }
                    checkNotNull(engine)
                    failureStage = "canonical_webrtc_plugin_unavailable"
                    val plugin = checkNotNull(engine.plugins.get(FlutterWebRTCPlugin::class.java)
                        as? FlutterWebRTCPlugin)
                    failureStage = "webrtc_audio_processing_unavailable"
                    val processing = checkNotNull(plugin.audioProcessingController)
                    failureStage = "processor_registration_failed"
                    val owner = ProcessingOwner(engine, checkNotNull(lease.generation), plugin, processing)
                    val current = Session(controller, call, owner, nonce, role, duration,
                        intent.getBooleanExtra("verifyTrackMute", false))
                    starting = current
                    session = current
                    processing.capturePostProcessing.addProcessor(current.capture)
                    processing.renderPreProcessing.addProcessor(current.render)
                    response = current.result("running")
                    publish(context, response)
                    handler.postDelayed({
                        if (session === current) {
                            runCatching { stop(context.applicationContext, "duration_elapsed") }
                        }
                    }, duration.toLong())
                    handler.post(object : Runnable {
                        override fun run() {
                            if (session !== current) return
                            if (!current.ownerValid()) {
                                current.ownerLost = true
                                runCatching { stop(context.applicationContext, "owner_lost") }
                            } else handler.postDelayed(this, 100)
                        }
                    })
                }
                "snapshot" -> {
                    check(intent.getStringExtra("nonce") == (session?.nonce ?: latest?.optString("nonce")))
                    response = session?.result("running") ?: latest ?: JSONObject().put("status", "idle")
                    publish(context, response)
                }
                "stop" -> {
                    check(intent.getStringExtra("nonce") == (session?.nonce ?: latest?.optString("nonce")))
                    response = stop(context, "explicit_stop")
                }
                else -> error("operation")
            }
            resultCode = Activity.RESULT_OK
        } catch (_: Exception) {
            if (starting != null && session === starting) {
                runCatching { stop(context, "setup_failed") }
            }
            response = JSONObject().put("status", "rejected").put("reason", failureStage)
            resultCode = Activity.RESULT_CANCELED
        }
        resultData = response.toString()
    }

    /** One bounded request to the already-authorized foreground engine. No engine/runtime creation. */
    private fun requestHistory(intent: Intent) {
        val started = SystemClock.elapsedRealtime()
        val request = debugHistoryRequest(intent.extras?.keySet().orEmpty()) { key ->
            @Suppress("DEPRECATION")
            intent.extras?.get(key)
        }
        val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
        check(lease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
            lease.role == CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
        val engine = checkNotNull(foregroundEngines.keys.singleOrNull {
            lease.ownerId == "foreground-${System.identityHashCode(it)}"
        })
        val controller = checkNotNull(MknoonCallRuntime.existingInstance()?.controller)
        val initial = controller.observeJournal()
        val currentCall = initial.descriptor?.nativeCallId
        if (request["operation"] == "current") {
            check(initial.liveOwnerPresent && !initial.cleanupPending &&
                initial.descriptor?.terminalEvent == null && currentCall != null)
            request["_nativeCallId"] = currentCall.toString()
        } else check(!initial.liveOwnerPresent && !initial.cleanupPending)
        fun ownerValid(): Boolean {
            val current = ProcessCanonicalRuntimeLease.broker.snapshot()
            if (current != lease || foregroundEngines[engine] != true) return false
            val observation = runCatching { controller.observeJournal() }.getOrNull() ?: return false
            return if (request["operation"] == "current")
                observation.liveOwnerPresent && !observation.cleanupPending &&
                    observation.descriptor?.nativeCallId == currentCall && observation.descriptor?.terminalEvent == null
            else !observation.liveOwnerPresent && !observation.cleanupPending
        }
        val pending = goAsync()
        val gate = DebugCallEvidenceReplyGate(started, SystemClock::elapsedRealtime, ::ownerValid) { value ->
            pending.resultCode = Activity.RESULT_OK
            pending.resultData = JSONObject(value).toString()
            pending.finish()
        }
        val timeout = Runnable { gate.complete { mapOf("status" to "unavailable") } }
        handler.postDelayed(timeout, (5000 - (SystemClock.elapsedRealtime() - started)).coerceAtLeast(0))
        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, "mknoon/debug_call_evidence")
                .invokeMethod("snapshot", request, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        handler.removeCallbacks(timeout)
                        gate.complete {
                            debugHistoryResponse(result, request["nonce"] as String,
                                request["operation"] as String, currentCall?.let {
                                    debugEvidenceHash("${request["nonce"]}:$it")
                                })
                        }
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        handler.removeCallbacks(timeout)
                        gate.complete { mapOf("status" to "unavailable") }
                    }
                    override fun notImplemented() = error("unavailable", null, null)
                })
        } catch (_: Exception) {
            handler.removeCallbacks(timeout)
            gate.complete { mapOf("status" to "unavailable") }
        }
    }

    private class ProcessingOwner(
        private val engine: FlutterEngine,
        private val generation: Long,
        private val plugin: FlutterWebRTCPlugin,
        val processing: AudioProcessingController,
    ) {
        fun isCurrent(): Boolean {
            val lease = ProcessCanonicalRuntimeLease.broker.snapshot()
            return lease.state == CanonicalRuntimeLeaseBroker.State.ACTIVE &&
                lease.role == CanonicalRuntimeLeaseBroker.Role.FOREGROUND &&
                lease.generation == generation &&
                lease.ownerId == "foreground-${System.identityHashCode(engine)}" &&
                engine.plugins.get(FlutterWebRTCPlugin::class.java) === plugin &&
                runCatching { plugin.audioProcessingController === processing }.getOrDefault(false)
        }
    }

    private class Session(
        private val controller: MknoonCallLifecycleController,
        private val call: UUID,
        private val owner: ProcessingOwner,
        val nonce: String,
        private val role: String,
        private val duration: Int,
        verifyTrackMute: Boolean,
    ) {
        val processing get() = owner.processing
        private val started = SystemClock.elapsedRealtime()
        private val startedAtMs = System.currentTimeMillis()
        private val signal = DebugCallAudioSignal(role == "caller", verifyTrackMute)
        @Volatile var enabled = true
        @Volatile var ownerLost = false
        private val binding = MessageDigest.getInstance("SHA-256")
            .digest("$nonce:$call".toByteArray()).joinToString("") { "%02x".format(it) }

        fun ownerValid(): Boolean = owner.isCurrent() &&
            controller.withActiveAudioOwner(call, false) { true }

        private fun process(capture: Boolean, frames: Int, buffer: ByteBuffer) {
            if (!enabled || SystemClock.elapsedRealtime() - started >= duration) return
            val valid = try {
                controller.withActiveAudioOwner(call, false) { muted ->
                    if (capture) signal.inject(frames, buffer, muted) else signal.observe(frames, buffer)
                    true
                }
            } catch (_: Exception) {
                false
            }
            if (!valid) { ownerLost = true; enabled = false }
        }

        val capture = object : AudioProcessingAdapter.ExternalAudioFrameProcessing {
            override fun initialize(sampleRateHz: Int, numChannels: Int) = Unit
            override fun reset(newRate: Int) = Unit
            override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) =
                process(true, numFrames, buffer)
        }
        val render = object : AudioProcessingAdapter.ExternalAudioFrameProcessing {
            override fun initialize(sampleRateHz: Int, numChannels: Int) = Unit
            override fun reset(newRate: Int) = Unit
            override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) =
                process(false, numFrames, buffer)
        }

        fun result(reason: String): JSONObject {
            val measurement = signal.result()
            return JSONObject(measurement).put("schema", "mknoon.debug-call-audio-signal.v1")
                .put("status", if (reason == "running") "running" else "complete")
                .put("nonce", nonce).put("role", role).put("callBindingSha256", binding)
                .put("startedAtMs", startedAtMs)
                .put("elapsedMs", SystemClock.elapsedRealtime() - started)
                .put("durationMs", duration).put("reason", reason)
                .put("exactOwnerRetained", !ownerLost)
                .put("canonicalEngineBound", true)
                .put("processorsRemoved", !enabled && reason != "running")
                .put("passed", reason != "running" && !ownerLost &&
                    measurement["decodedSignalVerified"] == true &&
                    (measurement["injectedFrames"] as Int) >= 120)
                .put("signalBoundary", "capture_post_processing_to_remote_render_pre_processing")
                .put("physicalMicrophoneOrSpeakerClaimed", false)
                .put("audioSamplesRetained", false)
        }
    }
}
