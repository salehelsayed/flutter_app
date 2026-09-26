package com.mknoon.app.call

import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonCallLifecycleControllerTest {
    @Test
    fun `PCM observer sees only current adopted active audio owner and authoritative mute`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        var calls = 0
        fun observe(owner: UUID = id): String = rig.controller.withActiveAudioOwner(owner, "unavailable") { muted ->
            calls += 1
            if (muted) "muted" else "active"
        }
        assertEquals("unavailable", observe())
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.registerOutgoing(rig.payload))
        assertEquals("unavailable", observe())
        rig.controller.attach()
        assertTrue(rig.controller.markAdopted(id))
        assertTrue(rig.controller.acknowledge(id, requireNotNull(rig.controller.snapshot()).highestSequence, PendingNativeCallAcknowledgement.ADOPTED))
        assertEquals("unavailable", observe())
        assertTrue(rig.controller.activateAudio(id))
        assertEquals("active", observe())
        assertEquals("unavailable", observe(UUID.randomUUID()))
        assertTrue(rig.controller.onMuteChanged(id, true))
        assertEquals("muted", observe())
        assertTrue(rig.controller.endFromDart(id))
        assertEquals("unavailable", observe())
        assertEquals(2, calls)
    }

    @Test
    fun `diagnostic sink failure cannot change persisted native answer or audio admission`() {
        val rig = LifecycleRig(journalDiagnostic = { _, _ -> error("diagnostic sink unavailable") })
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(rig.controller.answer(rig.payload.nativeCallId))
        assertTrue(requireNotNull(rig.controller.snapshot()).answerRequested)
        assertEquals(0, rig.platform.startMicrophoneCalls)
        assertFalse(rig.controller.answer(rig.payload.nativeCallId))
        assertTrue(rig.controller.endFromDart(rig.payload.nativeCallId))
    }
    @Test
    fun `durable create and successful Telecom registration precede presentation side effects`() {
        val rig = LifecycleRig()

        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            rig.controller.present(rig.payload),
        )

        assertEquals(
            listOf(
                "store.create",
                "platform.registerIncoming",
                "store.append:PRESENTED",
                "platform.showIncoming",
                "platform.startForeground",
            ),
            rig.operations,
        )
        assertEquals(1, rig.store.createCalls)
        assertEquals(1, rig.platform.registerCalls)
        assertEquals(1, rig.platform.showIncomingCalls)
        assertEquals(1, rig.platform.startForegroundCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    // B5 (beta 2026-09-25): core-telecom's addCall may wait up to 5 s for Telecom,
    // longer on a loaded device. That wait must not hold the controller lock, which
    // main-thread readers take and, on some Telecom versions, the registration needs.

    @Test
    fun `controller reads do not wait while incoming Telecom registration is in flight`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            val reads = executor.submit<Boolean> {
                rig.controller.snapshot()
                rig.controller.activeNativeCallId()
                rig.controller.isCleanupPending(id)
                rig.controller.presentation(id)
                true
            }
            assertTrue(reads.get(1, TimeUnit.SECONDS))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertEquals(1, rig.platform.showIncomingCalls)
            assertEquals(1, rig.platform.startForegroundCalls)
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `controller reads do not wait while outgoing Telecom registration is in flight`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterOutgoing = hold::register
        val executor = Executors.newFixedThreadPool(2)
        try {
            val registering = executor.submit<MknoonCallPresentationResult> {
                rig.controller.registerOutgoing(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            val reads = executor.submit<Boolean> {
                rig.controller.snapshot()
                rig.controller.activeNativeCallId()
                true
            }
            assertTrue(reads.get(1, TimeUnit.SECONDS))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                registering.get(5, TimeUnit.SECONDS),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a call ended while its Telecom registration is in flight is never presented and the late registration is ended`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            val ended = executor.submit<Boolean> { rig.controller.endFromDart(id) }
            assertTrue(ended.get(1, TimeUnit.SECONDS))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.STALE,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertFalse(rig.operations.contains("store.append:PRESENTED"))
            assertEquals(0, rig.platform.showIncomingCalls)
            assertEquals(0, rig.platform.startForegroundCalls)
            assertTrue(
                rig.operations.lastIndexOf("platform.end") >
                    rig.operations.indexOf(HeldTelecomRegistration.RETURNED),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `an outgoing call ended while its Telecom registration is in flight is not registered and the late registration is ended`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterOutgoing = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val registering = executor.submit<MknoonCallPresentationResult> {
                rig.controller.registerOutgoing(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            val ended = executor.submit<Boolean> { rig.controller.endFromDart(id) }
            assertTrue(ended.get(1, TimeUnit.SECONDS))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.STALE,
                registering.get(5, TimeUnit.SECONDS),
            )
            assertFalse(rig.operations.contains("store.append:PRESENTED"))
            assertTrue(
                rig.operations.lastIndexOf("platform.end") >
                    rig.operations.indexOf(HeldTelecomRegistration.RETURNED),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `an app answer during registration waits and is applied after the presentation`() {
        // Dart shows Answer once the call is validated, before the native presentation.
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))
            assertTrue(rig.controller.isRegistrationInFlight(id))

            val answered = executor.submit<Boolean> { rig.controller.answer(id) }
            Thread.sleep(200L)
            assertFalse(answered.isDone)

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertTrue(answered.get(5, TimeUnit.SECONDS))
            assertFalse(rig.controller.isRegistrationInFlight(id))
            assertEquals(1, rig.platform.answerCalls)
            assertTrue(
                rig.operations.indexOf("store.append:PRESENTED") <
                    rig.operations.indexOf("store.append:ANSWER_REQUESTED"),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a caller display update sent during registration survives the presentation`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val initial = MknoonIncomingCallDisplay("Initial contact", byteArrayOf(7), true)
        val update = MknoonIncomingCallDisplay("Updated contact", byteArrayOf(9), true).toRingingMetadata()
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload, initial)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))
            assertTrue(
                executor.submit<Boolean> { rig.controller.updatePresentation(id, update) }
                    .get(1, TimeUnit.SECONDS),
            )

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertEquals("Updated contact", rig.controller.presentation(id)?.displayName)
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a late Telecom end that fails is kept as pending cleanup and retried`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))
            assertTrue(executor.submit<Boolean> { rig.controller.endFromDart(id) }.get(1, TimeUnit.SECONDS))
            assertFalse(rig.controller.isCleanupPending(id))

            // Telecom registers the ended call; ending that late registration fails once.
            rig.platform.endFailuresRemaining = 1
            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.STALE,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertTrue(rig.controller.isCleanupPending(id))
            assertTrue(rig.cleanupPending.contains(id))

            assertTrue(rig.controller.retryCleanup(id))
            assertFalse(rig.controller.isCleanupPending(id))
            assertEquals(3, rig.platform.endCalls)
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a Telecom answer that arrives during registration is applied after the presentation`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newFixedThreadPool(2)
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            val answered = executor.submit<Boolean> { rig.controller.answerFromTelecom(id) }
            Thread.sleep(200L)
            assertFalse(answered.isDone)

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertTrue(answered.get(5, TimeUnit.SECONDS))
            assertTrue(
                rig.operations.indexOf("store.append:PRESENTED") <
                    rig.operations.indexOf("store.append:ANSWER_REQUESTED"),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    private fun recreatedOver(rig: LifecycleRig, platform: LifecycleFakePlatform, isMainThread: () -> Boolean = { false }) =
        MknoonCallLifecycleController(
            store = rig.store,
            platform = platform,
            eventSink = LifecycleFakeEventSink(rig.operations),
            capabilityEnabled = { true },
            recordAudioPermissionGranted = { true },
            nowMs = { NOW_MS },
            isMainThread = isMainThread,
        )

    @Test
    fun `new presentation and restart re-registration both wait past core-telecom`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertEquals(MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS, rig.platform.lastRegistrationTimeoutMs)

        // B8: restart re-registration no longer holds the lock or runs on main, so it
        // needs no shorter bound.
        val recreatedPlatform = LifecycleFakePlatform(rig.operations)
        val recreated = recreatedOver(rig, recreatedPlatform)
        assertTrue(recreated.reconcilePresented())
        assertEquals(MKNOON_TELECOM_REGISTRATION_TIMEOUT_MS, recreatedPlatform.lastRegistrationTimeoutMs)
    }

    // B8 (review of B5, 2026-09-26): the runtime is created on main and restored a
    // presented call there, holding the controller lock for the whole Telecom wait.
    // Below Android 14 Telecom needs main to finish that registration, so it could
    // only time out and the restored call failed.

    @Test
    fun `restart re-registration runs without the controller lock on the thread it is handed`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        val recreatedPlatform = LifecycleFakePlatform(rig.operations)
        val hold = HeldTelecomRegistration()
        recreatedPlatform.onRegisterIncoming = hold::register
        val recreated = recreatedOver(rig, recreatedPlatform)
        val executor = Executors.newSingleThreadExecutor()
        try {
            var restoring: java.util.concurrent.Future<*>? = null
            assertTrue(recreated.reconcilePresented { work -> restoring = executor.submit(work) })
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            // The caller (main, in the runtime constructor) has control back and the lock is free.
            assertTrue(recreated.isRegistrationInFlight(id))
            assertEquals(id, recreated.activeNativeCallId())
            assertNotNull(recreated.snapshot())

            hold.finish(registered = true)
            requireNotNull(restoring).get(5, TimeUnit.SECONDS)
            assertFalse(recreated.isRegistrationInFlight(id))
            assertEquals(1, recreatedPlatform.startForegroundCalls)
            assertFalse(recreated.hasTerminalLifecycle(id))
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a failed restart re-registration still fails the restored call`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        val recreatedPlatform = LifecycleFakePlatform(rig.operations)
        val hold = HeldTelecomRegistration()
        recreatedPlatform.onRegisterIncoming = hold::register
        val recreated = recreatedOver(rig, recreatedPlatform)
        val executor = Executors.newSingleThreadExecutor()
        try {
            var restoring: java.util.concurrent.Future<*>? = null
            assertTrue(recreated.reconcilePresented { work -> restoring = executor.submit(work) })
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))
            hold.finish(registered = false)
            requireNotNull(restoring).get(5, TimeUnit.SECONDS)
            assertTrue(recreated.hasTerminalLifecycle(id))
            assertEquals(
                PendingNativeCallEventType.NATIVE_FAILURE,
                requireNotNull(rig.store.lastDescriptor).terminalEvent?.type,
            )
            assertEquals(0, recreatedPlatform.startForegroundCalls)
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a main-thread answer during registration is applied when the registration settles`() {
        // Notification action or lock-screen Answer: main must never wait for Telecom.
        val rig = LifecycleRig(isMainThread = { true })
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newSingleThreadExecutor()
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            assertTrue(rig.controller.answer(id))
            assertEquals(0, rig.platform.answerCalls)
            assertFalse(rig.operations.contains("store.append:ANSWER_REQUESTED"))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertEquals(1, rig.platform.answerCalls)
            assertTrue(
                rig.operations.indexOf("store.append:PRESENTED") <
                    rig.operations.indexOf("store.append:ANSWER_REQUESTED"),
            )
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a Telecom answer delivered on main during registration is applied when it settles`() {
        // Below Android 14 core-telecom's ConnectionService callbacks arrive on main.
        val rig = LifecycleRig(isMainThread = { true })
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val id = rig.payload.nativeCallId
        val executor = Executors.newSingleThreadExecutor()
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))

            assertTrue(rig.controller.answerFromTelecom(id))
            assertFalse(rig.operations.contains("store.append:ANSWER_REQUESTED"))

            hold.finish(registered = true)
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertTrue(requireNotNull(rig.store.lastDescriptor).answerRequested)
            assertEquals(0, rig.platform.answerCalls)
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `a failed Telecom registration still fails the call after the unlocked wait`() {
        val rig = LifecycleRig()
        val hold = HeldTelecomRegistration()
        rig.platform.onRegisterIncoming = hold::register
        val executor = Executors.newSingleThreadExecutor()
        try {
            val presenting = executor.submit<MknoonCallPresentationResult> {
                rig.controller.present(rig.payload)
            }
            assertTrue(hold.started.await(5, TimeUnit.SECONDS))
            hold.finish(registered = false)
            assertEquals(
                MknoonCallPresentationResult.PLATFORM_FAILED,
                presenting.get(5, TimeUnit.SECONDS),
            )
            assertTrue(rig.operations.contains("store.append:NATIVE_FAILURE"))
            assertEquals(0, rig.platform.showIncomingCalls)
            assertNull(rig.controller.presentation(rig.payload.nativeCallId))
        } finally {
            hold.finish(registered = false)
            executor.shutdownNow()
        }
    }

    @Test
    fun `authenticated initial display is visible before first incoming notification without audio admission`() {
        val rig = LifecycleRig()
        val initial = MknoonIncomingCallDisplay("Known contact", byteArrayOf(7), true)
        var notificationMetadata: MknoonLockedCallMetadata? = null
        rig.platform.onShowIncoming = { id ->
            assertEquals(rig.payload.nativeCallId, id)
            assertEquals(1, rig.store.createCalls)
            assertEquals(1, rig.platform.registerCalls)
            assertEquals(PendingNativeCallEventType.PRESENTED, rig.controller.snapshot()!!.events.last().type)
            notificationMetadata = rig.controller.presentation(id)
        }

        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload, initial))
        val visible = requireNotNull(notificationMetadata)
        assertEquals("Known contact", visible.displayName)
        assertEquals(7.toByte(), visible.avatarPng!![0])
        initial.avatarPng!![0] = 8
        assertEquals(7.toByte(), visible.avatarPng[0])
        assertTrue(visible.light)
        assertEquals("ringing", visible.state)
        assertNull(visible.connectedAtMs)
        assertFalse(visible.muted)
        assertFalse(visible.muteAvailable)
        assertFalse(visible.speakerOn)
        assertFalse(visible.speakerAvailable)
        assertEquals("", visible.routeLabel)
        assertFalse(rig.controller.snapshot()!!.answerRequested)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    @Test
    fun `duplicate or busy initial display cannot overwrite exact call foreground presentation`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        val initial = MknoonIncomingCallDisplay("Initial contact", null, true)
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload, initial))
        val foreground = initial.toRingingMetadata().copy(
            displayName = "Foreground contact", state = "connected", connectedAtMs = NOW_MS,
            light = false, muted = true, muteAvailable = true,
        )
        assertTrue(rig.controller.updatePresentation(id, foreground))
        val descriptor = requireNotNull(rig.controller.snapshot())
        rig.store.createOverride = PendingNativeCallCreateResult.Duplicate(descriptor)
        val staleDisplay = MknoonIncomingCallDisplay("Stale contact", null, true)
        assertEquals(MknoonCallPresentationResult.DUPLICATE, rig.controller.present(rig.payload, staleDisplay))
        assertEquals(foreground, rig.controller.presentation(id))

        val other = rig.payload.copy(nativeCallId = UUID.fromString(OTHER_CALL_ID), callHandle = OTHER_CALL_ID)
        rig.store.createOverride = PendingNativeCallCreateResult.Busy(descriptor)
        assertEquals(MknoonCallPresentationResult.BUSY, rig.controller.present(other, staleDisplay))
        assertEquals(foreground, rig.controller.presentation(id))
        assertNull(rig.controller.presentation(other.nativeCallId))
        assertEquals(1, rig.platform.showIncomingCalls)
        assertEquals(1, rig.platform.registerCalls)
    }

    @Test
    fun `terminal cleanup clears initial display and a replay cannot seed the successor`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        val initial = MknoonIncomingCallDisplay("First contact", null, true)
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload, initial))
        assertTrue(rig.controller.endFromDart(id))
        assertNull(rig.controller.presentation(id))
        val terminal = requireNotNull(rig.controller.snapshot())
        assertTrue(rig.controller.acknowledge(id, terminal.highestSequence, PendingNativeCallAcknowledgement.TERMINAL))

        val successor = rig.payload.copy(nativeCallId = UUID.fromString(OTHER_CALL_ID), callHandle = OTHER_CALL_ID)
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(successor))
        assertNull(rig.controller.presentation(successor.nativeCallId))
        assertEquals(MknoonCallPresentationResult.DUPLICATE, rig.controller.present(rig.payload, initial))
        assertNull(rig.controller.presentation(successor.nativeCallId))
        assertNull(rig.controller.presentation(id))
        assertEquals(2, rig.platform.showIncomingCalls)
    }

    @Test
    fun `initial display does not bypass disabled expired persistence or platform gates`() {
        val initial = MknoonIncomingCallDisplay("Known contact", null, true)
        val cases = listOf(
            LifecycleRig(capabilityEnabled = false) to MknoonCallPresentationResult.DISABLED,
            LifecycleRig().apply { store.createOverride = PendingNativeCallCreateResult.PersistenceFailure } to
                MknoonCallPresentationResult.PERSISTENCE_FAILED,
            LifecycleRig().apply { platform.registrationSucceeds = false } to MknoonCallPresentationResult.PLATFORM_FAILED,
            LifecycleRig().apply { store.appendFailuresRemaining = 1 } to MknoonCallPresentationResult.PERSISTENCE_FAILED,
        )
        for ((rig, expected) in cases) {
            assertEquals(expected, rig.controller.present(rig.payload, initial))
            assertNull(rig.controller.presentation(rig.payload.nativeCallId))
            assertEquals(0, rig.platform.showIncomingCalls)
        }
        val expired = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.STALE,
            expired.controller.present(expired.payload.copy(expiresAtMs = NOW_MS), initial))
        assertNull(expired.controller.presentation(expired.payload.nativeCallId))
        assertEquals(0, expired.platform.showIncomingCalls)
    }

    @Test
    fun `outgoing registration is durable and Telecom bound before Dart can activate media`() {
        val rig = LifecycleRig()

        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            rig.controller.registerOutgoing(rig.payload),
        )
        assertEquals(
            listOf(
                "store.createOutgoing",
                "platform.registerOutgoing",
                "store.append:PRESENTED",
            ),
            rig.operations,
        )
        assertEquals(
            PendingNativeCallDirection.OUTGOING,
            requireNotNull(rig.controller.snapshot()).direction,
        )
        assertEquals(1, rig.platform.registerOutgoingCalls)
        assertEquals(0, rig.platform.registerCalls)
        assertEquals(0, rig.platform.showIncomingCalls)
        assertEquals(0, rig.platform.startForegroundCalls)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)

        assertEquals(
            MknoonCallPresentationResult.DUPLICATE,
            rig.controller.registerOutgoing(rig.payload),
        )
        assertEquals(1, rig.platform.registerOutgoingCalls)

        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        val adoptionSequence = requireNotNull(rig.controller.snapshot()).highestSequence
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                adoptionSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertTrue(
            rig.operations.indexOf("platform.registerOutgoing") <
                rig.operations.indexOf("platform.requestAudioFocus"),
        )

        assertTrue(rig.controller.endFromDart(rig.payload.nativeCallId))
        assertTrue(rig.controller.endFromDart(rig.payload.nativeCallId))
        assertEquals(1, rig.platform.endCalls)
        assertEquals(1, rig.platform.stopEndpointUpdatesCalls)
        assertEquals(1, rig.platform.abandonAudioFocusCalls)
        assertEquals(1, rig.platform.cancelNotificationCalls)
        assertEquals(1, rig.platform.stopForegroundCalls)
    }

    @Test
    fun `recreated presented outgoing descriptor re-registers as outgoing without incoming UI`() {
        val rig = LifecycleRig()
        val presented = PendingNativeCallEvent(
            nativeCallId = rig.payload.nativeCallId,
            sequence = 1L,
            eventId = UUID(0L, 1L),
            type = PendingNativeCallEventType.PRESENTED,
        )
        rig.store.lastDescriptor = descriptorFor(rig.payload).copy(
            direction = PendingNativeCallDirection.OUTGOING,
            highestSequence = 1L,
            events = listOf(presented),
        )

        assertTrue(rig.controller.reconcilePresented())
        assertEquals(listOf("platform.registerOutgoing"), rig.operations)
        assertEquals(1, rig.platform.registerOutgoingCalls)
        assertEquals(0, rig.platform.registerCalls)
        assertEquals(0, rig.platform.showIncomingCalls)
        assertEquals(0, rig.platform.startForegroundCalls)
    }

    @Test
    fun `persistence or Telecom registration failure suppresses notification and service`() {
        val persistenceFailure = LifecycleRig().apply {
            store.createOverride = PendingNativeCallCreateResult.PersistenceFailure
        }

        assertEquals(
            MknoonCallPresentationResult.PERSISTENCE_FAILED,
            persistenceFailure.controller.present(persistenceFailure.payload),
        )
        assertEquals(listOf("store.create"), persistenceFailure.operations)
        assertEquals(0, persistenceFailure.platform.registerCalls)
        assertEquals(0, persistenceFailure.platform.showIncomingCalls)
        assertEquals(0, persistenceFailure.platform.startForegroundCalls)

        val platformFailure = LifecycleRig().apply {
            platform.registrationSucceeds = false
        }

        assertEquals(
            MknoonCallPresentationResult.PLATFORM_FAILED,
            platformFailure.controller.present(platformFailure.payload),
        )
        assertEquals(
            listOf(
                "store.create",
                "platform.registerIncoming",
                "store.append:NATIVE_FAILURE",
                "platform.stopIncomingRinger",
                "platform.stopEndpointUpdates",
                "platform.abandonAudioFocus",
                "platform.end",
                "platform.cancelNotification",
                "platform.stopForeground",
            ),
            platformFailure.operations,
        )
        assertEquals(
            PendingNativeCallEventType.NATIVE_FAILURE,
            requireNotNull(platformFailure.store.lastDescriptor).terminalEvent?.type,
        )
        assertEquals(0, platformFailure.platform.showIncomingCalls)
        assertEquals(0, platformFailure.platform.startForegroundCalls)
    }

    @Test
    fun `duplicate and busy results never register a second Telecom call`() {
        val duplicate = LifecycleRig()
        val existing = descriptorFor(duplicate.payload)
        duplicate.store.createOverride = PendingNativeCallCreateResult.Duplicate(existing)

        assertEquals(
            MknoonCallPresentationResult.DUPLICATE,
            duplicate.controller.present(duplicate.payload),
        )
        assertEquals(0, duplicate.platform.registerCalls)

        val busy = LifecycleRig()
        val other = descriptorFor(
            busy.payload.copy(nativeCallId = UUID.fromString(OTHER_CALL_ID)),
        )
        busy.store.createOverride = PendingNativeCallCreateResult.Busy(other)

        assertEquals(
            MknoonCallPresentationResult.BUSY,
            busy.controller.present(busy.payload),
        )
        assertEquals(0, busy.platform.registerCalls)
        assertEquals(0, busy.platform.showIncomingCalls)
        assertEquals(0, busy.platform.startForegroundCalls)
    }

    @Test
    fun `default-off capability and stale payload perform no durable or presentation work`() {
        val disabled = LifecycleRig(capabilityEnabled = false)

        assertEquals(
            MknoonCallPresentationResult.DISABLED,
            disabled.controller.present(disabled.payload),
        )
        assertEquals(
            MknoonCallPresentationResult.DISABLED,
            disabled.controller.registerOutgoing(disabled.payload),
        )
        assertTrue(disabled.operations.isEmpty())

        val stale = LifecycleRig()
        val expired = stale.payload.copy(expiresAtMs = NOW_MS)

        assertEquals(
            MknoonCallPresentationResult.STALE,
            stale.controller.present(expired),
        )
        assertTrue(stale.operations.isEmpty())
    }

    @Test
    fun `answer is persisted before platform and Dart delivery and never starts audio`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.operations.clear()

        assertTrue(rig.controller.answer(rig.payload.nativeCallId))
        assertFalse(rig.controller.answer(rig.payload.nativeCallId))

        assertEquals(
            listOf(
                "store.append:ANSWER_REQUESTED",
                "platform.stopIncomingRinger",
                "platform.answer",
            ),
            rig.operations,
        )
        assertEquals(1, rig.platform.stopIncomingRingerCalls)
        assertTrue(rig.eventSink.events.isEmpty())
        assertEquals(0, rig.platform.startMicrophoneCalls)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startEndpointUpdatesCalls)

        val attachment = rig.controller.attach()
        assertNotNull(attachment)
        assertEquals(
            1,
            rig.eventSink.events.count {
                it.type == PendingNativeCallEventType.ANSWER_REQUESTED
            },
        )
        assertEquals(
            1,
            requireNotNull(attachment).deliverableEvents.count {
                it.type == PendingNativeCallEventType.ANSWER_REQUESTED
            },
        )
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    @Test
    fun `Telecom answer stops incoming ringtone after durable answer persistence`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.operations.clear()

        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))

        assertEquals(
            listOf(
                "store.append:ANSWER_REQUESTED",
                "platform.stopIncomingRinger",
            ),
            rig.operations,
        )
        assertEquals(1, rig.platform.stopIncomingRingerCalls)
        assertEquals(0, rig.platform.answerCalls)
    }

    @Test
    fun `successful platform answer marks Telecom active before Dart starts media`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                requireNotNull(rig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        rig.operations.clear()
        rig.eventSink.events.clear()
        rig.platform.onAnswer = {
            assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        }

        assertTrue(rig.controller.answer(rig.payload.nativeCallId))
        assertTrue(rig.controller.activateAudio(rig.payload.nativeCallId))

        assertEquals(1, rig.platform.answerCalls)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(1, rig.platform.startEndpointUpdatesCalls)
        assertEquals(1, rig.platform.startMicrophoneCalls)
        assertEquals(
            1,
            requireNotNull(rig.controller.snapshot()).events.count {
                it.type == PendingNativeCallEventType.ANSWER_REQUESTED
            },
        )
        assertEquals(
            1,
            rig.eventSink.events.count {
                it.type == PendingNativeCallEventType.ANSWER_REQUESTED
            },
        )
        assertEquals(
            listOf(
                MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SKIP_ALREADY_ACTIVE,
                MknoonCallLifecycleDiagnostic.DART_ACTIVATE_COMPLETED,
            ),
            rig.diagnosticSink.diagnostics,
        )
    }

    // Plan 404 (device 2026-09-05 17:44Z): a headlessly presented call declined
    // from the notification never answered the caller; the iPhone rang back
    // until its own cancel. A decline with no adopted Dart lifecycle hands the
    // ended descriptor to the headless decline reply exactly once.
    @Test
    fun `a native decline without a Dart owner schedules one headless decline reply`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.DECLINE_REQUESTED,
            ),
        )
        assertFalse(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.DECLINE_REQUESTED,
            ),
        )
        assertEquals(
            listOf(rig.payload.nativeCallId),
            rig.declineReplies.map { it.nativeCallId },
        )
        assertEquals(rig.payload.expiresAtMs, rig.declineReplies.single().expiresAtMs)
        assertEquals(rig.payload.wakeHandle, rig.declineReplies.single().wakeHandle)
        // A reply nobody accepted releases the foreground service as usual.
        assertTrue(rig.operations.contains("platform.stopForeground"))

        // Plan 404 (c), device 2026-09-05 18:46Z: the STOP queued by cleanup
        // tore the service down before the reply's START_ADMISSION behind it
        // was delivered, so the reply ran at background priority (9 s). An
        // accepted reply is asked before native cleanup and keeps the
        // foreground service; the reply run releases it.
        val acceptedRig = LifecycleRig().apply { declineReplyAccepted = true }
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            acceptedRig.controller.present(acceptedRig.payload),
        )
        assertTrue(
            acceptedRig.controller.terminate(
                acceptedRig.payload.nativeCallId,
                PendingNativeCallEventType.DECLINE_REQUESTED,
            ),
        )
        assertEquals(1, acceptedRig.declineReplies.size)
        assertFalse(acceptedRig.operations.contains("platform.stopForeground"))
        assertTrue(acceptedRig.operations.contains("platform.end"))
        assertTrue(acceptedRig.operations.contains("platform.cancelNotification"))
        assertTrue(acceptedRig.declineReplyAtOperation >= 0)
        assertTrue(
            acceptedRig.declineReplyAtOperation <= acceptedRig.operations.indexOf("platform.end"),
        )
        assertNull(acceptedRig.controller.activeNativeCallId())

        for (
            other in listOf(
                PendingNativeCallEventType.END_REQUESTED,
                PendingNativeCallEventType.REMOTE_CANCELLED,
                PendingNativeCallEventType.PROVIDER_REMOVED,
                PendingNativeCallEventType.EXPIRED,
            )
        ) {
            val otherRig = LifecycleRig()
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                otherRig.controller.present(otherRig.payload),
            )
            otherRig.controller.terminate(otherRig.payload.nativeCallId, other)
            assertTrue(otherRig.declineReplies.isEmpty())
        }

        val adoptedRig = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            adoptedRig.controller.present(adoptedRig.payload),
        )
        assertNotNull(adoptedRig.controller.attach())
        assertTrue(adoptedRig.controller.markAdopted(adoptedRig.payload.nativeCallId))
        adoptedRig.controller.terminate(
            adoptedRig.payload.nativeCallId,
            PendingNativeCallEventType.DECLINE_REQUESTED,
        )
        assertTrue(adoptedRig.declineReplies.isEmpty())
    }

    @Test
    fun `every terminal source dominates answer and cleans native resources exactly once`() {
        val terminalTypes = listOf(
            PendingNativeCallEventType.DECLINE_REQUESTED,
            PendingNativeCallEventType.END_REQUESTED,
            PendingNativeCallEventType.PROVIDER_REMOVED,
            PendingNativeCallEventType.REMOTE_CANCELLED,
            PendingNativeCallEventType.EXPIRED,
        )

        for (terminalType in terminalTypes) {
            val rig = LifecycleRig()
            assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
            assertTrue(rig.controller.answer(rig.payload.nativeCallId))

            assertTrue(rig.controller.terminate(rig.payload.nativeCallId, terminalType))
            assertFalse(rig.controller.terminate(rig.payload.nativeCallId, terminalType))
            assertFalse(rig.controller.answer(rig.payload.nativeCallId))

            val attachment = requireNotNull(rig.controller.attach())
            assertEquals(
                listOf(
                    PendingNativeCallEventType.PRESENTED,
                    PendingNativeCallEventType.ANSWER_REQUESTED,
                    terminalType,
                ),
                attachment.descriptor.events.map { it.type },
            )
            assertEquals(
                listOf(terminalType),
                attachment.deliverableEvents.map { it.type },
            )
            assertEquals(listOf(terminalType), rig.eventSink.events.map { it.type })
            assertEquals(1, rig.platform.cancelNotificationCalls)
            assertEquals(1, rig.platform.stopForegroundCalls)
            assertEquals(1, rig.platform.abandonAudioFocusCalls)
            assertEquals(1, rig.platform.stopEndpointUpdatesCalls)
            assertEquals(2, rig.platform.stopIncomingRingerCalls)
        }
    }

    @Test
    fun `Dart end and Telecom end each cross the ownership boundary exactly once`() {
        val dartEnd = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            dartEnd.controller.present(dartEnd.payload),
        )
        dartEnd.controller.attach()
        dartEnd.eventSink.events.clear()

        assertTrue(dartEnd.controller.endFromDart(dartEnd.payload.nativeCallId))
        assertTrue(dartEnd.controller.endFromDart(dartEnd.payload.nativeCallId))
        assertFalse(dartEnd.controller.endFromTelecom(dartEnd.payload.nativeCallId))
        assertEquals(1, dartEnd.platform.endCalls)
        assertEquals(
            1,
            requireNotNull(dartEnd.store.lastDescriptor).events.count {
                it.type == PendingNativeCallEventType.END_REQUESTED
            },
        )

        val telecomEnd = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            telecomEnd.controller.present(telecomEnd.payload),
        )
        telecomEnd.controller.attach()
        telecomEnd.eventSink.events.clear()

        assertTrue(telecomEnd.controller.endFromTelecom(telecomEnd.payload.nativeCallId))
        assertFalse(telecomEnd.controller.endFromTelecom(telecomEnd.payload.nativeCallId))
        assertEquals(0, telecomEnd.platform.endCalls)
        assertEquals(
            listOf(PendingNativeCallEventType.PROVIDER_REMOVED),
            telecomEnd.eventSink.events.map { it.type },
        )
    }

    @Test
    fun `incoming audio activation requires durable adoption permission and answer`() {
        val rig = LifecycleRig(recordAudioGranted = false)
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))

        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        val adoptionSequence = requireNotNull(rig.store.lastDescriptor).highestSequence
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                adoptionSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertEquals(0, rig.platform.startMicrophoneCalls)

        rig.recordAudioGranted = true
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)

        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        rig.platform.onRequestAudioFocus = {
            assertTrue(rig.controller.activateAudioFromTelecom(rig.payload.nativeCallId))
        }
        assertTrue(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))

        assertEquals(1, rig.platform.requestAudioFocusCalls)
        assertEquals(1, rig.platform.startEndpointUpdatesCalls)
        assertEquals(1, rig.platform.startMicrophoneCalls)
        assertEquals(
            PendingNativeCallPhase.JOURNAL,
            requireNotNull(rig.controller.snapshot()).phase,
        )
        assertEquals(
            1,
            rig.eventSink.events.count {
                it.type == PendingNativeCallEventType.AUDIO_ACTIVATED
            },
        )
        assertEquals(
            listOf(
                MknoonCallLifecycleDiagnostic.SET_ACTIVE_ACCEPTED_AFTER_DART,
                MknoonCallLifecycleDiagnostic.DART_ACTIVATE_COMPLETED,
            ),
            rig.diagnosticSink.diagnostics,
        )
    }

    @Test
    fun `answer associated early Core active is buffered until Dart activates media`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                requireNotNull(rig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )

        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        assertTrue(rig.controller.activateAudioFromTelecom(rig.payload.nativeCallId))
        assertNull(requireNotNull(rig.controller.snapshot()).terminalEvent)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(0, rig.platform.startEndpointUpdatesCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)

        assertTrue(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertNull(requireNotNull(rig.controller.snapshot()).terminalEvent)
        assertEquals(0, rig.platform.requestAudioFocusCalls)
        assertEquals(1, rig.platform.startEndpointUpdatesCalls)
        assertEquals(1, rig.platform.startMicrophoneCalls)
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertEquals(1, rig.platform.startEndpointUpdatesCalls)
        assertEquals(1, rig.platform.startMicrophoneCalls)
        assertEquals(
            listOf(
                MknoonCallLifecycleDiagnostic.SET_ACTIVE_BUFFERED_AFTER_ANSWER,
                MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SKIP_ALREADY_ACTIVE,
                MknoonCallLifecycleDiagnostic.DART_ACTIVATE_COMPLETED,
            ),
            rig.diagnosticSink.diagnostics,
        )
    }

    @Test
    fun `answered active to inactive transition stays ringtone ineligible`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                requireNotNull(rig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        rig.platform.onRequestAudioFocus = {
            assertTrue(rig.controller.activateAudioFromTelecom(rig.payload.nativeCallId))
        }

        assertTrue(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertTrue(rig.controller.deactivateAudio(rig.payload.nativeCallId))

        val descriptor = requireNotNull(rig.controller.snapshot())
        assertTrue(descriptor.answerRequested)
        assertFalse(
            isIncomingRingtoneEligible(
                descriptor,
                rig.payload.nativeCallId,
                NOW_MS,
            ),
        )
    }

    @Test
    fun `mute route and audio callbacks append one monotonic native event stream`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.controller.attach()
        rig.eventSink.events.clear()

        assertTrue(rig.controller.onMuteChanged(rig.payload.nativeCallId, muted = true))
        assertTrue(rig.controller.onRouteChanged(rig.payload.nativeCallId, route = "speaker"))
        assertTrue(rig.controller.onAudioActivationChanged(rig.payload.nativeCallId, active = true))
        assertTrue(rig.controller.onAudioActivationChanged(rig.payload.nativeCallId, active = false))

        val callbackEvents = requireNotNull(rig.store.lastDescriptor).events.takeLast(4)
        assertEquals(
            listOf(
                PendingNativeCallEventType.MUTE_CHANGED,
                PendingNativeCallEventType.ROUTE_CHANGED,
                PendingNativeCallEventType.AUDIO_ACTIVATED,
                PendingNativeCallEventType.AUDIO_DEACTIVATED,
            ),
            callbackEvents.map { it.type },
        )
        assertEquals(
            callbackEvents.map { it.sequence },
            callbackEvents.map { it.sequence }.sorted(),
        )
        assertEquals(
            callbackEvents.map { it.sequence }.distinct().size,
            callbackEvents.size,
        )
        assertEquals(callbackEvents, rig.eventSink.events)
    }

    @Test
    fun `endpoint inventory changes notify Dart even when the selected route is unchanged`() {
        val rig = LifecycleRig()
        val callId = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.onRouteChanged(callId, "speaker"))
        assertTrue(rig.controller.onAvailableRoutesChanged(callId, listOf("speaker", "earpiece")))
        rig.eventSink.events.clear()
        val sequenceBefore = requireNotNull(rig.controller.snapshot()).highestSequence

        assertTrue(
            rig.controller.onAvailableRoutesChanged(
                callId,
                listOf("speaker", "earpiece", "bluetooth", "bluetooth", "invalid"),
            ),
        )

        val added = rig.eventSink.events.single()
        assertEquals(PendingNativeCallEventType.ROUTE_CHANGED, added.type)
        assertEquals(sequenceBefore + 1L, added.sequence)
        assertEquals("speaker", rig.controller.audioState().route)
        assertEquals(listOf("speaker", "earpiece", "bluetooth"), rig.controller.audioState().availableRoutes)
        assertFalse(
            rig.controller.onAvailableRoutesChanged(callId, listOf("speaker", "earpiece", "bluetooth")),
        )
        assertEquals(1, rig.eventSink.events.size)

        assertTrue(rig.controller.onAvailableRoutesChanged(callId, listOf("speaker", "earpiece")))
        assertEquals(listOf("speaker", "earpiece"), rig.controller.audioState().availableRoutes)
        assertEquals(listOf(added.sequence, added.sequence + 1L), rig.eventSink.events.map { it.sequence })
    }

    @Test
    fun `endpoint inventory publishes only after durable journal append and rejects stale callbacks`() {
        val rig = LifecycleRig()
        val callId = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.onAvailableRoutesChanged(callId, listOf("speaker")))
        rig.eventSink.events.clear()
        rig.store.appendFailuresRemaining = 1

        assertFalse(rig.controller.onAvailableRoutesChanged(callId, listOf("speaker", "bluetooth")))
        assertEquals(listOf("speaker"), rig.controller.audioState().availableRoutes)
        assertTrue(rig.eventSink.events.isEmpty())
        assertTrue(rig.controller.onAvailableRoutesChanged(callId, listOf("speaker", "bluetooth")))
        assertEquals(1, rig.eventSink.events.size)
        rig.eventSink.events.clear()
        assertFalse(
            rig.controller.onAvailableRoutesChanged(UUID.fromString(OTHER_CALL_ID), listOf("earpiece")),
        )
        assertEquals(listOf("speaker", "bluetooth"), rig.controller.audioState().availableRoutes)
        assertTrue(rig.eventSink.events.isEmpty())

        assertTrue(rig.controller.endFromDart(callId))
        rig.eventSink.events.clear()
        assertFalse(rig.controller.onAvailableRoutesChanged(callId, listOf("bluetooth")))
        assertTrue(rig.controller.audioState().availableRoutes.isEmpty())
        assertTrue(rig.eventSink.events.isEmpty())
    }

    @Test
    fun `initial outgoing Telecom unmute is durably journaled once and duplicate is deduped`() {
        val rig = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            rig.controller.registerOutgoing(rig.payload),
        )
        assertNotNull(rig.controller.attach())
        rig.eventSink.events.clear()
        val before = requireNotNull(rig.store.lastDescriptor)

        assertTrue(rig.controller.onMuteChanged(rig.payload.nativeCallId, muted = false))
        assertFalse(rig.controller.onMuteChanged(rig.payload.nativeCallId, muted = false))

        val after = requireNotNull(rig.store.lastDescriptor)
        val muteEvents = after.events.filter {
            it.type == PendingNativeCallEventType.MUTE_CHANGED
        }
        val persisted = muteEvents.single()
        assertEquals(before.highestSequence + 1L, persisted.sequence)
        assertEquals(before.highestSequence + 1L, after.highestSequence)
        assertEquals(listOf(persisted), rig.eventSink.events)
        assertEquals(
            1,
            rig.operations.count {
                it == "store.append:${PendingNativeCallEventType.MUTE_CHANGED}"
            },
        )
    }

    @Test
    fun `durable adoption settles ring expiry and rejects a late expiry callback`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertEquals(listOf(rig.payload.nativeCallId to rig.payload.expiresAtMs), rig.presented)
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        val adoptionSequence = requireNotNull(rig.store.lastDescriptor).highestSequence

        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                adoptionSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertEquals(listOf(rig.payload.nativeCallId), rig.settled)
        assertFalse(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.EXPIRED,
            ),
        )
        assertEquals(listOf(rig.payload.nativeCallId), rig.settled)
        assertTrue(
            rig.eventSink.events.none { it.type == PendingNativeCallEventType.EXPIRED },
        )
    }

    @Test
    fun `every terminal source settles once and duplicate cleanup never reschedules`() {
        val terminalTypes = listOf(
            PendingNativeCallEventType.DECLINE_REQUESTED,
            PendingNativeCallEventType.END_REQUESTED,
            PendingNativeCallEventType.REMOTE_CANCELLED,
            PendingNativeCallEventType.EXPIRED,
            PendingNativeCallEventType.PROVIDER_REMOVED,
            PendingNativeCallEventType.NATIVE_FAILURE,
        )
        for (type in terminalTypes) {
            val rig = LifecycleRig()
            assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
            assertTrue(type.name, rig.controller.terminate(rig.payload.nativeCallId, type))
            assertEquals(type.name, 1, rig.platform.stopIncomingRingerCalls)
            assertEquals(type.name, listOf(rig.payload.nativeCallId), rig.settled)
            assertFalse(type.name, rig.controller.terminate(rig.payload.nativeCallId, type))
            assertEquals(type.name, listOf(rig.payload.nativeCallId), rig.settled)
        }

        val registrationFailure = LifecycleRig().apply {
            platform.registrationSucceeds = false
        }
        assertEquals(
            MknoonCallPresentationResult.PLATFORM_FAILED,
            registrationFailure.controller.present(registrationFailure.payload),
        )
        assertEquals(
            listOf(registrationFailure.payload.nativeCallId),
            registrationFailure.settled,
        )
    }

    @Test
    fun `ringtone stop failures never block answer or terminal cleanup`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.platform.stopIncomingRingerFailuresRemaining = 2

        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        assertTrue(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )

        assertEquals(2, rig.platform.stopIncomingRingerCalls)
    }

    @Test
    fun `terminal acknowledgement tombstones the wake until its expiry`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        val terminal = requireNotNull(rig.controller.snapshot())
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertNull(rig.controller.snapshot())

        assertEquals(
            MknoonCallPresentationResult.DUPLICATE,
            rig.controller.present(rig.payload),
        )
        assertEquals(1, rig.store.createCalls)
        assertEquals(1, rig.platform.registerCalls)
        assertEquals(1, rig.platform.showIncomingCalls)
    }

    @Test
    fun `stale action UUID cannot terminate or block the current call`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.operations.clear()

        assertFalse(
            rig.controller.terminate(
                UUID.fromString(OTHER_CALL_ID),
                PendingNativeCallEventType.DECLINE_REQUESTED,
            ),
        )

        assertTrue(rig.operations.isEmpty())
        assertEquals(rig.payload.nativeCallId, rig.controller.activeNativeCallId())
        assertNull(requireNotNull(rig.controller.snapshot()).terminalEvent)
        assertEquals(0, rig.platform.cancelNotificationCalls)
        assertEquals(0, rig.platform.stopForegroundCalls)
        assertEquals(0, rig.platform.abandonAudioFocusCalls)
        assertEquals(0, rig.platform.stopEndpointUpdatesCalls)
    }

    @Test
    fun `terminal racing audio focus acquisition is compensated before media starts`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        val adoptionSequence = requireNotNull(rig.store.lastDescriptor).highestSequence
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                adoptionSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        rig.platform.onRequestAudioFocus = {
            assertTrue(
                rig.controller.terminate(
                    rig.payload.nativeCallId,
                    PendingNativeCallEventType.REMOTE_CANCELLED,
                ),
            )
        }

        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))

        assertEquals(1, rig.platform.requestAudioFocusCalls)
        assertEquals(2, rig.platform.abandonAudioFocusCalls)
        assertEquals(0, rig.platform.startEndpointUpdatesCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
        assertFalse(rig.controller.audioState().active)
        assertEquals(
            PendingNativeCallEventType.REMOTE_CANCELLED,
            requireNotNull(rig.controller.attach()).descriptor.terminalEvent?.type,
        )
    }

    @Test
    fun `Dart activation failures emit only fixed boundary outcomes`() {
        val setActiveFailure = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            setActiveFailure.controller.present(setActiveFailure.payload),
        )
        assertNotNull(setActiveFailure.controller.attach())
        assertTrue(setActiveFailure.controller.markAdopted(setActiveFailure.payload.nativeCallId))
        assertTrue(
            setActiveFailure.controller.acknowledge(
                setActiveFailure.payload.nativeCallId,
                requireNotNull(setActiveFailure.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(
            setActiveFailure.controller.answerFromTelecom(
                setActiveFailure.payload.nativeCallId,
            ),
        )
        setActiveFailure.platform.requestAudioFocusFailuresRemaining = 1

        assertFalse(setActiveFailure.controller.activateAudio(setActiveFailure.payload.nativeCallId))
        assertEquals(
            listOf(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SET_ACTIVE_FAILED),
            setActiveFailure.diagnosticSink.diagnostics,
        )

        val serviceFailure = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            serviceFailure.controller.present(serviceFailure.payload),
        )
        assertNotNull(serviceFailure.controller.attach())
        assertTrue(serviceFailure.controller.markAdopted(serviceFailure.payload.nativeCallId))
        assertTrue(
            serviceFailure.controller.acknowledge(
                serviceFailure.payload.nativeCallId,
                requireNotNull(serviceFailure.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(
            serviceFailure.controller.answerFromTelecom(
                serviceFailure.payload.nativeCallId,
            ),
        )
        serviceFailure.platform.startMicrophoneFailuresRemaining = 1

        assertFalse(serviceFailure.controller.activateAudio(serviceFailure.payload.nativeCallId))
        assertEquals(
            listOf(MknoonCallLifecycleDiagnostic.DART_ACTIVATE_SERVICE_FAILED),
            serviceFailure.diagnosticSink.diagnostics,
        )
    }

    @Test
    fun `Core inactive takes terminal custody and waits off lock for exact terminal ACK`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        val executor = Executors.newSingleThreadExecutor()
        try {
            val callback = executor.submit<Boolean> {
                rig.controller.deactivateAudioFromTelecom(rig.payload.nativeCallId)
            }
            var terminal: PendingNativeCallDescriptor? = null
            for (attempt in 0 until 10_000) {
                terminal = rig.controller.snapshot()
                    ?.takeIf { descriptor -> descriptor.terminalEvent != null }
                if (terminal != null) break
                Thread.yield()
            }
            val durable = requireNotNull(terminal)
            assertEquals(
                PendingNativeCallEventType.END_REQUESTED,
                durable.terminalEvent?.type,
            )
            assertTrue(
                rig.controller.acknowledge(
                    rig.payload.nativeCallId,
                    durable.highestSequence,
                    PendingNativeCallAcknowledgement.TERMINAL,
                ),
            )
            assertTrue(callback.get(1, TimeUnit.SECONDS))
            assertEquals(0, rig.platform.endCalls)
            assertEquals(0, rig.platform.abandonAudioFocusCalls)
            assertNull(rig.controller.snapshot())
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `Core disconnect waits for media terminal ACK without recursive Telecom mutation`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        val executor = Executors.newSingleThreadExecutor()
        try {
            val callback = executor.submit<Boolean> {
                rig.controller.disconnectFromTelecom(rig.payload.nativeCallId)
            }
            var terminal: PendingNativeCallDescriptor? = null
            for (attempt in 0 until 10_000) {
                terminal = rig.controller.snapshot()
                    ?.takeIf { descriptor -> descriptor.terminalEvent != null }
                if (terminal != null) break
                Thread.yield()
            }
            val durable = requireNotNull(terminal)
            assertEquals(
                PendingNativeCallEventType.END_REQUESTED,
                durable.terminalEvent?.type,
            )
            assertTrue(
                rig.controller.acknowledge(
                    rig.payload.nativeCallId,
                    durable.highestSequence,
                    PendingNativeCallAcknowledgement.TERMINAL,
                ),
            )
            assertTrue(callback.get(1, TimeUnit.SECONDS))
            assertEquals(0, rig.platform.endCalls)
            assertEquals(0, rig.platform.abandonAudioFocusCalls)
            assertEquals(1, rig.platform.stopEndpointUpdatesCalls)
            assertTrue("duplicate provider disconnect is idempotent", rig.controller.disconnectFromTelecom(rig.payload.nativeCallId))
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun `unrequested Core active fails closed and adopted owner detach preserves terminal replay`() {
        val activeRig = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            activeRig.controller.present(activeRig.payload),
        )
        assertNotNull(activeRig.controller.attach())
        assertTrue(activeRig.controller.markAdopted(activeRig.payload.nativeCallId))
        assertTrue(
            activeRig.controller.acknowledge(
                activeRig.payload.nativeCallId,
                requireNotNull(activeRig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertFalse(activeRig.controller.activateAudioFromTelecom(activeRig.payload.nativeCallId))
        assertEquals(
            PendingNativeCallEventType.NATIVE_FAILURE,
            requireNotNull(activeRig.controller.snapshot()).terminalEvent?.type,
        )
        assertEquals(0, activeRig.platform.startMicrophoneCalls)
        assertEquals(
            listOf(MknoonCallLifecycleDiagnostic.SET_ACTIVE_REJECTED_UNSOLICITED),
            activeRig.diagnosticSink.diagnostics,
        )

        val detachRig = LifecycleRig()
        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            detachRig.controller.present(detachRig.payload),
        )
        assertNotNull(detachRig.controller.attach())
        assertTrue(detachRig.controller.markAdopted(detachRig.payload.nativeCallId))
        assertTrue(
            detachRig.controller.acknowledge(
                detachRig.payload.nativeCallId,
                requireNotNull(detachRig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        detachRig.controller.detach()
        val replay = requireNotNull(detachRig.controller.attach())
        assertEquals(PendingNativeCallPhase.JOURNAL, replay.descriptor.phase)
        assertEquals(
            PendingNativeCallEventType.PROVIDER_REMOVED,
            replay.descriptor.terminalEvent?.type,
        )
        assertEquals(listOf(PendingNativeCallEventType.PROVIDER_REMOVED), replay.deliverableEvents.map { it.type })
    }

    @Test
    fun `failed terminal persistence fences every nonterminal transition until recovery`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.store.appendFailuresRemaining = 1

        assertFalse(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
            ),
        )
        assertFalse(rig.controller.answer(rig.payload.nativeCallId))
        assertFalse(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertFalse(rig.controller.activateAudio(rig.payload.nativeCallId))
        assertNull(rig.controller.attach())

        assertTrue(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.NATIVE_FAILURE,
            ),
        )
        assertEquals(
            PendingNativeCallEventType.NATIVE_FAILURE,
            requireNotNull(rig.controller.snapshot()).terminalEvent?.type,
        )
    }

    @Test
    fun `presented recreation restores durable answer dedupe without a second presentation`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(rig.controller.answer(rig.payload.nativeCallId))
        assertTrue(requireNotNull(rig.store.lastDescriptor).answerRequested)
        rig.operations.clear()
        val recreatedPlatform = LifecycleFakePlatform(rig.operations)
        val recreated = MknoonCallLifecycleController(
            store = rig.store,
            platform = recreatedPlatform,
            eventSink = LifecycleFakeEventSink(rig.operations),
            capabilityEnabled = { true },
            recordAudioPermissionGranted = { true },
            nowMs = { NOW_MS },
        )

        assertTrue(recreated.reconcilePresented())
        assertTrue(recreated.answerFromTelecom(rig.payload.nativeCallId))
        assertEquals(
            1,
            requireNotNull(rig.store.lastDescriptor).events.count {
                it.type == PendingNativeCallEventType.ANSWER_REQUESTED
            },
        )
        assertEquals(0, recreatedPlatform.showIncomingCalls)
        assertEquals(1, recreatedPlatform.startForegroundCalls)
    }

    @Test
    fun `recreated adopted journal preserves provider loss until exact terminal acknowledgement`() {
        val rig = LifecycleRig()
        val id = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.answer(id))
        assertTrue(rig.controller.markAdopted(id))
        assertTrue(rig.controller.acknowledge(id, requireNotNull(rig.controller.snapshot()).highestSequence,
            PendingNativeCallAcknowledgement.ADOPTED))
        assertTrue(rig.controller.activateAudio(id))
        rig.operations.clear()
        val platform = LifecycleFakePlatform(rig.operations)
        val restarted = MknoonCallLifecycleController(rig.store, platform,
            LifecycleFakeEventSink(rig.operations), { true }, { false }, { NOW_MS })

        assertTrue(restarted.reconcileAdoptedJournal())
        val terminal = requireNotNull(restarted.snapshot())
        assertEquals(PendingNativeCallEventType.PROVIDER_REMOVED, terminal.terminalEvent?.type)
        assertEquals(PendingNativeCallAcknowledgement.ADOPTED, terminal.handoffAcknowledgement)
        assertEquals(PendingNativeCallPhase.JOURNAL, terminal.phase)
        assertEquals(id, terminal.terminalEvent?.nativeCallId)
        assertEquals(terminal.highestSequence, terminal.terminalEvent?.sequence)
        assertEquals(0, rig.store.deleteCalls)
        assertNull(restarted.activeNativeCallId())
        assertFalse(restarted.isCleanupPending(id))
        assertFalse(restarted.answer(id))
        assertFalse(restarted.activateAudio(id))
        assertNull(restarted.presentation(id))
        assertEquals(0, platform.registerCalls)
        assertEquals(0, platform.showIncomingCalls)
        assertEquals(0, platform.startForegroundCalls)
        assertEquals(0, platform.startMicrophoneCalls)
        val beforeRead = rig.operations.toList()
        repeat(2) {
            val observed = restarted.observeJournal()
            assertEquals(terminal, observed.descriptor)
            assertFalse(observed.liveOwnerPresent)
            assertFalse(observed.cleanupPending)
        }
        assertEquals(beforeRead, rig.operations)
        assertFalse(restarted.acknowledge(id, terminal.highestSequence - 1,
            PendingNativeCallAcknowledgement.TERMINAL))
        assertEquals(terminal, restarted.snapshot())
        assertTrue(restarted.acknowledge(id, terminal.highestSequence,
            PendingNativeCallAcknowledgement.TERMINAL))
        assertNull(restarted.snapshot())
        val successor = rig.payload.copy(nativeCallId = UUID.randomUUID(), callHandle = UUID.randomUUID().toString())
        assertEquals(MknoonCallPresentationResult.PRESENTED, restarted.present(successor))
        restarted.acknowledge(id, terminal.highestSequence, PendingNativeCallAcknowledgement.TERMINAL)
        assertEquals(successor.nativeCallId, restarted.snapshot()?.nativeCallId)
        assertEquals(successor.nativeCallId, restarted.activeNativeCallId())
    }

    @Test
    fun `startup terminal fence failure blocks attach and ACK until durable repair`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        val terminal = requireNotNull(rig.controller.snapshot())

        assertFalse(rig.controller.reconcileTerminalFence(persisted = false))
        assertNull(rig.controller.attach())
        assertFalse(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertTrue(rig.controller.reconcileTerminalFence(persisted = true))
        assertNotNull(rig.controller.attach())
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
    }

    @Test
    fun `post-adoption append failure never synthesizes an in-memory success`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                requireNotNull(rig.controller.snapshot()).highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        rig.store.appendFailuresRemaining = 1
        assertFalse(rig.controller.onMuteChanged(rig.payload.nativeCallId, muted = true))
        assertTrue(requireNotNull(rig.controller.snapshot()).events.isEmpty())

        rig.store.appendFailuresRemaining = 1
        assertFalse(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.PROVIDER_REMOVED,
            ),
        )
        val journal = requireNotNull(rig.controller.snapshot())
        assertEquals(PendingNativeCallPhase.JOURNAL, journal.phase)
        assertNull(journal.terminalEvent)
        assertNull(rig.controller.attach())
    }

    @Test
    fun `Dart end confirms an exact retained native decline without repeating cleanup or crossing retirement`() {
        val rig = LifecycleRig()
        val callId = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        assertTrue(rig.controller.markAdopted(callId))
        assertTrue(rig.controller.acknowledge(
            callId,
            requireNotNull(rig.controller.snapshot()).highestSequence,
            PendingNativeCallAcknowledgement.ADOPTED,
        ))
        assertTrue(rig.controller.terminate(callId, PendingNativeCallEventType.DECLINE_REQUESTED))
        val declined = requireNotNull(rig.controller.snapshot())
        val operationsAfterDecline = rig.operations.toList()

        // A queued canonical terminal snapshot can arrive before the native
        // journal ACK. End confirms the completed state, not a new event.
        assertTrue(rig.controller.endFromDart(callId))
        assertTrue(rig.controller.endFromDart(callId))
        assertEquals(declined, rig.controller.snapshot())
        assertEquals(operationsAfterDecline, rig.operations)
        assertFalse(rig.controller.endFromDart(UUID(9L, 9L)))
        assertFalse(rig.controller.terminate(callId, PendingNativeCallEventType.DECLINE_REQUESTED))
        assertTrue(rig.controller.acknowledge(
            callId,
            declined.highestSequence,
            PendingNativeCallAcknowledgement.TERMINAL,
        ))
        assertNull(rig.controller.snapshot())
        assertFalse(rig.controller.endFromDart(callId))

        val successor = callPayload(UUID(8L, 8L))
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(successor))
        val successorBefore = requireNotNull(rig.controller.snapshot())
        val operationsBeforeStale = rig.operations.toList()
        assertFalse(rig.controller.endFromDart(callId))
        assertEquals(successorBefore, rig.controller.snapshot())
        assertEquals(operationsBeforeStale, rig.operations)
        assertTrue(rig.controller.answer(successor.nativeCallId))
    }

    @Test
    fun `Dart end confirms native terminal only after exact cleanup retry completes`() {
        val rig = LifecycleRig()
        val callId = rig.payload.nativeCallId
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        rig.platform.endFailuresRemaining = 2
        assertFalse(rig.controller.terminate(callId, PendingNativeCallEventType.DECLINE_REQUESTED))
        val declined = requireNotNull(rig.controller.snapshot())

        assertFalse(rig.controller.endFromDart(callId))
        assertTrue(rig.controller.isCleanupPending(callId))
        assertFalse(rig.controller.acknowledge(
            callId,
            declined.highestSequence,
            PendingNativeCallAcknowledgement.TERMINAL,
        ))
        assertTrue(rig.controller.endFromDart(callId))
        assertFalse(rig.controller.isCleanupPending(callId))
        assertEquals(declined, rig.controller.snapshot())
        assertEquals(3, rig.platform.endCalls)
        assertEquals(1, rig.platform.stopEndpointUpdatesCalls)
        assertEquals(1, rig.platform.abandonAudioFocusCalls)
        assertEquals(1, rig.platform.cancelNotificationCalls)
        assertEquals(1, rig.platform.stopForegroundCalls)
        assertTrue(rig.controller.acknowledge(
            callId,
            declined.highestSequence,
            PendingNativeCallAcknowledgement.TERMINAL,
        ))
    }

    @Test
    fun `incomplete terminal cleanup retries in endpoint focus disconnect order before ACK`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertNotNull(rig.controller.attach())
        rig.operations.clear()
        rig.eventSink.events.clear()
        rig.platform.endFailuresRemaining = 1

        assertFalse(
            rig.controller.terminate(
                rig.payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        val terminal = requireNotNull(rig.controller.snapshot())
        val terminalEvent = requireNotNull(terminal.terminalEvent)
        assertEquals(listOf(terminalEvent), rig.eventSink.events)
        assertEquals(listOf(rig.payload.nativeCallId), rig.cleanupPending)
        assertTrue(
            rig.operations.indexOf("platform.stopEndpointUpdates") <
                rig.operations.indexOf("platform.abandonAudioFocus"),
        )
        assertTrue(
            rig.operations.indexOf("platform.abandonAudioFocus") <
                rig.operations.indexOf("platform.end"),
        )
        assertFalse(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )

        rig.store.snapshotFailuresRemaining = 1
        assertTrue(rig.controller.retryCleanup(rig.payload.nativeCallId))
        rig.store.snapshotFailuresRemaining = 0
        assertEquals(2, rig.platform.endCalls)
        assertEquals(1, rig.platform.abandonAudioFocusCalls)
        assertEquals(listOf(terminalEvent, terminalEvent), rig.eventSink.events)
        assertTrue(
            rig.controller.acknowledge(
                rig.payload.nativeCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
    }
}

internal class LifecycleRig(
    capabilityEnabled: Boolean = true,
    recordAudioGranted: Boolean = true,
    journalDiagnostic: (String, PendingNativeCallEventType) -> Unit = { _, _ -> },
    isMainThread: () -> Boolean = { false },
) {
    val operations = mutableListOf<String>()
    val store = LifecycleFakeStore(operations)
    val platform = LifecycleFakePlatform(operations)
    val eventSink = LifecycleFakeEventSink(operations)
    val diagnosticSink = LifecycleFakeDiagnosticSink()
    val payload = callPayload()
    val presented = mutableListOf<Pair<UUID, Long>>()
    val settled = mutableListOf<UUID>()
    val cleanupPending = mutableListOf<UUID>()
    val declineReplies = mutableListOf<PendingNativeCallDescriptor>()
    var declineReplyAccepted = false
    var declineReplyAtOperation = -1
    var capabilityEnabled: Boolean = capabilityEnabled
    var recordAudioGranted: Boolean = recordAudioGranted
    val controller = MknoonCallLifecycleController(
        store = store,
        platform = platform,
        eventSink = eventSink,
        capabilityEnabled = { this.capabilityEnabled },
        recordAudioPermissionGranted = { this.recordAudioGranted },
        nowMs = { NOW_MS },
        onPresented = { nativeCallId, expiresAtMs ->
            presented += nativeCallId to expiresAtMs
        },
        onSettled = { nativeCallId -> settled += nativeCallId },
        onCleanupPending = { nativeCallId -> cleanupPending += nativeCallId },
        onDeclineWithoutOwner = { descriptor ->
            declineReplies += descriptor
            declineReplyAtOperation = operations.size
            declineReplyAccepted
        },
        diagnosticSink = diagnosticSink,
        journalDiagnostic = journalDiagnostic,
        isMainThread = isMainThread,
    )
}

internal class LifecycleFakeStore(
    private val operations: MutableList<String> = mutableListOf(),
) : MknoonCallLifecycleStore {
    override fun observeProtectedJournal(): PendingNativeCallDescriptor? = snapshot()
    var createOverride: PendingNativeCallCreateResult? = null
    var lastDescriptor: PendingNativeCallDescriptor? = null
    var createCalls = 0
    var deleteCalls = 0
    var appendFailuresRemaining = 0
    var snapshotFailuresRemaining = 0
    var onAppend: ((PendingNativeCallEventType) -> Unit)? = null
    private var lastAcknowledgementReceipt: LifecycleAcknowledgementCall? = null
    val receiptNativeCallIds = mutableMapOf<String, UUID>()
    val acknowledgementCalls = mutableListOf<LifecycleAcknowledgementCall>()

    override fun create(payload: CallWakePayload): PendingNativeCallCreateResult {
        createCalls += 1
        operations += "store.create"
        val overridden = createOverride
        if (overridden != null) {
            lastDescriptor = when (overridden) {
                is PendingNativeCallCreateResult.Created -> overridden.descriptor
                is PendingNativeCallCreateResult.Duplicate -> overridden.descriptor
                is PendingNativeCallCreateResult.Busy -> overridden.activeDescriptor
                PendingNativeCallCreateResult.PersistenceFailure -> null
            }
            return overridden
        }
        return PendingNativeCallCreateResult.Created(
            descriptorFor(payload).also { lastDescriptor = it },
        )
    }

    override fun createOutgoing(payload: CallWakePayload): PendingNativeCallCreateResult {
        createCalls += 1
        operations += "store.createOutgoing"
        val overridden = createOverride
        if (overridden != null) {
            lastDescriptor = when (overridden) {
                is PendingNativeCallCreateResult.Created -> overridden.descriptor
                is PendingNativeCallCreateResult.Duplicate -> overridden.descriptor
                is PendingNativeCallCreateResult.Busy -> overridden.activeDescriptor
                PendingNativeCallCreateResult.PersistenceFailure -> null
            }
            return overridden
        }
        val existing = lastDescriptor
        if (existing != null) {
            return if (
                existing.direction == PendingNativeCallDirection.OUTGOING &&
                existing.callHandle == payload.callHandle &&
                existing.expiresAtMs == payload.expiresAtMs &&
                existing.terminalEvent == null
            ) {
                PendingNativeCallCreateResult.Duplicate(existing)
            } else {
                PendingNativeCallCreateResult.Busy(existing)
            }
        }
        return PendingNativeCallCreateResult.Created(
            descriptorFor(payload).copy(direction = PendingNativeCallDirection.OUTGOING)
                .also { lastDescriptor = it },
        )
    }

    override fun append(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): PendingNativeCallAppendResult {
        operations += "store.append:$type"
        onAppend?.invoke(type)
        if (appendFailuresRemaining > 0) {
            appendFailuresRemaining -= 1
            return PendingNativeCallAppendResult.PersistenceFailure
        }
        val current = lastDescriptor ?: return PendingNativeCallAppendResult.NotFound
        if (current.nativeCallId != nativeCallId) {
            return PendingNativeCallAppendResult.NotFound
        }
        if (current.terminalEvent != null) {
            return PendingNativeCallAppendResult.IgnoredAfterTerminal(current)
        }
        val sequence = current.highestSequence + 1L
        val event = PendingNativeCallEvent(
            nativeCallId = nativeCallId,
            sequence = sequence,
            eventId = UUID(0L, sequence),
            type = type,
        )
        val updated = current.copy(
            highestSequence = sequence,
            terminalEvent = event.takeIf { type in lifecycleTerminalTypes },
            events = current.events + event,
            answerRequested = current.answerRequested ||
                type == PendingNativeCallEventType.ANSWER_REQUESTED,
        )
        lastDescriptor = updated
        return PendingNativeCallAppendResult.Appended(updated, event)
    }

    override fun snapshot(): PendingNativeCallDescriptor? {
        if (snapshotFailuresRemaining > 0) {
            snapshotFailuresRemaining -= 1
            throw IllegalStateException("injected snapshot failure")
        }
        return lastDescriptor
    }

    override fun resolveAcknowledgementReceipt(callHandle: String): UUID? =
        receiptNativeCallIds[callHandle]

    override fun acknowledge(
        nativeCallId: UUID,
        highestConsumedSequence: Long,
        acknowledgement: PendingNativeCallAcknowledgement,
    ): Boolean {
        operations += "store.acknowledge:$acknowledgement"
        acknowledgementCalls += LifecycleAcknowledgementCall(
            nativeCallId,
            highestConsumedSequence,
            acknowledgement,
        )
        if (
            lastAcknowledgementReceipt == LifecycleAcknowledgementCall(
                nativeCallId,
                highestConsumedSequence,
                acknowledgement,
            )
        ) {
            return true
        }
        val current = lastDescriptor ?: return false
        if (current.nativeCallId != nativeCallId) {
            return false
        }
        if (acknowledgement == PendingNativeCallAcknowledgement.NONE) {
            if (current.events.none { it.sequence == highestConsumedSequence }) {
                return false
            }
            lastDescriptor = current.copy(
                events = current.events.filter { it.sequence > highestConsumedSequence },
                lastAcknowledgement = PendingNativeCallAcknowledgement.NONE,
                lastAcknowledgedSequence = highestConsumedSequence,
            )
            lastAcknowledgementReceipt = acknowledgementCalls.last()
            return true
        }
        if (highestConsumedSequence != current.highestSequence) return false
        if (
            acknowledgement == PendingNativeCallAcknowledgement.ADOPTED &&
            (current.terminalEvent != null ||
                current.handoffAcknowledgement != PendingNativeCallAcknowledgement.NONE)
        ) return false
        if (
            acknowledgement == PendingNativeCallAcknowledgement.TERMINAL &&
            current.terminalEvent == null
        ) return false
        if (acknowledgement == PendingNativeCallAcknowledgement.ADOPTED) {
            lastDescriptor = current.copy(
                events = emptyList(),
                handoffAcknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
                phase = PendingNativeCallPhase.JOURNAL,
                wakeHandle = "",
                lastAcknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
                lastAcknowledgedSequence = highestConsumedSequence,
            )
        } else {
            lastDescriptor = null
            deleteCalls += 1
        }
        lastAcknowledgementReceipt = acknowledgementCalls.last()
        return true
    }
}

/** B5 tests: holds one fake Telecom registration open until [finish]. */
internal class HeldTelecomRegistration {
    val started = CountDownLatch(1)
    private val release = CountDownLatch(1)

    @Volatile
    private var registered = false

    fun register(callback: MknoonCallRegistrationCallback) {
        started.countDown()
        release.await(10, TimeUnit.SECONDS)
        if (registered) callback.onRegistered() else callback.onRegistrationAbandoned()
    }

    fun finish(registered: Boolean) = synchronized(this) {
        if (release.count == 0L) return@synchronized
        this.registered = registered
        release.countDown()
    }

    companion object {
        const val RETURNED = "platform.registrationReturned"
    }
}

internal data class LifecycleAcknowledgementCall(
    val nativeCallId: UUID,
    val highestConsumedSequence: Long,
    val acknowledgement: PendingNativeCallAcknowledgement,
)

internal class LifecycleFakePlatform(
    private val operations: MutableList<String> = mutableListOf(),
) : MknoonCallPlatform {
    var registrationSucceeds = true
    var registerCalls = 0
    var registerOutgoingCalls = 0
    var showIncomingCalls = 0
    var startForegroundCalls = 0
    var answerCalls = 0
    var endCalls = 0
    var cancelNotificationCalls = 0
    var stopForegroundCalls = 0
    var requestAudioFocusCalls = 0
    var abandonAudioFocusCalls = 0
    var startEndpointUpdatesCalls = 0
    var stopEndpointUpdatesCalls = 0
    var startMicrophoneCalls = 0
    var stopIncomingRingerCalls = 0
    var lastRegistrationTimeoutMs: Long? = null
    var onRegisterIncoming: ((MknoonCallRegistrationCallback) -> Unit)? = null
    var onRegisterOutgoing: ((MknoonCallRegistrationCallback) -> Unit)? = null
    var onAnswer: (() -> Unit)? = null
    var onRequestAudioFocus: (() -> Unit)? = null
    var onShowIncoming: ((UUID) -> Unit)? = null
    var endFailuresRemaining = 0
    var requestAudioFocusFailuresRemaining = 0
    var startMicrophoneFailuresRemaining = 0
    var stopIncomingRingerFailuresRemaining = 0

    override fun registerIncoming(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
        timeoutMs: Long,
    ) {
        registerCalls += 1
        lastRegistrationTimeoutMs = timeoutMs
        operations += "platform.registerIncoming"
        onRegisterIncoming?.let { hold ->
            hold(callback)
            operations += HeldTelecomRegistration.RETURNED
            return
        }
        if (registrationSucceeds) {
            callback.onRegistered()
        } else {
            callback.onFailure()
        }
    }

    override fun registerOutgoing(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
        timeoutMs: Long,
    ) {
        registerOutgoingCalls += 1
        lastRegistrationTimeoutMs = timeoutMs
        operations += "platform.registerOutgoing"
        onRegisterOutgoing?.let { hold ->
            hold(callback)
            operations += HeldTelecomRegistration.RETURNED
            return
        }
        if (registrationSucceeds) {
            callback.onRegistered()
        } else {
            callback.onFailure()
        }
    }

    override fun showIncoming(nativeCallId: UUID) {
        showIncomingCalls += 1
        operations += "platform.showIncoming"
        onShowIncoming?.invoke(nativeCallId)
    }

    override fun startForeground(nativeCallId: UUID) {
        startForegroundCalls += 1
        operations += "platform.startForeground"
    }

    override fun answer(nativeCallId: UUID) {
        answerCalls += 1
        operations += "platform.answer"
        onAnswer?.invoke()
    }

    override fun end(nativeCallId: UUID) {
        endCalls += 1
        operations += "platform.end"
        if (endFailuresRemaining > 0) {
            endFailuresRemaining -= 1
            throw IllegalStateException("injected end failure")
        }
    }

    override fun cancelNotification(nativeCallId: UUID) {
        cancelNotificationCalls += 1
        operations += "platform.cancelNotification"
    }

    override fun stopForeground(nativeCallId: UUID) {
        stopForegroundCalls += 1
        operations += "platform.stopForeground"
    }

    override fun stopIncomingRinger(nativeCallId: UUID) {
        stopIncomingRingerCalls += 1
        operations += "platform.stopIncomingRinger"
        if (stopIncomingRingerFailuresRemaining > 0) {
            stopIncomingRingerFailuresRemaining -= 1
            throw IllegalStateException("injected incoming ringer stop failure")
        }
    }

    override fun requestAudioFocus(nativeCallId: UUID) {
        requestAudioFocusCalls += 1
        operations += "platform.requestAudioFocus"
        if (requestAudioFocusFailuresRemaining > 0) {
            requestAudioFocusFailuresRemaining -= 1
            throw IllegalStateException("injected audio focus failure")
        }
        onRequestAudioFocus?.invoke()
    }

    override fun abandonAudioFocus(nativeCallId: UUID) {
        abandonAudioFocusCalls += 1
        operations += "platform.abandonAudioFocus"
    }

    override fun startEndpointUpdates(nativeCallId: UUID) {
        startEndpointUpdatesCalls += 1
        operations += "platform.startEndpointUpdates"
    }

    override fun stopEndpointUpdates(nativeCallId: UUID) {
        stopEndpointUpdatesCalls += 1
        operations += "platform.stopEndpointUpdates"
    }

    override fun startMicrophoneService(nativeCallId: UUID) {
        startMicrophoneCalls += 1
        operations += "platform.startMicrophoneService"
        if (startMicrophoneFailuresRemaining > 0) {
            startMicrophoneFailuresRemaining -= 1
            throw IllegalStateException("injected microphone service failure")
        }
    }
}

internal class LifecycleFakeDiagnosticSink : MknoonCallLifecycleDiagnosticSink {
    val diagnostics = mutableListOf<MknoonCallLifecycleDiagnostic>()

    override fun emit(diagnostic: MknoonCallLifecycleDiagnostic) {
        diagnostics += diagnostic
    }
}

internal class LifecycleFakeEventSink(
    private val operations: MutableList<String> = mutableListOf(),
) : MknoonCallEventSink {
    val events = mutableListOf<PendingNativeCallEvent>()

    override fun emit(event: PendingNativeCallEvent) {
        events += event
        operations += "sink.emit:${event.type}"
    }
}

internal fun callPayload(
    nativeCallId: UUID = UUID.fromString(CALL_ID),
): CallWakePayload = CallWakePayload(
    nativeCallId = nativeCallId,
    callHandle = nativeCallId.toString(),
    wakeHandle = "00000000-0000-4000-8000-000000000499",
    receivedAtMs = NOW_MS - 1_000L,
    expiresAtMs = NOW_MS + 40_000L,
)

internal fun descriptorFor(payload: CallWakePayload): PendingNativeCallDescriptor =
    PendingNativeCallDescriptor(
        nativeCallId = payload.nativeCallId,
        callHandle = payload.callHandle,
        wakeHandle = payload.wakeHandle,
        receivedAtMs = payload.receivedAtMs,
        expiresAtMs = payload.expiresAtMs,
        highestSequence = 0L,
        terminalEvent = null,
        events = emptyList(),
    )

internal val lifecycleTerminalTypes = setOf(
    PendingNativeCallEventType.DECLINE_REQUESTED,
    PendingNativeCallEventType.END_REQUESTED,
    PendingNativeCallEventType.REMOTE_CANCELLED,
    PendingNativeCallEventType.EXPIRED,
    PendingNativeCallEventType.PROVIDER_REMOVED,
    PendingNativeCallEventType.NATIVE_FAILURE,
)

internal const val NOW_MS = 10_000L
internal const val CALL_ID = "00000000-0000-4000-8000-000000000401"
internal const val OTHER_CALL_ID = "00000000-0000-4000-8000-000000000402"
