package com.mknoon.app.call

import android.content.pm.ServiceInfo

/** Media a call was registered with. Absent on the wire means audio, which is
 * every call today; video stays unreachable until Dart sends it. */
internal enum class MknoonCallMedia(val wireValue: String) {
    AUDIO("audio"),
    VIDEO("video");

    companion object {
        /** Null for an unknown value so the caller can fail closed. */
        fun parse(wire: Any?): MknoonCallMedia? = when (wire) {
            null -> AUDIO
            AUDIO.wireValue -> AUDIO
            VIDEO.wireValue -> VIDEO
            else -> null
        }
    }
}

/** Facts the native side checks before the call service may carry the camera
 * foreground type. Android 14+ throws if a camera type starts from the
 * background, so visibility is required, not just a granted permission. */
internal data class MknoonCallLocalCameraInputs(
    val media: MknoonCallMedia,
    val audioActive: Boolean,
    val uiVisible: Boolean,
    val cameraPermissionGranted: Boolean,
    val sdkInt: Int,
    /** The call service's manifest entry lists the "camera" type. Held out of
     * the manifest until the build that enables video (Play declaration).
     * Without it a visible call still gets an untyped lease (VC-FG-CAMERA):
     * while-in-use camera access from a visible activity needs no FGS type. */
    val manifestDeclaresCameraType: Boolean,
)

internal sealed interface MknoonCallLocalCameraDecision {
    data object Apply : MknoonCallLocalCameraDecision

    data class Refuse(val reason: Reason) : MknoonCallLocalCameraDecision

    enum class Reason(val wireValue: String) {
        UNSUPPORTED("unsupported"),
        NOT_VIDEO("not_video"),
        NOT_ACTIVE("not_active"),
        NO_PERMISSION("no_permission"),
        NOT_VISIBLE("not_visible"),
    }
}

/** FOREGROUND_SERVICE_TYPE_CAMERA exists from API 30. */
internal const val MKNOON_CALL_CAMERA_TYPE_MIN_SDK = 30

internal fun decideMknoonCallLocalCamera(
    inputs: MknoonCallLocalCameraInputs,
): MknoonCallLocalCameraDecision {
    val reason = when {
        inputs.sdkInt < MKNOON_CALL_CAMERA_TYPE_MIN_SDK -> MknoonCallLocalCameraDecision.Reason.UNSUPPORTED
        inputs.media != MknoonCallMedia.VIDEO -> MknoonCallLocalCameraDecision.Reason.NOT_VIDEO
        !inputs.audioActive -> MknoonCallLocalCameraDecision.Reason.NOT_ACTIVE
        !inputs.cameraPermissionGranted -> MknoonCallLocalCameraDecision.Reason.NO_PERMISSION
        !inputs.uiVisible -> MknoonCallLocalCameraDecision.Reason.NOT_VISIBLE
        else -> return MknoonCallLocalCameraDecision.Apply
    }
    return MknoonCallLocalCameraDecision.Refuse(reason)
}

/** Foreground types for the ongoing call service. The camera type rides only
 * on an active (microphone) service; an inactive call never keeps the camera. */
internal fun mknoonCallOngoingForegroundTypes(withMicrophone: Boolean, withCamera: Boolean): Int =
    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
        (if (withMicrophone) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0) or
        (if (withMicrophone && withCamera) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0)
