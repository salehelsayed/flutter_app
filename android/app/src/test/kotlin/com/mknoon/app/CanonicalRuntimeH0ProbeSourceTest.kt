package com.mknoon.app

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CanonicalRuntimeH0ProbeSourceTest {
    @Test
    fun `debug receiver is no Activity and uses an explicit minimal plugin allowlist`() {
        val manifest = repoFile("android/app/src/debug/AndroidManifest.xml").readText()
        val receiver = repoFile(
            "android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt",
        ).readText()

        assertTrue(manifest.contains(".CanonicalRuntimeH0ProbeReceiver"))
        assertTrue(manifest.contains("android.permission.DUMP"))
        assertTrue(receiver.contains("FlutterEngine(applicationContext, null, false)"))
        assertFalse(receiver.contains("GeneratedPluginRegistrant"))
        assertTrue(receiver.contains("FlutterSecureStoragePlugin()"))
        assertTrue(receiver.contains("SqfliteSqlCipherPlugin()"))
        assertTrue(receiver.contains("FlutterLocalNotificationsPlugin()"))
        assertTrue(receiver.contains("FlutterFirebaseCorePlugin()"))
        assertTrue(receiver.contains("FlutterFirebaseMessagingPlugin()"))
        assertFalse(receiver.contains("MainActivity("))
        assertTrue(receiver.contains("runContender("))
        assertTrue(receiver.contains("admitH0ProbeJniHold("))
        assertTrue(receiver.contains("maxObservedWritableDatabaseHandles"))
        assertTrue(receiver.contains("closeFailureRetentionPassed"))
        assertTrue(receiver.contains("runFlutterFireReadOnlyPeer("))
        assertTrue(receiver.contains("registeredWritableLeaseBridge\", false"))
        assertTrue(receiver.contains("registeredGoBridge\", false"))
    }

    @Test
    fun `Dart entrypoint opens only through lease and cannot drain or acknowledge recovery`() {
        val main = repoFile("lib/main.dart").readText()
        val probe = repoFile(
            "lib/core/debug/android_canonical_runtime_h0_probe.dart",
        ).readText()

        assertTrue(main.contains("@pragma('vm:entry-point')"))
        assertTrue(main.contains("androidCanonicalRuntimeH0ProbeMain"))
        assertTrue(probe.contains("CanonicalWritableRuntimeSession"))
        assertTrue(probe.contains("openEncryptedDatabase("))
        assertFalse(probe.contains("acknowledgeGeneration"))
        assertFalse(probe.contains("drainDirectInbox"))
        assertFalse(probe.contains("drainGroupInbox"))
        assertFalse(probe.contains("ApplicationRoot"))
        assertFalse(probe.contains("runApp("))
        assertFalse(probe.contains("runApplicationBootstrap("))
        assertTrue(probe.contains("readyForActiveContention"))
        assertTrue(probe.contains("readyForCloseFailureContention"))
        assertTrue(probe.contains("database.close.injected_failure"))
        assertTrue(probe.contains("openEncryptedDatabaseReadOnlyTolerant("))
        assertTrue(probe.contains("readOnlyDatabaseOpened"))
    }

    @Test
    fun `queue inversion receiver fixes the causal order and preserves RED before cleanup`() {
        val receiver = repoFile(
            "android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt",
        ).readText()
        val dartProbe = repoFile(
            "lib/core/debug/android_canonical_runtime_h0_probe.dart",
        ).readText()

        assertTrue(receiver.contains("EXTRA_QUEUE_INVERSION = \"queueInversion\""))
        assertTrue(receiver.contains("EXTRA_RUN_NONCE = \"runNonce\""))
        assertTrue(receiver.contains("QUEUE_INVERSION_WATCHDOG_MS = 4_000L"))
        assertTrue(receiver.contains("QUEUE_INVERSION_HARD_TIMEOUT_MS = 8_000L"))
        assertTrue(receiver.contains("class QueueInversionRunner"))
        assertTrue(receiver.contains("queue-inversion-writer"))
        assertTrue(receiver.contains("queue-inversion-reader"))
        assertTrue(receiver.contains("queue-inversion-sentinel"))
        assertTrue(receiver.contains("queueWriterDatabaseOpened"))
        assertTrue(receiver.contains("queueReaderReady"))
        assertTrue(receiver.contains("queueReaderDatabaseOpened"))
        assertTrue(receiver.contains("queueWriterBeginExclusive"))
        assertTrue(receiver.contains("queueReaderQueryPosted"))
        assertTrue(receiver.contains("pendingWriterBegin?.success(null)"))
        assertTrue(receiver.contains("\"writer.database_opened\""))
        assertTrue(receiver.contains("\"reader.database_opened\""))
        assertTrue(receiver.contains("\"writer.begin_exclusive\""))
        assertTrue(receiver.contains("\"reader.query_posted\""))
        assertTrue(receiver.contains("\"writer.resume_requested\""))
        assertTrue(receiver.contains("status = if (acceptedUpstreamInversion) \"EXPECTED_RED\""))
        assertTrue(receiver.contains("!writerCommit &&"))
        assertTrue(receiver.contains("!readerQueryResult"))
        assertTrue(dartProbe.contains("PRAGMA cipher_version"))
        assertTrue(dartProbe.contains("PRAGMA journal_mode = DELETE"))
        assertTrue(dartProbe.contains("'cipherVersion': _firstPragmaValue(cipherRows)"))
        assertTrue(dartProbe.contains("'journalMode': _firstPragmaValue(journalRows)"))
        assertTrue(receiver.contains("writerCipherVersion = payloadText(payload, \"cipherVersion\")"))
        assertTrue(receiver.contains("readerCipherVersion = payloadText(payload, \"cipherVersion\")"))
        assertTrue(receiver.contains("writerJournalMode = payloadText(payload, \"journalMode\")"))
        assertTrue(receiver.contains("writerCipher == readerCipher"))
        assertTrue(receiver.contains("writerJournalMode.equals(\"delete\", ignoreCase = true)"))
        assertTrue(receiver.contains("exactUpstreamInversion && sqlCipherRuntimeIdentityVerified()"))
        assertTrue(
            Regex("""workerCensusSettled\s*&&\s*sqlCipherRuntimeIdentityVerified\(\)""")
                .containsMatchIn(receiver),
        )
        assertTrue(receiver.contains(".put(\"writerCipherVersion\", writerCipherVersion"))
        assertTrue(receiver.contains(".put(\"readerCipherVersion\", readerCipherVersion"))
        assertTrue(receiver.contains(".put(\"writerJournalMode\", writerJournalMode"))
        assertTrue(receiver.contains(".put(\"sqlCipherRuntimeIdentityVerified\""))
        assertTrue(receiver.contains("\"PASS\" -> if (passed) \"PASS\" else \"FAIL\""))
        assertTrue(
            receiver.contains(
                "\"EXPECTED_RED\" -> if (expectedRedValid) \"EXPECTED_RED\" else \"FAIL\"",
            ),
        )
        assertTrue(receiver.contains(".put(\"status\", terminalStatus)"))
        assertTrue(receiver.contains("queueSentinelVerified"))
        assertTrue(receiver.contains("destroyWriterAndReader()"))
        assertTrue(receiver.contains("liveEngineCount == 0"))
        assertTrue(receiver.contains(".put(\"enginesDestroyed\", enginesDestroyed)"))
        assertTrue(receiver.contains("getMethod(\"getDebugCensus\")"))
        assertFalse(receiver.contains("SqfliteSqlCipherPlugin.getDebugCensus()"))
        assertTrue(receiver.contains("finishGreenWhenWorkerCensusSettles()"))
        assertTrue(receiver.contains("censusValue(\"liveHandles\") == 0"))
        assertTrue(receiver.contains("censusValue(\"queuedTasks\") == 0"))
        assertTrue(receiver.contains("censusValue(\"runningTasks\") == 0"))
        assertTrue(receiver.contains("censusValue(\"terminatedInstances\") >= 3"))
        assertTrue(receiver.contains(".put(\"pluginWorkerCensusSettled\", workerCensusSettled)"))
        assertTrue(receiver.contains(".put(\"peakLiveEngineCount\", peakLiveEngineCount)"))
        assertTrue(receiver.contains(".put(\"peakLivePluginWorkerCount\", peakLivePluginWorkerCount)"))
        assertTrue(receiver.contains(".put(\"peakLivePluginHandleCount\", peakLivePluginHandleCount)"))
        assertTrue(receiver.contains(".put(\"orderedLifecycleTransitions\", orderedLifecycleTransitions())"))
        assertTrue(receiver.contains(".put(\"applicationRootConstructed\", false)"))
        assertTrue(receiver.contains(".put(\"applicationRootConstructionCount\", 0)"))
        assertTrue(receiver.contains(".put(\"runNonce\", runNonce)"))
        assertTrue(receiver.contains(".put(\"phases\", orderedPhases)"))
        assertTrue(receiver.contains("finish(artifact, passed || expectedRedValid)"))
    }

    @Test
    fun `queue artifact timeout literals stay bound to Dart production constants`() {
        val receiver = repoFile(
            "android/app/src/debug/kotlin/com/mknoon/app/CanonicalRuntimeH0ProbeReceiver.kt",
        ).readText()
        val backgroundHandler = repoFile(
            "lib/features/push/application/background_message_handler.dart",
        ).readText()
        val encryptedOpener = repoFile(
            "lib/core/database/encrypted_db_opener.dart",
        ).readText()
        val boundedFlock = repoFile(
            "lib/core/notifications/bounded_posix_flock.dart",
        ).readText()
        val livenessJournal = repoFile(
            "lib/features/push/application/background_storage_liveness_journal.dart",
        ).readText()

        assertEquals(
            dartDurationMilliseconds(
                backgroundHandler,
                "_productionBackgroundStorageAggregateDeadline",
            ),
            artifactInteger(receiver, "storageAggregateDeadlineMs"),
        )
        assertEquals(
            dartDurationMilliseconds(
                backgroundHandler,
                "_productionBackgroundStoragePhaseDeadline",
            ),
            artifactInteger(receiver, "storagePhaseDeadlineMs"),
        )
        assertEquals(
            dartDurationMilliseconds(encryptedOpener, "encryptedReadOnlyOpenDeadline"),
            artifactInteger(receiver, "encryptedReadOnlyOpenDeadlineMs"),
        )
        assertEquals(
            dartInteger(encryptedOpener, "encryptedReadOnlyBusyTimeoutMilliseconds"),
            artifactInteger(receiver, "encryptedReadOnlyBusyTimeoutMs"),
        )
        assertEquals(
            dartDurationMilliseconds(boundedFlock, "acquisitionTimeout"),
            artifactInteger(receiver, "androidFlockAcquisitionMs"),
        )
        assertEquals(
            dartDurationMilliseconds(
                livenessJournal,
                "backgroundStorageLivenessJournalMaxCallerImpact",
            ),
            artifactInteger(receiver, "journalMaxCallerImpactMs"),
        )
    }

    @Test
    fun `ADB script pins a device and supports handoff and process death`() {
        val script = repoFile(
            "scripts/run_android_canonical_runtime_h0_probe.sh",
        ).readText()

        assertTrue(script.contains("device-id"))
        assertTrue(script.contains("--handoff"))
        assertTrue(script.contains("--process-death"))
        assertTrue(script.contains("--sqlcipher-queue-inversion"))
        assertTrue(script.contains("--expect-red"))
        assertTrue(script.contains("queue-inversion-{nonce}.json"))
        assertTrue(script.contains("runtime.get(\"elapsedMs\") <= 8000"))
        assertTrue(script.contains("runtime.get(\"storageAggregateDeadlineMs\") == 8000"))
        assertTrue(script.contains("runtime.get(\"encryptedReadOnlyOpenDeadlineMs\") == 2000"))
        assertTrue(script.contains("runtime.get(\"encryptedReadOnlyBusyTimeoutMs\") == 1000"))
        assertTrue(script.contains("runtime.get(\"sqlCipherRuntimeIdentityVerified\") is True"))
        assertTrue(script.contains("runtime.get(\"peakLivePluginWorkerCount\", 0) >= 2"))
        assertTrue(script.contains("runtime.get(\"applicationRootConstructionCount\") == 0"))
        assertTrue(script.contains("runtime.get(\"pluginWorkerCensusSettled\") is True"))
        assertTrue(script.contains("census.get(\"liveHandles\") == 0"))
        assertTrue(script.contains("census.get(\"terminatedInstances\") >= 3"))
        assertTrue(script.contains("prewarm_canonical_database"))
        assertTrue(
            script.contains(
                "queue_inversion_then_canonical_phase_pass_process_killed",
            ),
        )
        assertTrue(script.contains("set(lifecycle_closes) =="))
        assertTrue(script.contains("adb -s"))
        assertTrue(script.contains("activeContentionPassed"))
        assertTrue(script.contains("closeFailureRetentionPassed"))
        assertTrue(script.contains("maxObservedWritableDatabaseHandles"))
        assertTrue(script.contains("dumpsys activity activities"))
        assertTrue(script.contains("adbActivityRecordCount"))
        assertTrue(script.contains("flutterFireReadOnlyPeerPassed"))
        assertTrue(script.contains("uninstall \"\$APP_ID\""))
        assertFalse(script.contains("force-stop"))
    }

    private fun repoFile(relativePath: String): File = sequenceOf(
        File(relativePath),
        File("../$relativePath"),
        File("../../$relativePath"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $relativePath")

    private fun dartDurationMilliseconds(source: String, constantName: String): Int {
        val match = Regex(
            """(?:static\s+)?const\s+Duration\s+${Regex.escape(constantName)}\s*=\s*""" +
                """Duration\(\s*(seconds|milliseconds):\s*(\d+),?\s*\);""",
        ).find(source) ?: error("Cannot locate Dart Duration constant $constantName")
        val value = match.groupValues[2].toInt()
        return when (match.groupValues[1]) {
            "seconds" -> value * 1_000
            "milliseconds" -> value
            else -> error("Unsupported Dart Duration unit for $constantName")
        }
    }

    private fun dartInteger(source: String, constantName: String): Int {
        val match = Regex(
            """(?:static\s+)?const\s+int\s+${Regex.escape(constantName)}\s*=\s*(\d+)\s*;""",
        ).find(source) ?: error("Cannot locate Dart int constant $constantName")
        return match.groupValues[1].toInt()
    }

    private fun artifactInteger(receiver: String, fieldName: String): Int {
        val match = Regex(
            """\.put\("${Regex.escape(fieldName)}",\s*([\d_]+)\)""",
        ).find(receiver) ?: error("Cannot locate queue artifact field $fieldName")
        return match.groupValues[1].replace("_", "").toInt()
    }
}
