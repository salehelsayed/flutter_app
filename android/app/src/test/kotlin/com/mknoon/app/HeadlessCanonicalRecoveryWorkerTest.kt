package com.mknoon.app

import androidx.work.Data
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HeadlessCanonicalRecoveryWorkerTest {
    @Test
    fun `exact current generation succeeds only after close release and final resnapshot`() =
        runBlocking {
            val authority = FakeHeadlessRecoveryAuthority()
            val runner = FakeHeadlessRecoveryRunner { snapshot ->
                assertEquals(7L, snapshot.pendingRecovery?.generation)
                authority.pending = null // Dart compare-and-acknowledged generation 7.
                successfulCompletion()
            }
            val execution = execution(authority, runner)

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.SUCCESS,
                execution.execute(deletedWake(generation = 3L)),
            )
            assertEquals(1, runner.runCalls)
            assertEquals(1, runner.finishCalls)
            assertEquals(0, runner.stopCalls)
        }

    @Test
    fun `newer generation surviving stale completion retries instead of reporting success`() =
        runBlocking {
            val authority = FakeHeadlessRecoveryAuthority()
            val runner = FakeHeadlessRecoveryRunner {
                authority.pending = DroppedPushRecoveryStore.PendingRecovery(
                    generation = 8L,
                    binding = TEST_BINDING,
                )
                successfulCompletion()
            }

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.RETRY,
                execution(authority, runner).execute(deletedWake(generation = 7L)),
            )
            assertEquals(1, runner.finishCalls)
        }

    @Test
    fun `periodic success retries when a marker arrives and never consumes it`() =
        runBlocking {
            val authority = FakeHeadlessRecoveryAuthority(pending = null)
            val runner = FakeHeadlessRecoveryRunner { snapshot ->
                assertEquals(null, snapshot.pendingRecovery)
                authority.pending = DroppedPushRecoveryStore.PendingRecovery(
                    generation = 9L,
                    binding = TEST_BINDING,
                )
                successfulCompletion()
            }

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.RETRY,
                execution(authority, runner).execute(periodicWake()),
            )
            assertEquals(9L, authority.pending?.generation)
            assertEquals(1, runner.finishCalls)
        }

    @Test
    fun `success without database close or lease release is retry`() = runBlocking {
        listOf(
            successfulCompletion().copy(databaseClosed = false),
            successfulCompletion().copy(leaseReleased = false),
        ).forEach { unsafeCompletion ->
            val authority = FakeHeadlessRecoveryAuthority()
            val runner = FakeHeadlessRecoveryRunner {
                authority.pending = null
                unsafeCompletion
            }

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.RETRY,
                execution(authority, runner).execute(deletedWake()),
            )
            assertEquals(1, runner.finishCalls)
        }
    }

    @Test
    fun `account cutover accepts only an explicitly stale safely released result`() =
        runBlocking {
            val authority = FakeHeadlessRecoveryAuthority()
            val runner = FakeHeadlessRecoveryRunner {
                authority.binding = "installation-b/account-b"
                authority.pending = null
                successfulCompletion().copy(
                    disposition = HeadlessCanonicalRecoveryDisposition.STALE,
                )
            }

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.SUCCESS,
                execution(authority, runner).execute(deletedWake()),
            )
            assertEquals(1, runner.finishCalls)
        }

    @Test
    fun `timeout signals cooperative stop and finally owns cleanup`() = runBlocking {
        val neverCompletes = CompletableDeferred<HeadlessCanonicalRecoveryCompletion>()
        val runner = FakeHeadlessRecoveryRunner { neverCompletes.await() }

        assertEquals(
            HeadlessCanonicalRecoveryWorkOutcome.RETRY,
            execution(
                authority = FakeHeadlessRecoveryAuthority(),
                runner = runner,
                timeoutMillis = 25L,
            ).execute(deletedWake()),
        )
        assertEquals(1, runner.stopCalls)
        assertEquals(1, runner.finishCalls)
    }

    @Test
    fun `stop only signals while execute finally performs cleanup`() = runBlocking {
        val entered = CompletableDeferred<Unit>()
        val cancelled = CompletableDeferred<Unit>()
        val runner = FakeHeadlessRecoveryRunner {
            entered.complete(Unit)
            cancelled.await()
            successfulCompletion()
        }.also { candidate ->
            candidate.onStop = { cancelled.complete(Unit) }
        }
        val execution = execution(FakeHeadlessRecoveryAuthority(), runner)

        val result = async { execution.execute(deletedWake()) }
        entered.await()
        execution.requestStop()

        assertEquals(0, runner.finishCalls)
        assertEquals(HeadlessCanonicalRecoveryWorkOutcome.RETRY, result.await())
        assertTrue(runner.stopCalls >= 1)
        assertEquals(1, runner.finishCalls)
    }

    @Test
    fun `engine exception and cleanup exception both remain retry`() = runBlocking {
        val runFailure = FakeHeadlessRecoveryRunner {
            throw IllegalStateException("engine failed")
        }
        assertEquals(
            HeadlessCanonicalRecoveryWorkOutcome.RETRY,
            execution(FakeHeadlessRecoveryAuthority(), runFailure).execute(deletedWake()),
        )
        assertEquals(1, runFailure.stopCalls)
        assertEquals(1, runFailure.finishCalls)

        val cleanupFailure = FakeHeadlessRecoveryRunner {
            successfulCompletion()
        }.also { it.finishFailure = IllegalStateException("cleanup failed") }
        assertEquals(
            HeadlessCanonicalRecoveryWorkOutcome.RETRY,
            execution(FakeHeadlessRecoveryAuthority(), cleanupFailure).execute(deletedWake()),
        )
        assertEquals(1, cleanupFailure.finishCalls)
    }

    @Test
    fun `disabled stale or malformed wake exits without constructing an engine`() =
        runBlocking {
            var factories = 0
            val authority = FakeHeadlessRecoveryAuthority(enabled = false)
            val execution = HeadlessCanonicalRecoveryExecution(
                authority = authority,
                runnerFactory = {
                    factories += 1
                    FakeHeadlessRecoveryRunner { successfulCompletion() }
                },
                isStopped = { false },
                timeoutMillis = 1_000L,
            )

            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.SUCCESS,
                execution.execute(deletedWake()),
            )
            authority.enabled = true
            assertEquals(
                HeadlessCanonicalRecoveryWorkOutcome.SUCCESS,
                execution.execute(
                    deletedWake(binding = "installation-stale/account-stale"),
                ),
            )
            assertEquals(0, factories)
        }

    @Test
    fun `completion protocol rejects forged and late run identities exactly once`() {
        val identity = HeadlessCanonicalRecoveryRunIdentity(
            nonce = "nonce-a",
            reason = DroppedPushRecoveryWorkScheduler.REASON_DELETED_BATCH,
            binding = TEST_BINDING,
            generation = 7L,
        )
        val valid = validCompletionPayload(identity)

        val gate = HeadlessCanonicalRecoveryCompletionGate(identity)
        assertEquals(
            HeadlessCanonicalRecoveryDisposition.SUCCEEDED,
            gate.accept(valid, "complete")?.disposition,
        )
        assertEquals(null, gate.accept(valid, "complete"))
        assertEquals(
            null,
            HeadlessCanonicalRecoveryCompletionGate(identity).accept(
                valid,
                "failed",
            ),
        )
        assertEquals(
            HeadlessCanonicalRecoveryDisposition.RETRY,
            HeadlessCanonicalRecoveryCompletionGate(identity).accept(
                valid + ("disposition" to "retry"),
                "failed",
            )?.disposition,
        )

        listOf(
            valid + ("nonce" to "nonce-from-prior-run"),
            valid + ("reason" to DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP),
            valid + ("binding" to "installation-b/account-b"),
            valid + ("generation" to 8L),
        ).forEach { forged ->
            val forgedGate = HeadlessCanonicalRecoveryCompletionGate(identity)
            assertEquals(null, forgedGate.accept(forged, "complete"))
            assertTrue(forgedGate.accept(valid, "complete") != null)
        }

        val periodicIdentity = identity.copy(
            reason = DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP,
            generation = null,
        )
        assertEquals(
            null,
            HeadlessCanonicalRecoveryCompletionGate(periodicIdentity).accept(
                validCompletionPayload(periodicIdentity) + ("generation" to "invalid"),
                "complete",
            ),
        )
    }

    @Test
    fun `Dart close release flags cannot destroy while either native owner is active`() {
        val safeReport = successfulCompletion()

        assertFalse(
            HeadlessCanonicalRecoveryDestructionPolicy.mayDestroy(
                safeReport,
                nativeLeaseReleased = false,
                nativeGoReleased = true,
            ),
        )
        assertFalse(
            HeadlessCanonicalRecoveryDestructionPolicy.mayDestroy(
                safeReport,
                nativeLeaseReleased = true,
                nativeGoReleased = false,
            ),
        )
        assertFalse(
            HeadlessCanonicalRecoveryDestructionPolicy.mayDestroy(
                safeReport.copy(databaseClosed = false),
                nativeLeaseReleased = true,
                nativeGoReleased = true,
            ),
        )
        assertTrue(
            HeadlessCanonicalRecoveryDestructionPolicy.mayDestroy(
                safeReport,
                nativeLeaseReleased = true,
                nativeGoReleased = true,
            ),
        )
    }

    @Test
    fun `worker source keeps engine lifecycle on main with explicit plugin allowlist`() {
        val source = sourceFile("HeadlessCanonicalRecoveryWorker.kt").readText()
        val onStoppedStart = source.indexOf("override fun onStopped()")
        val onStoppedEnd = source.indexOf("\n    }", onStoppedStart)
        val onStopped = source.substring(onStoppedStart, onStoppedEnd)

        assertTrue(source.contains("withContext(Dispatchers.Main.immediate)"))
        assertTrue(source.contains("engine?.destroy()"))
        assertTrue(source.contains("registerAllowlistedPlugins(created)"))
        assertTrue(source.contains("UUID.randomUUID().toString()"))
        assertTrue(source.contains("HeadlessCanonicalRecoveryCompletionGate(identity)"))
        assertTrue(source.contains("nativeLeaseReleased ="))
        assertTrue(source.contains("nativeGoReleased ="))
        assertTrue(source.contains("FlutterSecureStoragePlugin()"))
        assertTrue(source.contains("SqfliteSqlCipherPlugin()"))
        assertTrue(source.contains("FlutterLocalNotificationsPlugin()"))
        assertTrue(source.contains("FlutterFirebaseCorePlugin()"))
        assertTrue(source.contains("FlutterFirebaseMessagingPlugin()"))
        assertFalse(source.contains("GeneratedPluginRegistrant"))
        assertTrue(onStopped.contains("execution.requestStop()"))
        assertFalse(onStopped.contains("destroy"))
        assertFalse(onStopped.contains("dispose"))
    }

    private fun execution(
        authority: FakeHeadlessRecoveryAuthority,
        runner: FakeHeadlessRecoveryRunner,
        timeoutMillis: Long = 1_000L,
    ): HeadlessCanonicalRecoveryExecution = HeadlessCanonicalRecoveryExecution(
        authority = authority,
        runnerFactory = { runner },
        isStopped = { false },
        timeoutMillis = timeoutMillis,
    )

    private fun deletedWake(
        generation: Long = 7L,
        binding: String = TEST_BINDING,
    ): Data = Data.Builder()
        .putString(
            DroppedPushRecoveryWorkScheduler.INPUT_REASON,
            DroppedPushRecoveryWorkScheduler.REASON_DELETED_BATCH,
        )
        .putLong(DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION, generation)
        .putString(
            DroppedPushRecoveryWorkScheduler.INPUT_BINDING_DIGEST,
            DroppedPushRecoveryWorkScheduler.bindingDigest(binding),
        )
        .build()

    private fun periodicWake(binding: String = TEST_BINDING): Data =
        Data.Builder()
            .putString(
                DroppedPushRecoveryWorkScheduler.INPUT_REASON,
                DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP,
            )
            .putString(
                DroppedPushRecoveryWorkScheduler.INPUT_BINDING_DIGEST,
                DroppedPushRecoveryWorkScheduler.bindingDigest(binding),
            )
            .build()

    private fun validCompletionPayload(
        identity: HeadlessCanonicalRecoveryRunIdentity,
    ): Map<String, Any?> = mapOf(
        "nonce" to identity.nonce,
        "reason" to identity.reason,
        "binding" to identity.binding,
        "generation" to identity.generation,
        "disposition" to "succeeded",
        "databaseClosed" to true,
        "leaseReleased" to true,
    )

    private fun successfulCompletion() = HeadlessCanonicalRecoveryCompletion(
        disposition = HeadlessCanonicalRecoveryDisposition.SUCCEEDED,
        databaseClosed = true,
        leaseReleased = true,
    )

    private fun sourceFile(name: String): File = sequenceOf(
        File("src/main/kotlin/com/mknoon/app/$name"),
        File("android/app/src/main/kotlin/com/mknoon/app/$name"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $name")

    private companion object {
        const val TEST_BINDING = "installation-a/account-a"
    }
}

private class FakeHeadlessRecoveryAuthority(
    var enabled: Boolean = true,
    var binding: String? = "installation-a/account-a",
    var pending: DroppedPushRecoveryStore.PendingRecovery? =
        DroppedPushRecoveryStore.PendingRecovery(
            generation = 7L,
            binding = "installation-a/account-a",
        ),
) : HeadlessCanonicalRecoveryAuthority {
    override fun recoveryWorkEnabled(): Boolean = enabled

    override fun currentBinding(): String? = binding

    override fun pendingRecovery(): DroppedPushRecoveryStore.PendingRecovery? = pending
}

private class FakeHeadlessRecoveryRunner(
    private val onRun: suspend (
        HeadlessCanonicalRecoveryStartSnapshot,
    ) -> HeadlessCanonicalRecoveryCompletion,
) : HeadlessCanonicalRecoveryEngineRunner {
    var runCalls = 0
    var stopCalls = 0
    var finishCalls = 0
    var finishFailure: Throwable? = null
    var onStop: () -> Unit = {}

    override suspend fun run(
        snapshot: HeadlessCanonicalRecoveryStartSnapshot,
    ): HeadlessCanonicalRecoveryCompletion {
        runCalls += 1
        return onRun(snapshot)
    }

    override fun requestStop() {
        stopCalls += 1
        onStop()
    }

    override suspend fun finish() {
        finishCalls += 1
        finishFailure?.let { throw it }
    }
}
