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

    /**
     * 408: device 2026-09-05 22:00:41Z — the killed-app missed-call card died
     * with MissingPluginException because this engine's allowlist omitted the
     * notifications plugin. HeadlessCanonicalRecoveryWorker, which posts cards
     * headlessly today, registers it; this engine must too.
     */
    @Test
    fun headlessEngineRegistersTheNotificationsPlugin() {
        val source = java.io.File(
            "src/main/kotlin/com/mknoon/app/call/HeadlessCallAdmissionWorker.kt",
        ).readText()
        val allowlist = source.substringAfter("private fun registerAllowlistedPlugins")
            .substringBefore("}")
        assertTrue(
            "the headless engine must register the notifications plugin or " +
                "every card it posts throws MissingPluginException",
            allowlist.contains("FlutterLocalNotificationsPlugin()"),
        )
    }

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
    fun `completion diagnostic cause cannot reject valid authority or admit invalid authority`() {
        for (cause in listOf<Any?>("graph_not_owner", "private failure $CALL_ID", 123, null)) {
            val identity = identity()
            val payload = validCompletion(identity) + ("diagnosticCause" to cause)
            val parsed = HeadlessCallAdmissionCompletionProtocol.parse("complete", payload, identity)
            assertTrue("optional diagnostic metadata must not reject a valid old authority result", parsed != null)
            assertEquals(if (cause == "graph_not_owner") cause else null, parsed?.diagnosticCause)
            assertEquals(null, HeadlessCallAdmissionCompletionProtocol.parse("complete", payload + ("nonce" to "wrong"), identity))
        }
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
            assertTrue(operations.none { it.contains("releaseDeclineReply") })
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

    // Plan 404 (device 2026-09-05 17:44Z): a call presented headlessly and
    // declined natively never told the caller, whose ringback played until its
    // own cancel. The decline schedules one decline-reply run for the same
    // call: serialized behind any admission job of that call, carrying the
    // mode as one extra input key and the descriptor's own wake handle.
    @Test
    fun `scheduler enqueues one decline reply job for a declined headless call`() {
        val enqueuer = RecordingHeadlessCallAdmissionEnqueuer()
        val scheduler = HeadlessCallAdmissionWorkScheduler(
            context = context,
            enqueuer = enqueuer,
            nowMs = { NOW_MS },
        )
        val descriptor = declinedDescriptor()

        assertTrue(scheduler.enqueue(payload()))
        assertTrue(scheduler.enqueueDeclineReply(descriptor))

        assertEquals(2, enqueuer.requests.size)
        assertEquals(enqueuer.requests[0].uniqueName, enqueuer.requests[1].uniqueName)
        val recorded = enqueuer.requests[1]
        assertEquals(ExistingWorkPolicy.APPEND_OR_REPLACE, recorded.policy)
        assertTrue(recorded.request.workSpec.expedited)
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
                HeadlessCallAdmissionWorkScheduler.INPUT_MODE,
            ),
            input.keyValueMap.keys,
        )
        assertEquals(CALL_ID, input.getString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID))
        assertEquals(
            NATIVE_WAKE_HANDLE,
            input.getString(HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE),
        )
        assertEquals(
            EXPIRES_AT_MS,
            input.getLong(HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS, -1L),
        )
        assertEquals(
            HeadlessCallAdmissionMode.DECLINE_REPLY.wireName,
            input.getString(HeadlessCallAdmissionWorkScheduler.INPUT_MODE),
        )

        assertFalse(scheduler.enqueueDeclineReply(descriptor.copy(expiresAtMs = NOW_MS)))
        assertFalse(scheduler.enqueueDeclineReply(descriptor.copy(callHandle = "readable")))
        assertEquals(2, enqueuer.requests.size)
    }

    @Test
    fun `decline reply input runs the engine in decline mode and never presents`() =
        runBlocking {
            for (
                disposition in listOf(
                    HeadlessCallAdmissionDisposition.ADMITTED,
                    HeadlessCallAdmissionDisposition.TERMINAL,
                )
            ) {
                var observedMode: HeadlessCallAdmissionMode? = null
                val operations = mutableListOf<String>()
                val runner = FakeHeadlessCallAdmissionRunner { observed ->
                    observedMode = observed.mode
                    operations += "dart.complete"
                    validCompletionObject(observed).copy(disposition = disposition)
                }.also {
                    it.onFinish = {
                        operations += "engine.finish"
                        true
                    }
                }
                var presentations = 0
                var terminalizations = 0
                val released = mutableListOf<String>()
                val execution = execution(
                    runner = runner,
                    nowMs = { NOW_MS },
                    presentAuthenticated = { _, _ ->
                        presentations += 1
                        true
                    },
                    terminalizeAuthenticated = { _, _ ->
                        terminalizations += 1
                        true
                    },
                    releaseDeclineReply = { callId ->
                        operations += "native.releaseDeclineReply"
                        released += callId
                    },
                )

                assertEquals(
                    HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                    execution.execute(declineInput()),
                )
                assertEquals(HeadlessCallAdmissionMode.DECLINE_REPLY, observedMode)
                assertEquals(1, runner.runCalls)
                assertEquals(1, runner.finishCalls)
                assertEquals(0, presentations)
                assertEquals(0, terminalizations)
                // Plan 404 (c): the reply runs under the call foreground
                // service (device 2026-09-05 18:23Z: without it the run took
                // 7 s to reach the network); the worker releases it once the
                // engine is safely finished, whatever Dart reported.
                assertEquals(listOf(CALL_ID), released)
                assertEquals(
                    listOf("dart.complete", "engine.finish", "native.releaseDeclineReply"),
                    operations,
                )
            }
        }

    @Test
    fun `an unknown mode never constructs an engine`() = runBlocking {
        for (mode in listOf("admission", "", "DECLINE_REPLY", "decline-reply")) {
            var constructed = 0
            val execution = HeadlessCallAdmissionExecution(
                runnerFactory = {
                    constructed += 1
                    FakeHeadlessCallAdmissionRunner { validCompletionObject(it) }
                },
                isStopped = { false },
                nowMs = { NOW_MS },
                timeoutMillis = 1_000L,
                nonceFactory = { "nonce-a" },
                presentAuthenticated = { _, _ -> true },
                terminalizeAuthenticated = { _, _ -> true },
            )

            assertEquals(
                HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                execution.execute(declineInput(mode = mode)),
            )
            assertEquals(0, constructed)
        }
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
    fun `diagnostics distinguish deferred completion and incomplete custody without admitting either`() = runBlocking {
        for (unsafeField in listOf("none", "databaseClosed", "leaseReleased", "requiredPersistenceComplete")) {
            val events = mutableListOf<HeadlessCallAdmissionDiagnostic>()
            val runner = FakeHeadlessCallAdmissionRunner { identity ->
                validCompletionObject(identity).copy(
                    disposition = HeadlessCallAdmissionDisposition.DEFERRED,
                    databaseClosed = unsafeField != "databaseClosed",
                    leaseReleased = unsafeField != "leaseReleased",
                    requiredPersistenceComplete = unsafeField != "requiredPersistenceComplete",
                )
            }
            var presented = false
            val result = execution(
                runner = runner,
                nowMs = { NOW_MS },
                presentAuthenticated = { _, _ -> presented = true; true },
                diagnostic = { _, event -> events += event },
            ).execute(validInput())

            assertFalse(presented)
            assertEquals(HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION, result)
            assertTrue("native-only admission must leave durable start/result evidence", events.isNotEmpty())
            val completion = events.single { it.action == "response" }
            assertEquals("deferred", completion.values["admissionDisposition"])
            assertEquals(unsafeField != "databaseClosed", completion.values["databaseClosed"])
            assertEquals(unsafeField != "leaseReleased", completion.values["leaseReleased"])
            assertEquals(unsafeField != "requiredPersistenceComplete", completion.values["requiredPersistenceComplete"])
            val reason = when (unsafeField) {
                "none" -> "unknown"
                "requiredPersistenceComplete" -> "unknown"
                else -> "cleanup_failed"
            }
            assertEquals(reason, events.last().reason)
            if (unsafeField == "requiredPersistenceComplete") assertEquals("pending", events.last().outcome)
            assertEquals(1, events.map { it.operationId }.distinct().size)
            assertTrue(events.all { MknoonCallDiagnosticSpool.uuid(it.operationId) })
            assertFalse(events.toString().contains(CALL_ID))
            assertFalse(events.toString().contains(WAKE_HANDLE))
            assertFalse(events.toString().contains("nonce-a"))
        }
    }

    @Test
    fun `deferred cause is diagnostic only with unsatisfied persistence gate`() = runBlocking {
        for (cause in listOf("graph_not_owner", "authority_invalid", "transport_failed", "private error")) {
            val events = mutableListOf<HeadlessCallAdmissionDiagnostic>()
            val runner = FakeHeadlessCallAdmissionRunner { validCompletionObject(it).copy(
                disposition = HeadlessCallAdmissionDisposition.DEFERRED,
                requiredPersistenceComplete = false, diagnosticCause = cause,
            ) }
            var presented = false
            val result = execution(runner = runner, nowMs = { NOW_MS },
                presentAuthenticated = { _, _ -> presented = true; true },
                diagnostic = { _, event -> events += event }).execute(validInput())
            assertFalse(presented)
            assertEquals(HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION, result)
            assertEquals("pending", events.last().outcome)
            assertEquals(if (cause == "private error") "unknown" else cause, events.last().reason)
            assertFalse(events.toString().contains("private error"))
        }
    }

    @Test
    fun `diagnostics preserve exact admitted terminal rejection empty and deferred dispositions`() = runBlocking {
        val expected = mapOf(
            HeadlessCallAdmissionDisposition.ADMITTED to "ok",
            HeadlessCallAdmissionDisposition.TERMINAL to "completed",
            HeadlessCallAdmissionDisposition.PERMANENT_REJECT to "rejected",
            HeadlessCallAdmissionDisposition.EMPTY_OR_ALREADY_ACKED to "not_found",
            HeadlessCallAdmissionDisposition.DEFERRED to "pending",
        )
        for ((disposition, outcome) in expected) {
            val events = mutableListOf<HeadlessCallAdmissionDiagnostic>()
            val runner = FakeHeadlessCallAdmissionRunner { validCompletionObject(it).copy(disposition = disposition) }
            var presentations = 0
            val result = execution(
                runner = runner,
                nowMs = { NOW_MS },
                presentAuthenticated = { _, _ -> presentations += 1; true },
                diagnostic = { _, event -> events += event },
            ).execute(validInput())
            assertEquals(disposition.name.lowercase(), events.single { it.action == "response" }.values["admissionDisposition"])
            assertEquals(outcome, events.last().outcome)
            assertEquals(if (disposition == HeadlessCallAdmissionDisposition.ADMITTED) 1 else 0, presentations)
            assertEquals(
                if (presentations == 1) HeadlessCallAdmissionWorkOutcome.PRESENTED else HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION,
                result,
            )
        }
    }

    @Test
    fun `diagnostics distinguish engine timeout from exception without recording error text`() = runBlocking {
        for (timeout in listOf(false, true)) {
            val events = mutableListOf<HeadlessCallAdmissionDiagnostic>()
            val runner = FakeHeadlessCallAdmissionRunner {
                if (timeout) CompletableDeferred<HeadlessCallAdmissionCompletion>().await()
                else throw IllegalStateException("private-error-$WAKE_HANDLE")
            }
            val result = execution(
                runner = runner,
                nowMs = { NOW_MS },
                timeoutMillis = 25L,
                presentAuthenticated = { _, _ -> error("must not present") },
                diagnostic = { _, event -> events += event },
            ).execute(validInput())
            assertEquals(HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION, result)
            assertTrue("failure must remain diagnosable without a Dart completion", events.isNotEmpty())
            assertEquals(if (timeout) "timeout" else "native_lifecycle_failed", events.last().reason)
            assertTrue((events.last().values["durationMs"] as Long) >= 0L)
            assertFalse(events.toString().contains("private-error"))
            assertFalse(events.toString().contains(WAKE_HANDLE))
            assertEquals(1, runner.stopCalls)
            assertEquals(1, runner.finishCalls)
        }
    }

    @Test
    fun `diagnostic sink failure cannot change authenticated presentation or cleanup ordering`() = runBlocking {
        val order = mutableListOf<String>()
        val runner = FakeHeadlessCallAdmissionRunner { validCompletionObject(it) }.also {
            it.onFinish = { order += "finish"; true }
        }
        val result = execution(
            runner = runner,
            nowMs = { NOW_MS },
            presentAuthenticated = { _, _ -> order += "present"; true },
            diagnostic = { _, _ -> throw IllegalStateException("sink unavailable") },
        ).execute(validInput())
        assertEquals(HeadlessCallAdmissionWorkOutcome.PRESENTED, result)
        assertEquals(listOf("finish", "present"), order)
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
        val runtime = sourceFile("MknoonCallAndroidRuntime.kt").readText()
        val declineReply = runtime.substringAfter("fun scheduleHeadlessDeclineReply")
        assertTrue(declineReply.contains("enqueueDeclineReply(descriptor)"))
        assertTrue(declineReply.contains("MknoonCallForegroundService.ACTION_START_ADMISSION"))
        assertTrue(runtime.contains("fun stopAdmissionForeground("))
        assertTrue(runtime.contains("MknoonCallForegroundService.ACTION_STOP"))
        assertTrue(source.contains("stopAdmissionForeground("))
    }

    private fun execution(
        runner: FakeHeadlessCallAdmissionRunner,
        nowMs: () -> Long,
        timeoutMillis: Long = 1_000L,
        presentAuthenticated: suspend (String, Long) -> Boolean,
        terminalizeAuthenticated: suspend (String, Long) -> Boolean = { _, _ -> true },
        releaseDeclineReply: suspend (String) -> Unit = {},
        diagnostic: (String?, HeadlessCallAdmissionDiagnostic) -> Unit = { _, _ -> },
    ): HeadlessCallAdmissionExecution = HeadlessCallAdmissionExecution(
        runnerFactory = { runner },
        isStopped = { false },
        nowMs = nowMs,
        timeoutMillis = timeoutMillis,
        nonceFactory = { "nonce-a" },
        presentAuthenticated = presentAuthenticated,
        terminalizeAuthenticated = terminalizeAuthenticated,
        releaseDeclineReply = releaseDeclineReply,
        diagnostic = diagnostic,
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

    private fun declinedDescriptor() = PendingNativeCallDescriptor(
        nativeCallId = UUID.fromString(CALL_ID),
        callHandle = CALL_ID,
        wakeHandle = NATIVE_WAKE_HANDLE,
        receivedAtMs = NOW_MS,
        expiresAtMs = EXPIRES_AT_MS,
        highestSequence = 2L,
        terminalEvent = null,
        events = emptyList(),
    )

    private fun declineInput(
        mode: String = HeadlessCallAdmissionMode.DECLINE_REPLY.wireName,
    ): Data = Data.Builder()
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID, CALL_ID)
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE, NATIVE_WAKE_HANDLE)
        .putLong(HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS, EXPIRES_AT_MS)
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_MODE, mode)
        .build()

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
        private const val NATIVE_WAKE_HANDLE = "30112233-4455-4677-8899-aabbccddeeff"
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
