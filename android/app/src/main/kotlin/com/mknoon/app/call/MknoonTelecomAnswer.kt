package com.mknoon.app.call

import androidx.core.telecom.CallControlResult
import androidx.core.telecom.CallException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

internal const val MKNOON_TELECOM_ANSWER_DIAGNOSTIC_TAG = "MknoonCallAnswer"

internal enum class MknoonTelecomAnswerOutcome(val outcome: String, val reason: String) {
    APPLIED("applied", "none"),
    SESSION_UNAVAILABLE("failed", "session_unavailable"),
    REJECTED("failed", "telecom_rejected"),
    TIMEOUT("failed", "timeout"),
    CANCELLED("failed", "cancelled"),
    SECURITY_EXCEPTION("failed", "security_exception"),
    ILLEGAL_STATE_EXCEPTION("failed", "illegal_state_exception"),
    CALL_EXCEPTION("failed", "call_exception"),
    PLATFORM_EXCEPTION("failed", "platform_exception"),
}

internal enum class MknoonTelecomAnswerCode(val wireValue: String) {
    NONE("none"),
    UNKNOWN("unknown"),
    CANNOT_HOLD_ACTIVE("cannot_hold_active"),
    CALL_NOT_TRACKED("call_not_tracked"),
    CANNOT_SET_ACTIVE("cannot_set_active"),
    CALL_NOT_PERMITTED("call_not_permitted"),
    OPERATION_TIMED_OUT("operation_timed_out"),
    HOLD_UNSUPPORTED("hold_unsupported"),
    BLUETOOTH_DEVICE_NULL("bluetooth_device_null"),
}

internal data class MknoonTelecomAnswerDiagnostic(
    val outcome: MknoonTelecomAnswerOutcome,
    val code: MknoonTelecomAnswerCode = MknoonTelecomAnswerCode.NONE,
)

internal fun formatMknoonTelecomAnswerDiagnostic(diagnostic: MknoonTelecomAnswerDiagnostic): String =
    "CALL_ANDROID_ANSWER outcome=${diagnostic.outcome.outcome} " +
        "reason=${diagnostic.outcome.reason} code=${diagnostic.code.wireValue}"

internal fun mknoonTelecomAnswerCode(code: Int): MknoonTelecomAnswerCode = when (code) {
    CallException.ERROR_CANNOT_HOLD_CURRENT_ACTIVE_CALL -> MknoonTelecomAnswerCode.CANNOT_HOLD_ACTIVE
    CallException.ERROR_CALL_IS_NOT_BEING_TRACKED -> MknoonTelecomAnswerCode.CALL_NOT_TRACKED
    CallException.ERROR_CALL_CANNOT_BE_SET_TO_ACTIVE -> MknoonTelecomAnswerCode.CANNOT_SET_ACTIVE
    CallException.ERROR_CALL_NOT_PERMITTED_AT_PRESENT_TIME -> MknoonTelecomAnswerCode.CALL_NOT_PERMITTED
    CallException.ERROR_OPERATION_TIMED_OUT -> MknoonTelecomAnswerCode.OPERATION_TIMED_OUT
    CallException.ERROR_CALL_DOES_NOT_SUPPORT_HOLD -> MknoonTelecomAnswerCode.HOLD_UNSUPPORTED
    CallException.ERROR_BLUETOOTH_DEVICE_IS_NULL -> MknoonTelecomAnswerCode.BLUETOOTH_DEVICE_NULL
    else -> MknoonTelecomAnswerCode.UNKNOWN
}

/** Preserve the existing control result and timeout; only closed diagnostics leave this boundary. */
internal fun performMknoonTelecomAnswer(
    answer: (suspend () -> CallControlResult)?,
    timeoutMs: Long,
    diagnostic: (MknoonTelecomAnswerDiagnostic) -> Unit,
) {
    fun record(outcome: MknoonTelecomAnswerOutcome, code: MknoonTelecomAnswerCode = MknoonTelecomAnswerCode.NONE) {
        runCatching { diagnostic(MknoonTelecomAnswerDiagnostic(outcome, code)) }
    }
    if (answer == null) {
        record(MknoonTelecomAnswerOutcome.SESSION_UNAVAILABLE)
        error("call session unavailable")
    }
    val result = try {
        runBlocking {
            withTimeout(timeoutMs) { answer() }
        }
    } catch (failure: Exception) {
        val outcome = when (failure) {
            is TimeoutCancellationException -> MknoonTelecomAnswerOutcome.TIMEOUT
            is CancellationException -> MknoonTelecomAnswerOutcome.CANCELLED
            is SecurityException -> MknoonTelecomAnswerOutcome.SECURITY_EXCEPTION
            is IllegalStateException -> MknoonTelecomAnswerOutcome.ILLEGAL_STATE_EXCEPTION
            is CallException -> MknoonTelecomAnswerOutcome.CALL_EXCEPTION
            else -> MknoonTelecomAnswerOutcome.PLATFORM_EXCEPTION
        }
        record(outcome, if (failure is CallException) mknoonTelecomAnswerCode(failure.code) else MknoonTelecomAnswerCode.NONE)
        throw failure
    }
    if (result !is CallControlResult.Success) {
        record(MknoonTelecomAnswerOutcome.REJECTED,
            if (result is CallControlResult.Error) mknoonTelecomAnswerCode(result.errorCode) else MknoonTelecomAnswerCode.UNKNOWN)
        error("Telecom answer rejected")
    }
    record(MknoonTelecomAnswerOutcome.APPLIED)
}
