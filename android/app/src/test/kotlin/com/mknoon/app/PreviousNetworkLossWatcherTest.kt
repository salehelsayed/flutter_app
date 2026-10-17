package com.mknoon.app

import android.net.ConnectivityManager
import android.net.Network
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class PreviousNetworkLossWatcherTest {
    private lateinit var connectivity: ConnectivityManager
    private val lost = mutableListOf<Long>()
    private val wifi: Network = ShadowNetwork.newInstance(101)
    private val cellular: Network = ShadowNetwork.newInstance(202)
    private val otherWifi: Network = ShadowNetwork.newInstance(303)

    @Before
    fun setUp() {
        connectivity = RuntimeEnvironment.getApplication()
            .getSystemService(ConnectivityManager::class.java)
    }

    private fun watcher(): PreviousNetworkLossWatcher {
        val watcher = PreviousNetworkLossWatcher(
            connectivity,
            sink = { epoch -> lost += epoch },
            dispatch = { work -> work.run() },
        )
        assertTrue(watcher.start())
        return watcher
    }

    private fun callback(): ConnectivityManager.NetworkCallback =
        shadowOf(connectivity).networkCallbacks.single()

    @Test
    fun `the previous default's loss after a switch reports the current epoch once`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)
        watcher.pathAnnounced(cellular, 1)

        callback().onLost(wifi)
        callback().onLost(wifi)

        assertEquals(listOf(1L), lost)
    }

    @Test
    fun `the old network becoming the default again is not watched`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)
        watcher.pathAnnounced(cellular, 1)
        watcher.pathAnnounced(wifi, 2)

        callback().onLost(wifi)
        assertEquals(emptyList<Long>(), lost)

        callback().onLost(cellular)
        assertEquals(listOf(2L), lost)
    }

    @Test
    fun `after a later switch only the latest previous network is watched`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)
        watcher.pathAnnounced(cellular, 1)
        watcher.pathAnnounced(otherWifi, 2)

        callback().onLost(wifi)
        assertEquals(emptyList<Long>(), lost)

        callback().onLost(cellular)
        assertEquals(listOf(2L), lost)
    }

    @Test
    fun `a repeat announcement of the current network only moves its epoch`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)
        watcher.pathAnnounced(cellular, 1)
        watcher.pathAnnounced(cellular, 2)

        callback().onLost(wifi)

        assertEquals(listOf(2L), lost)
    }

    @Test
    fun `nothing is reported before a path epoch exists`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)

        callback().onLost(wifi)
        callback().onLost(cellular)

        assertEquals(emptyList<Long>(), lost)
    }

    @Test
    fun `close unregisters and later losses report nothing`() {
        val watcher = watcher()
        watcher.pathAnnounced(wifi, 0)
        watcher.pathAnnounced(cellular, 1)
        val registered = callback()

        watcher.close()
        registered.onLost(wifi)

        assertEquals(emptyList<Long>(), lost)
        assertEquals(0, shadowOf(connectivity).networkCallbacks.size)
    }
}
