package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MknoonCallLocalCameraForegroundTest {
    private val ready = MknoonCallLocalCameraInputs(
        media = MknoonCallMedia.VIDEO,
        audioActive = true,
        uiVisible = true,
        cameraPermissionGranted = true,
        sdkInt = 34,
        manifestDeclaresCameraType = true,
    )

    @Test
    fun `absent media is audio and unknown media fails closed`() {
        assertEquals(MknoonCallMedia.AUDIO, MknoonCallMedia.parse(null))
        assertEquals(MknoonCallMedia.AUDIO, MknoonCallMedia.parse("audio"))
        assertEquals(MknoonCallMedia.VIDEO, MknoonCallMedia.parse("video"))
        assertNull(MknoonCallMedia.parse("VIDEO"))
        assertNull(MknoonCallMedia.parse("screen"))
        assertNull(MknoonCallMedia.parse(true))
    }

    @Test
    fun `a visible active video call with camera permission may carry the camera type`() {
        assertEquals(MknoonCallLocalCameraDecision.Apply, decideMknoonCallLocalCamera(ready))
    }

    @Test
    fun `each missing fact refuses with its own fixed reason`() {
        val cases = listOf(
            ready.copy(sdkInt = 29) to "unsupported",
            ready.copy(manifestDeclaresCameraType = false) to "unsupported",
            ready.copy(media = MknoonCallMedia.AUDIO) to "not_video",
            ready.copy(audioActive = false) to "not_active",
            ready.copy(cameraPermissionGranted = false) to "no_permission",
            ready.copy(uiVisible = false) to "not_visible",
        )
        for ((inputs, wire) in cases) {
            assertEquals(
                wire,
                (decideMknoonCallLocalCamera(inputs) as MknoonCallLocalCameraDecision.Refuse).reason.wireValue,
            )
        }
    }

    @Test
    fun `without the manifest camera type every request is unsupported, even a fully ready call`() {
        assertEquals(
            MknoonCallLocalCameraDecision.Refuse(MknoonCallLocalCameraDecision.Reason.UNSUPPORTED),
            decideMknoonCallLocalCamera(ready.copy(manifestDeclaresCameraType = false)),
        )
    }

    @Test
    fun `a background or locked answer without visible UI never gets the camera type`() {
        val backgroundAnswer = ready.copy(uiVisible = false)
        assertEquals(
            MknoonCallLocalCameraDecision.Refuse(MknoonCallLocalCameraDecision.Reason.NOT_VISIBLE),
            decideMknoonCallLocalCamera(backgroundAnswer),
        )
    }

    @Test
    fun `camera type rides only on an active microphone service`() {
        val phoneCall = 4
        val microphone = 128
        val camera = 64
        assertEquals(phoneCall or microphone, mknoonCallOngoingForegroundTypes(withMicrophone = true, withCamera = false))
        assertEquals(phoneCall or microphone or camera, mknoonCallOngoingForegroundTypes(withMicrophone = true, withCamera = true))
        assertEquals(phoneCall, mknoonCallOngoingForegroundTypes(withMicrophone = false, withCamera = true))
        assertEquals(phoneCall, mknoonCallOngoingForegroundTypes(withMicrophone = false, withCamera = false))
    }
}
