package com.mknoon.app.call

import android.os.ParcelUuid
import androidx.core.telecom.CallEndpointCompat
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.TimeoutCancellationException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallAudioEndpointTest {
    private fun endpoint(name: String, type: Int) = CallEndpointCompat(name, type, ParcelUuid(UUID.randomUUID()))
    @Test fun `accepted preference succeeds only after the exact endpoint is observed`() = runBlocking {
        var selected = "synthetic-a"
        val update = launch { delay(30); selected = "synthetic-b" }
        assertTrue(withTimeout(2000) { awaitCallAudioOutputConfirmation("synthetic-b", { selected }, { true }, { true }) })
        update.join()
    }
    @Test fun `confirmation refuses removed endpoint or ended native owner`() = runBlocking {
        assertFalse(awaitCallAudioOutputConfirmation("synthetic-b", { "synthetic-a" }, { true }, { false }))
        assertFalse(awaitCallAudioOutputConfirmation("synthetic-b", { "synthetic-b" }, { false }, { true }))
    }
    @Test fun `unobserved accepted preference stays bounded by the native deadline`() = runBlocking {
        try {
            withTimeout(100) { awaitCallAudioOutputConfirmation("synthetic-b", { "synthetic-a" }, { true }, { true }) }
            fail("unobserved selection cannot succeed")
        } catch (_: TimeoutCancellationException) { }
    }

    @Test fun `same-class outputs keep distinct identifiers and names only in transient inventory`() {
        val a = endpoint("Synthetic headset A", CallEndpointCompat.TYPE_BLUETOOTH)
        val b = endpoint("Synthetic headset B", CallEndpointCompat.TYPE_BLUETOOTH)
        val speaker = endpoint("Synthetic speaker", CallEndpointCompat.TYPE_SPEAKER)
        val inventory = callAudioOutputInventory(listOf(a, b, speaker), b.identifier.toString())
        assertEquals(3, inventory.size)
        assertEquals(listOf(a.identifier.toString(), b.identifier.toString(), speaker.identifier.toString()), inventory.map { it.id })
        assertEquals(listOf(false, true, false), inventory.map { it.selected })
        assertEquals("Synthetic headset B", inventory[1].name)
        assertFalse(inventory.toString().contains("Synthetic"))
        assertFalse(inventory.toString().contains(b.identifier.toString()))
    }
    @Test fun `selection matches the exact endpoint and refuses missing hot-unplugged identifiers`() {
        val a = endpoint("Synthetic A", CallEndpointCompat.TYPE_BLUETOOTH)
        val b = endpoint("Synthetic B", CallEndpointCompat.TYPE_BLUETOOTH)
        assertSame(b, selectCallEndpointByIdentifier(listOf(a, b), b.identifier.toString()))
        assertNull(selectCallEndpointByIdentifier(listOf(a), b.identifier.toString()))
        assertNull(selectCallEndpointByIdentifier(emptyList(), a.identifier.toString()))
        assertNull(selectCallEndpointByIdentifier(listOf(a), ""))
    }
}
