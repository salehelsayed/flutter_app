package com.mknoon.app.call

internal const val MKNOON_CALL_ADMISSION_TAG = "MknoonCallAdmission"

/** Closed, identifier-free evidence from the service command's actual application. */
internal enum class MknoonCallAdmissionEvent(
    val wireValue: String,
    val action: String,
    val outcome: String,
    val reason: String = "none",
) {
    START_APPLIED("start_applied", "configure", "ok"),
    START_REPLACED_OWNER("start_replaced_owner", "replace", "ok"),
    START_IGNORED_UPGRADED("start_ignored_upgraded", "configure", "skipped"),
    START_IGNORED_OTHER_CALL("start_ignored_other_call", "configure", "skipped", "busy"),
    START_IGNORED_OWNER("start_ignored_owner", "configure", "skipped", "stale_epoch"),
    RELEASE_APPLIED_TERMINAL("release_applied_terminal", "stop", "ok"),
    RELEASE_APPLIED_SETTLED("release_applied_settled", "stop", "ok"),
    RELEASE_DEFERRED("release_deferred", "stop", "pending", "unknown"),
    RELEASE_IGNORED_OWNER("release_ignored_owner", "stop", "skipped", "stale_epoch"),
    RELEASE_IGNORED_CALL("release_ignored_call", "stop", "skipped", "stale_epoch"),
    RELEASE_IGNORED_UPGRADED("release_ignored_upgraded", "stop", "skipped"),
    RELEASE_IDLE("release_idle", "stop", "skipped"),
    RELEASE_FAILED("release_failed", "stop", "failed", "cleanup_failed"),
    STOP_APPLIED("stop_applied", "stop", "ok"),
    STOP_FAILED("stop_failed", "stop", "failed", "cleanup_failed"),
    TIMEOUT_APPLIED("timeout_applied", "expire", "ok", "timeout"),
    TIMEOUT_FAILED("timeout_failed", "expire", "failed", "cleanup_failed"),
    ;

    val values: Map<String, Boolean>
        get() = when (this) {
            START_APPLIED, START_REPLACED_OWNER -> mapOf("foreground" to true)
            RELEASE_APPLIED_TERMINAL -> mapOf(
                "foreground" to false, "ownerMatched" to true, "terminal" to true,
            )
            RELEASE_APPLIED_SETTLED -> mapOf("foreground" to false, "ownerMatched" to true)
            STOP_APPLIED, TIMEOUT_APPLIED -> mapOf("foreground" to false)
            RELEASE_DEFERRED -> mapOf("ownerMatched" to true)
            RELEASE_IGNORED_OWNER, RELEASE_IGNORED_CALL -> mapOf("ownerMatched" to false)
            else -> emptyMap()
        }
}

internal enum class MknoonCallForegroundMode(val wireValue: String) {
    ADMISSION("admission"),
    RINGING("ringing"),
    ACTIVE("active"),
    INACTIVE("inactive"),
}

internal fun formatMknoonCallAdmissionEvent(
    event: MknoonCallAdmissionEvent,
    mode: MknoonCallForegroundMode?,
): String = "CALL_ANDROID_ADMISSION event=${event.wireValue} mode=${mode?.wireValue ?: "idle"}"
