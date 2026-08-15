package com.mknoon.app

import android.content.Context
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MainActivityAppVisibilityTest {
    private lateinit var context: Context
    private lateinit var recordFile: File

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        recordFile = File(context.filesDir, AppVisibilitySnapshotStore.FILE_NAME)
        listOf(recordFile, File(recordFile.path + ".bak"), File(recordFile.path + ".new"))
            .forEach { it.delete() }
        AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
    }

    @Test
    fun `TC-371-07 lifecycle and stale route CAS preserve newest state`() {
        val now = longArrayOf(10L)
        val store = AppVisibilitySnapshotStore(
            context = context,
            monotonicClock = AppVisibilityMonotonicClock { now[0] },
            bootSessionProvider = AppVisibilityBootSessionProvider { "android:7" },
        )
        val coordinator = AppVisibilityLifecycleCoordinator(store)

        val launch = coordinator.onLaunch()
        assertEquals(AppVisibilityLifecycle.INACTIVE, launch.snapshot?.lifecycle)
        assertNull(launch.snapshot?.visibleConversationDigest)

        now[0] = 11L
        val active = coordinator.onResume()
        val activeGeneration = checkNotNull(active.snapshot).lifecycleGeneration
        assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, active.snapshot?.lifecycle)

        now[0] = 12L
        val digest = "a".repeat(64)
        assertTrue(
            store.publishVisibleConversation(digest, activeGeneration).committed,
        )

        now[0] = 13L
        val inactive = coordinator.onPause()
        assertEquals(AppVisibilityLifecycle.INACTIVE, inactive.snapshot?.lifecycle)
        assertNull(inactive.snapshot?.visibleConversationDigest)
        val inactiveRecord = checkNotNull(inactive.snapshot)

        now[0] = 14L
        assertFalse(
            store.publishVisibleConversation(digest, activeGeneration).committed,
        )
        val durableAfterStaleRoute = decodeRecord()
        assertEquals(inactiveRecord, durableAfterStaleRoute)

        now[0] = 15L
        val background = coordinator.onStop()
        assertEquals(AppVisibilityLifecycle.BACKGROUND, background.snapshot?.lifecycle)
        assertNull(background.snapshot?.visibleConversationDigest)
        assertTrue(
            checkNotNull(background.snapshot).lifecycleGeneration > activeGeneration,
        )
    }

    @Test
    fun `MainActivity persists every native transition before Flutter exposure`() {
        val source = repoFile(
            "android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt",
        ).readText()

        assertOrderedInFunction(
            source,
            "override fun onCreate",
            "visibilityLifecycleCoordinator().onLaunch()",
            "super.onCreate(savedInstanceState)",
        )
        assertOrderedInFunction(
            source,
            "override fun onResume",
            "visibilityLifecycleCoordinator().onResume()",
            "super.onResume()",
        )
        assertOrderedInFunction(
            source,
            "override fun onPause",
            "visibilityLifecycleCoordinator().onPause()",
            "super.onPause()",
        )
        assertOrderedInFunction(
            source,
            "override fun onStop",
            "visibilityLifecycleCoordinator().onStop()",
            "super.onStop()",
        )
        assertTrue(source.contains("\"mknoon/app_visibility\""))
        assertTrue(source.contains("\"readSnapshot\""))
        assertTrue(source.contains("\"publishVisibleConversation\""))
        assertTrue(source.contains("\"visibleConversationDigest\""))
        assertTrue(source.contains("\"lifecycleGeneration\""))
    }

    @Test
    fun `manifest and Gradle freeze one process and the independent N04 proof`() {
        val manifest = repoFile("android/app/src/main/AndroidManifest.xml").readText()
        assertFalse(manifest.contains("android:process"))
        assertTrue(manifest.contains("android:name=\".MainActivity\""))
        assertTrue(manifest.contains("android:name=\".MknoonFirebaseMessagingService\""))
        assertTrue(
            manifest.contains(
                "android:name=\"androidx.work.impl.foreground.SystemForegroundService\"",
            ),
        )

        val gradle = repoFile("android/app/build.gradle.kts").readText()
        assertTrue(gradle.contains("enableAppVisibility371Proof"))
        assertTrue(gradle.contains("com.mknoon.app.visibilityproof"))
        assertTrue(gradle.contains("disableGoogleServicesForDisposableProof"))
        assertTrue(gradle.contains("androidx.test.runner.AndroidJUnitRunner"))
        assertTrue(gradle.contains("src/appVisibility371AndroidTest/kotlin"))
        assertTrue(gradle.contains("androidx.test:runner:1.2.0"))
        assertTrue(gradle.contains("androidx.test:rules:1.2.0"))
        assertTrue(
            gradle.contains(
                "enableAppVisibility371Proof && enableGroupExitReleaseDiagnosticsProof",
            ),
        )
    }

    private fun decodeRecord(): AppVisibilitySnapshotV1 =
        (AppVisibilitySnapshotCodec.decode(
            AndroidAppVisibilityAtomicBackend(recordFile).readFully(),
        ) as AppVisibilitySnapshotDecodeResult.Supported).snapshot

    private fun assertOrderedInFunction(
        source: String,
        functionAnchor: String,
        first: String,
        second: String,
    ) {
        val functionStart = source.indexOf(functionAnchor)
        val nextFunction = source.indexOf("\n    override fun ", functionStart + 1)
            .let { if (it < 0) source.length else it }
        val body = source.substring(functionStart, nextFunction)
        val firstIndex = body.indexOf(first)
        val secondIndex = body.indexOf(second)
        assertTrue("Missing $first in $functionAnchor", firstIndex >= 0)
        assertTrue("Missing $second in $functionAnchor", secondIndex >= 0)
        assertTrue("$first must precede $second", firstIndex < secondIndex)
    }

    private fun repoFile(relativePath: String): File = sequenceOf(
        File(relativePath),
        File("../$relativePath"),
        File("../../$relativePath"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $relativePath")
}
