package com.mknoon.app.diagnostics

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import com.mknoon.app.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal interface MknoonAppDiagnosticBackend {
    fun read(): ByteArray?
    fun replace(bytes: ByteArray)
}

internal object MknoonAppDiagnosticBridgeResult {
    private val methods = mapOf("startNode" to "node_start", "stopNode" to "node_stop", "relayReconnect" to "relay_reconnect",
        "relayProbe" to "relay_probe", "connectToPeer" to "peer_dial", "disconnectPeer" to "peer_disconnect", "nodeStatus" to "other",
        "blobDecrypt" to "other", "blobEncrypt" to "other")
    fun response(value: Any?): Pair<String, String> {
        if (value is String && value.length > 16384) return "unknown" to "unknown"
        val row = (value as? String)?.takeIf { it.length <= 16384 }?.let { runCatching { JSONObject(it) }.getOrNull() }
            ?: return "failed" to "malformed_response"
        if (row.opt("ok") == true) return "ok" to "none"
        if (row.opt("ok") != false) return "failed" to "malformed_response"
        val reason = when (row.optString("errorCode")) {
            "DECRYPT_AUTH_ERROR" -> "auth_failed"
            "DECRYPT_METADATA_ERROR" -> "metadata_invalid"
            "DECRYPT_IO_ERROR" -> "io_failed"
            "NOT_INITIALIZED", "GO_RUNTIME_NOT_ACTIVE" -> "bridge_rejected"
            else -> "unknown"
        }
        return "failed" to reason
    }
    fun wrap(method: String, arguments: Any?, delegate: MethodChannel.Result,
             record: (String, String, Map<String, Any?>, String) -> Unit,
             clock: () -> Long = SystemClock::elapsedRealtime): MethodChannel.Result {
        val operation = methods[method] ?: return delegate
        val trace = (arguments as? String)?.takeIf { it.length <= 16384 }?.let { runCatching { JSONObject(it).optJSONObject("diagnostics")?.optString("traceId") }.getOrNull() }
            ?.takeIf(MknoonAppDiagnosticSpool::uuid) ?: UUID.randomUUID().toString()
        val started = clock()
        fun emit(outcome: String, reason: String) { runCatching { record(outcome, reason, mapOf("durationMs" to (clock() - started).coerceAtLeast(0), "operation" to operation), trace) } }
        emit("started", "none")
        return object : MethodChannel.Result {
            override fun success(result: Any?) { val (outcome, reason) = response(result); emit(outcome, reason); delegate.success(result) }
            override fun error(code: String, message: String?, details: Any?) {
                emit("failed", when (code) { "GO_RUNTIME_NOT_ACTIVE" -> "bridge_rejected"; "GO_BRIDGE_DISPOSED" -> "bridge_unavailable"; "TIMEOUT" -> "bridge_timeout"; else -> "unknown" })
                delegate.error(code, message, details)
            }
            override fun notImplemented() { emit("failed", "bridge_handler_missing"); delegate.notImplemented() }
        }
    }
}

internal object MknoonAppDiagnosticFingerprint {
    fun appFrames(text: String): String? {
        // Only app-owned Java/Kotlin frame symbols and source line numbers enter
        // the hash. Thread names, exception messages, paths and native dumps do not.
        val pattern = Regex("^\\s*at (com\\.mknoon\\.app\\.[A-Za-z0-9_$.]+)\\(([A-Za-z0-9_.]+):([0-9]{1,8})\\)\\s*$")
        val frames = text.take(65_536).lineSequence().mapNotNull { line -> pattern.matchEntire(line)?.groupValues?.drop(1)?.joinToString(":") }.take(64).toList()
        if (frames.isEmpty()) return null
        return MessageDigest.getInstance("SHA-256").digest(frames.joinToString("\n").toByteArray()).joinToString("") { "%02x".format(it) }
    }
}

/** Independent encrypted no-backup archive; never contains authority handles. */
internal class AndroidAppDiagnosticBackend(context: Context) : MknoonAppDiagnosticBackend {
    private val file = AtomicFile(File(context.noBackupFilesDir, "app_diagnostics_v1.bin"))
    private val alias = "mknoon.app.diagnostics.v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    override fun read(): ByteArray? {
        if (!file.baseFile.exists()) return null
        require(file.baseFile.length() <= MknoonAppDiagnosticSpool.MAX_BYTES + 64)
        val bytes = file.readFully(); require(bytes.size >= 29 && bytes[0] == 1.toByte())
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            updateAAD(alias.toByteArray()); doFinal(bytes.copyOfRange(13, bytes.size))
        }
    }
    override fun replace(bytes: ByteArray) {
        require(bytes.size <= MknoonAppDiagnosticSpool.MAX_BYTES)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD(alias.toByteArray()) }
        val encoded = byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
        val stream = file.startWrite()
        try { stream.write(encoded); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
}

internal class MknoonAppDiagnosticSpool(
    private val backend: MknoonAppDiagnosticBackend,
    private val now: () -> Long = System::currentTimeMillis,
    private val elapsed: () -> Long = SystemClock::elapsedRealtime,
    private val installedBuild: String = "unknown",
) {
    companion object {
        const val MAX_BYTES = 1_048_576
        const val RETENTION_MS = 7L * 24 * 60 * 60 * 1000
        fun uuid(value: String?) = value != null && Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$").matches(value)
        fun build(value: String) = value.takeIf { it.length in 1..80 && Regex("^[A-Za-z0-9._+()-]+$").matches(it) } ?: "unknown"
        fun values(raw: Map<String, Any?>): Map<String, Any> = buildMap {
            for ((key, value) in raw.entries.take(16)) when {
                key in MknoonAppDiagnosticSchema.booleanValues && value is Boolean -> put(key, value)
                key in MknoonAppDiagnosticSchema.integerValues && (value is Int || value is Long) && (value as Number).toLong() in 0..9_007_199_254_740_991L -> put(key, value)
                value is String && value in (MknoonAppDiagnosticSchema.enumValues[key] ?: emptySet()) -> put(key, value)
                key in MknoonAppDiagnosticSchema.hashValues && value is String && Regex("^[0-9a-f]{64}$").matches(value) -> put(key, value)
            }
        }
        private fun valid(event: JSONObject): Boolean = runCatching {
            val keys = event.keys().asSequence().toSet()
            keys.containsAll(MknoonAppDiagnosticSchema.required) && keys.all { it in MknoonAppDiagnosticSchema.required || it in MknoonAppDiagnosticSchema.optional } &&
                event.opt("schemaVersion") == 1 && event.getString("source") == "android" && event.getString("platform") == "android" &&
                uuid(event.getString("eventId")) && uuid(event.getString("runId")) && MknoonAppDiagnosticSchema.uuidFields.all { !event.has(it) || (event.opt(it) is String && uuid(event.getString(it))) } &&
                event.getString("feature") in MknoonAppDiagnosticSchema.feature && event.getString("stage") in MknoonAppDiagnosticSchema.stage &&
                event.getString("outcome") in MknoonAppDiagnosticSchema.outcome && event.getString("reason") in MknoonAppDiagnosticSchema.reason &&
                listOf("sequence", "occurredAtMs", "elapsedMs").all { (event.opt(it) is Int || event.opt(it) is Long) && event.getLong(it) in 0..9_007_199_254_740_991L } &&
                build(event.getString("build")) == event.getString("build") &&
                event.getJSONObject("values").let { fields -> values(fields.keys().asSequence().associateWith { fields.get(it) }).size == fields.length() } &&
                event.toString().toByteArray().size <= 4096
        }.getOrDefault(false)
        fun exitReason(code: Int): Pair<String, String> = when (code) {
            4, 5 -> "crash" to "os_crash"
            6 -> "hang" to "os_anr"
            3 -> "recovery" to "os_low_memory"
            else -> "recovery" to "unknown"
        }
    }
    val runId = UUID.randomUUID().toString()
    private var enabled = false
    val captureEnabled: Boolean get() = enabled && loaded
    private var requested = false
    private var epoch = 0L
    private var enabledSince = 0L
    private var sequence = 0L
    private var dropped = 0L
    private var loaded = false
    private var openRun = false
    private val events = mutableListOf<JSONObject>()
    private val osReports = linkedSetOf<String>()
    init {
        runCatching {
            backend.read()?.let { bytes ->
                require(bytes.size <= MAX_BYTES)
                val state = JSONObject(String(bytes)); require(state.getInt("version") == 1)
                enabled = state.getBoolean("enabled"); requested = state.optBoolean("requested", enabled)
                epoch = state.optLong("consentEpoch", 0).coerceAtLeast(0)
                enabledSince = state.optLong("enabledSince", 0).coerceAtLeast(0)
                sequence = state.optLong("sequence", 0).coerceAtLeast(0); dropped = state.optLong("dropped", 0).coerceAtLeast(0)
                openRun = state.optBoolean("openRun", false)
                state.getJSONArray("events").let { rows -> for (i in 0 until rows.length()) rows.optJSONObject(i)?.takeIf(::valid)?.let(events::add) }
                state.optJSONArray("osReports")?.let { rows -> for (i in 0 until minOf(rows.length(), 128)) rows.optString(i).takeIf { Regex("^[0-9:]+$").matches(it) }?.let(osReports::add) }
            }
            loaded = true
            if (enabled) {
                val interrupted = openRun; openRun = true
                append("runtime", "recover", if (interrupted) "interrupted_unknown" else "ok", if (interrupted) "interrupted_before_final_record" else "bootstrap")
            }
        }.onFailure { enabled = false; loaded = false }
    }
    fun configure(value: Boolean, consentEpoch: Long?): Boolean {
        if (consentEpoch != null && (consentEpoch <= 0 || consentEpoch < epoch || (consentEpoch == epoch && requested != value))) return false
        if (consentEpoch == null && epoch > 0) return false
        if (!loaded) { events.clear(); osReports.clear(); sequence = 0; dropped = 0 }
        if (value && !requested) enabledSince = now()
        if (consentEpoch != null) epoch = consentEpoch
        loaded = true; requested = value; enabled = value; openRun = value
        if (!value) { events.clear(); osReports.clear(); dropped = 0; enabledSince = 0 }
        return persist().also { if (!it) enabled = false }
    }
    fun append(feature: String, stage: String, outcome: String, reason: String = "none", rawValues: Map<String, Any?> = emptyMap(), traceId: String? = null,
               occurredAt: Long = now(), eventBuild: String = installedBuild): Boolean {
        if (!enabled || !loaded || sequence >= 9_007_199_254_740_991L) return false
        if (feature !in MknoonAppDiagnosticSchema.feature || stage !in MknoonAppDiagnosticSchema.stage || outcome !in MknoonAppDiagnosticSchema.outcome || reason !in MknoonAppDiagnosticSchema.reason) return false
        val event = JSONObject().put("schemaVersion", 1).put("eventId", UUID.randomUUID().toString()).put("runId", runId)
            .put("source", "android").put("platform", "android").put("sequence", ++sequence).put("occurredAtMs", occurredAt.coerceAtLeast(0))
            .put("elapsedMs", elapsed().coerceAtLeast(0)).put("feature", feature).put("stage", stage).put("outcome", outcome).put("reason", reason)
            .put("build", build(eventBuild)).put("values", JSONObject(values(rawValues)))
        if (uuid(traceId)) event.put("traceId", traceId!!.lowercase())
        if (!valid(event)) return false
        events.add(event); enforceCaps(); return persist()
    }
    fun importExit(code: Int, timestamp: Long, fingerprint: String? = null): Boolean {
        if (!enabled || enabledSince <= 0 || timestamp < enabledSince || timestamp > now()) return false
        val id = "$timestamp:$code"; if (id in osReports) return false
        val (stage, reason) = exitReason(code)
        osReports.add(id); while (osReports.size > 128) osReports.remove(osReports.first())
        return append("runtime", stage, if (reason == "unknown") "unknown" else "failed", reason,
            mapOf("osReasonCode" to code.coerceAtLeast(0), "reportDelayed" to true, "originalBuildKnown" to false, "reportTimeIsIntervalEnd" to false, "fingerprint" to fingerprint),
            traceId = UUID.randomUUID().toString(), occurredAt = timestamp, eventBuild = "unknown")
    }
    fun drain(limit: Int): Map<String, Any> {
        enforceCaps()
        return mapOf("version" to 1, "events" to events.take(limit.coerceIn(1, 64)).map { row -> row.keys().asSequence().associateWith { key -> if (key == "values") row.getJSONObject(key).let { fields -> fields.keys().asSequence().associateWith { fields.get(it) } } else row.get(key) } }, "droppedEvents" to dropped)
    }
    fun ack(ids: List<String>): Boolean {
        if (ids.size > 64 || ids.any { !uuid(it) }) return false
        val previous = events.toList(); events.removeAll { it.optString("eventId") in ids }
        if (persist()) return true
        events.clear(); events.addAll(previous); return false
    }
    fun clear(): Boolean {
        val previous = events.toList(); val oldDropped = dropped
        events.clear(); dropped = 0
        if (persist()) return true
        events.addAll(previous); dropped = oldDropped; return false
    }
    private fun enforceCaps() {
        val cutoff = now() - RETENTION_MS
        val old = events.size; events.removeAll { it.optLong("occurredAtMs") < cutoff }; dropped += old - events.size
        fun group(e: JSONObject) = e.optString("traceId", e.optString("runId"))
        while (events.map(::group).toSet().size > 100) { val first = group(events.first()); val before = events.size; events.removeAll { group(it) == first }; dropped += before - events.size }
        for (id in events.map(::group).toSet()) {
            while (events.count { group(it) == id } > 256 || events.filter { group(it) == id }.sumOf { it.toString().toByteArray().size } > 65_536) { events.removeAt(events.indexOfFirst { group(it) == id }); dropped++ }
        }
        while (events.isNotEmpty() && encoded().size > MAX_BYTES) { events.removeAt(0); dropped++ }
    }
    private fun encoded() = JSONObject().put("version", 1).put("enabled", enabled).put("requested", requested).put("consentEpoch", epoch)
        .put("enabledSince", enabledSince).put("sequence", sequence).put("dropped", dropped).put("openRun", openRun)
        .put("events", JSONArray(events)).put("osReports", JSONArray(osReports.toList())).toString().toByteArray()
    private fun persist(): Boolean = loaded && runCatching { val data = encoded(); require(data.size <= MAX_BYTES); backend.replace(data); true }.getOrDefault(false)
}

/** Serial writer shared by Activity, FCM, Go bridge and headless workers. */
internal class MknoonAppDiagnostics private constructor(private val context: Context) {
    companion object {
        @Volatile private var shared: MknoonAppDiagnostics? = null
        fun get(context: Context): MknoonAppDiagnostics = shared ?: synchronized(this) { shared ?: MknoonAppDiagnostics(context.applicationContext).also { shared = it } }
    }
    private val writer = Executors.newSingleThreadExecutor { work -> Thread(work, "mknoon-app-diagnostics").apply { isDaemon = true } }
    private val backend = AndroidAppDiagnosticBackend(context)
    private var spool: MknoonAppDiagnosticSpool? = null
    init { writer.execute { runCatching { spool = MknoonAppDiagnosticSpool(backend, installedBuild = "${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"); importOsExits() } } }
    fun record(feature: String, stage: String, outcome: String, reason: String = "none", values: Map<String, Any?> = emptyMap(), traceId: String? = null) {
        runCatching { writer.execute { runCatching { spool?.append(feature, stage, outcome, reason, values, traceId) } } }
    }
    private fun importOsExits() {
        if (Build.VERSION.SDK_INT < 30 || spool?.captureEnabled != true) return
        runCatching {
            context.getSystemService(ActivityManager::class.java)?.getHistoricalProcessExitReasons(context.packageName, 0, 16)
                ?.sortedBy { it.timestamp }?.forEach { report ->
                    val fingerprint = if (report.reason == ApplicationExitInfo.REASON_ANR) runCatching {
                        report.traceInputStream?.bufferedReader()?.use { reader ->
                            val buffer = CharArray(65_536); val size = reader.read(buffer)
                            if (size > 0) MknoonAppDiagnosticFingerprint.appFrames(String(buffer, 0, size)) else null
                        }
                    }.getOrNull() else null
                    spool?.importExit(report.reason, report.timestamp, fingerprint)
                }
        }
    }
    fun bridge(messenger: BinaryMessenger) = MethodChannel(messenger, "mknoon/app_diagnostics").also { channel ->
        channel.setMethodCallHandler { call, result ->
            writer.execute {
                val value: Any = runCatching {
                    val args = call.arguments as? Map<*, *> ?: return@runCatching false
                    if (args["version"] != 1) return@runCatching false
                    val store = spool ?: MknoonAppDiagnosticSpool(backend, installedBuild = "${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}").also { spool = it }
                    when (call.method) {
                        "configure" -> {
                            val epoch = args["consentEpoch"]
                            if (epoch != null && epoch !is Int && epoch !is Long) false
                            else (args["enabled"] as? Boolean)?.let { store.configure(it, (epoch as? Number)?.toLong()).also { accepted -> if (accepted && it) { store.append("startup", "bridge", "ok", "bootstrap"); importOsExits() } } } ?: false
                        }
                        "drain" -> store.drain((args["limit"] as? Number)?.toInt() ?: 64)
                        "ack" -> (args["eventIds"] as? List<*>)?.takeIf { it.all { id -> id is String } }?.map { it as String }?.let(store::ack) ?: false
                        "clear" -> store.clear()
                        else -> false
                    }
                }.getOrDefault(false)
                Handler(Looper.getMainLooper()).post { result.success(value) }
            }
        }
    }
}
