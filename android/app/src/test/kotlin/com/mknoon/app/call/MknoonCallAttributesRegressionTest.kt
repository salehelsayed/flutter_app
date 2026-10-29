package com.mknoon.app.call

import androidx.core.telecom.CallAttributesCompat
import java.util.Collections
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class MknoonCallAttributesRegressionTest {
    @Test
    fun `incoming and outgoing Telecom requests do not advertise unsupported hold`() {
        val captured = Collections.synchronizedList(mutableListOf<CallAttributesCompat>())
        val platform = AndroidMknoonCallPlatform(
            context = RuntimeEnvironment.getApplication(),
            controller = { error("The captured request must not deliver callbacks") },
            stopIncomingRinger = {},
            registerAppWithTelecom = {},
            addCall = { attributes, _, _, _, _, _ ->
                captured += attributes
                // End the isolated system-boundary call without starting a
                // Telecom session; capture the real production argument first.
                error("Captured Core-Telecom request")
            },
        )
        val callback = object : MknoonCallRegistrationCallback {
            override fun onRegistered() = Unit
            override fun onFailure() = Unit
        }

        platform.registerIncoming(UUID.randomUUID(), callback, 2_000L)
        platform.registerOutgoing(UUID.randomUUID(), callback, 2_000L)

        assertEquals(2, captured.size)
        assertEquals(
            listOf(CallAttributesCompat.DIRECTION_INCOMING, CallAttributesCompat.DIRECTION_OUTGOING),
            captured.map { it.direction },
        )
        captured.forEach { attributes ->
            assertEquals(
                "An inactive callback ends this call, so Telecom must not offer hold",
                0,
                attributes.callCapabilities and CallAttributesCompat.SUPPORTS_SET_INACTIVE,
            )
        }
    }
}
