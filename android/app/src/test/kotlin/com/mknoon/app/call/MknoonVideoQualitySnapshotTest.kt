package com.mknoon.app.call

import android.net.ConnectivityManager
import android.os.PowerManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MknoonVideoQualitySnapshotTest {
    private fun net(
        wifi: Boolean = false,
        cellular: Boolean = false,
        vpn: Boolean = false,
        notMetered: Boolean? = true,
    ) = MknoonVideoNetworkInputs(wifi, cellular, vpn, notMetered)

    @Test
    fun unknownNetworkStaysUnknownNotUnmetered() {
        val snapshot = MknoonVideoQualitySnapshot.build(MknoonVideoNetworkInputs.UNKNOWN, null, null)
        assertEquals("unknown", snapshot["networkClass"])
        assertNull(snapshot["metered"])
        assertNull(snapshot["lowDataMode"])
        assertEquals("unknown", snapshot["thermalState"])
        assertEquals(setOf("networkClass", "lowDataMode", "metered", "thermalState"), snapshot.keys)
    }

    @Test
    fun unmeteredCellularIsStillCellular() {
        assertEquals("cellular", MknoonVideoQualitySnapshot.networkClass(net(cellular = true, notMetered = true)))
        assertEquals(false, MknoonVideoQualitySnapshot.metered(net(cellular = true, notMetered = true)))
        assertEquals(true, MknoonVideoQualitySnapshot.metered(net(cellular = true, notMetered = false)))
    }

    @Test
    fun wifiOtherAndVpnClasses() {
        assertEquals("wifi", MknoonVideoQualitySnapshot.networkClass(net(wifi = true)))
        assertEquals("other", MknoonVideoQualitySnapshot.networkClass(net()))
        assertEquals("unknown", MknoonVideoQualitySnapshot.networkClass(net(wifi = true, vpn = true)))
    }

    @Test
    fun dataSaverActiveEvenWhenAllowlisted() {
        assertEquals(false, MknoonVideoQualitySnapshot.lowDataMode(ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED))
        assertEquals(true, MknoonVideoQualitySnapshot.lowDataMode(ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED))
        assertEquals(true, MknoonVideoQualitySnapshot.lowDataMode(ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED))
        assertNull(MknoonVideoQualitySnapshot.lowDataMode(null))
        assertNull(MknoonVideoQualitySnapshot.lowDataMode(99))
    }

    @Test
    fun thermalMapping() {
        assertEquals("nominal", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_NONE))
        assertEquals("elevated", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_LIGHT))
        assertEquals("elevated", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_MODERATE))
        assertEquals("serious", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_SEVERE))
        assertEquals("critical", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_CRITICAL))
        assertEquals("critical", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_EMERGENCY))
        assertEquals("critical", MknoonVideoQualitySnapshot.thermalState(PowerManager.THERMAL_STATUS_SHUTDOWN))
        assertEquals("unknown", MknoonVideoQualitySnapshot.thermalState(null))
        assertEquals("unknown", MknoonVideoQualitySnapshot.thermalState(42))
    }
}
