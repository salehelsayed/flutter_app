package com.mknoon.app.call

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MknoonCallOngoingNotificationHandoverTest {
    @Test
    fun `ongoing notification takes the foreground before the ringing heads-up is cancelled`() {
        val sequence = mutableListOf<String>()

        handOverToOngoingCallNotification(
            startForeground = { id -> sequence += "startForeground:$id" },
            cancel = { id -> sequence += "cancel:$id" },
        )

        assertEquals(
            listOf(
                "startForeground:${MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID}",
                "cancel:${MknoonCallNotificationFactory.NOTIFICATION_ID}",
            ),
            sequence,
        )
        assertEquals(505, MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID)
        assertEquals(504, MknoonCallNotificationFactory.NOTIFICATION_ID)
    }

    @Test
    fun `a refused foreground keeps the ringing notification that still holds the service`() {
        val cancelled = mutableListOf<Int>()
        val refusal = IllegalStateException("foreground refused")

        val thrown = assertThrows(IllegalStateException::class.java) {
            handOverToOngoingCallNotification(
                startForeground = { throw refusal },
                cancel = { id -> cancelled += id },
            )
        }

        assertEquals(refusal, thrown)
        assertEquals(emptyList<Int>(), cancelled)
    }

    @Test
    fun `active and inactive calls both hand over through the ongoing notification`() {
        val source = File("src/main/kotlin/com/mknoon/app/call/MknoonCallAndroidRuntime.kt").readText()
        val active = source.substringAfter("override fun startActive(").substringBefore("override fun startInactive(")
        val inactive = source.substringAfter("override fun startInactive(").substringBefore("override fun stop(")

        for ((name, body) in listOf("startActive" to active, "startInactive" to inactive)) {
            assertEquals("$name hands over once", 1, Regex("handOverToOngoingCallNotification\\(").findAll(body).count())
            assertEquals(
                "$name never starts the ongoing notification on the ringing id",
                0,
                Regex("MknoonCallNotificationFactory\\.NOTIFICATION_ID").findAll(body).count(),
            )
        }
    }
}
