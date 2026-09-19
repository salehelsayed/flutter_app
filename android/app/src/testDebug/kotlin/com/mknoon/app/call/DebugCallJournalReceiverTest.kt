package com.mknoon.app.call

import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DebugCallJournalReceiverTest {
    @Test fun debugReceiverRequiresSignatureSystemDumpPermission() {
        val context = RuntimeEnvironment.getApplication()
        val info = context.packageManager.getReceiverInfo(
            ComponentName(context, DebugCallAudioOracleReceiver::class.java), 0)
        assertEquals("android.permission.DUMP", info.permission)
        assertTrue(info.exported)
    }

    @Test fun journalQueryDoesNotInitializeRuntimeOrPublishAudioProbeFiles() {
        val context = RuntimeEnvironment.getApplication()
        assertNull(MknoonCallRuntime.existingInstance())
        var result: JSONObject? = null
        val receipt = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                result = JSONObject(resultData)
            }
        }
        context.sendOrderedBroadcast(Intent(DebugCallAudioOracleReceiver.ACTION)
            .setComponent(ComponentName(context, DebugCallAudioOracleReceiver::class.java))
            .putExtra("operation", "journal_snapshot")
            .putExtra("nonce", "1234567890abcdef"), null, receipt, null, 0, null, null)
        shadowOf(android.os.Looper.getMainLooper()).idle()
        assertEquals("runtime_unavailable", requireNotNull(result).getString("reason"))
        assertNull(MknoonCallRuntime.existingInstance())
        assertFalse(java.io.File(context.filesDir, "debug-call-audio-oracle").exists())
    }
}
