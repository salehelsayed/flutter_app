package com.example.video_compress

import com.otaliastudios.transcoder.common.TrackType
import org.junit.Assert.assertEquals
import org.junit.Test

class MonotonicTimeInterpolatorTest {
    @Test
    fun repairsOutOfOrderVideoTimestampsWithoutChangingAudio() {
        val interpolator = MonotonicTimeInterpolator()

        assertEquals(0L, interpolator.interpolate(TrackType.VIDEO, 0L))
        assertEquals(65000L, interpolator.interpolate(TrackType.VIDEO, 65000L))
        assertEquals(65001L, interpolator.interpolate(TrackType.VIDEO, 30000L))
        assertEquals(65002L, interpolator.interpolate(TrackType.VIDEO, 50000L))
        assertEquals(100000L, interpolator.interpolate(TrackType.VIDEO, 100000L))

        assertEquals(0L, interpolator.interpolate(TrackType.AUDIO, 0L))
        assertEquals(21000L, interpolator.interpolate(TrackType.AUDIO, 21000L))
    }
}
