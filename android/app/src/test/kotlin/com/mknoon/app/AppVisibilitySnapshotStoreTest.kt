package com.mknoon.app

import android.content.Context
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
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
class AppVisibilitySnapshotStoreTest {
    private lateinit var context: Context
    private lateinit var recordFile: File
    private lateinit var fixture: JSONObject
    private lateinit var fixtureText: String

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        recordFile = File(context.filesDir, AppVisibilitySnapshotStore.FILE_NAME)
        deleteAtomicRecord()
        AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
        fixtureText = checkNotNull(
            javaClass.classLoader?.getResourceAsStream(
                "app_visibility_snapshot_v1.json",
            ),
        ).use { stream ->
            stream.reader(StandardCharsets.UTF_8).readText()
        }
        fixture = JSONObject(fixtureText)
    }

    @Test
    fun `TC-371-07 v1 store is atomic fresh and fail-notify`() {
        assertEquals(APP_VISIBILITY_SCHEMA_VERSION, fixture.getInt("schemaVersion"))
        assertEquals(APP_VISIBILITY_FRESHNESS_MS, fixture.getLong("freshnessWindowMs"))

        val digestVectors = fixture.getJSONArray("digestVectors")
        for (index in 0 until digestVectors.length()) {
            val vector = digestVectors.getJSONObject(index)
            val lane = when (vector.getString("lane")) {
                "direct" -> AppVisibilityConversationLane.DIRECT
                "group" -> AppVisibilityConversationLane.GROUP
                else -> error("Unknown fixture lane")
            }
            val input = vector.getString("input")
            assertEquals(
                vector.getString("normalizedId"),
                AppVisibilityConversationDigest.normalizedLocalId(lane, input),
            )
            assertEquals(vector.getInt("laneByte"), lane.wireByte.toInt())
            assertEquals(
                vector.getString("preimageHex"),
                AppVisibilityConversationDigest.preimage(lane, input)?.toHex(),
            )
            assertEquals(
                vector.getString("digest"),
                AppVisibilityConversationDigest.digest(lane, input),
            )
        }

        val invalidConversationVectors = fixture.getJSONArray(
            "invalidConversationVectors",
        )
        for (index in 0 until invalidConversationVectors.length()) {
            val vector = invalidConversationVectors.getJSONObject(index)
            val lane = when (vector.getString("lane")) {
                "direct" -> AppVisibilityConversationLane.DIRECT
                "group" -> AppVisibilityConversationLane.GROUP
                else -> error("Unknown fixture lane")
            }
            assertNull(
                vector.getString("name"),
                AppVisibilityConversationDigest.digest(
                    lane,
                    vector.getString("input"),
                ),
            )
        }
        assertNull(
            AppVisibilityConversationDigest.digest(
                AppVisibilityConversationLane.GROUP,
                "group:embedded:colon",
            ),
        )

        val predicateVectors = fixture.getJSONArray("predicateVectors")
        for (index in 0 until predicateVectors.length()) {
            val vector = predicateVectors.getJSONObject(index)
            val snapshot = decodeSupported(vector.getJSONObject("snapshot"))
            assertEquals(
                vector.getString("name"),
                vector.getBoolean("maySuppress"),
                AppVisibilitySnapshotPredicate.maySuppress(
                    snapshot = snapshot,
                    currentMonotonicMs = vector.getLong("currentMonotonicMs"),
                    currentBootSession = vector.getString("currentBootSession"),
                    expectedConversationDigest = vector.optStringOrNull(
                        "expectedConversationDigest",
                    ),
                ),
            )
        }

        val invalidSnapshots = fixture.getJSONArray("invalidSnapshotVectors")
        for (index in 0 until invalidSnapshots.length()) {
            val vector = invalidSnapshots.getJSONObject(index)
            val result = AppVisibilitySnapshotCodec.decode(
                rawInvalidSnapshot(vector.getString("name"))
                    .toByteArray(StandardCharsets.UTF_8),
            )
            when (vector.getString("name")) {
                "future_schema" -> assertEquals(
                    AppVisibilitySnapshotDecodeResult.FutureSchema,
                    result,
                )
                "revision_overflow" -> assertEquals(
                    AppVisibilitySnapshotDecodeResult.UnsupportedBounds,
                    result,
                )
                else -> assertEquals(
                    AppVisibilitySnapshotDecodeResult.Corrupt,
                    result,
                )
            }
        }

        val roundTrip = AppVisibilitySnapshotV1(
            revision = 9L,
            lifecycleGeneration = 4L,
            lifecycle = AppVisibilityLifecycle.FOREGROUND_ACTIVE,
            visibleConversationDigest = digestVectors.getJSONObject(0).getString("digest"),
            updatedMonotonicMs = 44L,
            bootSession = "android:42",
        )
        val encoded = AppVisibilitySnapshotCodec.encode(roundTrip)
        assertEquals(roundTrip, decodeSupported(encoded))
        for (invalidBoot in listOf(" android:42", "android:42 ", "android:42\u0085")) {
            val invalidBootJson = String(encoded, StandardCharsets.UTF_8).replace(
                "\"bootSession\":\"android:42\"",
                "\"bootSession\":${JSONObject.quote(invalidBoot)}",
            )
            assertEquals(
                AppVisibilitySnapshotDecodeResult.Corrupt,
                AppVisibilitySnapshotCodec.decode(
                    invalidBootJson.toByteArray(StandardCharsets.UTF_8),
                ),
            )
        }
        val malformedUtf8 = encoded.copyOf().also { bytes ->
            bytes[bytes.lastIndex - 1] = 0xc3.toByte()
        }
        assertEquals(
            AppVisibilitySnapshotDecodeResult.Corrupt,
            AppVisibilitySnapshotCodec.decode(malformedUtf8),
        )
        assertEquals(
            setOf(
                "schemaVersion",
                "revision",
                "lifecycleGeneration",
                "lifecycle",
                "visibleConversationDigest",
                "updatedMonotonicMs",
                "bootSession",
            ),
            roundTrip.toChannelMap().keys,
        )
    }

    @Test
    fun `AtomicFile faults retain one complete record and make this process ineligible`() {
        val seed = AppVisibilitySnapshotV1(
            revision = 10L,
            lifecycleGeneration = 5L,
            lifecycle = AppVisibilityLifecycle.FOREGROUND_ACTIVE,
            visibleConversationDigest = fixture.getJSONArray("digestVectors")
                .getJSONObject(0).getString("digest"),
            updatedMonotonicMs = 500L,
            bootSession = "android:42",
        )
        val expectedNew = seed.copy(
            revision = 11L,
            lifecycleGeneration = 6L,
            lifecycle = AppVisibilityLifecycle.INACTIVE,
            visibleConversationDigest = null,
            updatedMonotonicMs = 600L,
        )

        for (stage in FaultStage.entries) {
            deleteAtomicRecord()
            AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
            AndroidAppVisibilityAtomicBackend(recordFile).replace(
                AppVisibilitySnapshotCodec.encode(seed),
            )
            val faults = StagedFaultInjector(stage)
            val backend = AndroidAppVisibilityAtomicBackend(recordFile, faults)
            val store = newStore(
                nowMs = 600L,
                faults = faults,
                backend = backend,
            )

            val result = store.transitionLifecycle(AppVisibilityLifecycle.INACTIVE)

            assertFalse(stage.name, result.committed)
            assertNull(stage.name, store.readSnapshot())
            val durable = decodeSupported(
                AndroidAppVisibilityAtomicBackend(recordFile).readFully(),
            )
            assertTrue(
                "${stage.name} must leave exactly the old or new record",
                durable == seed || durable == expectedNew,
            )
            if (stage == FaultStage.READBACK) {
                assertEquals(expectedNew, durable)
            } else {
                assertEquals(seed, durable)
            }
            if (stage == FaultStage.WRITE) {
                val recovered = newStore(nowMs = 601L).transitionLifecycle(
                    AppVisibilityLifecycle.FOREGROUND_ACTIVE,
                )
                assertTrue(recovered.committed)
                assertEquals(11L, recovered.snapshot?.revision)
                assertEquals(6L, recovered.snapshot?.lifecycleGeneration)
                assertNull(recovered.snapshot?.visibleConversationDigest)
            }
        }

        deleteAtomicRecord()
        AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
        val rawBackend = AndroidAppVisibilityAtomicBackend(recordFile)
        rawBackend.replace(AppVisibilitySnapshotCodec.encode(seed))
        val mismatchingBackend = MismatchingReadbackBackend(
            delegate = rawBackend,
            staleReadback = AppVisibilitySnapshotCodec.encode(seed),
        )
        val store = newStore(nowMs = 600L, backend = mismatchingBackend)
        val mismatch = store.transitionLifecycle(AppVisibilityLifecycle.INACTIVE)
        assertFalse(mismatch.committed)
        assertNull(store.readSnapshot())
        assertEquals(expectedNew, decodeSupported(rawBackend.readFully()))
    }

    @Test
    fun `lifecycle generations coalesce duplicates reject stale routes and preserve immutable bytes`() {
        val now = longArrayOf(100L)
        val store = newStore(nowProvider = { now[0] })

        val launch = store.transitionLifecycle(
            AppVisibilityLifecycle.INACTIVE,
            force = true,
        )
        assertTrue(launch.committed)
        assertEquals(1L, launch.snapshot?.revision)
        assertEquals(1L, launch.snapshot?.lifecycleGeneration)

        now[0] = 101L
        val active = store.transitionLifecycle(AppVisibilityLifecycle.FOREGROUND_ACTIVE)
        assertTrue(active.committed)
        assertEquals(2L, active.snapshot?.revision)
        assertEquals(2L, active.snapshot?.lifecycleGeneration)
        val activeGeneration = checkNotNull(active.snapshot).lifecycleGeneration
        val digest = fixture.getJSONArray("digestVectors")
            .getJSONObject(0).getString("digest")

        now[0] = 102L
        val route = store.publishVisibleConversation(digest, activeGeneration)
        assertTrue(route.committed)
        assertEquals(3L, route.snapshot?.revision)
        assertEquals(activeGeneration, route.snapshot?.lifecycleGeneration)

        now[0] = 103L
        val duplicateResume = store.transitionLifecycle(
            AppVisibilityLifecycle.FOREGROUND_ACTIVE,
        )
        assertTrue(duplicateResume.committed)
        assertEquals(route.snapshot, duplicateResume.snapshot)

        now[0] = 104L
        val paused = store.transitionLifecycle(AppVisibilityLifecycle.INACTIVE)
        assertTrue(paused.committed)
        assertEquals(4L, paused.snapshot?.revision)
        assertEquals(3L, paused.snapshot?.lifecycleGeneration)
        assertNull(paused.snapshot?.visibleConversationDigest)
        val pausedBytes = AndroidAppVisibilityAtomicBackend(recordFile).readFully()

        now[0] = 105L
        val staleRoute = store.publishVisibleConversation(digest, activeGeneration)
        assertFalse(staleRoute.committed)
        assertArrayEquals(
            pausedBytes,
            AndroidAppVisibilityAtomicBackend(recordFile).readFully(),
        )

        now[0] = 106L
        val stopped = store.transitionLifecycle(AppVisibilityLifecycle.BACKGROUND)
        assertTrue(stopped.committed)
        assertEquals(5L, stopped.snapshot?.revision)
        assertEquals(4L, stopped.snapshot?.lifecycleGeneration)

        val invalidSnapshots = fixture.getJSONArray("invalidSnapshotVectors")
        for (immutableName in listOf("future_schema", "revision_overflow")) {
            assertTrue(
                (0 until invalidSnapshots.length())
                    .map(invalidSnapshots::getJSONObject)
                    .any { it.getString("name") == immutableName },
            )
            val raw = rawInvalidSnapshot(immutableName)
                .toByteArray(StandardCharsets.UTF_8)
            AndroidAppVisibilityAtomicBackend(recordFile).replace(raw)
            AppVisibilitySnapshotStore.resetProcessEligibilityForTests()

            val rejected = newStore(nowMs = 200L).transitionLifecycle(
                AppVisibilityLifecycle.FOREGROUND_ACTIVE,
            )

            assertFalse(immutableName, rejected.committed)
            assertArrayEquals(
                immutableName,
                raw,
                AndroidAppVisibilityAtomicBackend(recordFile).readFully(),
            )
        }

        AndroidAppVisibilityAtomicBackend(recordFile).replace(
            "{truncated".toByteArray(StandardCharsets.UTF_8),
        )
        AppVisibilitySnapshotStore.resetProcessEligibilityForTests()
        val reset = newStore(nowMs = 300L).transitionLifecycle(
            AppVisibilityLifecycle.INACTIVE,
        )
        assertTrue(reset.committed)
        assertEquals(1L, reset.snapshot?.revision)
        assertEquals(1L, reset.snapshot?.lifecycleGeneration)
    }

    private fun newStore(
        nowMs: Long = 100L,
        nowProvider: (() -> Long)? = null,
        faults: AppVisibilitySnapshotFaultInjector = NoAppVisibilitySnapshotFaults,
        backend: AppVisibilityAtomicBackend = AndroidAppVisibilityAtomicBackend(
            recordFile,
            faults,
        ),
    ): AppVisibilitySnapshotStore = AppVisibilitySnapshotStore(
        context = context,
        monotonicClock = AppVisibilityMonotonicClock {
            nowProvider?.invoke() ?: nowMs
        },
        bootSessionProvider = AppVisibilityBootSessionProvider { "android:42" },
        faults = faults,
        backend = backend,
    )

    private fun decodeSupported(json: JSONObject): AppVisibilitySnapshotV1 =
        decodeSupported(json.toString().toByteArray(StandardCharsets.UTF_8))

    private fun decodeSupported(bytes: ByteArray): AppVisibilitySnapshotV1 =
        (AppVisibilitySnapshotCodec.decode(bytes) as
            AppVisibilitySnapshotDecodeResult.Supported).snapshot

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else getString(key)

    private fun rawInvalidSnapshot(name: String): String {
        val nameAnchor = "\"name\": \"$name\""
        val nameIndex = fixtureText.indexOf(nameAnchor)
        check(nameIndex >= 0) { "Missing invalid fixture vector $name" }
        val snapshotKey = fixtureText.indexOf("\"snapshot\"", nameIndex)
        val objectStart = fixtureText.indexOf('{', snapshotKey)
        check(snapshotKey >= 0 && objectStart >= 0)
        var depth = 0
        var inString = false
        var escaped = false
        for (index in objectStart until fixtureText.length) {
            val character = fixtureText[index]
            if (inString) {
                when {
                    escaped -> escaped = false
                    character == '\\' -> escaped = true
                    character == '"' -> inString = false
                }
                continue
            }
            when (character) {
                '"' -> inString = true
                '{' -> depth += 1
                '}' -> {
                    depth -= 1
                    if (depth == 0) return fixtureText.substring(objectStart, index + 1)
                }
            }
        }
        error("Unterminated snapshot for invalid fixture vector $name")
    }

    private fun ByteArray.toHex(): String = joinToString("") { byte ->
        "%02x".format(byte)
    }

    private fun deleteAtomicRecord() {
        listOf(recordFile, File(recordFile.path + ".bak"), File(recordFile.path + ".new"))
            .forEach { it.delete() }
    }

    private enum class FaultStage {
        WRITE,
        SYNC,
        PROMOTION,
        READBACK,
    }

    private class StagedFaultInjector(
        private val stage: FaultStage,
    ) : AppVisibilitySnapshotFaultInjector {
        override fun beforeWrite() = failAt(FaultStage.WRITE)

        override fun beforeSync() = failAt(FaultStage.SYNC)

        override fun beforePromotion() = failAt(FaultStage.PROMOTION)

        override fun beforeReadback() = failAt(FaultStage.READBACK)

        private fun failAt(candidate: FaultStage) {
            if (stage == candidate) throw IOException("injected ${stage.name}")
        }
    }

    private class MismatchingReadbackBackend(
        private val delegate: AppVisibilityAtomicBackend,
        private val staleReadback: ByteArray,
    ) : AppVisibilityAtomicBackend {
        private var mismatchArmed = false

        override val exists: Boolean
            get() = delegate.exists

        override fun readFully(): ByteArray {
            if (mismatchArmed) {
                mismatchArmed = false
                return staleReadback
            }
            return delegate.readFully()
        }

        override fun replace(bytes: ByteArray) {
            delegate.replace(bytes)
            mismatchArmed = true
        }
    }
}
