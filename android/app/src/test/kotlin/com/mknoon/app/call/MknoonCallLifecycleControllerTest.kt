package com.mknoon.app.call

import java.util.UUID
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
        assertFalse(rig.controller.endFromDart(rig.payload.nativeCallId))
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
        assertFalse(dartEnd.controller.endFromDart(dartEnd.payload.nativeCallId))
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
    )
}

internal class LifecycleFakeStore(
    private val operations: MutableList<String> = mutableListOf(),
) : MknoonCallLifecycleStore {
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
    var onAnswer: (() -> Unit)? = null
    var onRequestAudioFocus: (() -> Unit)? = null
    var endFailuresRemaining = 0
    var requestAudioFocusFailuresRemaining = 0
    var startMicrophoneFailuresRemaining = 0
    var stopIncomingRingerFailuresRemaining = 0

    override fun registerIncoming(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    ) {
        registerCalls += 1
        operations += "platform.registerIncoming"
        if (registrationSucceeds) {
            callback.onRegistered()
        } else {
            callback.onFailure()
        }
    }

    override fun registerOutgoing(
        nativeCallId: UUID,
        callback: MknoonCallRegistrationCallback,
    ) {
        registerOutgoingCalls += 1
        operations += "platform.registerOutgoing"
        if (registrationSucceeds) {
            callback.onRegistered()
        } else {
            callback.onFailure()
        }
    }

    override fun showIncoming(nativeCallId: UUID) {
        showIncomingCalls += 1
        operations += "platform.showIncoming"
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
