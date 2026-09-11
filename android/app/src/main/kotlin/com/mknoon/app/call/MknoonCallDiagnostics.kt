package com.mknoon.app.call

import com.mknoon.app.diagnostics.MknoonAppDiagnosticAdmission

import android.content.Context
import com.mknoon.app.BuildConfig
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal interface MknoonCallDiagnosticBackend {
    fun read(): ByteArray?
    fun replace(bytes: ByteArray)
}

internal object MknoonCallDiagnosticScope {
    private val local = ThreadLocal<Map<String, Any?>>()
    fun current(): Map<String, Any?> = local.get() ?: emptyMap()
    fun <T> withContext(context: Map<String, Any?>, action: () -> T): T {
        val previous = local.get(); local.set(context)
        return try { action() } finally { if (previous == null) local.remove() else local.set(previous) }
    }
}

/** Private encrypted file, independent of the authoritative native call journal. */
internal class AndroidCallDiagnosticBackend(context: Context) : MknoonCallDiagnosticBackend {
    private val file = AtomicFile(File(context.noBackupFilesDir, "call_diagnostics_v1.bin"))
    private val alias = "mknoon.call.diagnostics.v1"
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
        require(file.baseFile.length() <= MknoonCallDiagnosticSpool.MAX_BYTES + 64)
        val bytes = file.readFully()
        require(bytes.size >= 29 && bytes[0] == 1.toByte())
        return Cipher.getInstance("AES/GCM/NoPadding").run {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
            updateAAD(alias.toByteArray(Charsets.UTF_8))
            doFinal(bytes.copyOfRange(13, bytes.size))
        }
    }
    override fun replace(bytes: ByteArray) {
        require(bytes.size <= MknoonCallDiagnosticSpool.MAX_BYTES)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, key()); updateAAD(alias.toByteArray(Charsets.UTF_8))
        }
        val protected = byteArrayOf(1) + cipher.iv + cipher.doFinal(bytes)
        val stream = file.startWrite()
        try { stream.write(protected); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
}

internal class MknoonCallDiagnosticSpool(
    private val backend: MknoonCallDiagnosticBackend,
    private val now: () -> Long = System::currentTimeMillis,
    private val elapsed: () -> Long = SystemClock::elapsedRealtime,
    private val installedBuild: String? = null,
) {
    companion object {
        const val MAX_BYTES = 1_048_576
        const val RETENTION_MS = 7L * 24 * 60 * 60 * 1000
        fun journalReason(type: PendingNativeCallEventType, input: Map<String, Any?>): String = when (type) {
            PendingNativeCallEventType.PROVIDER_REMOVED -> "provider_reset"
            PendingNativeCallEventType.NATIVE_FAILURE -> "native_lifecycle_failed"
            PendingNativeCallEventType.EXPIRED -> "expired"
            PendingNativeCallEventType.REMOTE_CANCELLED -> "remote_terminal"
            PendingNativeCallEventType.END_REQUESTED, PendingNativeCallEventType.DECLINE_REQUESTED -> commandReason(input)
            else -> "none"
        }
        fun validBuild(value: String): Boolean = Regex("^[0-9A-Za-z.+_-]{1,80}$").matches(value)
        fun commandReason(input: Map<String, Any?>): String =
            (context(input)["reason"] as? String)?.takeUnless { it == "none" } ?: "unknown"
        fun uuid(value: String): Boolean = value.length == 36 && runCatching { UUID.fromString(value).toString() == value.lowercase() }.getOrDefault(false)
        fun handle(value: String): Boolean = CALL_RANDOM_ID.matches(value) || CANONICAL_CALL_HANDLE.matches(value)
        fun canonical(value: String): String = runCatching { nativeCallIdFromCallHandle(value).toString() }.getOrDefault(value)
        fun context(input: Map<String, Any?>): Map<String, Any> = buildMap {
            for (key in listOf("traceId", "requestId", "operationId", "parentOperationId")) {
                (input[key] as? String)?.takeIf(::uuid)?.let { put(key, it.lowercase()) }
            }
            // Wire contexts use cause; emitted events and private native scopes use reason.
            ((input["cause"] ?: input["reason"]) as? String)?.takeIf { it in MknoonCallDiagnosticSchema.reason }?.let { put("reason", it) }
        }
        fun values(input: Map<String, Any?>): Map<String, Any> = buildMap {
            for ((key, value) in input) {
                when {
                    key in MknoonCallDiagnosticSchema.booleanValues && value is Boolean -> put(key, value)
                    key in MknoonCallDiagnosticSchema.integerValues && (value is Int || value is Long) && (value as Number).toLong() in 0..9_007_199_254_740_991L -> put(key, value)
                    value is String && value in (MknoonCallDiagnosticSchema.enumValues[key] ?: emptySet()) -> put(key, value)
                }
            }
        }
        private fun validEvent(event: JSONObject): Boolean = runCatching {
            val keys = event.keys().asSequence().toSet()
            keys.all { it in MknoonCallDiagnosticSchema.eventKeys } && event.getInt("schemaVersion") == 1 &&
                event.getString("source") == "android" && event.getString("role") in setOf("caller", "callee", "local") &&
                uuid(event.getString("eventId")) && uuid(event.getString("runId")) &&
                listOf("traceId", "requestId", "operationId", "parentOperationId").all { !event.has(it) || uuid(event.getString(it)) } &&
                listOf("sequence", "occurredAtMs", "elapsedMs").all { event.getLong(it) >= 0 } &&
                event.getString("stage") in MknoonCallDiagnosticSchema.stage && event.getString("action") in MknoonCallDiagnosticSchema.action &&
                event.getString("outcome") in MknoonCallDiagnosticSchema.outcome && event.getString("reason") in MknoonCallDiagnosticSchema.reason &&
                event.getJSONObject("values").let { values(jsonMap(it)).size == it.length() } &&
                (!event.has("build") || (event.opt("build") is String && validBuild(event.getString("build")))) && event.toString().toByteArray().size <= 4096
        }.getOrDefault(false)
        internal fun jsonMap(value: JSONObject): Map<String, Any> = value.keys().asSequence().associateWith { key ->
            when (val field = value.get(key)) {
                is JSONObject -> jsonMap(field)
                else -> field
            }
        }
    }
    val runId = UUID.randomUUID().toString()
    private var enabled = false
    private var loaded = false
    private var sequence = 0L
    private var dropped = 0L
    private var consentEpoch = 0L
    private var requestedEnabled = false
    private var openRun: String? = null
    private val events = mutableListOf<JSONObject>()
    private val pendingEvents = mutableSetOf<String>()
    private val bindings = linkedMapOf<String, JSONObject>()

    init {
        runCatching {
            backend.read()?.let { bytes ->
                require(bytes.size <= MAX_BYTES)
                val root = JSONObject(String(bytes, Charsets.UTF_8))
                require(root.getInt("version") == 1)
                enabled = root.getBoolean("enabled")
                requestedEnabled = root.optBoolean("requestedEnabled", enabled)
                sequence = root.optLong("sequence", 0).coerceAtLeast(0)
                dropped = root.optLong("dropped", 0).coerceAtLeast(0)
                consentEpoch = root.optLong("consentEpoch", 0).coerceAtLeast(0)
                openRun = root.optString("openRun").takeIf(::uuid)
                root.getJSONArray("events").let { data -> for (i in 0 until data.length()) data.optJSONObject(i)?.takeIf(::validEvent)?.let(events::add) }
                root.getJSONObject("bindings").let { data -> for (key in data.keys()) if (handle(key)) data.optJSONObject(key)?.let { bindings[key] = it } }
            }
            loaded = true
            if (enabled) {
                val interrupted = openRun != null
                openRun = runId
                append(stage = "runtime", action = "recover", outcome = if (interrupted) "interrupted" else "ok",
                    reason = if (interrupted) "interrupted_before_final_record" else "bootstrap")
            }
        }.onFailure { enabled = false; loaded = false }
    }
    fun configure(value: Boolean, epoch: Long? = null): Boolean {
        if (epoch != null && (epoch <= 0 || epoch < consentEpoch || (epoch == consentEpoch && requestedEnabled != value))) return false
        if (epoch == null && consentEpoch > 0) return false
        if (!loaded) { events.clear(); bindings.clear(); sequence = 0; dropped = 0 }
        if (epoch != null) consentEpoch = epoch
        loaded = true; requestedEnabled = value; enabled = value; openRun = if (value) runId else null
        if (!value) { events.clear(); bindings.clear(); dropped = 0 }
        return persist().also { if (!it) enabled = false }
    }
    fun bind(handle: String, traceId: String, context: Map<String, Any?> = emptyMap()): Boolean {
        if (!enabled || !handle(handle) || !uuid(traceId) || canonical(handle) == traceId.lowercase()) return false
        prune()
        val key = canonical(handle)
        val previous = bindings[key]?.optString("traceId")
        bindings[key] = JSONObject(context(context)).put("traceId", traceId.lowercase()).put("at", now())
        if (previous != null && previous != traceId.lowercase()) events.filter { it.optString("traceId") == previous }.forEach { it.put("traceId", traceId.lowercase()) }
        enforceCaps(); return persist()
    }
    fun lookup(handle: String): Map<String, Any> {
        if (!enabled || !handle(handle)) return mapOf("version" to 1)
        prune()
        val canonical = canonical(handle)
        val trace = bindings[canonical]?.optString("traceId")?.takeIf { uuid(it) && it != canonical }
        return if (trace == null) mapOf("version" to 1) else mapOf("version" to 1, "traceId" to trace)
    }
    fun append(handle: String? = null, stage: String, action: String, outcome: String, reason: String = "none",
               values: Map<String, Any?> = emptyMap(), context: Map<String, Any?> = emptyMap(), deferPersistence: Boolean = false): Boolean {
        if (!enabled || !loaded || sequence == Long.MAX_VALUE) return false
        if (!deferPersistence) prune()
        val metadata = mutableMapOf<String, Any>()
        if (handle != null && handle(handle)) {
            val key = canonical(handle)
            if ((bindings[key]?.optLong("at") ?: Long.MAX_VALUE) < (now() - RETENTION_MS).coerceAtLeast(0)) bindings.remove(key)
            metadata.putAll(jsonMap(bindings.getOrPut(key) { JSONObject().put("traceId", UUID.randomUUID().toString()).put("at", now()) }))
        }
        metadata.putAll(context(context))
        val event = JSONObject().put("schemaVersion", 1).put("eventId", UUID.randomUUID().toString()).put("source", "android")
            .put("role", (context["role"] as? String)?.takeIf { it in setOf("caller", "callee", "local") } ?: "local")
            .put("runId", runId).put("sequence", ++sequence).put("occurredAtMs", now().coerceAtLeast(0)).put("elapsedMs", elapsed().coerceAtLeast(0))
            .put("stage", stage.takeIf { it in MknoonCallDiagnosticSchema.stage } ?: "runtime")
            .put("action", action.takeIf { it in MknoonCallDiagnosticSchema.action } ?: "snapshot")
            .put("outcome", outcome.takeIf { it in MknoonCallDiagnosticSchema.outcome } ?: "unknown")
            .put("reason", reason.takeIf { it in MknoonCallDiagnosticSchema.reason } ?: "unknown").put("values", JSONObject(values(values)))
        for (key in listOf("traceId", "requestId", "operationId", "parentOperationId")) {
            (metadata[key] as? String)?.takeIf { uuid(it) && (handle == null || it != canonical(handle)) }?.let { event.put(key, it) }
        }
        // Stamp only newly created records; loading/draining preserves historical builds.
        installedBuild?.takeIf(::validBuild)?.let { event.put("build", it) }
        if (!validEvent(event)) return false
        events.add(event)
        if (deferPersistence) { pendingEvents.add(event.getString("eventId")); return true }
        if (persist()) return true
        events.remove(event); dropped++; return false
    }
    fun drain(limit: Int): Map<String, Any> {
        prune(); persist()
        return mapOf("version" to 1, "events" to if (enabled) events.take(limit.coerceIn(0, 64)).map(::jsonMap) else emptyList<Any>(), "droppedEvents" to dropped)
    }
    fun ack(ids: List<String>): Boolean {
        if (ids.size > 64 || !ids.all(::uuid)) return false
        val selected = ids.map { it.lowercase() }.toSet()
        val prior = events.toList()
        events.removeAll { it.optString("eventId") in selected }
        if (persist()) return true
        events.clear(); events.addAll(prior); return false
    }
    fun clear(): Boolean { events.clear(); bindings.clear(); dropped = 0; return persist() }
    private fun prune() {
        val deadline = (now() - RETENTION_MS).coerceAtLeast(0)
        events.removeAll { it.optLong("occurredAtMs") < deadline }
        bindings.entries.removeAll { it.value.optLong("at") < deadline }
    }
    private fun dropFirst() { if (events.isNotEmpty()) { events.removeAt(0); dropped = (dropped + 1).coerceAtLeast(0) } }
    private fun enforceCaps() {
        while (events.mapNotNull { it.optString("traceId").takeIf(::uuid) }.toSet().size > 100) {
            val trace = events.firstOrNull { it.has("traceId") }?.optString("traceId") ?: break
            val previous = events.size
            events.removeAll { it.optString("traceId") == trace }
            dropped += previous - events.size
            bindings.entries.removeAll { it.value.optString("traceId") == trace }
        }
        while (bindings.size > 100) {
            val oldest = bindings.minByOrNull { it.value.optLong("at") } ?: break
            val trace = oldest.value.optString("traceId")
            bindings.remove(oldest.key)
            val previous = events.size; events.removeAll { it.optString("traceId") == trace }; dropped += previous - events.size
        }
        for (trace in events.map { it.optString("traceId", "local") }.toSet()) {
            while (true) {
                val selected = events.filter { it.optString("traceId", "local") == trace }
                if (selected.size <= 256 && selected.sumOf { it.toString().toByteArray().size } <= 65_536) break
                val index = events.indexOfFirst { it.optString("traceId", "local") == trace }; if (index < 0) break
                events.removeAt(index); dropped++
            }
        }
        while (events.isNotEmpty() && encoded().size > MAX_BYTES) dropFirst()
    }
    private fun encoded(): ByteArray = JSONObject().put("version", 1).put("enabled", enabled).put("requestedEnabled", requestedEnabled).put("consentEpoch", consentEpoch).put("sequence", sequence).put("dropped", dropped)
        .put("openRun", openRun ?: JSONObject.NULL).put("events", JSONArray(events)).put("bindings", JSONObject(bindings)).toString().toByteArray(Charsets.UTF_8)
    fun recordDropped(count: Long) {
        if (enabled && count > 0) dropped = (dropped + count.coerceAtMost(9_007_199_254_740_991L)).coerceAtMost(9_007_199_254_740_991L)
    }
    fun persistPending(): Boolean {
        if (persist()) return true
        val before = events.size
        events.removeAll { it.optString("eventId") in pendingEvents }
        dropped += before - events.size; pendingEvents.clear(); return false
    }
    private fun persist(): Boolean = loaded && runCatching {
        prune(); enforceCaps(); val bytes = encoded(); require(bytes.size <= MAX_BYTES)
        backend.replace(bytes); pendingEvents.clear(); true
    }.getOrDefault(false)
}

/** One asynchronous writer shared by pre-Flutter FCM/Telecom and the Dart bridge. */
internal class MknoonCallDiagnostics private constructor(context: Context) {
    companion object {
        @Volatile private var instance: MknoonCallDiagnostics? = null
        fun get(context: Context): MknoonCallDiagnostics = instance ?: synchronized(this) {
            instance ?: MknoonCallDiagnostics(context.applicationContext).also { instance = it }
        }
    }
    private val writer = Executors.newSingleThreadExecutor { task -> Thread(task, "mknoon-call-diagnostics").apply { isDaemon = true } }
    private val admission = MknoonAppDiagnosticAdmission()
    private val backend = AndroidCallDiagnosticBackend(context)
    private var spool: MknoonCallDiagnosticSpool? = null
    private var persistenceScheduled = false
    init { writer.execute { runCatching { spool = MknoonCallDiagnosticSpool(backend, installedBuild = "${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}") } } }
    fun record(handle: String? = null, stage: String, action: String, outcome: String, reason: String = "none",
               values: Map<String, Any?> = emptyMap(), context: Map<String, Any?> = emptyMap()) {
        val captured = MknoonCallDiagnosticScope.current() + context
        admission.enqueue({ work -> writer.execute(work) }) { dropped ->
            spool?.recordDropped(dropped)
            if (spool?.append(handle, stage, action, outcome, reason, values, captured, deferPersistence = true) == true && !persistenceScheduled) {
                persistenceScheduled = true
                writer.execute { persistenceScheduled = false; spool?.persistPending() }
            }
        }
    }
    fun bind(handle: String, trace: String, context: Map<String, Any?> = emptyMap()) { runCatching { writer.execute { runCatching { spool?.bind(handle, trace, context) } } } }
    fun journal(handle: String, type: PendingNativeCallEventType) {
        val stage = when (type) {
            PendingNativeCallEventType.PRESENTED -> "presentation"
            PendingNativeCallEventType.ANSWER_REQUESTED -> "answer"
            PendingNativeCallEventType.AUDIO_ACTIVATED, PendingNativeCallEventType.AUDIO_DEACTIVATED,
            PendingNativeCallEventType.MUTE_CHANGED, PendingNativeCallEventType.ROUTE_CHANGED -> "audio"
            else -> "terminal"
        }
        val reason = MknoonCallDiagnosticSpool.journalReason(type, MknoonCallDiagnosticScope.current())
        record(handle, stage, "commit", "ok", reason, mapOf("nativeCommitted" to true, "terminal" to (stage == "terminal")))
    }
    fun bridge(messenger: BinaryMessenger): MethodChannel = MethodChannel(messenger, "mknoon/call_diagnostics").also { channel ->
        channel.setMethodCallHandler { call, result ->
            writer.execute {
                val value: Any = runCatching {
                    val args = call.arguments as? Map<*, *> ?: return@runCatching false
                    if (args["version"] != 1) return@runCatching false
                    val store = spool ?: MknoonCallDiagnosticSpool(backend, installedBuild = "${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}").also { spool = it }
                    when (call.method) {
                        "configure" -> {
                            val rawEpoch = args["consentEpoch"]
                            if (rawEpoch != null && rawEpoch !is Int && rawEpoch !is Long) false
                            else (args["enabled"] as? Boolean)?.let { store.configure(it, (rawEpoch as? Number)?.toLong()) } ?: false
                        }
                        "drain" -> store.drain((args["limit"] as? Number)?.toInt() ?: 64)
                        "ack" -> (args["eventIds"] as? List<*>)?.takeIf { it.all { value -> value is String } }?.map { it as String }?.let(store::ack) ?: false
                        "clear" -> store.clear()
                        "bind" -> if (args["callHandle"] is String && args["traceId"] is String) store.bind(args["callHandle"] as String, args["traceId"] as String) else false
                        "lookup" -> (args["callHandle"] as? String)?.let(store::lookup) ?: mapOf("version" to 1)
                        else -> false
                    }
                }.getOrDefault(false)
                Handler(Looper.getMainLooper()).post { result.success(value) }
            }
        }
    }
}
