package com.mknoon.app.call

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.Instrumentation
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.core.telecom.CallAttributesCompat
import androidx.test.platform.app.InstrumentationRegistry
import com.mknoon.app.MainActivity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Disposable VC2-04 device proof.
 *
 * Every method is independently invokable. Host-owned locking, permissions,
 * and `am kill` changes occur only between methods. The network-transition
 * method coordinates connectivity changes through coarse status markers while
 * its call remains active. The test never writes payload handles, native call
 * IDs, notification contents, account data, tokens, or media to instrumentation
 * output.
 */
class Vc204AndroidCallLifecycleInstrumentationTest {
    private lateinit var context: Context
    private lateinit var instrumentation: Instrumentation
    private lateinit var runtime: MknoonCallRuntime

    @Before
    fun setUp() {
        instrumentation = InstrumentationRegistry.getInstrumentation()
        context = instrumentation.targetContext.applicationContext
        assertEquals("disposable package boundary", PROOF_APPLICATION_ID, context.packageName)
        assertTrue("VC2-04 requires Android API 26+", Build.VERSION.SDK_INT >= 26)
        runtime = MknoonCallRuntime.get(context)
        assertTrue(
            "production call capability must persist as enabled in the disposable build",
            runtime.setCapabilityEnabled(true),
        )
    }

    @Test
    fun testVc204ForegroundBackgroundActualPlatformPresentation() {
        assertFalse("initial phase requires an unlocked device", keyguard().isDeviceLocked)
        val activity = launchMainActivity()
        try {
            await("MainActivity foreground window") { activity.hasWindowFocus() }
            val payload = payload(SLOT_FOREGROUND)

            assertEquals(
                "actual production platform presentation",
                MknoonCallPresentationResult.PRESENTED,
                runtime.present(payload),
            )
            assertRingingDescriptor(payload.nativeCallId)
            await("privacy-minimal OS call notification") {
                activeCallNotificationCount() == 1
            }

            var movedToBackground = false
            instrumentation.runOnMainSync {
                movedToBackground = activity.moveTaskToBack(true)
            }
            instrumentation.waitForIdleSync()
            assertTrue("MainActivity task moves to background", movedToBackground)
            await("MainActivity loses foreground focus") { !activity.hasWindowFocus() }
            assertTrue(
                "background transition must retain the durable ringing descriptor",
                runtime.controller.snapshot()?.terminalEvent == null,
            )
            assertTrue(
                "foreground/background cleanup must terminate once",
                runtime.controller.terminate(
                    payload.nativeCallId,
                    PendingNativeCallEventType.REMOTE_CANCELLED,
                ),
            )
            acknowledgeTerminal(payload.nativeCallId)
        } finally {
            finishActivity(activity)
        }
    }

    @Test
    fun testVc204ReportKeyguardAutomationPolicy() {
        instrumentation.sendStatus(
            KEYGUARD_POLICY_STATUS_CODE,
            Bundle().apply {
                putString(
                    KEYGUARD_POLICY_STATUS_KEY,
                    if (keyguard().isDeviceSecure) KEYGUARD_SECURE else KEYGUARD_NON_SECURE,
                )
            },
        )
    }

    @Test
    fun testVc204DuplicateDelayedWakeAndPreAnswerCancel() {
        val payload = payload(SLOT_DELAYED_DUPLICATE, deliveryDelayMs = 15_000L)
        assertEquals(
            "delayed but live wake reaches the production runtime",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertEquals(
            "duplicate wake is idempotent",
            MknoonCallPresentationResult.DUPLICATE,
            runtime.present(payload),
        )
        assertTrue(
            "remote pre-answer cancellation wins",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        assertFalse(
            "answer cannot resurrect a pre-answer cancellation",
            runtime.controller.answer(payload.nativeCallId),
        )
        assertFalse(
            "duplicate terminal cleanup is a no-op",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        val descriptor = requireDescriptor("pre-answer terminal descriptor")
        assertEquals(
            "one coarse terminal state",
            PendingNativeCallEventType.REMOTE_CANCELLED,
            descriptor.terminalEvent?.type,
        )
        assertEquals(
            "one terminal event is durable",
            1,
            descriptor.events.count { it.type == PendingNativeCallEventType.REMOTE_CANCELLED },
        )
        acknowledgeTerminal(payload.nativeCallId)
    }

    @Test
    fun testVc204SeedRingingBeforeAmKill() {
        val payload = payload(SLOT_RINGING_PROCESS_DEATH)
        assertEquals(
            "ringing seed uses actual platform presentation",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertRingingDescriptor(payload.nativeCallId)
        await("ringing notification before host am kill") {
            activeCallNotificationCount() == 1
        }
        assertTrue(
            "same-UID proof quiesces the non-exported foreground service",
            context.stopService(Intent(context, MknoonCallForegroundService::class.java)),
        )
        await("ringing foreground service notification is quiesced") {
            activeCallNotificationCount() == 0
        }
        // Deliberately do not acknowledge or terminate. The host's proof-only
        // seed receiver exercises this setup outside the instrumentation
        // teardown boundary before invoking real `am kill`.
    }

    @Test
    fun testVc204RecoverRingingAfterAmKill() {
        val expectedCallId = payload(SLOT_RINGING_PROCESS_DEATH).nativeCallId
        val descriptor = requireDescriptor("ringing descriptor after am kill")
        assertTrue("same opaque fixture call", expectedCallId == descriptor.nativeCallId)
        assertNull("process recreation preserves nonterminal ringing custody", descriptor.terminalEvent)
        assertEquals("ringing custody stays pre-start", PendingNativeCallPhase.PRE_START, descriptor.phase)
        assertEquals(
            "re-registration does not duplicate durable presentation",
            listOf(PendingNativeCallEventType.PRESENTED),
            descriptor.events.map { it.type },
        )
        val attachment = runtime.controller.attach()
        assertNotNull("recreated process can attach to ringing ownership", attachment)
        await("recreated ringing call restores one OS call notification") {
            activeCallNotificationCount() == 1
        }
        assertTrue(
            "recreated ringing ownership terminalizes once for phase cleanup",
            runtime.controller.terminate(
                expectedCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        val terminal = requireDescriptor("recreated ringing terminal before acknowledgement")
        assertTrue(
            "terminal reconciliation is acknowledged exactly",
            runtime.controller.acknowledge(
                expectedCallId,
                terminal.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertNull("terminal acknowledgement deletes pending ownership", runtime.controller.snapshot())
    }

    @Test
    fun testVc204LockedActualPlatformPresentation() {
        assertTrue("host must invoke this phase while keyguard is showing", keyguard().isKeyguardLocked)
        val payload = payload(SLOT_LOCKED)
        assertEquals(
            "locked presentation reaches the actual platform",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertRingingDescriptor(payload.nativeCallId)
        await("locked OS call notification") { activeCallNotificationCount() == 1 }
        assertTrue(
            "locked presentation cleanup",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        acknowledgeTerminal(payload.nativeCallId)
    }

    @Test
    fun testVc204NotificationAndFullScreenDeniedFallback() {
        if (Build.VERSION.SDK_INT >= 33) {
            assertEquals(
                "POST_NOTIFICATIONS is host-denied",
                PackageManager.PERMISSION_DENIED,
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS),
            )
        }
        if (Build.VERSION.SDK_INT >= 34) {
            assertFalse(
                "full-screen intent special access is host-denied",
                notifications().canUseFullScreenIntent(),
            )
        }
        if (Build.VERSION.SDK_INT >= 34) {
            assertTrue("denial phase starts without an Activity", hasNoLiveAppActivity())
        }

        val payload = payload(SLOT_NOTIFICATION_DENIED)
        val presentation = runtime.present(payload)
        assertTrue(
            "denial must either retain Telecom ownership or fail closed by platform policy",
            presentation == MknoonCallPresentationResult.PRESENTED ||
                presentation == MknoonCallPresentationResult.PLATFORM_FAILED,
        )
        SystemClock.sleep(DENIAL_SETTLE_MS)
        if (Build.VERSION.SDK_INT >= 34) {
            assertTrue(
                "denied full-screen access must not launch app UI",
                hasNoLiveAppActivity(),
            )
        }
        if (presentation == MknoonCallPresentationResult.PRESENTED) {
            assertRingingDescriptor(payload.nativeCallId)
            reportNotificationDenialBoundary(
                if (Build.VERSION.SDK_INT >= 34) {
                    NOTIFICATION_DENIAL_PRESENTED_NO_UI
                } else {
                    NOTIFICATION_DENIAL_PRESENTED_FULL_SCREEN_NA
                },
            )
            assertTrue(
                "denial fallback cleanup",
                runtime.controller.terminate(
                    payload.nativeCallId,
                    PendingNativeCallEventType.REMOTE_CANCELLED,
                ),
            )
        } else {
            val descriptor = requireDescriptor("platform-denied terminal descriptor")
            assertEquals(
                "platform denial fails closed exactly once",
                PendingNativeCallEventType.NATIVE_FAILURE,
                descriptor.terminalEvent?.type,
            )
            assertEquals("platform denial leaves no notification", 0, activeCallNotificationCount())
            assertFalse("platform denial never activates audio", runtime.controller.audioState().active)
            reportNotificationDenialBoundary(NOTIFICATION_DENIAL_PLATFORM_REJECTED)
        }
        acknowledgeTerminal(payload.nativeCallId)
    }

    @Test
    fun testVc204MicrophoneDeniedDoesNotActivateAudio() {
        assertEquals(
            "RECORD_AUDIO is host-denied",
            PackageManager.PERMISSION_DENIED,
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        val payload = payload(SLOT_MICROPHONE_DENIED)
        assertEquals(
            "denied-microphone call still presents",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertTrue("answer is durably accepted", runtime.controller.answer(payload.nativeCallId))
        assertNotNull("Dart ownership attach is represented", runtime.controller.attach())
        adoptDurably(payload.nativeCallId)
        assertFalse(
            "denied microphone never activates audio",
            runtime.controller.activateAudio(payload.nativeCallId),
        )
        assertFalse("audio state remains inactive", runtime.controller.audioState().active)
        assertTrue(
            "denied-microphone cleanup",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.END_REQUESTED,
            ),
        )
        acknowledgeTerminal(payload.nativeCallId)
    }

    @Test
    fun testVc204MicrophoneGrantAudioAndRouteChange() {
        assertEquals(
            "RECORD_AUDIO is host-granted",
            PackageManager.PERMISSION_GRANTED,
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        val payload = payload(SLOT_MICROPHONE_GRANTED)
        assertEquals(
            "granted-microphone call presents",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertTrue("answer is durably accepted", runtime.controller.answer(payload.nativeCallId))
        assertNotNull("Dart ownership attach is represented", runtime.controller.attach())
        adoptDurably(payload.nativeCallId)
        assertTrue(
            "granted microphone activates production audio ownership",
            runtime.controller.activateAudio(payload.nativeCallId),
        )
        assertTrue("audio state is active", runtime.controller.audioState().active)
        await("speaker endpoint availability") {
            ROUTE_SPEAKER in runtime.controller.audioState().availableRoutes
        }
        assertTrue(
            "speaker route request crosses the production platform",
            runtime.controller.requestRoute(payload.nativeCallId, ROUTE_SPEAKER),
        )
        await("speaker route callback") {
            runtime.controller.audioState().route == ROUTE_SPEAKER
        }
        assertTrue(
            "audio resources deactivate once",
            runtime.controller.deactivateAudio(payload.nativeCallId),
        )
        assertFalse("audio state is inactive after deactivation", runtime.controller.audioState().active)
        assertTrue(
            "granted-microphone cleanup",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.END_REQUESTED,
            ),
        )
        acknowledgeTerminal(payload.nativeCallId)
    }

    @Test
    fun testVc204OutgoingAuthenticatedCoreTelecomLifecycle() {
        assertEquals(
            "RECORD_AUDIO is host-granted for outgoing lifecycle proof",
            PackageManager.PERMISSION_GRANTED,
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        val payload = outgoingPayload(SLOT_OUTGOING)
        val expectedCallId = nativeCallIdFromCallHandle(payload.callHandle)
        assertTrue("outgoing handle maps to one opaque native UUID", expectedCallId == payload.nativeCallId)

        assertTrue(
            "authenticated outgoing registration reaches the actual production platform",
            runtime.registerOutgoingAuthenticated(payload.callHandle, payload.expiresAtMs),
        )
        val descriptor = requireDescriptor("authenticated outgoing descriptor")
        assertTrue("outgoing registration retains the same opaque UUID", expectedCallId == descriptor.nativeCallId)
        assertEquals(
            "durable outgoing direction",
            PendingNativeCallDirection.OUTGOING,
            descriptor.direction,
        )
        assertEquals(
            "durable direction maps to the Core-Telecom outgoing contract",
            CallAttributesCompat.DIRECTION_OUTGOING,
            coreTelecomDirection(descriptor.direction),
        )
        assertNull("outgoing registration is nonterminal", descriptor.terminalEvent)
        assertEquals(
            "one actual registration has one durable presentation event",
            listOf(PendingNativeCallEventType.PRESENTED),
            descriptor.events.map { it.type },
        )
        assertFalse(
            "outgoing registration precedes audio activation",
            runtime.controller.audioState().active,
        )
        assertEquals(
            "outgoing registration does not present an incoming notification",
            0,
            activeCallNotificationCount(),
        )
        assertFalse(
            "outgoing registration does not start the microphone service",
            isCallForegroundServiceRunning(),
        )

        assertTrue(
            "authenticated outgoing retry is idempotent",
            runtime.registerOutgoingAuthenticated(payload.callHandle, payload.expiresAtMs),
        )
        assertEquals(
            "authenticated retry does not register a second durable call",
            listOf(PendingNativeCallEventType.PRESENTED),
            requireDescriptor("outgoing descriptor after retry").events.map { it.type },
        )

        assertNotNull("outgoing ownership attaches before adoption", runtime.controller.attach())
        adoptDurably(payload.nativeCallId)
        assertTrue(
            "the registered outgoing Core-Telecom call can activate production audio",
            runtime.controller.activateAudio(payload.nativeCallId),
        )
        await("outgoing active service and notification") {
            runtime.controller.audioState().active &&
                isCallForegroundServiceRunning() &&
                activeCallNotificationCount() == 1
        }

        assertTrue(
            "first outgoing cleanup owns the terminal transition",
            runtime.controller.endFromDart(payload.nativeCallId),
        )
        repeat(REPEATED_CLEANUP_ATTEMPTS) {
            assertFalse(
                "repeated outgoing Dart cleanup is a no-op",
                runtime.controller.endFromDart(payload.nativeCallId),
            )
            assertFalse(
                "repeated outgoing remote cleanup is a no-op",
                runtime.controller.terminate(
                    payload.nativeCallId,
                    PendingNativeCallEventType.END_REQUESTED,
                ),
            )
            assertFalse(
                "repeated outgoing Telecom cleanup is a no-op",
                runtime.controller.endFromTelecom(payload.nativeCallId),
            )
            assertFalse(
                "repeated outgoing audio cleanup is a no-op",
                runtime.controller.deactivateAudio(payload.nativeCallId),
            )
        }
        val terminal = requireDescriptor("outgoing terminal descriptor")
        assertEquals(
            "outgoing cleanup persists exactly one terminal event",
            1,
            terminal.events.count { it.type == PendingNativeCallEventType.END_REQUESTED },
        )
        await("outgoing cleanup removes service and notification residue") {
            !isCallForegroundServiceRunning() && activeCallNotificationCount() == 0
        }
        assertFalse(
            "outgoing cleanup leaves audio inactive",
            runtime.controller.audioState().active,
        )
        acknowledgeTerminal(payload.nativeCallId)
        assertNull(
            "outgoing terminal acknowledgement leaves no descriptor",
            runtime.controller.snapshot(),
        )
        assertFalse(
            "outgoing terminal acknowledgement leaves no service",
            isCallForegroundServiceRunning(),
        )
        assertEquals(
            "outgoing terminal acknowledgement leaves no notification",
            0,
            activeCallNotificationCount(),
        )
    }

    @Test
    fun testVc204DurablyAdoptedAudioActiveAcrossNetworkTransition() {
        assertEquals(
            "RECORD_AUDIO is host-granted for the live network transition",
            PackageManager.PERMISSION_GRANTED,
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        await("validated network before transition", NETWORK_TIMEOUT_MS) {
            hasValidatedInternet()
        }
        val payload = payload(SLOT_NETWORK_TRANSITION)
        var callEnded = false
        try {
            assertEquals(
                "online call reaches actual platform presentation",
                MknoonCallPresentationResult.PRESENTED,
                runtime.present(payload),
            )
            assertRingingDescriptor(payload.nativeCallId)
            assertTrue(
                "network-transition call answers",
                runtime.controller.answer(payload.nativeCallId),
            )
            assertNotNull("network-transition call attaches", runtime.controller.attach())
            adoptDurably(payload.nativeCallId)
            assertTrue(
                "network-transition call activates production audio ownership",
                runtime.controller.activateAudio(payload.nativeCallId),
            )
            await("speaker endpoint for the active network-transition call") {
                ROUTE_SPEAKER in runtime.controller.audioState().availableRoutes
            }
            assertTrue(
                "same adopted call selects the production speaker endpoint",
                runtime.controller.requestRoute(payload.nativeCallId, ROUTE_SPEAKER),
            )
            await("active call reaches the speaker endpoint") {
                runtime.controller.audioState().active &&
                    runtime.controller.audioState().route == ROUTE_SPEAKER
            }
            await("active call notification before host transition") {
                activeCallNotificationCount() == 1
            }
            assertEquals(
                "online active call remains in the protected journal",
                PendingNativeCallPhase.JOURNAL,
                requireDescriptor("online active journal").phase,
            )
            reportNetworkBoundary(NETWORK_BOUNDARY_READY)

            await("host makes validated connectivity unavailable", NETWORK_TIMEOUT_MS) {
                !hasValidatedInternet()
            }
            assertEquals(
                "offline active call remains in the protected journal",
                PendingNativeCallPhase.JOURNAL,
                requireDescriptor("offline active journal").phase,
            )
            assertTrue(
                "offline transition keeps production audio active",
                runtime.controller.audioState().active,
            )
            assertEquals(
                "offline transition keeps the selected production route",
                ROUTE_SPEAKER,
                runtime.controller.audioState().route,
            )
            assertEquals(
                "offline transition keeps exactly one OS call notification",
                1,
                activeCallNotificationCount(),
            )
            reportNetworkBoundary(NETWORK_BOUNDARY_OFFLINE)

            await("host restores validated connectivity", NETWORK_TIMEOUT_MS) {
                hasValidatedInternet()
            }
            assertEquals(
                "restored active call remains in the protected journal",
                PendingNativeCallPhase.JOURNAL,
                requireDescriptor("restored active journal").phase,
            )
            assertTrue(
                "restored transition keeps production audio active",
                runtime.controller.audioState().active,
            )
            assertEquals(
                "restored transition keeps the selected production route",
                ROUTE_SPEAKER,
                runtime.controller.audioState().route,
            )
            assertEquals(
                "restored transition keeps exactly one OS call notification",
                1,
                activeCallNotificationCount(),
            )
            reportNetworkBoundary(NETWORK_BOUNDARY_RESTORED)

            assertTrue(
                "same adopted call releases audio after both transitions",
                runtime.controller.deactivateAudio(payload.nativeCallId),
            )
            assertFalse(
                "network-transition audio is inactive after cleanup",
                runtime.controller.audioState().active,
            )
            assertTrue(
                "same adopted call ends exactly once after restored connectivity",
                runtime.controller.endFromDart(payload.nativeCallId),
            )
            callEnded = true
            assertFalse(
                "same adopted call cannot end twice",
                runtime.controller.endFromDart(payload.nativeCallId),
            )
            acknowledgeTerminal(payload.nativeCallId)
        } finally {
            if (!callEnded) {
                if (runtime.controller.audioState().active) {
                    runtime.controller.deactivateAudio(payload.nativeCallId)
                }
                if (!runtime.controller.endFromDart(payload.nativeCallId)) {
                    runtime.controller.terminate(
                        payload.nativeCallId,
                        PendingNativeCallEventType.END_REQUESTED,
                    )
                }
            }
        }
    }

    @Test
    fun testVc204SeedAcknowledgedActiveBeforeAmKill() {
        assertEquals(
            "RECORD_AUDIO is host-granted for active process-death proof",
            PackageManager.PERMISSION_GRANTED,
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO),
        )
        val payload = payload(SLOT_ACTIVE_PROCESS_DEATH)
        assertEquals(
            "active process-death seed presents",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertTrue("active seed answers", runtime.controller.answer(payload.nativeCallId))
        val attachment = runtime.controller.attach()
        assertNotNull("active seed attaches", attachment)
        adoptDurably(payload.nativeCallId)
        assertTrue("active seed owns audio", runtime.controller.activateAudio(payload.nativeCallId))
        assertEquals(
            "acknowledged active ownership is durably journaled",
            PendingNativeCallPhase.JOURNAL,
            requireDescriptor("active seed journal").phase,
        )
        assertTrue(
            "same-UID proof quiesces the non-exported active foreground service",
            context.stopService(Intent(context, MknoonCallForegroundService::class.java)),
        )
        await("active foreground service notification is quiesced") {
            activeCallNotificationCount() == 0
        }
        // Deliberately leave volatile platform/audio ownership live. The
        // proof-only seed receiver repeats this setup in a resident background
        // process so the host can exercise a real `am kill` boundary.
    }

    @Test
    fun testVc204AcknowledgedActiveDoesNotResurrectAfterAmKill() {
        val callId = payload(SLOT_ACTIVE_PROCESS_DEATH).nativeCallId
        val descriptor = requireDescriptor("adopted journal after process recreation")
        assertEquals("adopted custody remains journaled", PendingNativeCallPhase.JOURNAL, descriptor.phase)
        assertEquals(
            "provider loss is the dominating replayable terminal",
            PendingNativeCallEventType.PROVIDER_REMOVED,
            descriptor.terminalEvent?.type,
        )
        assertEquals(
            "provider-loss terminal is durable exactly once",
            1,
            descriptor.events.count { it.type == PendingNativeCallEventType.PROVIDER_REMOVED },
        )
        assertNotNull("new process can replay the terminal journal", runtime.controller.attach())
        assertFalse("new process has no adopted audio", runtime.controller.audioState().active)
        assertFalse("answer cannot resurrect acknowledged ownership", runtime.controller.answer(callId))
        assertFalse("end cannot resurrect acknowledged ownership", runtime.controller.endFromDart(callId))
        assertTrue(
            "terminal journal is acknowledged exactly",
            runtime.controller.acknowledge(
                callId,
                descriptor.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertNull("terminal acknowledgement hides the durable receipt", runtime.controller.snapshot())
    }

    @Test
    fun testVc204RepeatedCleanupIsIdempotent() {
        val payload = payload(SLOT_REPEATED_CLEANUP)
        assertEquals(
            "cleanup seed presents",
            MknoonCallPresentationResult.PRESENTED,
            runtime.present(payload),
        )
        assertTrue(
            "first cleanup owns the terminal transition",
            runtime.controller.terminate(
                payload.nativeCallId,
                PendingNativeCallEventType.REMOTE_CANCELLED,
            ),
        )
        repeat(REPEATED_CLEANUP_ATTEMPTS) {
            assertFalse(
                "repeated remote cleanup is a no-op",
                runtime.controller.terminate(
                    payload.nativeCallId,
                    PendingNativeCallEventType.REMOTE_CANCELLED,
                ),
            )
            assertFalse(
                "repeated Dart cleanup is a no-op",
                runtime.controller.endFromDart(payload.nativeCallId),
            )
            assertFalse(
                "repeated Telecom cleanup is a no-op",
                runtime.controller.endFromTelecom(payload.nativeCallId),
            )
            assertFalse(
                "repeated audio cleanup is a no-op",
                runtime.controller.deactivateAudio(payload.nativeCallId),
            )
        }
        val descriptor = requireDescriptor("repeated cleanup terminal descriptor")
        assertEquals(
            "cleanup persists exactly one terminal event",
            1,
            descriptor.events.count { it.type == PendingNativeCallEventType.REMOTE_CANCELLED },
        )
        acknowledgeTerminal(payload.nativeCallId)
    }

    private fun assertRingingDescriptor(expectedCallId: UUID) {
        val descriptor = requireDescriptor("durable ringing descriptor")
        assertTrue("same opaque fixture call", expectedCallId == descriptor.nativeCallId)
        assertNull("ringing descriptor is nonterminal", descriptor.terminalEvent)
        assertTrue(
            "presentation event is durable",
            descriptor.events.any { it.type == PendingNativeCallEventType.PRESENTED },
        )
    }

    private fun requireDescriptor(boundary: String): PendingNativeCallDescriptor {
        val descriptor = runtime.controller.snapshot()
        assertNotNull(boundary, descriptor)
        return checkNotNull(descriptor) { boundary }
    }

    private fun adoptDurably(expectedCallId: UUID) {
        assertTrue(
            "call is marked adopted before durable handoff",
            runtime.controller.markAdopted(expectedCallId),
        )
        val descriptor = requireDescriptor("descriptor before durable adoption")
        assertTrue("same opaque fixture call", expectedCallId == descriptor.nativeCallId)
        assertTrue(
            "exact ADOPTED acknowledgement starts the protected journal",
            runtime.controller.acknowledge(
                expectedCallId,
                descriptor.highestSequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertEquals(
            "durably adopted ownership remains replayable in the protected journal",
            PendingNativeCallPhase.JOURNAL,
            requireDescriptor("descriptor after durable adoption").phase,
        )
    }

    private fun acknowledgeTerminal(expectedCallId: UUID) {
        val descriptor = requireDescriptor("terminal descriptor before exact acknowledgement")
        assertTrue("same opaque fixture call", expectedCallId == descriptor.nativeCallId)
        assertNotNull("terminal acknowledgement requires terminal state", descriptor.terminalEvent)
        await("terminal platform notification cleanup") {
            activeCallNotificationCount() == 0
        }
        await("terminal acknowledgement deletes durable native ownership") {
            runtime.controller.acknowledge(
                expectedCallId,
                descriptor.highestSequence,
                PendingNativeCallAcknowledgement.TERMINAL,
            )
        }
        assertNull("terminal acknowledgement leaves no descriptor", runtime.controller.snapshot())
    }

    private fun payload(slot: Int, deliveryDelayMs: Long = 0L): CallWakePayload {
        val observedNow = System.currentTimeMillis()
        val nativeCallId = nativeCallIdFromCallHandle(opaqueHandle(slot))
        return CallWakePayload(
            nativeCallId = nativeCallId,
            callHandle = nativeCallId.toString(),
            wakeHandle = opaqueHandle(slot + WAKE_HANDLE_OFFSET),
            receivedAtMs = observedNow,
            expiresAtMs = observedNow + PAYLOAD_LIFETIME_MS - deliveryDelayMs,
        )
    }

    private fun outgoingPayload(slot: Int): CallWakePayload {
        val observedNow = System.currentTimeMillis()
        val callHandle = "00000000-0000-4000-8000-${slot.toString(16).padStart(12, '0')}"
        return CallWakePayload(
            nativeCallId = nativeCallIdFromCallHandle(callHandle),
            callHandle = callHandle,
            wakeHandle = opaqueHandle(slot + WAKE_HANDLE_OFFSET),
            receivedAtMs = observedNow,
            expiresAtMs = observedNow + PAYLOAD_LIFETIME_MS,
        )
    }

    private fun opaqueHandle(value: Int): String = value.toString(16).padStart(32, '0')

    private fun launchMainActivity(): MainActivity {
        val launchIntent = checkNotNull(
            context.packageManager.getLaunchIntentForPackage(PROOF_APPLICATION_ID),
        ) { "disposable launcher Activity" }
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return instrumentation.startActivitySync(launchIntent) as MainActivity
    }

    private fun finishActivity(activity: Activity) {
        instrumentation.runOnMainSync { activity.finishAndRemoveTask() }
        instrumentation.waitForIdleSync()
    }

    private fun hasNoLiveAppActivity(): Boolean =
        context.getSystemService(android.app.ActivityManager::class.java)
            .appTasks
            .none { it.taskInfo.topActivity?.packageName == PROOF_APPLICATION_ID }

    private fun notifications(): NotificationManager =
        context.getSystemService(NotificationManager::class.java)

    private fun keyguard(): KeyguardManager =
        context.getSystemService(KeyguardManager::class.java)

    @Suppress("DEPRECATION")
    private fun isCallForegroundServiceRunning(): Boolean {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        return activityManager.getRunningServices(Int.MAX_VALUE).any {
            it.service.className == MknoonCallForegroundService::class.java.name
        }
    }

    private fun activeCallNotificationCount(): Int =
        notifications().activeNotifications.count {
            it.id == MknoonCallNotificationFactory.NOTIFICATION_ID &&
                it.notification.category == Notification.CATEGORY_CALL
        }

    private fun hasValidatedInternet(): Boolean {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val active = connectivity.activeNetwork ?: return false
        val capabilities = connectivity.getNetworkCapabilities(active) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun reportNetworkBoundary(boundary: String) {
        instrumentation.sendStatus(
            NETWORK_BOUNDARY_STATUS_CODE,
            Bundle().apply { putString(NETWORK_BOUNDARY_STATUS_KEY, boundary) },
        )
    }

    private fun reportNotificationDenialBoundary(boundary: String) {
        instrumentation.sendStatus(
            NOTIFICATION_DENIAL_STATUS_CODE,
            Bundle().apply { putString(NOTIFICATION_DENIAL_STATUS_KEY, boundary) },
        )
    }

    private fun await(
        boundary: String,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
        predicate: () -> Boolean,
    ) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        do {
            instrumentation.waitForIdleSync()
            if (predicate()) return
            SystemClock.sleep(POLL_MS)
        } while (SystemClock.elapsedRealtime() < deadline)
        assertTrue(boundary, predicate())
    }

    private companion object {
        const val PROOF_APPLICATION_ID = "com.mknoon.app.vc204proof"
        const val ROUTE_SPEAKER = "speaker"
        const val SLOT_FOREGROUND = 1
        const val SLOT_DELAYED_DUPLICATE = 2
        const val SLOT_RINGING_PROCESS_DEATH = 3
        const val SLOT_LOCKED = 4
        const val SLOT_NOTIFICATION_DENIED = 5
        const val SLOT_MICROPHONE_DENIED = 6
        const val SLOT_MICROPHONE_GRANTED = 7
        const val SLOT_NETWORK_TRANSITION = 8
        const val SLOT_ACTIVE_PROCESS_DEATH = 9
        const val SLOT_REPEATED_CLEANUP = 10
        const val SLOT_OUTGOING = 11
        const val WAKE_HANDLE_OFFSET = 10_000
        const val REPEATED_CLEANUP_ATTEMPTS = 3
        const val PAYLOAD_LIFETIME_MS = 40_000L
        const val DEFAULT_TIMEOUT_MS = 8_000L
        const val NETWORK_TIMEOUT_MS = 30_000L
        const val NETWORK_BOUNDARY_STATUS_CODE = 2
        const val NOTIFICATION_DENIAL_STATUS_CODE = 3
        const val KEYGUARD_POLICY_STATUS_CODE = 4
        const val NETWORK_BOUNDARY_STATUS_KEY = "vc204NetworkBoundary"
        const val NOTIFICATION_DENIAL_STATUS_KEY = "vc204NotificationDenial"
        const val KEYGUARD_POLICY_STATUS_KEY = "vc204KeyguardPolicy"
        const val NETWORK_BOUNDARY_READY = "audio-active-online-ready"
        const val NETWORK_BOUNDARY_OFFLINE = "same-call-audio-active-offline"
        const val NETWORK_BOUNDARY_RESTORED = "same-call-audio-active-restored"
        const val NOTIFICATION_DENIAL_PRESENTED_NO_UI = "telecom-presented-no-ui"
        const val NOTIFICATION_DENIAL_PRESENTED_FULL_SCREEN_NA =
            "telecom-presented-notification-denied-full-screen-na"
        const val NOTIFICATION_DENIAL_PLATFORM_REJECTED = "platform-rejected-clean"
        const val KEYGUARD_SECURE = "secure"
        const val KEYGUARD_NON_SECURE = "non-secure"
        const val DENIAL_SETTLE_MS = 750L
        const val POLL_MS = 50L
    }
}
