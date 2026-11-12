package com.mknoon.app.call

import java.util.UUID

/** Applies or removes the camera type on the running call service for one
 * call, synchronously. Returns false when the platform refuses (for example a
 * SecurityException from startForeground) or the service is not ACTIVE for
 * that call. */
internal fun interface MknoonCallCameraForegroundApplier {
    fun apply(nativeCallId: UUID, withCamera: Boolean): Boolean
}

/** Live facts read at decision time; none is cached. */
internal interface MknoonCallLocalCameraFacts {
    fun audioActive(nativeCallId: UUID): Boolean
    fun uiVisible(): Boolean
    fun cameraPermissionGranted(): Boolean
    fun sdkInt(): Int
    fun manifestDeclaresCameraType(): Boolean
}

/**
 * Process-wide native video truth (Astra m-bd5297cd): the video capability
 * flag, each call's current media, and the single camera lease. Video stays
 * off unless the capability is enabled AND the call's current media is video.
 * It never starts capture and never ends audio; releasing the lease runs no
 * start guards.
 */
internal class MknoonCallVideoAuthority(
    private val facts: MknoonCallLocalCameraFacts,
    private val applier: MknoonCallCameraForegroundApplier,
) {
    private val lock = Any()
    private var videoCapabilityEnabled = false
    private val mediaByCall = mutableMapOf<UUID, MknoonCallMedia>()
    private var cameraLeaseCall: UUID? = null

    fun setVideoCapability(enabled: Boolean) {
        val released = synchronized(lock) {
            videoCapabilityEnabled = enabled
            if (enabled) null else takeLease()
        }
        released?.let { applier.apply(it, false) }
    }

    fun videoCapabilityEnabled(): Boolean = synchronized(lock) { videoCapabilityEnabled }

    /** Media as the platform should present it: video only while the
     * capability is on and the call's current media is video. */
    fun effectiveMedia(nativeCallId: UUID): MknoonCallMedia = synchronized(lock) {
        if (videoCapabilityEnabled && mediaByCall[nativeCallId] == MknoonCallMedia.VIDEO) {
            MknoonCallMedia.VIDEO
        } else MknoonCallMedia.AUDIO
    }

    /** Registration (C1) and later settlement (setCallMedia) both land here.
     * Audio releases this call's camera lease. */
    fun setCallMedia(nativeCallId: UUID, media: MknoonCallMedia) {
        val released = synchronized(lock) {
            mediaByCall[nativeCallId] = media
            if (media == MknoonCallMedia.AUDIO && cameraLeaseCall == nativeCallId) takeLease() else null
        }
        released?.let { applier.apply(it, false) }
    }

    /** Call end: forget media and release any camera lease for it. */
    fun forget(nativeCallId: UUID) {
        val released = synchronized(lock) {
            mediaByCall.remove(nativeCallId)
            if (cameraLeaseCall == nativeCallId) takeLease() else null
        }
        released?.let { applier.apply(it, false) }
    }

    fun requestLocalCamera(nativeCallId: UUID): MknoonCallLocalCameraDecision {
        val decision = decide(nativeCallId)
        if (decision != MknoonCallLocalCameraDecision.Apply) return decision
        if (!applier.apply(nativeCallId, true)) {
            return MknoonCallLocalCameraDecision.Refuse(MknoonCallLocalCameraDecision.Reason.NOT_ACTIVE)
        }
        // Recheck after the platform call: anything that changed meanwhile
        // (media downgrade, capability off, backgrounded) wins.
        val recheck = decide(nativeCallId)
        if (recheck != MknoonCallLocalCameraDecision.Apply) {
            applier.apply(nativeCallId, false)
            return recheck
        }
        synchronized(lock) { cameraLeaseCall = nativeCallId }
        return MknoonCallLocalCameraDecision.Apply
    }

    /** Always succeeds; no start guards on stop. */
    fun releaseLocalCamera(nativeCallId: UUID) {
        synchronized(lock) { if (cameraLeaseCall == nativeCallId) cameraLeaseCall = null }
        applier.apply(nativeCallId, false)
    }

    fun holdsCameraLease(nativeCallId: UUID): Boolean = synchronized(lock) { cameraLeaseCall == nativeCallId }

    /** Drops the lease without touching the platform, for a caller that is
     * itself about to re-apply the service types without the camera. */
    fun dropLease(nativeCallId: UUID) {
        synchronized(lock) { if (cameraLeaseCall == nativeCallId) cameraLeaseCall = null }
    }

    private fun takeLease(): UUID? {
        val held = cameraLeaseCall
        cameraLeaseCall = null
        return held
    }

    private fun decide(nativeCallId: UUID): MknoonCallLocalCameraDecision =
        decideMknoonCallLocalCamera(
            MknoonCallLocalCameraInputs(
                media = effectiveMedia(nativeCallId),
                audioActive = facts.audioActive(nativeCallId),
                uiVisible = facts.uiVisible(),
                cameraPermissionGranted = facts.cameraPermissionGranted(),
                sdkInt = facts.sdkInt(),
                manifestDeclaresCameraType = facts.manifestDeclaresCameraType(),
            ),
        )
}
