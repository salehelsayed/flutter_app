package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

class MknoonCallVideoAuthorityTest {
    private val call = UUID.fromString("11111111-1111-4111-8111-111111111111")
    private val other = UUID.fromString("22222222-2222-4222-8222-222222222222")

    private class Facts : MknoonCallLocalCameraFacts {
        var active = true
        var visible = true
        var permission = true
        var sdk = 34
        var manifest = true
        override fun audioActive(nativeCallId: UUID) = active
        override fun uiVisible() = visible
        override fun cameraPermissionGranted() = permission
        override fun sdkInt() = sdk
        override fun manifestDeclaresCameraType() = manifest
    }

    private val facts = Facts()
    private val applied = mutableListOf<Pair<UUID, Boolean>>()
    private var platformAccepts = true
    private val authority = MknoonCallVideoAuthority(facts) { id, withCamera ->
        applied += id to withCamera
        platformAccepts || !withCamera
    }

    private fun readyVideoCall() {
        authority.setVideoCapability(true)
        authority.setCallMedia(call, MknoonCallMedia.VIDEO)
    }

    @Test
    fun `video stays off until capability and current media are both video`() {
        assertEquals(MknoonCallMedia.AUDIO, authority.effectiveMedia(call))
        authority.setCallMedia(call, MknoonCallMedia.VIDEO)
        assertEquals(MknoonCallMedia.AUDIO, authority.effectiveMedia(call))
        authority.setVideoCapability(true)
        assertEquals(MknoonCallMedia.VIDEO, authority.effectiveMedia(call))
        assertEquals(MknoonCallMedia.AUDIO, authority.effectiveMedia(other))
    }

    @Test
    fun `a ready visible video call gets the lease and the camera type`() {
        readyVideoCall()
        assertEquals(MknoonCallLocalCameraDecision.Apply, authority.requestLocalCamera(call))
        assertTrue(authority.holdsCameraLease(call))
        assertEquals(listOf(call to true), applied)
    }

    @Test
    fun `refusal never touches the platform and grants no lease`() {
        authority.setCallMedia(call, MknoonCallMedia.VIDEO)
        val decision = authority.requestLocalCamera(call)
        assertEquals("not_video", (decision as MknoonCallLocalCameraDecision.Refuse).reason.wireValue)
        assertFalse(authority.holdsCameraLease(call))
        assertTrue(applied.isEmpty())
    }

    @Test
    fun `without the manifest camera type a visible ready call gets an untyped lease`() {
        readyVideoCall()
        facts.manifest = false
        assertEquals(MknoonCallLocalCameraDecision.Apply, authority.requestLocalCamera(call))
        assertTrue(authority.holdsCameraLease(call))
        // The service never gets the camera type it does not declare.
        assertFalse(authority.holdsCameraForegroundType(call))
        assertTrue(applied.isEmpty())
        // Background release stays as before: it always succeeds.
        authority.releaseLocalCamera(call)
        assertFalse(authority.holdsCameraLease(call))
        assertEquals(listOf(call to false), applied)
    }

    @Test
    fun `without the manifest camera type hidden UI is still refused`() {
        readyVideoCall()
        facts.manifest = false
        facts.visible = false
        val decision = authority.requestLocalCamera(call)
        assertEquals("not_visible", (decision as MknoonCallLocalCameraDecision.Refuse).reason.wireValue)
        assertFalse(authority.holdsCameraLease(call))
        assertTrue(applied.isEmpty())
    }

    @Test
    fun `a typed lease reports the camera foreground type`() {
        readyVideoCall()
        assertEquals(MknoonCallLocalCameraDecision.Apply, authority.requestLocalCamera(call))
        assertTrue(authority.holdsCameraForegroundType(call))
    }

    @Test
    fun `platform refusal of the camera type grants no lease`() {
        readyVideoCall()
        platformAccepts = false
        val decision = authority.requestLocalCamera(call)
        assertTrue(decision is MknoonCallLocalCameraDecision.Refuse)
        assertFalse(authority.holdsCameraLease(call))
    }

    @Test
    fun `a change during the platform call is caught by the recheck and rolled back`() {
        readyVideoCall()
        val racing = MknoonCallVideoAuthority(facts) { id, withCamera ->
            applied += id to withCamera
            if (withCamera) facts.visible = false
            true
        }
        racing.setVideoCapability(true)
        racing.setCallMedia(call, MknoonCallMedia.VIDEO)
        val decision = racing.requestLocalCamera(call)
        assertEquals("not_visible", (decision as MknoonCallLocalCameraDecision.Refuse).reason.wireValue)
        assertFalse(racing.holdsCameraLease(call))
        assertEquals(listOf(call to true, call to false), applied)
    }

    @Test
    fun `a revocation after the final check but before commit cannot leave a lease (NATIVE-VIDEO-1)`() {
        lateinit var racing: MknoonCallVideoAuthority
        var manifestReads = 0
        val racingFacts = object : MknoonCallLocalCameraFacts {
            override fun audioActive(nativeCallId: UUID) = true
            override fun uiVisible() = true
            override fun cameraPermissionGranted() = true
            override fun sdkInt() = 34
            override fun manifestDeclaresCameraType(): Boolean {
                manifestReads += 1
                // Second read is inside the final check, after media was read
                // as video: a Telecom disconnect ends the call right here.
                if (manifestReads == 2) racing.forget(call)
                return true
            }
        }
        racing = MknoonCallVideoAuthority(racingFacts) { id, withCamera ->
            applied += id to withCamera
            true
        }
        racing.setVideoCapability(true)
        racing.setCallMedia(call, MknoonCallMedia.VIDEO)

        val decision = racing.requestLocalCamera(call)

        assertEquals("not_active", (decision as MknoonCallLocalCameraDecision.Refuse).reason.wireValue)
        assertFalse(racing.holdsCameraLease(call))
        assertEquals(listOf(call to true, call to false), applied)
    }

    @Test
    fun `release always removes the camera type even after facts changed`() {
        readyVideoCall()
        authority.requestLocalCamera(call)
        facts.visible = false
        facts.permission = false
        applied.clear()
        authority.releaseLocalCamera(call)
        assertFalse(authority.holdsCameraLease(call))
        assertEquals(listOf(call to false), applied)
    }

    @Test
    fun `downgrade to audio, capability off and call end each release the lease`() {
        for (release in listOf<() -> Unit>(
            { authority.setCallMedia(call, MknoonCallMedia.AUDIO) },
            { authority.setVideoCapability(false) },
            { authority.forget(call) },
        )) {
            readyVideoCall()
            authority.requestLocalCamera(call)
            applied.clear()
            release()
            assertFalse(authority.holdsCameraLease(call))
            assertEquals(listOf(call to false), applied)
        }
    }

    @Test
    fun `audio for another call does not release this call's lease`() {
        readyVideoCall()
        authority.requestLocalCamera(call)
        applied.clear()
        authority.setCallMedia(other, MknoonCallMedia.AUDIO)
        assertTrue(authority.holdsCameraLease(call))
        assertTrue(applied.isEmpty())
    }
}
