package com.mknoon.app

import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import java.io.File
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Two independently invokable phases; the host force-stops the app between them. */
class AppVisibilityLifecycleInstrumentationTest {
    private lateinit var context: Context
    private lateinit var recordFile: File
    private lateinit var instrumentation: Instrumentation

    @Before
    fun setUp() {
        instrumentation = InstrumentationRegistry.getInstrumentation()
        context = instrumentation.targetContext
        recordFile = File(context.filesDir, AppVisibilitySnapshotStore.FILE_NAME)
        assertEquals(PROOF_APPLICATION_ID, context.packageName)
        AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
    }

    @Test
    fun testTC37108aSeedLifecycleAndDurableRecord() {
        deleteAtomicRecord()
        val boot = AndroidBootSessionProvider(context).currentBootSession()
        assertNotNull("Settings.Global.BOOT_COUNT must be readable", boot)
        var activeGeneration = 0L

        val activity = launchMainActivity()
        try {
            val store = AppVisibilitySnapshotStore(activity.applicationContext)
            val active = checkNotNull(store.readSnapshot())
            assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, active.snapshot.lifecycle)
            assertNull(active.snapshot.visibleConversationDigest)
            assertEquals(boot, active.currentBootSession)
            assertTrue(active.currentMonotonicMs >= active.snapshot.updatedMonotonicMs)
            activeGeneration = active.snapshot.lifecycleGeneration

            val digest = checkNotNull(
                AppVisibilityConversationDigest.digest(
                    AppVisibilityConversationLane.DIRECT,
                    "peer-A",
                ),
            )
            val route = store.publishVisibleConversation(digest, activeGeneration)
            assertTrue(route.committed)
            assertEquals(digest, route.snapshot?.visibleConversationDigest)
            assertEquals(activeGeneration, route.snapshot?.lifecycleGeneration)
        } finally {
            finishMainActivity(activity)
        }

        val durable = readDurableRecord()
        assertEquals(AppVisibilityLifecycle.BACKGROUND, durable.lifecycle)
        assertNull(durable.visibleConversationDigest)
        assertTrue(durable.lifecycleGeneration > activeGeneration)
        assertEquals(boot, durable.bootSession)
    }

    @Test
    fun testTC37108bReopenDiskAndRejectStaleRoute() {
        val reopened = readDurableRecord()
        assertEquals(
            "phase B must reopen the phase-A background record after host force-stop",
            AppVisibilityLifecycle.BACKGROUND,
            reopened.lifecycle,
        )
        assertNull(reopened.visibleConversationDigest)
        val staleGeneration = reopened.lifecycleGeneration
        val boot = AndroidBootSessionProvider(context).currentBootSession()
        assertEquals(reopened.bootSession, boot)

        val activity = launchMainActivity()
        try {
            val store = AppVisibilitySnapshotStore(activity.applicationContext)
            val active = checkNotNull(store.readSnapshot()).snapshot
            assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, active.lifecycle)
            assertNull(active.visibleConversationDigest)
            assertTrue(active.revision > reopened.revision)
            assertTrue(active.lifecycleGeneration > staleGeneration)

            val beforeStaleRoute = AndroidAppVisibilityAtomicBackend(recordFile)
                .readFully()
            val digest = checkNotNull(
                AppVisibilityConversationDigest.digest(
                    AppVisibilityConversationLane.DIRECT,
                    "peer-A",
                ),
            )
            val rejected = store.publishVisibleConversation(
                digest,
                staleGeneration,
            )
            assertFalse(rejected.committed)

            val afterStaleRoute = AndroidAppVisibilityAtomicBackend(recordFile)
                .readFully()
            assertTrue(beforeStaleRoute.contentEquals(afterStaleRoute))
            val durable = readDurableRecord()
            assertEquals(active, durable)
            assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, durable.lifecycle)
            assertNull(durable.visibleConversationDigest)
        } finally {
            finishMainActivity(activity)
        }
    }

    private fun launchMainActivity(): MainActivity {
        val intent = checkNotNull(
            context.packageManager.getLaunchIntentForPackage(PROOF_APPLICATION_ID),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return instrumentation.startActivitySync(intent) as MainActivity
    }

    private fun finishMainActivity(activity: MainActivity) {
        instrumentation.runOnMainSync { activity.finish() }
        val deadline = SystemClock.elapsedRealtime() + ACTIVITY_STOP_TIMEOUT_MS
        var durableLifecycle: AppVisibilityLifecycle? = null
        do {
            instrumentation.waitForIdleSync()
            durableLifecycle = runCatching { readDurableRecord().lifecycle }
                .getOrNull()
            if (durableLifecycle == AppVisibilityLifecycle.BACKGROUND) return
            SystemClock.sleep(ACTIVITY_STOP_POLL_MS)
        } while (SystemClock.elapsedRealtime() < deadline)
        assertEquals(
            "finish must synchronously persist the real pause/stop callbacks",
            AppVisibilityLifecycle.BACKGROUND,
            durableLifecycle,
        )
    }

    private fun readDurableRecord(): AppVisibilitySnapshotV1 {
        val decoded = AppVisibilitySnapshotCodec.decode(
            AndroidAppVisibilityAtomicBackend(recordFile).readFully(),
        )
        return (decoded as AppVisibilitySnapshotDecodeResult.Supported).snapshot
    }

    private fun deleteAtomicRecord() {
        listOf(recordFile, File(recordFile.path + ".bak"), File(recordFile.path + ".new"))
            .forEach { it.delete() }
    }

    private companion object {
        const val PROOF_APPLICATION_ID = "com.mknoon.app.visibilityproof"
        const val ACTIVITY_STOP_TIMEOUT_MS = 5_000L
        const val ACTIVITY_STOP_POLL_MS = 50L
    }
}
