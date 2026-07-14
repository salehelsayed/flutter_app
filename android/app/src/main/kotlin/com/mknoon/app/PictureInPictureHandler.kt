package com.mknoon.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

/**
 * Android-only channel boundary for received-video Picture-in-Picture.
 *
 * The media path never enters an Intent, Bundle, log, or durable native store.
 * It exists only in [PictureInPictureSessionRegistry] for the lifetime of the
 * current process and is fenced by both session and attachment identity.
 */
internal class PictureInPictureHandler(
    private val activity: Activity,
    messenger: BinaryMessenger? = null,
    private val registry: PictureInPictureSessionRegistry = PictureInPictureProcessRegistry.registry,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    private val hasPictureInPictureFeature: () -> Boolean = {
        activity.packageManager.hasSystemFeature(
            PackageManager.FEATURE_PICTURE_IN_PICTURE,
        )
    },
    private val resolveOwnedVideo: (String) -> File? = { rawPath ->
        resolveOwnedVideo(activity, rawPath)
    },
    private val launchActivity: (Intent) -> Unit = activity::startActivity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        const val METHOD_CHANNEL = "mknoon/picture_in_picture"
        const val EVENT_CHANNEL = "mknoon/picture_in_picture/events"
        const val SESSION_EXTRA = "mknoon.picture_in_picture.session"

        private val START_FIELDS =
            setOf("session", "attachment", "path", "positionMs", "durationMs")
        private val FENCE_FIELDS = setOf("session", "attachment")
        private val APP_OWNED_MEDIA_ROOTS = setOf("media", "local_media", "post_media")

        internal fun isSupported(sdkInt: Int, hasFeature: Boolean): Boolean =
            sdkInt >= Build.VERSION_CODES.O && hasFeature

        internal fun resolveOwnedPath(dataDir: String?, rawPath: String): File? {
            if (rawPath.isBlank() || rawPath != rawPath.trim() || rawPath.length > 4096) {
                return null
            }
            if (dataDir.isNullOrBlank()) return null
            val literalDataRoot = File(dataDir).absoluteFile
            val canonicalDataRoot = try {
                literalDataRoot.canonicalFile
            } catch (_: Exception) {
                return null
            }
            val literalDocumentsRoot = File(canonicalDataRoot, "app_flutter").absoluteFile
            val documentsRoot = try {
                literalDocumentsRoot.canonicalFile
            } catch (_: Exception) {
                return null
            }
            // path_provider's getApplicationDocumentsDirectory() resolves to
            // applicationInfo.dataDir/app_flutter on Android. A replaced root
            // must never become native path authority.
            if (literalDocumentsRoot.path != documentsRoot.path) return null
            val candidate = try {
                File(rawPath).canonicalFile
            } catch (_: Exception) {
                return null
            }
            if (!candidate.isFile) return null

            val owned = APP_OWNED_MEDIA_ROOTS.any { rootName ->
                val literalRoot = File(documentsRoot, rootName).absoluteFile
                val canonicalRoot = try {
                    literalRoot.canonicalFile
                } catch (_: Exception) {
                    return@any false
                }
                // A replaced/symlinked literal root is never app-owned authority.
                if (literalRoot.path != canonicalRoot.path) return@any false
                candidate.path.startsWith(canonicalRoot.path + File.separator)
            }
            return candidate.takeIf { owned }
        }

        internal fun resolveOwnedVideo(activity: Activity, rawPath: String): File? {
            val candidate = resolveOwnedPath(activity.applicationInfo.dataDir, rawPath)
                ?: return null

            val retriever = MediaMetadataRetriever()
            return try {
                retriever.setDataSource(candidate.path)
                val hasVideo = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO,
                )
                candidate.takeIf { hasVideo == "yes" }
            } catch (_: RuntimeException) {
                null
            } finally {
                try {
                    retriever.release()
                } catch (_: RuntimeException) {
                    // Release failure cannot turn an invalid source into authority.
                }
            }
        }
    }

    private val methodChannel = messenger?.let { MethodChannel(it, METHOD_CHANNEL) }
    private val eventChannel = messenger?.let { EventChannel(it, EVENT_CHANNEL) }
    private var disposed = false

    init {
        PictureInPictureEngineCleanupCoordinator.bind(this)
    }

    init {
        methodChannel?.setMethodCallHandler(this)
        eventChannel?.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("pip_unavailable", "Picture-in-Picture is unavailable", null)
            return
        }
        when (call.method) {
            "capability" -> capability(call.arguments, result)
            "start" -> start(call.arguments, result)
            "activate" -> activate(call.arguments, result)
            "stop" -> stop(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (!disposed && arguments == null) registry.setEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        registry.setEventSink(null)
    }

    fun dispose(reason: String) {
        if (disposed) return
        disposed = true
        PictureInPictureEngineCleanupCoordinator.unbind(this)
        registry.stopCurrent(reason)
        registry.setEventSink(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
    }

    private fun capability(arguments: Any?, result: MethodChannel.Result) {
        if (arguments != null) {
            badArguments(result)
            return
        }
        result.success(
            mapOf(
                "supported" to isSupported(sdkInt, hasPictureInPictureFeature()),
            ),
        )
    }

    private fun start(arguments: Any?, result: MethodChannel.Result) {
        if (!isSupported(sdkInt, hasPictureInPictureFeature())) {
            result.error("unsupported", "Picture-in-Picture is unavailable", null)
            return
        }
        val map = arguments as? Map<*, *>
        if (map == null || map.keys != START_FIELDS) {
            badArguments(result)
            return
        }
        val session = opaqueIdentifier(map["session"], 128)
        val attachment = opaqueIdentifier(map["attachment"], 512)
        val rawPath = map["path"] as? String
        val positionMs = integralMilliseconds(map["positionMs"])
        val durationMs = nullableIntegralMilliseconds(map["durationMs"])
        if (
            session == null ||
            attachment == null ||
            rawPath == null ||
            positionMs == null ||
            durationMs === InvalidDuration
        ) {
            badArguments(result)
            return
        }
        val canonicalVideo = resolveOwnedVideo(rawPath)
        if (canonicalVideo == null) {
            result.error("invalid_path", "Video is not an app-owned canonical file", null)
            return
        }
        val knownDurationMs = durationMs as Int?
        val normalizedPositionMs = if (knownDurationMs == null) {
            positionMs
        } else {
            positionMs.coerceAtMost(knownDurationMs)
        }
        val request = PictureInPictureSessionRequest(
            session = session,
            attachment = attachment,
            path = canonicalVideo.path,
            positionMs = normalizedPositionMs,
            durationMs = knownDurationMs,
        )
        if (!registry.begin(request)) {
            result.error("busy", "A Picture-in-Picture session is already active", null)
            return
        }
        try {
            // The opaque session is the only Intent extra. Media identity and
            // path remain solely in the process-local registry.
            launchActivity(
                Intent(activity, ReceivedVideoPictureInPictureActivity::class.java).apply {
                    putExtra(SESSION_EXTRA, session)
                },
            )
        } catch (_: RuntimeException) {
            registry.terminate(
                session = session,
                attachment = attachment,
                state = "failed",
                reason = "playback_error",
                observedPositionMs = normalizedPositionMs,
                durationMs = knownDurationMs,
            )
            result.error("activity_unavailable", "Picture-in-Picture could not start", null)
            return
        }
        result.success(mapOf("accepted" to true))
    }

    private fun activate(arguments: Any?, result: MethodChannel.Result) {
        val fence = parseFence(arguments)
        if (fence == null) {
            badArguments(result)
            return
        }
        if (!registry.activate(fence.first, fence.second)) {
            result.error("stale_session", "Picture-in-Picture session is not ready", null)
            return
        }
        result.success(mapOf("accepted" to true))
    }

    private fun stop(arguments: Any?, result: MethodChannel.Result) {
        val fence = parseFence(arguments)
        if (fence == null) {
            badArguments(result)
            return
        }
        if (!registry.stop(fence.first, fence.second, "explicit_stop")) {
            result.error("stale_session", "Picture-in-Picture session is not active", null)
            return
        }
        result.success(mapOf("accepted" to true))
    }

    private fun parseFence(arguments: Any?): Pair<String, String>? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != FENCE_FIELDS) return null
        val session = opaqueIdentifier(map["session"], 128) ?: return null
        val attachment = opaqueIdentifier(map["attachment"], 512) ?: return null
        return session to attachment
    }

    private fun opaqueIdentifier(value: Any?, maxLength: Int): String? {
        val identifier = value as? String ?: return null
        if (
            identifier.isBlank() ||
            identifier.length > maxLength ||
            identifier != identifier.trim() ||
            identifier.any(Char::isISOControl)
        ) {
            return null
        }
        return identifier
    }

    private fun integralMilliseconds(value: Any?): Int? {
        val number = value as? Number ?: return null
        val asDouble = number.toDouble()
        if (!asDouble.isFinite() || asDouble < 0 || asDouble > Int.MAX_VALUE) return null
        val asInt = number.toInt()
        return asInt.takeIf { it.toDouble() == asDouble }
    }

    private fun nullableIntegralMilliseconds(value: Any?): Any? =
        if (value == null) {
            null
        } else {
            integralMilliseconds(value)?.takeIf { it > 0 } ?: InvalidDuration
        }

    private fun badArguments(result: MethodChannel.Result) {
        result.error("bad_args", "Invalid Picture-in-Picture request", null)
    }

    private object InvalidDuration
}

internal data class PictureInPictureSessionRequest(
    val session: String,
    val attachment: String,
    val path: String,
    val positionMs: Int,
    val durationMs: Int?,
)

internal data class PictureInPictureSessionSnapshot(
    val active: Boolean,
    val session: String?,
    val attachment: String?,
    val positionMs: Int?,
    val durationMs: Int?,
)

internal object PictureInPictureEventContract {
    val STATES = setOf(
        "nativeReady",
        "active",
        "checkpoint",
        "restoring",
        "stopped",
        "completed",
        "failed",
    )
    val TERMINAL_STATE_BY_REASON = mapOf(
        "system_return" to "restoring",
        "system_close" to "stopped",
        "explicit_stop" to "stopped",
        "interrupted" to "stopped",
        "completed" to "completed",
        "activity_destroyed" to "stopped",
        "flutter_engine_detached" to "stopped",
        "host_destroyed" to "stopped",
        "playback_error" to "failed",
    )
    val REASONS = TERMINAL_STATE_BY_REASON.keys
    val TERMINAL_STATES = setOf("restoring", "stopped", "completed", "failed")

    fun isTerminalCompatible(state: String, reason: String): Boolean =
        TERMINAL_STATE_BY_REASON[reason] == state
}

/** A single process-local native playback owner with exactly-once terminals. */
internal class PictureInPictureSessionRegistry(
    private val terminalLogger: (String) -> Unit = { message ->
        Log.i(LIFECYCLE_TAG, message)
    },
) {
    private companion object {
        const val LIFECYCLE_TAG = "MknoonPiP"
    }

    private data class Session(
        val request: PictureInPictureSessionRequest,
        var state: String = "starting",
        var positionMs: Int = request.positionMs,
        var durationMs: Int? = request.durationMs,
        var activity: WeakReference<ReceivedVideoPictureInPictureActivity> =
            WeakReference(null),
        var terminalEmitted: Boolean = false,
    )

    private val lock = Any()
    private var current: Session? = null
    private var eventSink: EventChannel.EventSink? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        synchronized(lock) { eventSink = sink }
    }

    fun begin(request: PictureInPictureSessionRequest): Boolean = synchronized(lock) {
        if (current != null) return@synchronized false
        current = Session(request)
        true
    }

    fun current(session: String): PictureInPictureSessionRequest? = synchronized(lock) {
        current
            ?.takeIf { !it.terminalEmitted && it.request.session == session }
            ?.request
    }

    fun attach(
        session: String,
        attachment: String,
        activity: ReceivedVideoPictureInPictureActivity,
    ): Boolean = synchronized(lock) {
        val owner = matching(session, attachment) ?: return@synchronized false
        owner.activity = WeakReference(activity)
        true
    }

    fun detach(activity: ReceivedVideoPictureInPictureActivity) {
        synchronized(lock) {
            val owner = current ?: return
            if (owner.activity.get() === activity) owner.activity.clear()
        }
    }

    fun nativeReady(
        session: String,
        attachment: String,
        positionMs: Int,
        durationMs: Int?,
    ): Boolean {
        val event = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            if (owner.state != "starting") return false
            owner.durationMs = normalizedDuration(owner.durationMs, durationMs)
            owner.positionMs = boundPosition(
                maxOf(owner.positionMs, positionMs),
                owner.durationMs,
            )
            owner.state = "nativeReady"
            envelope(owner, state = "nativeReady", reason = null)
        }
        emit(event)
        return true
    }

    fun activate(session: String, attachment: String): Boolean {
        val activity = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            if (owner.state != "nativeReady") return false
            owner.activity.get() ?: return false
        }
        return activity.activateNativePlayback()
    }

    fun active(session: String, attachment: String): Boolean {
        val event = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            if (owner.state != "nativeReady") return false
            owner.state = "active"
            envelope(owner, state = "active", reason = null)
        }
        emit(event)
        return true
    }

    fun checkpoint(
        session: String,
        attachment: String,
        observedPositionMs: Int,
        durationMs: Int?,
    ): Boolean {
        val event = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            if (owner.state != "active") return false
            owner.durationMs = normalizedDuration(owner.durationMs, durationMs)
            owner.positionMs = boundPosition(
                maxOf(owner.positionMs, observedPositionMs),
                owner.durationMs,
            )
            envelope(owner, state = "checkpoint", reason = null)
        }
        emit(event)
        return true
    }

    fun stop(session: String, attachment: String, reason: String): Boolean {
        if (reason !in PictureInPictureEventContract.REASONS) return false
        val activity = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            owner.activity.get()
        }
        if (activity != null) return activity.stopNativePlayback(reason)
        return terminate(
            session = session,
            attachment = attachment,
            state = "stopped",
            reason = reason,
            observedPositionMs = null,
            durationMs = null,
        )
    }

    fun stopCurrent(reason: String): Boolean {
        val fence = synchronized(lock) {
            val owner = current ?: return false
            owner.request.session to owner.request.attachment
        }
        return stop(fence.first, fence.second, reason)
    }

    fun terminate(
        session: String,
        attachment: String,
        state: String,
        reason: String,
        observedPositionMs: Int?,
        durationMs: Int?,
    ): Boolean {
        if (!PictureInPictureEventContract.isTerminalCompatible(state, reason)) {
            return false
        }
        val event = synchronized(lock) {
            val owner = matching(session, attachment) ?: return false
            if (owner.terminalEmitted) return false
            owner.terminalEmitted = true
            owner.durationMs = normalizedDuration(owner.durationMs, durationMs)
            owner.positionMs = if (state == "completed") {
                0
            } else {
                val observed = observedPositionMs ?: 0
                boundPosition(maxOf(owner.positionMs, observed), owner.durationMs)
            }
            owner.state = state
            val payload = envelope(owner, state = state, reason = reason)
            current = null
            payload
        }
        terminalLogger("[MKNOON_PIP] TERMINAL state=$state reason=$reason")
        emit(event)
        return true
    }

    fun snapshot(): PictureInPictureSessionSnapshot = synchronized(lock) {
        val owner = current
        PictureInPictureSessionSnapshot(
            active = owner != null && !owner.terminalEmitted,
            session = owner?.request?.session,
            attachment = owner?.request?.attachment,
            positionMs = owner?.positionMs,
            durationMs = owner?.durationMs,
        )
    }

    private fun matching(session: String, attachment: String): Session? {
        val owner = current ?: return null
        if (
            owner.terminalEmitted ||
            owner.request.session != session ||
            owner.request.attachment != attachment
        ) {
            return null
        }
        return owner
    }

    private fun envelope(
        owner: Session,
        state: String,
        reason: String?,
    ): Map<String, Any?> = linkedMapOf(
        "session" to owner.request.session,
        "attachment" to owner.request.attachment,
        "state" to state,
        "positionMs" to owner.positionMs,
        "durationMs" to owner.durationMs,
        "reason" to reason,
    )

    private fun normalizedDuration(previous: Int?, observed: Int?): Int? =
        when {
            observed != null && observed > 0 -> observed
            previous != null && previous > 0 -> previous
            else -> null
        }

    private fun boundPosition(positionMs: Int, durationMs: Int?): Int =
        positionMs.coerceAtLeast(0).let { position ->
            if (durationMs == null) position else position.coerceAtMost(durationMs)
        }

    private fun emit(event: Map<String, Any?>) {
        val sink = synchronized(lock) { eventSink }
        sink?.success(event)
    }
}

internal object PictureInPictureProcessRegistry {
    val registry = PictureInPictureSessionRegistry()
}
