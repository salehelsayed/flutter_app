package com.mknoon.app.call

import android.os.Looper
import androidx.work.Data
import com.mknoon.app.CanonicalRuntimeLeaseBroker
import com.mknoon.app.ProcessCanonicalRuntimeLease
import java.util.Collections
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
class HeadlessCallAdmissionMainQueueTest {
    @Test
    fun `foreground acquisition after preflight defers before constructing a headless engine`() {
        val broker = ProcessCanonicalRuntimeLease.broker
        assertEquals(CanonicalRuntimeLeaseBroker.State.RELEASED, broker.snapshot().state)
        assertFalse(isHeadlessCallAdmissionEngineClaimed())
        val factoryCalls = AtomicInteger()
        val preflight = AtomicReference<CanonicalRuntimeLeaseBroker.Snapshot>()
        val preflightFinished = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val result = CompletableFuture<HeadlessCallAdmissionWorkOutcome>()
        val diagnostics = Collections.synchronizedList(mutableListOf<HeadlessCallAdmissionDiagnostic>())
        val releases = Collections.synchronizedList(mutableListOf<Pair<String, Boolean>>())
        val runner = FlutterHeadlessCallAdmissionEngineRunner(
            RuntimeEnvironment.getApplication(),
            engineFactory = {
                factoryCalls.incrementAndGet()
                // Observe the real construction boundary without loading JNI.
                error("An active foreground owner must prevent this construction")
            },
        )
        val execution = HeadlessCallAdmissionExecution(
            runnerFactory = { runner },
            isStopped = { false },
            nowMs = { NOW_MS },
            timeoutMillis = 10_000L,
            nonceFactory = { "main-queue-regression" },
            presentAuthenticated = { _, _, _ -> error("Deferred admission must not present") },
            terminalizeAuthenticated = { _, _ -> error("Deferred admission must not terminalize") },
            releaseAdmission = { callId, requireTerminal -> releases += callId to requireTerminal },
            diagnostic = { _, diagnostic -> diagnostics += diagnostic },
            foregroundOwnsRuntime = {
                val snapshot = broker.snapshot()
                preflight.set(snapshot)
                val owns = foregroundOwnsCanonicalRuntime(snapshot)
                preflightFinished.countDown()
                owns
            },
        )
        val worker = thread(name = "headless-main-queue-regression", isDaemon = true) {
            try {
                result.complete(runBlocking { execution.execute(input()) })
            } catch (failure: Throwable) {
                result.completeExceptionally(failure)
            } finally {
                finished.countDown()
            }
        }
        var foreground: CanonicalRuntimeLeaseBroker.Token? = null
        try {
            assertTrue("The worker must run its released preflight", preflightFinished.await(5, TimeUnit.SECONDS))
            assertEquals(CanonicalRuntimeLeaseBroker.State.RELEASED, preflight.get().state)
            // The paused main queue has not constructed anything yet. Change
            // real process ownership before allowing its continuation to run.
            assertEquals(0, factoryCalls.get())
            foreground = broker.acquire("foreground-regression", "account-regression", CanonicalRuntimeLeaseBroker.Role.FOREGROUND)
            assertNotNull(foreground)
            drainUntilFinished(finished)

            assertEquals("Late foreground ownership must prevent the real engine factory", 0, factoryCalls.get())
            assertEquals(HeadlessCallAdmissionWorkOutcome.COMPLETED_WITHOUT_PRESENTATION, result.get(1, TimeUnit.SECONDS))
            assertEquals("pending", diagnostics.last().outcome)
            assertEquals("busy", diagnostics.last().reason)
            val response = diagnostics.single { it.action == "response" }
            assertEquals("deferred", response.values["admissionDisposition"])
            assertEquals(false, response.values["requiredPersistenceComplete"])
            assertEquals(true, response.values["databaseClosed"])
            assertEquals(true, response.values["leaseReleased"])
            assertEquals(listOf(CALL_ID to true), releases)
            assertFalse("Deferral must not retain the headless construction slot", isHeadlessCallAdmissionEngineClaimed())
            assertEquals(foreground, broker.acquire("foreground-regression", "account-regression", CanonicalRuntimeLeaseBroker.Role.FOREGROUND))
        } finally {
            execution.requestStop()
            drainUntilFinished(finished)
            foreground?.let {
                assertTrue(broker.beginDrain(it))
                assertTrue(broker.release(it, databaseClosed = true))
            }
            worker.join(1_000L)
            assertFalse("The isolated host worker must finish", worker.isAlive)
        }
    }

    private fun drainUntilFinished(finished: CountDownLatch) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (finished.count > 0 && System.nanoTime() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            finished.await(10, TimeUnit.MILLISECONDS)
        }
        assertEquals("The main-queue admission run must complete", 0L, finished.count)
    }

    private fun input() = Data.Builder()
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_CALL_ID, CALL_ID)
        .putString(HeadlessCallAdmissionWorkScheduler.INPUT_WAKE_HANDLE, "00000000-0000-4000-8000-000000000499")
        .putLong(HeadlessCallAdmissionWorkScheduler.INPUT_EXPIRES_AT_MS, NOW_MS + 40_000L)
        .build()
}
