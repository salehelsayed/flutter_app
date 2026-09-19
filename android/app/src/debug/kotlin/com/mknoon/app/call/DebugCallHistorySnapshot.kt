package com.mknoon.app.call

/** Strict bridge grammar: caller cannot supply a native UUID, SQL, path, or account identity. */
internal fun debugHistoryRequest(keys: Set<String>, read: (String) -> Any?): MutableMap<String, Any?> {
    val nonce = read("nonce") as? String
    require(nonce != null && Regex("^[0-9a-f]{16,64}$").matches(nonce))
    val mode = read("historyOperation") as? String
    val common = setOf("operation", "nonce", "historyOperation")
    val extra = if (mode == "lookup") setOf("callBindingSha256", "accountBindingSha256", "sinceMs", "untilMs") else emptySet()
    require(mode in setOf("baseline", "current", "lookup") && keys == common + extra)
    val result = mutableMapOf<String, Any?>("nonce" to nonce, "operation" to mode)
    for (key in extra) {
        val value = read(key)
        if (key.endsWith("Sha256")) require(value is String && Regex("^[0-9a-f]{64}$").matches(value))
        else require(value is Long && value > 0)
        result[key] = value
    }
    return result
}

internal fun debugHistoryResponse(value: Any?, nonce: String, operation: String,
    nativeBinding: String? = null): Map<String, Any?> {
    val denied = mapOf("status" to "unavailable")
    if (value !is Map<*, *>) return denied
    if (value.size == 1 && value["status"] in setOf("rejected", "unavailable")) return denied
    val common = setOf("schema", "status", "nonce", "operation", "observedAtMs", "accountBindingSha256", "totalRows")
    val optional = setOf("callBindingSha256", "nativeCallBindingSha256", "matchingRows", "rowBindingSha256", "startedAtMs")
    if (!value.keys.containsAll(common) || value.keys.any { it !in common + optional } ||
        value["schema"] != "mknoon.debug-call-history.v1" || value["status"] != "snapshot" ||
        value["nonce"] != nonce || value["operation"] != operation) return denied
    for ((key, field) in value) {
        if (key.toString().endsWith("Sha256") && (field !is String || !Regex("^[0-9a-f]{64}$").matches(field))) return denied
        if (key in setOf("observedAtMs", "totalRows", "matchingRows", "startedAtMs") &&
            (field !is Number || field.toLong() < 0 || field !is Long && field !is Int)) return denied
    }
    val expected = when (operation) {
        "baseline" -> common
        "current" -> common + setOf("callBindingSha256", "nativeCallBindingSha256", "matchingRows", "startedAtMs") +
            if ((value["matchingRows"] as? Number)?.toLong() == 1L) setOf("rowBindingSha256") else emptySet()
        "lookup" -> common + setOf("callBindingSha256", "matchingRows", "rowBindingSha256")
        else -> return denied
    }
    if (value.keys != expected) return denied
    if (operation != "baseline" && (value["matchingRows"] as? Number)?.toLong() !in 0L..1L) return denied
    if (operation == "lookup" && (value["matchingRows"] as? Number)?.toLong() != 1L) return denied
    if (operation == "current" && (nativeBinding == null || value["nativeCallBindingSha256"] != nativeBinding)) return denied
    return value.entries.associate { it.key as String to it.value }
}

/** A delayed platform callback cannot gain new authority after its absolute query budget. */
internal class DebugCallEvidenceReplyGate(
    private val started: Long,
    private val elapsedMs: () -> Long,
    private val ownerValid: () -> Boolean,
    private val deliver: (Map<String, Any?>) -> Unit,
) {
    private var finished = false
    @Synchronized fun complete(value: () -> Map<String, Any?>) {
        if (finished) return
        finished = true
        val reply = runCatching {
            if (elapsedMs() - started !in 0..5000 || !ownerValid()) mapOf("status" to "unavailable")
            else value().let { if (elapsedMs() - started in 0..5000) it else mapOf("status" to "unavailable") }
        }.getOrElse { mapOf("status" to "unavailable") }
        deliver(reply)
    }
}
