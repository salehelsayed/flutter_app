package com.example.video_compress

import com.otaliastudios.transcoder.common.TrackType
import com.otaliastudios.transcoder.time.TimeInterpolator

/**
 * Some phone videos present decoded frames out of timestamp order. Transcoder
 * 0.11.x rejects those frames before its encoder can consume them. Keep the
 * original timestamp whenever possible and advance reordered frames by one
 * microsecond so the pipeline can continue.
 */
class MonotonicTimeInterpolator : TimeInterpolator {
    private val lastByTrack = mutableMapOf<TrackType, Long>()

    override fun interpolate(type: TrackType, time: Long): Long {
        val previous = lastByTrack[type]
        val corrected = if (previous != null && time <= previous) previous + 1L else time
        lastByTrack[type] = corrected
        return corrected
    }
}
