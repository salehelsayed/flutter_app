package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.UUID

/** CAM-DIAG: every lease decision names a fixed stage/reason; no ids. A null
 * logger (release) prints nothing and changes no decision. */
class MknoonCallCameraDiagTest {
    private val call = UUID.fromString("11111111-1111-4111-8111-111111111111")

    private class Facts : MknoonCallLocalCameraFacts {
        var active = true
        var visible = true
        var manifest = true
        override fun audioActive(nativeCallId: UUID) = active
        override fun uiVisible() = visible
        override fun cameraPermissionGranted() = true
        override fun sdkInt() = 34
        override fun manifestDeclaresCameraType() = manifest
    }

    private val facts = Facts()
    private val lines = mutableListOf<String>()
    private var platformAccepts = true

    private fun authority(applier: MknoonCallCameraForegroundApplier? = null) =
        MknoonCallVideoAuthority(
            facts,
            log = { lines += it },
            applier = applier ?: MknoonCallCameraForegroundApplier { _, withCamera -> platformAccepts || !withCamera },
        ).also {
            it.setVideoCapability(true)
            it.setCallMedia(call, MknoonCallMedia.VIDEO)
        }

    @Test
    fun `grant names typed and untyped leases, explicit release names its reason`() {
        val typed = authority()
        typed.requestLocalCamera(call)
        typed.releaseLocalCamera(call)
        facts.manifest = false
        val untyped = authority()
        untyped.requestLocalCamera(call)
        assertEquals(
            listOf("lease granted typed=true", "lease released reason=explicit", "lease granted typed=false"),
            lines,
        )
    }

    @Test
    fun `each refusal stage names its reason`() {
        facts.visible = false
        authority().requestLocalCamera(call)
        facts.visible = true
        platformAccepts = false
        authority().requestLocalCamera(call)
        platformAccepts = true
        val racing = authority(
            MknoonCallCameraForegroundApplier { _, withCamera ->
                if (withCamera) facts.visible = false
                true
            },
        )
        racing.requestLocalCamera(call)
        assertEquals(
            listOf(
                "lease refused stage=first reason=not_visible",
                "lease refused stage=platform reason=not_active",
                "lease refused stage=recheck reason=not_visible",
            ),
            lines,
        )
    }

    @Test
    fun `a revocation before commit names the commit stage`() {
        lateinit var racing: MknoonCallVideoAuthority
        var reads = 0
        val racingFacts = object : MknoonCallLocalCameraFacts {
            override fun audioActive(nativeCallId: UUID) = true
            override fun uiVisible() = true
            override fun cameraPermissionGranted() = true
            override fun sdkInt() = 34
            override fun manifestDeclaresCameraType(): Boolean {
                reads += 1
                if (reads == 2) racing.forget(call)
                return true
            }
        }
        racing = MknoonCallVideoAuthority(racingFacts, log = { lines += it }) { _, _ -> true }
        racing.setVideoCapability(true)
        racing.setCallMedia(call, MknoonCallMedia.VIDEO)
        racing.requestLocalCamera(call)
        assertEquals(listOf("lease refused stage=commit reason=not_active"), lines)
    }

    @Test
    fun `each release path names its reason, only when a lease was held`() {
        val a = authority()
        a.requestLocalCamera(call)
        a.setCallMedia(call, MknoonCallMedia.AUDIO)
        a.setCallMedia(call, MknoonCallMedia.VIDEO)
        a.requestLocalCamera(call)
        a.forget(call)
        a.setCallMedia(call, MknoonCallMedia.VIDEO)
        a.requestLocalCamera(call)
        a.setVideoCapability(false)
        a.setVideoCapability(true)
        a.requestLocalCamera(call)
        a.dropLease(call)
        a.releaseLocalCamera(call) // nothing held any more: no line
        assertEquals(
            listOf(
                "lease granted typed=true", "lease released reason=media_audio",
                "lease granted typed=true", "lease released reason=call_end",
                "lease granted typed=true", "lease released reason=capability_off",
                "lease granted typed=true", "lease released reason=dropped",
            ),
            lines,
        )
    }

    @Test
    fun `a null logger (release) prints nothing and decides the same`() {
        val quiet = MknoonCallVideoAuthority(facts) { _, _ -> true }
        quiet.setVideoCapability(true)
        quiet.setCallMedia(call, MknoonCallMedia.VIDEO)
        assertEquals(MknoonCallLocalCameraDecision.Apply, quiet.requestLocalCamera(call))
        quiet.releaseLocalCamera(call)
        assertEquals(emptyList<String>(), lines)
    }
}
