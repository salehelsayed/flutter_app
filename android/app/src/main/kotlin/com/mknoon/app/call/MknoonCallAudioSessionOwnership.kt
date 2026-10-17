package com.mknoon.app.call

import com.cloudwebrtc.webrtc.audio.AudioSwitchManager

/**
 * Decides once per process who owns Android's audio mode, route and mute
 * during a call.
 *
 * With the Telecom lane compiled in, CallControlScope owns them through
 * MknoonCallAndroidRuntime. flutter_webrtc's AudioSwitch must then not cache
 * the in-call state on getUserMedia and restore it after the last peer is
 * disposed, which re-selected MODE_IN_COMMUNICATION after Telecom had already
 * set MODE_NORMAL. Without that lane there is no native owner, so the plugin
 * keeps its default.
 */
object MknoonCallAudioSessionOwnership {
    fun applyProcessPolicy(telecomLaneCompiledIn: Boolean) {
        AudioSwitchManager.setAudioSessionManagementEnabled(!telecomLaneCompiledIn)
    }
}
