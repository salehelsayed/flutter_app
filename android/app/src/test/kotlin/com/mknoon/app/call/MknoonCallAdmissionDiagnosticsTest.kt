package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonCallAdmissionDiagnosticsTest {
    @Test
    fun `applied admission evidence has a fixed identifier free vocabulary`() {
        assertEquals("MknoonCallAdmission", MKNOON_CALL_ADMISSION_TAG)
        assertEquals(listOf(
            "start_applied", "start_replaced_owner", "start_ignored_upgraded", "start_ignored_other_call",
            "start_ignored_owner",
            "release_applied_terminal", "release_applied_settled", "release_deferred",
            "release_ignored_owner", "release_ignored_call", "release_ignored_upgraded", "release_idle",
            "release_failed", "stop_applied", "stop_failed", "timeout_applied", "timeout_failed",
        ), MknoonCallAdmissionEvent.entries.map { it.wireValue })
        for (event in MknoonCallAdmissionEvent.entries) {
            assertTrue(event.action in MknoonCallDiagnosticSchema.action)
            assertTrue(event.outcome in MknoonCallDiagnosticSchema.outcome)
            assertTrue(event.reason in MknoonCallDiagnosticSchema.reason)
            assertTrue(event.values.keys.all { it in MknoonCallDiagnosticSchema.booleanValues })
            for (mode in listOf(null) + MknoonCallForegroundMode.entries) {
                assertEquals(
                    "CALL_ANDROID_ADMISSION event=${event.wireValue} mode=${mode?.wireValue ?: "idle"}",
                    formatMknoonCallAdmissionEvent(event, mode),
                )
            }
        }
        assertEquals(mapOf("foreground" to false, "ownerMatched" to true, "terminal" to true),
            MknoonCallAdmissionEvent.RELEASE_APPLIED_TERMINAL.values)
        assertTrue("terminal" !in MknoonCallAdmissionEvent.RELEASE_DEFERRED.values)
    }
}
