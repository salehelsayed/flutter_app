package com.mknoon.app.call

import android.app.Notification
import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import com.mknoon.app.MknoonFirebaseMessagingService
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class HeadlessCallAdmissionWorkerTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
    }

    @Test
    fun `completion protocol accepts one exact authenticated result identity`() {
        val identity = identity()
        val valid = validCompletion(identity)
        val gate = HeadlessCallAdmissionCompletionGate(identity)

        assertEquals(
            HeadlessCallAdmissionDisposition.ADMITTED,
            gate.accept("complete", valid)?.disposition,
        )
        assertEquals(null, gate.accept("complete", valid))

        val malformed = listOf(
            valid - "requiredPersistenceComplete",
            valid + ("extra" to true),
            valid + ("nonce" to "a-prior-run"),
            valid + ("callId" to OTHER_CALL_ID),
            valid + ("wakeHandle" to OTHER_WAKE_HANDLE),
            valid + ("expiresAtMs" to (EXPIRES_AT_MS + 1L)),
            valid + ("disposition" to "accepted"),
            valid + ("requiredPersistenceComplete" to 1),
            valid + ("databaseClosed" to "true"),
            valid + ("leaseReleased" to null),
        )
        malformed.forEach { payload ->
            assertEquals(
                null,
                HeadlessCallAdmissionCompletionGate(identity)
                    .accept("complete", payload),
            )
        }
        assertEquals(
            null,
            HeadlessCallAdmissionCompletionGate(identity).accept("failed", valid),
        )
    }

    @Test
    fun `engine destruction is fenced by this owner and not a warm foreign owner`() {
        val safe = validCompletionObject(identity())

        assertTrue(
            HeadlessCallAdmissionDestructionPolicy.mayDestroy(
                completion = safe,
                leaseOwnerId = "headless-lease",
                currentLeaseOwnerId = "foreground-lease",
                goOwnerId = "headless-go",
                currentGoOwnerId = "foreground-go",
            ),
        )
        assertFalse(
            HeadlessCallAdmissionDestructionPolicy.mayDestroy(
                completion = safe,
                leaseOwnerId = "headless-lease",
                currentLeaseOwnerId = "headless-lease",
                goOwnerId = "headless-go",
                currentGoOwnerId = null,
            ),
        )
        assertFalse(
            HeadlessCallAdmissionDestructionPolicy.mayDestroy(
                completion = safe,
                leaseOwnerId = "headless-lease",
                currentLeaseOwnerId = null,
                goOwnerId = "headless-go",
                currentGoOwnerId = "headless-go",
            ),
        )
        assertFalse(
            HeadlessCallAdmissionDestructionPolicy.mayDestroy(
                completion = safe.copy(databaseClosed = false),
                leaseOwnerId = "headless-lease",
                currentLeaseOwnerId = null,
                goOwnerId = "headless-go",
                currentGoOwnerId = null,
            ),
        )
    }

    @Test
    fun `admitted result presents exact call once and only after safe engine cleanup`() =
        runBlocking {
            val operations = mutableListOf<String>()
            val runner = FakeHeadlessCallAdmissionRunner { observed ->
                operations += "dart.complete"
                validCompletionObject(observed)
            }.also {
                it.onFinish = {
                    operations += "engine.finish"
                    true
                }
            }
            val presented = mutableListOf<Pair<String, Long>>()
            val execution = execution(
                runner = runner,
                nowMs = { NOW_MS },
                presentAuthenticated = { callId, expiresAtMs ->
                    operations += "native.presentAuthenticated"
                    presented += callId to expiresAtMs
                    true
                },
            )

            assertEquals(
                HeadlessCallAdmissionWorkOutcome.PRESENTED,
                execution.execute(validInput()),
            )
            assertEquals(listOf(CALL_ID to EXPIRES_AT_MS), presented)
            assertEquals(
                listOf(
                    "dart.complete",
                    "engine.finish",
                    "native.presentAuthenticated",
                ),
                operations,
            )
            assertEquals(1, runner.runCalls)
            assertEquals(1, runner.finishCalls)
            assertEquals(0, runner.stopCalls)
        }

    @Test
    fun `terminal empty deferred and every unsafe result fail closed without presentation`() =
        runBlocking {
            val completions = listOf(
                validCompletionObject(identity()).copy(
                    disposition = HeadlessCallAdmissionDisposition.PERMANENT_REJECT,
                ),
                validCompletionObject(identity()).copy(
                    disposition = HeadlessCallAdmissionDisposition.EMPTY_OR_ALREADY_ACKED,
                ),
                validCompletionObject(identity()).copy(
                    disposition = HeadlessCallAdmissionDisposition.DEFERRED,
                ),
                validCompletionObject(identity()).copy(requiredPersistenceComplete = false),
                validCompletionObject(identity()).copy(databaseClosed = false),
                validCompletionObject(identity()).copy(leaseReleased = false),
            )

            completions.forEach { completion ->
                var presentationCalls = 0
                val runner = FakeHeadlessCallAdmissionRunner { observed ->
                    completion.copy(
                        nonce = observed.nonce,
                        callId = observed.callId,
                        wakeHandle = observed.wakeHandle,
                        expiresAtMs = observed.expiresAtMs,
                    )
                }
                assertEquals(
                    HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                    execution(
                        runner = runner,
                        nowMs = { NOW_MS },
                        presentAuthenticated = { _, _ ->
                            presentationCalls += 1
                            true
                        },
                    ).execute(validInput()),
                )
                assertEquals(0, presentationCalls)
                assertEquals(1, runner.finishCalls)
            }
        }

    @Test
    fun `authenticated terminal completion fences reordered presentation and cleans once`() =
        runBlocking {
            val operations = mutableListOf<String>()
            val runner = FakeHeadlessCallAdmissionRunner { observed ->
                operations += "dart.terminal"
                validCompletionObject(observed).copy(
                    disposition = HeadlessCallAdmissionDisposition.TERMINAL,
                )
            }.also {
                it.onFinish = {
                    operations += "engine.finish"
                    true
                }
            }
            var presentations = 0
            val terminalized = mutableListOf<Pair<String, Long>>()

            assertEquals(
                HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                execution(
                    runner = runner,
                    nowMs = { NOW_MS },
                    presentAuthenticated = { _, _ ->
                        presentations += 1
                        true
                    },
                    terminalizeAuthenticated = { callId, expiresAtMs ->
                        operations += "native.terminalizeAuthenticated"
                        terminalized += callId to expiresAtMs
                        true
                    },
                ).execute(validInput()),
            )
            assertEquals(0, presentations)
            assertEquals(listOf(CALL_ID to EXPIRES_AT_MS), terminalized)
            assertEquals(
                listOf(
                    "dart.terminal",
                    "engine.finish",
                    "native.terminalizeAuthenticated",
                ),
                operations,
            )
        }

    @Test
    fun `timeout exception stop expiry and cleanup failure all fail closed`() = runBlocking {
        val neverCompletes = CompletableDeferred<HeadlessCallAdmissionCompletion>()
        val timeoutRunner = FakeHeadlessCallAdmissionRunner {
            neverCompletes.await()
        }
        var presentations = 0
        assertEquals(
            HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
            execution(
                runner = timeoutRunner,
                nowMs = { NOW_MS },
                timeoutMillis = 25L,
                presentAuthenticated = { _, _ ->
                    presentations += 1
                    true
                },
            ).execute(validInput()),
        )
        assertEquals(1, timeoutRunner.stopCalls)
        assertEquals(1, timeoutRunner.finishCalls)

        val throwingRunner = FakeHeadlessCallAdmissionRunner {
            throw IllegalStateException("engine failed")
        }
        assertEquals(
            HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
            execution(
                runner = throwingRunner,
                nowMs = { NOW_MS },
                presentAuthenticated = { _, _ ->
                    presentations += 1
                    true
                },
            ).execute(validInput()),
        )
        assertEquals(1, throwingRunner.stopCalls)
        assertEquals(1, throwingRunner.finishCalls)

        val cleanupFailure = FakeHeadlessCallAdmissionRunner { observed ->
            validCompletionObject(observed)
        }.also { it.onFinish = { false } }
        assertEquals(
            HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
            execution(
                runner = cleanupFailure,
                nowMs = { NOW_MS },
                presentAuthenticated = { _, _ ->
                    presentations += 1
                    true
                },
            ).execute(validInput()),
        )

        var clock = NOW_MS
        val expiredAfterAdmission = FakeHeadlessCallAdmissionRunner { observed ->
            clock = EXPIRES_AT_MS
            validCompletionObject(observed)
        }
        assertEquals(
            HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
            execution(
                runner = expiredAfterAdmission,
                nowMs = { clock },
                presentAuthenticated = { _, _ ->
                    presentations += 1
                    true
                },
            ).execute(validInput()),
        )
        assertEquals(0, presentations)
    }

    @Test
    fun `malformed stale or retried worker input never constructs an engine`() = runBlocking {
        var factories = 0
        val execution = HeadlessCallAdmissionExecution(
            runnerFactory = {
                factories += 1
                FakeHeadlessCallAdmissionRunner { observed ->
                    validCompletionObject(observed)
                }
            },
            isStopped = { false },
            nowMs = { NOW_MS },
            timeoutMillis = 1_000L,
            nonceFactory = { "nonce-a" },
            presentAuthenticated = { _, _ -> error("must not present") },
            terminalizeAuthenticated = { _, _ -> error("must not terminalize") },
        )
        val malformed = listOf(
            Data.EMPTY,
            validInput(callId = "not-a-uuid"),
            validInput(wakeHandle = "not-a-wake"),
            validInput(expiresAtMs = NOW_MS),
            validInput(expiresAtMs = NOW_MS + CallPayloadParser.MAX_FUTURE_SKEW_MS + 1L),
            Data.Builder()
                .putAll(validInput())
                .putBoolean("extra", true)
                .build(),
        )
        malformed.forEach { input ->
            assertEquals(
                HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                execution.execute(input),
            )
        }
        assertEquals(
            HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
            execution.execute(validInput(), runAttemptCount = 1),
        )
        assertEquals(0, factories)
    }

    @Test
    fun `scheduler creates one opaque unique expedited connected job for exact wake identity`() {
        val enqueuer = RecordingHeadlessCallAdmissionEnqueuer()
        val scheduler = HeadlessCallAdmissionWorkScheduler(
            context = context,
            enqueuer = enqueuer,
            nowMs = { NOW_MS },
        )
        val payload = payload()

        assertTrue(scheduler.enqueue(payload))
        assertTrue(scheduler.enqueue(payload))

        assertEquals(2, enqueuer.requests.size)
        assertEquals(1, enqueuer.requests.map { it.uniqueName }.distinct().size)
        enqueuer.requests.forEach { recorded ->
            assertEquals(ExistingWorkPolicy.APPEND_OR_REPLACE, recorded.policy)
            assertTrue(recorded.request.workSpec.expedited)
            assertEquals(
                OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST,
                recorded.request.workSpec.outOfQuotaPolicy,
            )
            assertEquals(
                NetworkType.CONNECTED,
                recorded.request.workSpec.constraints.requiredNetworkType,
            )
            assertEquals(
                HeadlessCallAdmissionWorker::class.java.name,
                recorded.request.workSpec.workerClassName,
            )
            val input = recorded.request.workSpec.input
            assertEquals(
                setOf(
                    HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID,
                    HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE,
                    HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS,
                ),
                input.keyValueMap.keys,
            )
            assertEquals(
                payload.nativeCallId.toString(),
                input.getString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID),
            )
            assertEquals(
                payload.wakeHandle,
                input.getString(HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE),
            )
            assertEquals(
                payload.expiresAtMs,
                input.getLong(HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS, -1L),
            )
            assertFalse(recorded.uniqueName.contains(payload.callHandle))
            assertFalse(recorded.uniqueName.contains(payload.wakeHandle))
        }

        assertTrue(
            scheduler.enqueue(
                payload.copy(wakeHandle = OTHER_WAKE_HANDLE),
            ),
        )
        assertEquals(enqueuer.requests[0].uniqueName, enqueuer.requests[2].uniqueName)
        assertFalse(
            scheduler.enqueue(
                payload.copy(expiresAtMs = NOW_MS),
            ),
        )
        assertEquals(3, enqueuer.requests.size)
    }

    @Test
    @Config(sdk = [24])
    fun `pre Android 12 expedited foreground fallback is generic and silent`() {
        val notification = HeadlessCallAdmissionWorker
            .createForegroundInfo(context)
            .notification

        assertEquals(null, notification.sound)
        assertEquals(0, notification.defaults)
        assertTrue(notification.vibrate == null)
    }

    @Test
    @Config(sdk = [33])
    fun `Android foreground fallback cannot alert before authentication`() {
        val notification = HeadlessCallAdmissionWorker
            .createForegroundInfo(context)
            .notification

        assertEquals(
            MknoonFirebaseMessagingService.SILENT_RECOVERY_GROUP_KEY,
            notification.group,
        )
        assertEquals(Notification.GROUP_ALERT_SUMMARY, notification.groupAlertBehavior)
    }

    @Test
    fun `production source exposes only the fixed headless contract and authenticated presenter`() {
        val source = sourceFile("HeadlessCallAdmissionWorker.kt").readText()
        val service = File(
            requireNotNull(System.getProperty("user.dir")),
            "src/main/kotlin/com/mknoon/app/MknoonFirebaseMessagingService.kt",
        ).readText()

        assertTrue(source.contains("androidHeadlessCallAdmissionMain"))
        assertTrue(source.contains("mknoon/headless_call_admission"))
        assertTrue(source.contains("registerAllowlistedPlugins(created)"))
        assertTrue(source.contains("FlutterSecureStoragePlugin()"))
        assertTrue(source.contains("SqfliteSqlCipherPlugin()"))
        assertTrue(source.contains("PathProviderPlugin()"))
        assertTrue(source.contains("engine?.destroy()"))
        assertTrue(source.contains("presentAuthenticated("))
        assertFalse(source.contains("GeneratedPluginRegistrant"))
        assertFalse(source.contains("android.util.Log"))
        assertFalse(service.contains(".present(payload)"))
        assertTrue(service.contains("HeadlessCallAdmissionWorkScheduler"))
    }

    private fun execution(
        runner: FakeHeadlessCallAdmissionRunner,
        nowMs: () -> Long,
        timeoutMillis: Long = 1_000L,
        presentAuthenticated: suspend (String, Long) -> Boolean,
        terminalizeAuthenticated: suspend (String, Long) -> Boolean = { _, _ -> true },
    ): HeadlessCallAdmissionExecution = HeadlessCallAdmissionExecution(
        runnerFactory = { runner },
        isStopped = { false },
        nowMs = nowMs,
        timeoutMillis = timeoutMillis,
        nonceFactory = { "nonce-a" },
        presentAuthenticated = presentAuthenticated,
        terminalizeAuthenticated = terminalizeAuthenticated,
    )

    private fun identity() = HeadlessCallAdmissionRunIdentity(
        nonce = "nonce-a",
        callId = CALL_ID,
        wakeHandle = WAKE_HANDLE,
        expiresAtMs = EXPIRES_AT_MS,
    )

    private fun validCompletion(
        identity: HeadlessCallAdmissionRunIdentity,
    ): Map<String, Any?> = mapOf(
        "nonce" to identity.nonce,
        "callId" to identity.callId,
        "wakeHandle" to identity.wakeHandle,
        "expiresAtMs" to identity.expiresAtMs,
        "disposition" to "admitted",
        "requiredPersistenceComplete" to true,
        "databaseClosed" to true,
        "leaseReleased" to true,
    )

    private fun validCompletionObject(
        identity: HeadlessCallAdmissionRunIdentity,
    ) = HeadlessCallAdmissionCompletion(
        nonce = identity.nonce,
        callId = identity.callId,
        wakeHandle = identity.wakeHandle,
        expiresAtMs = identity.expiresAtMs,
        disposition = HeadlessCallAdmissionDisposition.ADMITTED,
        requiredPersistenceComplete = true,
        databaseClosed = true,
        leaseReleased = true,
    )

    private fun validInput(
        callId: String = CALL_ID,
        wakeHandle: String = WAKE_HANDLE,
        expiresAtMs: Long = EXPIRES_AT_MS,
    ): Data = Data.Builder()
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID, callId)
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE, wakeHandle)
        .putLong(HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS, expiresAtMs)
        .build()

    private fun payload() = CallWakePayload(
        nativeCallId = UUID.fromString(CALL_ID),
        callHandle = CALL_ID,
        wakeHandle = WAKE_HANDLE,
        receivedAtMs = NOW_MS,
        expiresAtMs = EXPIRES_AT_MS,
    )

    private fun sourceFile(name: String): File = File(
        requireNotNull(System.getProperty("user.dir")),
        "src/main/kotlin/com/mknoon/app/call/$name",
    )

    companion object {
        private const val NOW_MS = 1_800_000_000_000L
        private const val EXPIRES_AT_MS = NOW_MS + 45_000L
        private const val CALL_ID = "00112233-4455-6677-8899-aabbccddeeff"
        private const val OTHER_CALL_ID = "10112233-4455-6677-8899-aabbccddeeff"
        private const val WAKE_HANDLE = "10112233445566778899aabbccddeeff"
        private const val OTHER_WAKE_HANDLE = "20112233445566778899aabbccddeeff"
    }
}

private class FakeHeadlessCallAdmissionRunner(
    private val runBlock: suspend (
        HeadlessCallAdmissionRunIdentity,
    ) -> HeadlessCallAdmissionCompletion,
) : HeadlessCallAdmissionEngineRunner {
    var runCalls = 0
    var stopCalls = 0
    var finishCalls = 0
    var onFinish: suspend () -> Boolean = { true }

    override suspend fun run(
        identity: HeadlessCallAdmissionRunIdentity,
    ): HeadlessCallAdmissionCompletion {
        runCalls += 1
        return runBlock(identity)
    }

    override fun requestStop() {
        stopCalls += 1
    }

    override suspend fun finish(): Boolean {
        finishCalls += 1
        return onFinish()
    }
}

private data class RecordedHeadlessCallAdmissionWork(
    val uniqueName: String,
    val policy: ExistingWorkPolicy,
    val request: OneTimeWorkRequest,
)

private class RecordingHeadlessCallAdmissionEnqueuer : HeadlessCallAdmissionWorkEnqueuer {
    val requests = mutableListOf<RecordedHeadlessCallAdmissionWork>()

    override fun enqueueUnique(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        requests += RecordedHeadlessCallAdmissionWork(uniqueName, policy, request)
    }
}
