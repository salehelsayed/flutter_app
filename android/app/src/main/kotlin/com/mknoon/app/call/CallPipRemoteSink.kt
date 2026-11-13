package com.mknoon.app.call

import android.app.Activity
import android.view.ViewGroup
import android.widget.FrameLayout
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.utils.EglUtils
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoTrack

/**
 * Remote-only native renderer drawn over the Flutter view during OS PiP, so the
 * PiP window never shows chat pixels. It is a second sink on the plugin's
 * existing remote track; releasing it never touches the track, the peer
 * connection, the Flutter renderer or audio.
 */
internal class CallPipRemoteSink private constructor(
    private val track: VideoTrack,
    private val renderer: SurfaceViewRenderer,
) {
    /** Throws if native cleanup fails, so the lease core keeps owning it. */
    fun release() {
        try {
            track.removeSink(renderer)
            renderer.release()
        } finally {
            (renderer.parent as? ViewGroup)?.removeView(renderer)
        }
    }

    companion object {
        /** Exact peer + track lookup through the plugin's public API; never first match. */
        fun videoTrack(source: CallPipSource): VideoTrack? {
            val plugin = FlutterWebRTCPlugin.sharedSingleton ?: return null
            return resolveExactRemoteTrack(
                source,
                localTrack = { plugin.getLocalTrack(it) },
                peerTrack = { track, peer -> plugin.getTrackForId(track, peer) },
            ) as? VideoTrack
        }

        fun attach(activity: Activity, source: CallPipSource): CallPipRemoteSink? {
            val track = videoTrack(source) ?: return null
            val renderer = SurfaceViewRenderer(activity)
            return try {
                renderer.init(EglUtils.getRootEglBaseContext(), null)
                renderer.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                renderer.setZOrderMediaOverlay(true)
                renderer.clearImage()
                activity.addContentView(
                    renderer,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                track.addSink(renderer)
                CallPipRemoteSink(track, renderer)
            } catch (_: RuntimeException) {
                runCatching { renderer.release() }
                (renderer.parent as? ViewGroup)?.removeView(renderer)
                null
            }
        }
    }
}
