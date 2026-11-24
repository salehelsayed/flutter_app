package com.mknoon.app

import android.content.Context
import android.os.Looper
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
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
        val writes = QueuedExecutor()
        val coordinator = AppVisibilityLifecycleCoordinator(store, writes)

        coordinator.onLaunch()
        writes.runNext()
        val launch = decodeRecord()
        assertEquals(AppVisibilityLifecycle.INACTIVE, launch.lifecycle)
        assertNull(launch.visibleConversationDigest)

        now[0] = 11L
        coordinator.onResume()
        writes.runNext()
        val active = decodeRecord()
        val activeGeneration = active.lifecycleGeneration
        assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, active.lifecycle)

        now[0] = 12L
        val digest = "a".repeat(64)
        assertTrue(
            store.publishVisibleConversation(digest, activeGeneration).committed,
        )

        now[0] = 13L
        coordinator.onPause()
        writes.runNext()
        val inactive = decodeRecord()
        assertEquals(AppVisibilityLifecycle.INACTIVE, inactive.lifecycle)
        assertNull(inactive.visibleConversationDigest)

        now[0] = 14L
        assertFalse(
            store.publishVisibleConversation(digest, activeGeneration).committed,
        )
        val durableAfterStaleRoute = decodeRecord()
        assertEquals(inactive, durableAfterStaleRoute)

        now[0] = 15L
        coordinator.onStop()
        writes.runNext()
        val background = decodeRecord()
        assertEquals(AppVisibilityLifecycle.BACKGROUND, background.lifecycle)
        assertNull(background.visibleConversationDigest)
        assertTrue(background.lifecycleGeneration > activeGeneration)
    }

    @Test
    fun `BL-85 pause syncs the visibility record off the main looper`() {
        val mainThread = Looper.getMainLooper().thread
        assertEquals(
            "invoke the lifecycle callback on the main looper",
            mainThread,
            Thread.currentThread(),
        )
        val bootSession = AppVisibilityBootSessionProvider { "android:7" }
        val store = AppVisibilitySnapshotStore(context = context, bootSessionProvider = bootSession)
        assertTrue(store.transitionLifecycle(AppVisibilityLifecycle.FOREGROUND_ACTIVE).committed)

        val pauseReachedSync = CountDownLatch(1)
        val pauseSyncedOnMain = AtomicBoolean(true)
        val pauseStore = AppVisibilitySnapshotStore(
            context = context,
            bootSessionProvider = bootSession,
            faults = object : AppVisibilitySnapshotFaultInjector {
                override fun beforeSync() {
                    pauseSyncedOnMain.set(Thread.currentThread() == mainThread)
                    pauseReachedSync.countDown()
                }
            },
        )

        AppVisibilityLifecycleCoordinator(pauseStore).onPause()

        assertTrue("pause must still sync the record", pauseReachedSync.await(2, TimeUnit.SECONDS))
        assertFalse("pause must not sync on the main looper", pauseSyncedOnMain.get())
    }

    @Test
    fun `BL-85 pause fences queued writes and replies while resume waits for durable state`() {
        val store = AppVisibilitySnapshotStore(
            context = context,
            bootSessionProvider = AppVisibilityBootSessionProvider { "android:7" },
        )
        val writes = QueuedExecutor()
        val replies = QueuedExecutor()
        val coordinator = AppVisibilityLifecycleCoordinator(store, writes, replies)
        coordinator.onLaunch()
        writes.runNext()
        coordinator.onResume()
        writes.runNext()

        val active = decodeRecord()
        val digest = "a".repeat(64)
        assertTrue(store.publishVisibleConversation(digest, active.lifecycleGeneration).committed)
        val published = decodeRecord()

        val previousReads = mutableListOf<AppVisibilityReadEnvelope?>()
        coordinator.readSnapshot { previousReads.add(it) }
        writes.runNext()
        assertTrue(previousReads.isEmpty())

        val previousWrites = mutableListOf<AppVisibilityCommitEnvelope?>()
        coordinator.publishVisibleConversation("b".repeat(64), active.lifecycleGeneration) {
            previousWrites.add(it)
        }
        coordinator.onPause()

        val pendingPauseReads = mutableListOf<AppVisibilityReadEnvelope?>()
        coordinator.readSnapshot { pendingPauseReads.add(it) }
        replies.runAll()
        assertEquals(listOf<AppVisibilityReadEnvelope?>(null), previousReads)
        assertEquals(listOf<AppVisibilityReadEnvelope?>(null), pendingPauseReads)
        assertEquals(published, decodeRecord())

        writes.runNext()
        replies.runAll()
        assertEquals(listOf<AppVisibilityCommitEnvelope?>(null), previousWrites)
        assertEquals(published, decodeRecord())
        writes.runNext()

        val settledPauseReads = mutableListOf<AppVisibilityReadEnvelope?>()
        coordinator.readSnapshot { settledPauseReads.add(it) }
        writes.runNext()
        replies.runAll()
        val paused = checkNotNull(settledPauseReads.single()).snapshot
        assertEquals(decodeRecord(), paused)
        assertEquals(AppVisibilityLifecycle.INACTIVE, paused.lifecycle)
        assertNull(paused.visibleConversationDigest)

        coordinator.onResume()
        val resumeReads = mutableListOf<AppVisibilityReadEnvelope?>()
        coordinator.readSnapshot { resumeReads.add(it) }
        replies.runAll()
        assertTrue(resumeReads.isEmpty())
        assertEquals(paused, decodeRecord())
        writes.runNext()
        writes.runNext()
        replies.runAll()

        val resumed = checkNotNull(resumeReads.single()).snapshot
        assertEquals(decodeRecord(), resumed)
        assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, resumed.lifecycle)
        assertNull(resumed.visibleConversationDigest)
        assertTrue(resumed.lifecycleGeneration > paused.lifecycleGeneration)
    }

    @Test
    fun `BL-85 old activity cannot read or supersede a new foreground owner`() {
        val store = AppVisibilitySnapshotStore(
            context = context,
            bootSessionProvider = AppVisibilityBootSessionProvider { "android:7" },
        )
        val writes = QueuedExecutor()
        val replies = QueuedExecutor()
        val coordinator = AppVisibilityLifecycleCoordinator(store, writes, replies)
        val oldOwner = Any()
        val currentOwner = Any()
        coordinator.onLaunch(oldOwner)
        coordinator.onResume(oldOwner)
        writes.runAll()
        val previous = decodeRecord()
        assertTrue(store.publishVisibleConversation("a".repeat(64), previous.lifecycleGeneration).committed)

        coordinator.onResume(currentOwner)
        coordinator.onStop(oldOwner)
        val oldReads = mutableListOf<AppVisibilityReadEnvelope?>()
        coordinator.readSnapshot(oldOwner) { oldReads.add(it) }
        writes.runAll()
        replies.runAll()

        assertEquals(listOf<AppVisibilityReadEnvelope?>(null), oldReads)
        val foreground = decodeRecord()
        assertEquals(AppVisibilityLifecycle.FOREGROUND_ACTIVE, foreground.lifecycle)
        assertNull(foreground.visibleConversationDigest)
        assertTrue(foreground.lifecycleGeneration > previous.lifecycleGeneration)
    }

    @Test
    fun `MainActivity requests every native transition before Flutter exposure`() {
        val source = repoFile(
            "android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt",
        ).readText()

        assertOrderedInFunction(
            source,
            "override fun onCreate",
            "visibilityLifecycleCoordinator().onLaunch(appVisibilityOwner)",
            "super.onCreate(savedInstanceState)",
        )
        assertOrderedInFunction(
            source,
            "override fun onResume",
            "visibilityLifecycleCoordinator().onResume(appVisibilityOwner)",
            "super.onResume()",
        )
        assertOrderedInFunction(
            source,
            "override fun onPause",
            "visibilityLifecycleCoordinator().onPause(appVisibilityOwner)",
            "super.onPause()",
        )
        assertOrderedInFunction(
            source,
            "override fun onStop",
            "visibilityLifecycleCoordinator().onStop(appVisibilityOwner)",
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

    private class QueuedExecutor : Executor {
        private val tasks = ArrayDeque<Runnable>()

        override fun execute(command: Runnable) {
            tasks.addLast(command)
        }

        fun runNext() {
            tasks.removeFirst().run()
        }

        fun runAll() {
            while (tasks.isNotEmpty()) runNext()
        }
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
