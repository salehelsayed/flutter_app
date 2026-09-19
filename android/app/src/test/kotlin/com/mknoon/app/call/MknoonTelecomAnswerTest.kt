package com.mknoon.app.call

import androidx.core.telecom.CallControlResult
import androidx.core.telecom.CallException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class MknoonTelecomAnswerTest {
    @Test
    fun `successful control is invoked once and reports applied after it returns`() {
        val order = mutableListOf<String>()
        performMknoonTelecomAnswer(
            answer = { order.add("answer"); CallControlResult.Success() },
            timeoutMs = 100,
            diagnostic = { order.add(formatMknoonTelecomAnswerDiagnostic(it)) },
        )
        assertEquals(listOf("answer", "CALL_ANDROID_ANSWER outcome=applied reason=none code=none"), order)
    }

    @Test
    fun `missing session remains refused with distinct fixed diagnostic`() {
        val events = mutableListOf<MknoonTelecomAnswerDiagnostic>()
        assertThrows(IllegalStateException::class.java) {
            performMknoonTelecomAnswer(null, 100, events::add)
        }
        assertEquals(listOf(MknoonTelecomAnswerDiagnostic(MknoonTelecomAnswerOutcome.SESSION_UNAVAILABLE)), events)
    }

    @Test
    fun `every Telecom error remains refused and only known codes cross logging boundary`() {
        val codes = mapOf(
            CallException.ERROR_UNKNOWN to MknoonTelecomAnswerCode.UNKNOWN,
            CallException.ERROR_CANNOT_HOLD_CURRENT_ACTIVE_CALL to MknoonTelecomAnswerCode.CANNOT_HOLD_ACTIVE,
            CallException.ERROR_CALL_IS_NOT_BEING_TRACKED to MknoonTelecomAnswerCode.CALL_NOT_TRACKED,
            CallException.ERROR_CALL_CANNOT_BE_SET_TO_ACTIVE to MknoonTelecomAnswerCode.CANNOT_SET_ACTIVE,
            CallException.ERROR_CALL_NOT_PERMITTED_AT_PRESENT_TIME to MknoonTelecomAnswerCode.CALL_NOT_PERMITTED,
            CallException.ERROR_OPERATION_TIMED_OUT to MknoonTelecomAnswerCode.OPERATION_TIMED_OUT,
            CallException.ERROR_CALL_DOES_NOT_SUPPORT_HOLD to MknoonTelecomAnswerCode.HOLD_UNSUPPORTED,
            CallException.ERROR_BLUETOOTH_DEVICE_IS_NULL to MknoonTelecomAnswerCode.BLUETOOTH_DEVICE_NULL,
            900123 to MknoonTelecomAnswerCode.UNKNOWN,
        )
        codes.forEach { (raw, expected) ->
            val events = mutableListOf<MknoonTelecomAnswerDiagnostic>()
            assertThrows(IllegalStateException::class.java) {
                performMknoonTelecomAnswer({ CallControlResult.Error(raw) }, 100, events::add)
            }
            assertEquals(listOf(MknoonTelecomAnswerDiagnostic(MknoonTelecomAnswerOutcome.REJECTED, expected)), events)
            assertFalse(formatMknoonTelecomAnswerDiagnostic(events.single()).contains(raw.toString()))
        }
    }

    @Test
    fun `platform exceptions retain type message and cause without exposing private data`() {
        val privateMessage = "private-call-id peer-address credential-canary"
        val failures = listOf(
            SecurityException(privateMessage) to MknoonTelecomAnswerOutcome.SECURITY_EXCEPTION,
            IllegalStateException(privateMessage) to MknoonTelecomAnswerOutcome.ILLEGAL_STATE_EXCEPTION,
            CancellationException(privateMessage) to MknoonTelecomAnswerOutcome.CANCELLED,
            object : Exception(privateMessage) {} to MknoonTelecomAnswerOutcome.PLATFORM_EXCEPTION,
            CallException(CallException.ERROR_CALL_IS_NOT_BEING_TRACKED) to MknoonTelecomAnswerOutcome.CALL_EXCEPTION,
        )
        failures.forEach { (failure, expected) ->
            val events = mutableListOf<MknoonTelecomAnswerDiagnostic>()
            val thrown = assertThrows(Exception::class.java) {
                performMknoonTelecomAnswer({ throw failure }, 100, events::add)
            }
            // Coroutine stack-trace recovery may copy a Throwable; the
            // existing runBlocking boundary preserves its original as cause.
            assertEquals(failure.javaClass, thrown.javaClass)
            assertEquals(failure.message, thrown.message)
            assertSame(failure, generateSequence(thrown as Throwable) { it.cause }.last())
            val expectedCode = if (failure is CallException) MknoonTelecomAnswerCode.CALL_NOT_TRACKED else MknoonTelecomAnswerCode.NONE
            assertEquals(listOf(MknoonTelecomAnswerDiagnostic(expected, expectedCode)), events)
            val line = formatMknoonTelecomAnswerDiagnostic(events.single())
            assertFalse(line.contains(privateMessage))
            assertFalse(line.contains(failure.javaClass.name))
        }
    }

    @Test
    fun `bounded control timeout remains cancellation and never reports success`() {
        val events = mutableListOf<MknoonTelecomAnswerDiagnostic>()
        var stopped = false
        assertThrows(TimeoutCancellationException::class.java) {
            performMknoonTelecomAnswer(
                answer = {
                    try { delay(10_000); CallControlResult.Success() }
                    finally { stopped = true }
                },
                timeoutMs = 10,
                diagnostic = events::add,
            )
        }
        assertEquals(true, stopped)
        assertEquals(listOf(MknoonTelecomAnswerDiagnostic(MknoonTelecomAnswerOutcome.TIMEOUT)), events)
    }

    @Test
    fun `diagnostic sink failure cannot change applied success or original refusal`() {
        val broken: (MknoonTelecomAnswerDiagnostic) -> Unit = { throw IllegalStateException("sink") }
        performMknoonTelecomAnswer({ CallControlResult.Success() }, 100, broken)
        val original = SecurityException("platform-private")
        val thrown = assertThrows(SecurityException::class.java) {
            performMknoonTelecomAnswer({ throw original }, 100, broken)
        }
        assertEquals(original.message, thrown.message)
        assertSame(original, generateSequence(thrown as Throwable) { it.cause }.last())
        val rejected = assertThrows(IllegalStateException::class.java) {
            performMknoonTelecomAnswer({ CallControlResult.Error(CallException.ERROR_UNKNOWN) }, 100, broken)
        }
        assertEquals("Telecom answer rejected", rejected.message)
        val missing = assertThrows(IllegalStateException::class.java) {
            performMknoonTelecomAnswer(null, 100, broken)
        }
        assertEquals("call session unavailable", missing.message)
    }

    @Test
    fun `wire grammar is fixed and contains no caller supplied fields`() {
        assertEquals("MknoonCallAnswer", MKNOON_TELECOM_ANSWER_DIAGNOSTIC_TAG)
        assertEquals(
            listOf("none", "session_unavailable", "telecom_rejected", "timeout", "cancelled",
                "security_exception", "illegal_state_exception", "call_exception", "platform_exception"),
            MknoonTelecomAnswerOutcome.values().map { it.reason },
        )
        assertEquals(
            listOf("none", "unknown", "cannot_hold_active", "call_not_tracked", "cannot_set_active",
                "call_not_permitted", "operation_timed_out", "hold_unsupported", "bluetooth_device_null"),
            MknoonTelecomAnswerCode.values().map { it.wireValue },
        )
    }
}
