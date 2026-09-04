package com.mknoon.app.call

import androidx.core.telecom.CallAttributesCompat
import androidx.core.telecom.CallEndpointCompat
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonCallAndroidRuntimeTest {
    @Test
    fun `lifecycle diagnostics have one closed identifier free wire vocabulary`() {
        assertEquals(
            listOf(
                "CALL_ANDROID_LIFECYCLE transition=set_active outcome=accepted_after_dart",
                "CALL_ANDROID_LIFECYCLE transition=set_active outcome=buffered_after_answer",
                "CALL_ANDROID_LIFECYCLE transition=set_active outcome=rejected_unsolicited",
                "CALL_ANDROID_LIFECYCLE transition=dart_activate outcome=skip_already_active",
                "CALL_ANDROID_LIFECYCLE transition=dart_activate outcome=set_active_failed",
                "CALL_ANDROID_LIFECYCLE transition=dart_activate outcome=service_failed",
                "CALL_ANDROID_LIFECYCLE transition=dart_activate outcome=completed",
            ),
            MknoonCallLifecycleDiagnostic.values().map(::formatMknoonCallLifecycleDiagnostic),
        )
        assertEquals("MknoonCallLifecycle", MKNOON_CALL_LIFECYCLE_DIAGNOSTIC_TAG)
        assertEquals(
            "MKNOON_CALL_RINGTONE_DIAG stage=start result=playing",
            formatMknoonCallRingtoneDiagnostic("start", "playing"),
        )
        assertEquals("MknoonCallRingtone", MKNOON_CALL_RINGTONE_DIAGNOSTIC_TAG)
    }

    @Test
    fun `Telecom disconnect diagnostics identify every local release source`() {
        assertEquals(
            listOf(
                "CALL_ANDROID_DISCONNECT source=explicit_end stage=requested",
                "CALL_ANDROID_DISCONNECT source=late_registration stage=requested",
                "CALL_ANDROID_DISCONNECT source=set_active stage=rejected_disconnect",
                "CALL_ANDROID_DISCONNECT source=set_inactive stage=requested",
                "CALL_ANDROID_DISCONNECT source=telecom_callback stage=ignored_local",
                "CALL_ANDROID_DISCONNECT source=telecom_callback stage=forwarded_remote",
            ),
            MknoonTelecomDisconnectSource.values()
                .map(::formatMknoonTelecomDisconnectDiagnostic),
        )
        assertEquals("MknoonCallDisconnect", MKNOON_TELECOM_DISCONNECT_DIAGNOSTIC_TAG)
    }

    @Test
    fun `only an unanswered live incoming descriptor may start ringtone playback`() {
        val callId = UUID.fromString("00000000-0000-4000-8000-000000000401")
        val descriptor = PendingNativeCallDescriptor(
            nativeCallId = callId,
            callHandle = "00000000-0000-4000-8000-000000000402",
            wakeHandle = "wake",
            receivedAtMs = 1_000L,
            expiresAtMs = 60_000L,
            highestSequence = 1L,
            terminalEvent = null,
            events = emptyList(),
        )

        assertTrue(isIncomingRingtoneEligible(descriptor, callId, 59_999L))
        assertFalse(
            isIncomingRingtoneEligible(
                descriptor.copy(answerRequested = true),
                callId,
                59_999L,
            ),
        )
        assertFalse(
            isIncomingRingtoneEligible(
                descriptor.copy(direction = PendingNativeCallDirection.OUTGOING),
                callId,
                59_999L,
            ),
        )
        assertFalse(
            isIncomingRingtoneEligible(
                descriptor.copy(
                    terminalEvent = PendingNativeCallEvent(
                        nativeCallId = callId,
                        sequence = 2L,
                        eventId = UUID.fromString("00000000-0000-4000-8000-000000000403"),
                        type = PendingNativeCallEventType.REMOTE_CANCELLED,
                    ),
                ),
                callId,
                59_999L,
            ),
        )
        assertFalse(
            isIncomingRingtoneEligible(
                descriptor,
                UUID.fromString("00000000-0000-4000-8000-000000000404"),
                59_999L,
            ),
        )
        assertFalse(isIncomingRingtoneEligible(descriptor, callId, 60_000L))
        assertFalse(isIncomingRingtoneEligible(null, callId, 59_999L))
    }

    @Test
    fun `answer racing ringtone startup releases the newly started session`() {
        val callId = UUID.fromString("00000000-0000-4000-8000-000000000405")
        var descriptor = PendingNativeCallDescriptor(
            nativeCallId = callId,
            callHandle = "00000000-0000-4000-8000-000000000406",
            wakeHandle = "wake",
            receivedAtMs = 1_000L,
            expiresAtMs = 60_000L,
            highestSequence = 1L,
            terminalEvent = null,
            events = emptyList(),
        )
        var startCalls = 0
        val stops = mutableListOf<Pair<UUID, String>>()

        val result = coordinateIncomingRingtoneStart(
            nativeCallId = callId,
            snapshot = { descriptor },
            observedNowMs = { 59_999L },
            start = {
                startCalls += 1
                descriptor = descriptor.copy(answerRequested = true)
                true
            },
            stop = { stoppedCallId, reason -> stops += stoppedCallId to reason },
        )

        assertEquals(MknoonIncomingRingtoneStartResult.INELIGIBLE, result)
        assertEquals(1, startCalls)
        assertEquals(listOf(callId to "start_race"), stops)
    }

    @Test
    fun `startup expiry retires every persisted lifecycle phase`() {
        val callId = UUID.fromString("00000000-0000-4000-8000-000000000407")
        val presented = PendingNativeCallEvent(
            nativeCallId = callId,
            sequence = 1L,
            eventId = UUID.fromString("00000000-0000-4000-8000-000000000408"),
            type = PendingNativeCallEventType.PRESENTED,
        )
        val terminal = PendingNativeCallEvent(
            nativeCallId = callId,
            sequence = 2L,
            eventId = UUID.fromString("00000000-0000-4000-8000-000000000409"),
            type = PendingNativeCallEventType.EXPIRED,
        )
        val preStart = PendingNativeCallDescriptor(
            nativeCallId = callId,
            callHandle = callId.toString(),
            wakeHandle = "wake",
            receivedAtMs = 1_000L,
            expiresAtMs = 60_000L,
            highestSequence = 0L,
            terminalEvent = null,
            events = emptyList(),
        )
        val persistedPhases = mapOf(
            "pre-start" to preStart,
            "presented journal" to preStart.copy(
                phase = PendingNativeCallPhase.JOURNAL,
                highestSequence = presented.sequence,
                events = listOf(presented),
            ),
            "adopted journal" to preStart.copy(
                phase = PendingNativeCallPhase.JOURNAL,
                handoffAcknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
            ),
            "terminal journal" to preStart.copy(
                phase = PendingNativeCallPhase.JOURNAL,
                highestSequence = terminal.sequence,
                terminalEvent = terminal,
                events = listOf(presented, terminal),
            ),
        )

        persistedPhases.forEach { (phase, descriptor) ->
            assertFalse(
                "$phase must remain live before its deadline",
                shouldAutoDeleteExpiredPersistedCallAtStartup(
                    descriptor = descriptor,
                    observedNowMs = descriptor.expiresAtMs - 1L,
                ),
            )
            assertTrue(
                "$phase must be retired at its inclusive deadline",
                shouldAutoDeleteExpiredPersistedCallAtStartup(
                    descriptor = descriptor,
                    observedNowMs = descriptor.expiresAtMs,
                ),
            )
        }
    }

    @Test
    fun `persisted direction selects the exact Core Telecom direction`() {
        assertEquals(
            CallAttributesCompat.DIRECTION_INCOMING,
            coreTelecomDirection(PendingNativeCallDirection.INCOMING),
        )
        assertEquals(
            CallAttributesCompat.DIRECTION_OUTGOING,
            coreTelecomDirection(PendingNativeCallDirection.OUTGOING),
        )
    }

    @Test
    fun `route wire vocabulary is canonical and system default resolves fallback endpoints`() {
        assertEquals("earpiece", canonicalCallRoute(CallEndpointCompat.TYPE_EARPIECE))
        assertEquals("speaker", canonicalCallRoute(CallEndpointCompat.TYPE_SPEAKER))
        assertEquals("wired_headset", canonicalCallRoute(CallEndpointCompat.TYPE_WIRED_HEADSET))
        assertEquals("bluetooth", canonicalCallRoute(CallEndpointCompat.TYPE_BLUETOOTH))
        assertEquals("system_default", canonicalCallRoute(CallEndpointCompat.TYPE_STREAMING))
        assertEquals("system_default", canonicalCallRoute(Int.MIN_VALUE))
        assertEquals(
            setOf("system_default", "earpiece", "speaker", "wired_headset", "bluetooth"),
            CANONICAL_NATIVE_CALL_ROUTES,
        )

        val endpointTypes = listOf(
            CallEndpointCompat.TYPE_SPEAKER,
            CallEndpointCompat.TYPE_STREAMING,
            Int.MIN_VALUE,
        )
        assertEquals(
            CallEndpointCompat.TYPE_STREAMING,
            selectCallEndpointForRoute(endpointTypes, "system_default") { it },
        )
        assertEquals(
            CallEndpointCompat.TYPE_SPEAKER,
            selectCallEndpointForRoute(endpointTypes, "speaker") { it },
        )
        assertEquals(null, selectCallEndpointForRoute(endpointTypes, "streaming") { it })
        assertEquals(null, selectCallEndpointForRoute(endpointTypes, "unknown") { it })
        assertEquals(null, selectCallEndpointForRoute(endpointTypes, "wired") { it })
    }

    @Test
    fun `registration timeout is the one winner and a late scope is released`() = runBlocking {
        val winner = MknoonCallRegistrationWinner()
        var disconnects = 0

        assertTrue(winner.claimTimeout())
        assertFalse(winner.claimReady())
        assertTrue(
            releaseTelecomCallbackSession {
                disconnects += 1
                true
            },
        )
        assertTrue(disconnects == 1)
        assertFalse(winner.claimFailure())
    }

    @Test
    fun `ready registration prevents timeout and callback release is truthful`() = runBlocking {
        val winner = MknoonCallRegistrationWinner()

        assertTrue(winner.claimReady())
        assertFalse(winner.claimTimeout())
        assertFalse(releaseTelecomCallbackSession { false })
        assertFalse(
            releaseTelecomCallbackSession {
                throw IllegalStateException("provider unavailable")
            },
        )
        assertFalse(
            releaseTelecomCallbackSession {
                throw AssertionError("provider fatal boundary")
            },
        )
    }

    @Test
    fun `registration publication and ready claim are atomic against timeout`() {
        val winner = MknoonCallRegistrationWinner()
        val publicationEntered = CountDownLatch(1)
        val allowPublication = CountDownLatch(1)
        val timeoutFinished = CountDownLatch(1)
        var published = false
        var ready = false
        var timedOut = true

        val readyThread = Thread {
            ready = winner.claimReady {
                publicationEntered.countDown()
                assertTrue(allowPublication.await(1L, TimeUnit.SECONDS))
                published = true
            }
        }.apply { start() }
        assertTrue(publicationEntered.await(1L, TimeUnit.SECONDS))
        val timeoutThread = Thread {
            timedOut = winner.claimTimeout()
            timeoutFinished.countDown()
        }.apply { start() }

        assertFalse(timeoutFinished.await(50L, TimeUnit.MILLISECONDS))
        allowPublication.countDown()
        readyThread.join(1_000L)
        timeoutThread.join(1_000L)

        assertTrue(published)
        assertTrue(ready)
        assertFalse(timedOut)
    }

    @Test
    fun `registered Telecom session is handed back on its waiting owner thread`() {
        val winner = MknoonCallRegistrationWinner()
        val registration = CountDownLatch(1)
        val ownerLock = Any()
        val published = AtomicBoolean(false)
        val providerClaimedReady = AtomicBoolean(false)
        val callbackThread = AtomicReference<Thread?>(null)
        var registered = false
        var abandoned = false
        val provider = Thread {
            providerClaimedReady.set(
                winner.claimReady {
                    published.set(true)
                },
            )
            registration.countDown()
        }

        val outcome = synchronized(ownerLock) {
            provider.start()
            awaitAndDispatchTelecomRegistration(
                completion = winner,
                registration = registration,
                timeoutMs = 1_000L,
                callback = object : MknoonCallRegistrationCallback {
                    override fun onRegistered() {
                        synchronized(ownerLock) {
                            assertTrue(published.get())
                            callbackThread.set(Thread.currentThread())
                            registered = true
                        }
                    }

                    override fun onFailure() {
                        abandoned = true
                    }

                    override fun onRegistrationAbandoned() {
                        abandoned = true
                    }
                },
            )
        }

        provider.join(1_000L)
        assertFalse(provider.isAlive)
        assertTrue(providerClaimedReady.get())
        assertEquals(MknoonCallRegistrationWinner.Outcome.READY, outcome)
        assertEquals(Thread.currentThread(), callbackThread.get())
        assertTrue(registered)
        assertFalse(abandoned)
    }

    @Test
    fun `timed out Telecom handoff abandons once and rejects late readiness`() {
        val winner = MknoonCallRegistrationWinner()
        val registration = CountDownLatch(1)
        var registered = false
        var abandoned = 0

        val outcome = awaitAndDispatchTelecomRegistration(
            completion = winner,
            registration = registration,
            timeoutMs = 25L,
            callback = object : MknoonCallRegistrationCallback {
                override fun onRegistered() {
                    registered = true
                }

                override fun onFailure() {
                    abandoned += 1
                }

                override fun onRegistrationAbandoned() {
                    abandoned += 1
                }
            },
        )

        assertEquals(MknoonCallRegistrationWinner.Outcome.TIMED_OUT, outcome)
        assertFalse(registered)
        assertEquals(1, abandoned)
        assertFalse(winner.claimReady())
    }

    @Test
    fun `failed Telecom handoff abandons on its waiting owner thread`() {
        val winner = MknoonCallRegistrationWinner()
        val registration = CountDownLatch(1)
        val callbackThread = AtomicReference<Thread?>(null)
        var registered = false
        val provider = Thread {
            winner.claimFailure()
            registration.countDown()
        }.apply { start() }

        val outcome = awaitAndDispatchTelecomRegistration(
            completion = winner,
            registration = registration,
            timeoutMs = 1_000L,
            callback = object : MknoonCallRegistrationCallback {
                override fun onRegistered() {
                    registered = true
                }

                override fun onFailure() {
                    callbackThread.set(Thread.currentThread())
                }

                override fun onRegistrationAbandoned() {
                    callbackThread.set(Thread.currentThread())
                }
            },
        )

        provider.join(1_000L)
        assertFalse(provider.isAlive)
        assertEquals(MknoonCallRegistrationWinner.Outcome.FAILED, outcome)
        assertFalse(registered)
        assertEquals(Thread.currentThread(), callbackThread.get())
    }

    @Test
    fun `late Telecom scope release retries nonthrowing provider rejection`() = runBlocking {
        var attempts = 0

        assertTrue(
            releaseTelecomCallbackSession(attempts = 3) {
                attempts += 1
                attempts == 2
            },
        )
        assertEquals(2, attempts)
    }

    @Test
    fun `permanently rejected late Telecom scope unwinds visibly after bound`() = runBlocking {
        var attempts = 0
        var rejected = false

        try {
            releaseLateTelecomScope {
                attempts += 1
                false
            }
        } catch (_: IllegalStateException) {
            rejected = true
        }

        assertTrue(rejected)
        assertEquals(3, attempts)
    }

    @Test
    fun `failed capability persistence still runs fail closed cleanup`() {
        val operations = mutableListOf<String>()

        assertFalse(
            executeFailClosed(
                persistDisable = {
                    operations += "persist.false"
                    false
                },
                cleanup = {
                    operations += "cleanup"
                    true
                },
            ),
        )
        assertEquals(listOf("persist.false", "cleanup"), operations)
    }

    @Test
    fun `authenticated presenter returns true only for an actual platform presentation`() {
        val callHandle = "00000000-0000-4000-8000-000000000499"
        val wakeHandle = "00000000-0000-4000-8000-000000000498"
        val captured = mutableListOf<CallWakePayload>()
        val present: (CallWakePayload) -> MknoonCallPresentationResult = { payload ->
            captured += payload
            MknoonCallPresentationResult.PRESENTED
        }

        assertTrue(
            presentAuthenticatedCall(
                callHandle = callHandle,
                expiresAtMs = 45_000L,
                observedNowMs = 1_000L,
                capabilityEnabled = true,
                handleGrammar = Regex("^[0-9a-f-]{36}$"),
                wakeHandle = { wakeHandle },
                present = present,
            ),
        )
        assertEquals(callHandle, captured.single().callHandle)
        assertEquals(wakeHandle, captured.single().wakeHandle)
        assertEquals(1_000L, captured.single().receivedAtMs)

        for (failure in listOf(
            MknoonCallPresentationResult.PERSISTENCE_FAILED,
            MknoonCallPresentationResult.PLATFORM_FAILED,
            MknoonCallPresentationResult.DISABLED,
        )) {
            assertFalse(
                presentAuthenticatedCall(
                    callHandle = callHandle,
                    expiresAtMs = 45_000L,
                    observedNowMs = 1_000L,
                    capabilityEnabled = true,
                    handleGrammar = Regex("^[0-9a-f-]{36}$"),
                    wakeHandle = { wakeHandle },
                    present = { failure },
                ),
            )
        }
    }

    @Test
    fun `authenticated terminal result validates identity and persists one reorder fence`() {
        val callHandle = "00000000-0000-4000-8000-000000000499"
        val terminalized = mutableListOf<Pair<UUID, Long>>()

        assertTrue(
            terminalizeAuthenticatedCall(
                callHandle = callHandle,
                expiresAtMs = 45_000L,
                observedNowMs = 1_000L,
                capabilityEnabled = true,
                handleGrammar = Regex("^[0-9a-f-]{36}$"),
                terminalize = { nativeCallId, expiresAtMs ->
                    terminalized += nativeCallId to expiresAtMs
                    true
                },
            ),
        )
        assertEquals(
            listOf(UUID.fromString(callHandle) to 45_000L),
            terminalized,
        )
        assertFalse(
            terminalizeAuthenticatedCall(
                callHandle = callHandle.uppercase(),
                expiresAtMs = 45_000L,
                observedNowMs = 1_000L,
                capabilityEnabled = true,
                handleGrammar = Regex("^[0-9a-f-]{36}$"),
                terminalize = { _, _ -> error("must not terminalize") },
            ),
        )
        assertFalse(
            terminalizeAuthenticatedCall(
                callHandle = callHandle,
                expiresAtMs = 1_000L,
                observedNowMs = 1_000L,
                capabilityEnabled = true,
                handleGrammar = Regex("^[0-9a-f-]{36}$"),
                terminalize = { _, _ -> error("must not terminalize") },
            ),
        )
    }
}
