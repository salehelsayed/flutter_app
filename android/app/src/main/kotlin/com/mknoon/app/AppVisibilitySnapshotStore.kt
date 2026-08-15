package com.mknoon.app

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream

internal fun interface AppVisibilityMonotonicClock {
    fun nowMs(): Long?
}

internal fun interface AppVisibilityBootSessionProvider {
    fun currentBootSession(): String?
}

internal interface AppVisibilitySnapshotFaultInjector {
    fun beforeWrite() {}
    fun beforeSync() {}
    fun beforePromotion() {}
    fun beforeReadback() {}
}

internal object NoAppVisibilitySnapshotFaults : AppVisibilitySnapshotFaultInjector

internal interface AppVisibilityAtomicBackend {
    val exists: Boolean
    fun readFully(): ByteArray
    fun replace(bytes: ByteArray)
}

internal class AndroidAppVisibilityAtomicBackend(
    file: File,
    private val faults: AppVisibilitySnapshotFaultInjector = NoAppVisibilitySnapshotFaults,
) : AppVisibilityAtomicBackend {
    private val atomicFile = AtomicFile(file)

    override val exists: Boolean
        get() = atomicFile.baseFile.exists() || File(atomicFile.baseFile.path + ".bak").exists()

    override fun readFully(): ByteArray = atomicFile.readFully()

    override fun replace(bytes: ByteArray) {
        atomicFile.baseFile.parentFile?.let { directory ->
            check(directory.exists() || directory.mkdirs()) {
                "app visibility directory unavailable"
            }
        }
        var stream: FileOutputStream? = null
        try {
            stream = atomicFile.startWrite()
            faults.beforeWrite()
            stream.write(bytes)
            stream.flush()
            faults.beforeSync()
            stream.fd.sync()
            faults.beforePromotion()
            atomicFile.finishWrite(stream)
            stream = null
        } catch (error: Throwable) {
            stream?.let { active -> runCatching { atomicFile.failWrite(active) } }
            throw error
        }
    }
}

internal data class AppVisibilityReadEnvelope(
    val snapshot: AppVisibilitySnapshotV1,
    val currentMonotonicMs: Long,
    val currentBootSession: String,
) {
    fun toChannelMap(): Map<String, Any?> = linkedMapOf(
        "snapshot" to snapshot.toChannelMap(),
        "currentMonotonicMs" to currentMonotonicMs,
        "currentBootSession" to currentBootSession,
    )
}

internal data class AppVisibilityCommitEnvelope(
    val committed: Boolean,
    val snapshot: AppVisibilitySnapshotV1?,
    val currentMonotonicMs: Long,
    val currentBootSession: String,
) {
    fun toChannelMap(): Map<String, Any?> = linkedMapOf(
        "committed" to committed,
        "snapshot" to snapshot?.toChannelMap(),
        "currentMonotonicMs" to currentMonotonicMs,
        "currentBootSession" to currentBootSession,
    )
}

internal class AppVisibilitySnapshotStore(
    context: Context,
    private val monotonicClock: AppVisibilityMonotonicClock =
        AppVisibilityMonotonicClock { SystemClock.elapsedRealtime() },
    private val bootSessionProvider: AppVisibilityBootSessionProvider =
        AndroidBootSessionProvider(context.applicationContext),
    private val faults: AppVisibilitySnapshotFaultInjector = NoAppVisibilitySnapshotFaults,
    private val backend: AppVisibilityAtomicBackend = AndroidAppVisibilityAtomicBackend(
        File(context.applicationContext.filesDir, FILE_NAME),
        faults,
    ),
) {
    companion object {
        internal const val FILE_NAME = "app_visibility_snapshot_v1.json"
        private val processLock = Any()

        @Volatile
        private var currentProcessEligible = true

        internal fun resetProcessEligibilityForTests() {
            synchronized(processLock) {
                currentProcessEligible = true
            }
        }
    }

    fun readSnapshot(): AppVisibilityReadEnvelope? = synchronized(processLock) {
        if (!currentProcessEligible) return@synchronized null
        val now = validNow() ?: return@synchronized invalidateAndReturnNull()
        val boot = validBootSession() ?: return@synchronized invalidateAndReturnNull()
        val snapshot = when (val decoded = readDecoded()) {
            is AppVisibilitySnapshotDecodeResult.Supported -> decoded.snapshot
            AppVisibilitySnapshotDecodeResult.Corrupt,
            AppVisibilitySnapshotDecodeResult.FutureSchema,
            AppVisibilitySnapshotDecodeResult.UnsupportedBounds,
            null,
            -> return@synchronized null
        }
        AppVisibilityReadEnvelope(snapshot, now, boot)
    }

    fun publishVisibleConversation(
        visibleConversationDigest: String?,
        lifecycleGeneration: Long,
    ): AppVisibilityCommitEnvelope = synchronized(processLock) {
        val now = validNow()
        val boot = validBootSession()
        if (now == null || boot == null || lifecycleGeneration <= 0L) {
            currentProcessEligible = false
            return@synchronized failureEnvelope(now, boot)
        }
        if (
            visibleConversationDigest != null &&
            !Regex("^[0-9a-f]{64}$").matches(visibleConversationDigest)
        ) {
            currentProcessEligible = false
            return@synchronized failureEnvelope(now, boot)
        }
        val current = (readDecoded() as? AppVisibilitySnapshotDecodeResult.Supported)
            ?.snapshot
        if (
            current == null ||
            current.bootSession != boot ||
            current.lifecycle != AppVisibilityLifecycle.FOREGROUND_ACTIVE ||
            current.lifecycleGeneration != lifecycleGeneration ||
            current.revision == Long.MAX_VALUE
        ) {
            currentProcessEligible = false
            return@synchronized AppVisibilityCommitEnvelope(false, null, now, boot)
        }
        val expected = current.copy(
            revision = current.revision + 1L,
            visibleConversationDigest = visibleConversationDigest,
            updatedMonotonicMs = now,
        )
        commitExpected(expected, now, boot)
    }

    fun transitionLifecycle(
        lifecycle: AppVisibilityLifecycle,
        force: Boolean = false,
    ): AppVisibilityCommitEnvelope = synchronized(processLock) {
        val now = validNow()
        val boot = validBootSession()
        if (now == null || boot == null) {
            currentProcessEligible = false
            return@synchronized failureEnvelope(now, boot)
        }
        val decoded = readDecoded()
        if (
            decoded == AppVisibilitySnapshotDecodeResult.FutureSchema ||
            decoded == AppVisibilitySnapshotDecodeResult.UnsupportedBounds
        ) {
            currentProcessEligible = false
            return@synchronized AppVisibilityCommitEnvelope(false, null, now, boot)
        }
        val current = (decoded as? AppVisibilitySnapshotDecodeResult.Supported)?.snapshot
        if (
            !force &&
            currentProcessEligible &&
            current != null &&
            current.bootSession == boot &&
            current.lifecycle == lifecycle
        ) {
            currentProcessEligible = true
            return@synchronized AppVisibilityCommitEnvelope(true, current, now, boot)
        }
        if (
            current?.revision == Long.MAX_VALUE ||
            current?.lifecycleGeneration == Long.MAX_VALUE
        ) {
            currentProcessEligible = false
            return@synchronized AppVisibilityCommitEnvelope(false, null, now, boot)
        }
        val expected = AppVisibilitySnapshotV1(
            revision = (current?.revision ?: 0L) + 1L,
            lifecycleGeneration = (current?.lifecycleGeneration ?: 0L) + 1L,
            lifecycle = lifecycle,
            visibleConversationDigest = null,
            updatedMonotonicMs = now,
            bootSession = boot,
        )
        commitExpected(expected, now, boot)
    }

    private fun commitExpected(
        expected: AppVisibilitySnapshotV1,
        now: Long,
        boot: String,
    ): AppVisibilityCommitEnvelope {
        return try {
            backend.replace(AppVisibilitySnapshotCodec.encode(expected))
            faults.beforeReadback()
            val verified = when (val decoded = readDecoded()) {
                is AppVisibilitySnapshotDecodeResult.Supported -> decoded.snapshot
                else -> null
            }
            if (verified != expected) {
                currentProcessEligible = false
                AppVisibilityCommitEnvelope(false, null, now, boot)
            } else {
                currentProcessEligible = true
                AppVisibilityCommitEnvelope(true, verified, now, boot)
            }
        } catch (_: Throwable) {
            currentProcessEligible = false
            AppVisibilityCommitEnvelope(false, null, now, boot)
        }
    }

    private fun readDecoded(): AppVisibilitySnapshotDecodeResult? {
        if (!backend.exists) return null
        return try {
            AppVisibilitySnapshotCodec.decode(backend.readFully())
        } catch (_: Throwable) {
            currentProcessEligible = false
            null
        }
    }

    private fun validNow(): Long? = monotonicClock.nowMs()?.takeIf { it >= 0L }

    private fun validBootSession(): String? = bootSessionProvider.currentBootSession()
        ?.takeIf { ANDROID_BOOT_SESSION.matches(it) }

    private fun invalidateAndReturnNull(): AppVisibilityReadEnvelope? {
        currentProcessEligible = false
        return null
    }

    private fun failureEnvelope(
        now: Long?,
        boot: String?,
    ): AppVisibilityCommitEnvelope = AppVisibilityCommitEnvelope(
        committed = false,
        snapshot = null,
        currentMonotonicMs = now ?: 0L,
        currentBootSession = boot ?: "android:unavailable",
    )
}

private val ANDROID_BOOT_SESSION = Regex("^android:[0-9]+$")

internal class AndroidBootSessionProvider(context: Context) :
    AppVisibilityBootSessionProvider {
    private val resolver = context.contentResolver

    override fun currentBootSession(): String? = try {
        val count = Settings.Global.getInt(resolver, Settings.Global.BOOT_COUNT)
        if (count < 0) null else "android:$count"
    } catch (_: Throwable) {
        null
    }
}
