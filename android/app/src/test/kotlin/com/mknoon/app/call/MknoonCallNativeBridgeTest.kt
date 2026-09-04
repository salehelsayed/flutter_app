package com.mknoon.app.call

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallNativeBridgeTest {
    @Test
    fun `cold attach returns the exact empty compatibility envelope`() {
        val rig = LifecycleRig()
        val bridge = MknoonCallNativeBridge(controller = rig.controller, messenger = null)
        val result = CapturingCallBridgeResult()

        bridge.onMethodCall(MethodCall("attach", mapOf("version" to 1)), result)

        assertEquals(
            mapOf(
                "version" to 1,
                "descriptor" to null,
                "events" to emptyList<Map<String, Any?>>(),
                "nativeCallId" to null,
                "highestSequence" to 0L,
            ),
            result.value,
        )
    }

    @Test
    fun `attach returns the same pending snapshot without consuming it`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        assertTrue(rig.controller.answer(rig.payload.nativeCallId))
        val bridge = MknoonCallNativeBridge(
            controller = rig.controller,
            messenger = null,
        )

        val first = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall("attach", null), first)
        val second = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall("attach", null), second)

        assertNotNull(first.value)
        assertEquals(first.value, second.value)
        assertEquals(
            setOf("callHandle", "expiresAtMs", "direction", "phase", "presented"),
            ((first.value as Map<*, *>)["descriptor"] as Map<*, *>).keys,
        )
        assertEquals(
            "incoming",
            ((first.value as Map<*, *>)["descriptor"] as Map<*, *>)["direction"],
        )
        assertEquals(
            "preStart",
            ((first.value as Map<*, *>)["descriptor"] as Map<*, *>)["phase"],
        )
        assertEquals(
            rig.payload.nativeCallId.toString(),
            (first.value as Map<*, *>)["nativeCallId"],
        )
        assertEquals(
            requireNotNull(rig.store.lastDescriptor).highestSequence,
            (first.value as Map<*, *>)["highestSequence"],
        )
        assertNotNull(rig.store.lastDescriptor)
        assertEquals(0, rig.store.deleteCalls)
    }

    @Test
    fun `exact partial ACK retains then adopted or terminal ACK deletes once`() {
        for (finalAck in listOf("ADOPTED", "TERMINAL")) {
            val rig = LifecycleRig()
            assertEquals(
                MknoonCallPresentationResult.PRESENTED,
                rig.controller.present(rig.payload),
            )
            assertTrue(rig.controller.answer(rig.payload.nativeCallId))
            val bridge = MknoonCallNativeBridge(
                controller = rig.controller,
                messenger = null,
            )
            val firstHighest = requireNotNull(rig.store.lastDescriptor).highestSequence

            assertBridgeSuccess(
                bridge,
                "acknowledge",
                acknowledgementArguments(rig, firstHighest + 1L, "NONE"),
                expected = false,
            )
            assertBridgeSuccess(
                bridge,
                "acknowledge",
                acknowledgementArguments(rig, firstHighest - 1L, "NONE"),
                expected = true,
            )
            assertNotNull(rig.store.lastDescriptor)
            assertEquals(
                listOf(firstHighest),
                requireNotNull(rig.store.lastDescriptor).events.map { it.sequence },
            )
            assertEquals(0, rig.store.deleteCalls)

            if (finalAck == "ADOPTED") {
                assertTrue(
                    rig.controller.onMuteChanged(
                        rig.payload.nativeCallId,
                        muted = true,
                    ),
                )
            } else {
                assertTrue(
                    rig.controller.terminate(
                        rig.payload.nativeCallId,
                        PendingNativeCallEventType.REMOTE_CANCELLED,
                    ),
                )
            }
            val finalHighest = requireNotNull(rig.store.lastDescriptor).highestSequence
            val finalArguments = acknowledgementArguments(rig, finalHighest, finalAck)

            assertBridgeSuccess(
                bridge,
                "acknowledge",
                finalArguments,
                expected = true,
            )
            if (finalAck == "ADOPTED") {
                assertEquals(0, rig.store.deleteCalls)
                assertEquals(
                    PendingNativeCallPhase.JOURNAL,
                    requireNotNull(rig.store.lastDescriptor).phase,
                )
            } else {
                assertEquals(1, rig.store.deleteCalls)
            }
            assertBridgeSuccess(
                bridge,
                "acknowledge",
                finalArguments,
                expected = true,
            )
            assertEquals(if (finalAck == "ADOPTED") 0 else 1, rig.store.deleteCalls)
        }
    }

    @Test
    fun `malformed bridge calls return bad_args without throwing or mutating lifecycle`() {
        val rig = LifecycleRig()
        val bridge = MknoonCallNativeBridge(
            controller = rig.controller,
            messenger = null,
        )
        val malformedCalls = listOf(
            MethodCall("attach", mapOf("unexpected" to true)),
            MethodCall("acknowledge", null),
            MethodCall(
                "acknowledge",
                mapOf(
                    "nativeCallId" to "not-a-uuid",
                    "highestConsumedSequence" to 1L,
                    "acknowledgement" to "NONE",
                ),
            ),
            MethodCall(
                "acknowledge",
                mapOf(
                    "nativeCallId" to CALL_ID,
                    "highestConsumedSequence" to 1.5,
                    "acknowledgement" to "NONE",
                ),
            ),
            MethodCall(
                "acknowledge",
                mapOf(
                    "nativeCallId" to CALL_ID,
                    "highestConsumedSequence" to 1L,
                    "acknowledgement" to "CONSUMED",
                ),
            ),
            MethodCall("markAdopted", mapOf("nativeCallId" to 401L)),
            MethodCall("activateAudio", mapOf("nativeCallId" to "not-a-uuid")),
            MethodCall("end", emptyMap<String, Any?>()),
        )

        for (call in malformedCalls) {
            val result = CapturingCallBridgeResult()
            bridge.onMethodCall(call, result)
            assertEquals("bad_args", result.errorCode)
        }

        val unknown = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall("unknown", null), unknown)
        assertTrue(unknown.notImplemented)
        assertEquals(0, rig.store.createCalls)
        assertTrue(rig.store.acknowledgementCalls.isEmpty())
        assertEquals(0, rig.platform.registerCalls)
        assertEquals(0, rig.platform.startMicrophoneCalls)
    }

    @Test
    fun `outgoing authenticated registration is strict versioned idempotent and exposes direction`() {
        val rig = LifecycleRig()
        var registrarCalls = 0
        val bridge = MknoonCallNativeBridge(
            controller = rig.controller,
            messenger = null,
            authenticatedOutgoingRegistrar = { callHandle, expiresAtMs ->
                registrarCalls += 1
                val nativeCallId = UUID.fromString(callHandle)
                when (
                    rig.controller.registerOutgoing(
                        callPayload(nativeCallId).copy(expiresAtMs = expiresAtMs),
                    )
                ) {
                    MknoonCallPresentationResult.PRESENTED,
                    MknoonCallPresentationResult.DUPLICATE,
                    -> true
                    else -> false
                }
            },
        )
        val arguments = mapOf(
            "version" to 1,
            "callHandle" to rig.payload.callHandle,
            "expiresAtMs" to rig.payload.expiresAtMs,
        )

        assertBridgeSuccess(
            bridge,
            "registerOutgoingAuthenticated",
            arguments,
            expected = true,
        )
        assertBridgeSuccess(
            bridge,
            "registerOutgoingAuthenticated",
            arguments,
            expected = true,
        )
        assertEquals(1, registrarCalls)
        assertEquals(1, rig.platform.registerOutgoingCalls)
        assertEquals(0, rig.platform.registerCalls)

        val attached = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall("attach", mapOf("version" to 1)), attached)
        val envelope = attached.value as Map<*, *>
        val descriptor = envelope["descriptor"] as Map<*, *>
        assertEquals("outgoing", descriptor["direction"])
        assertEquals(true, descriptor["presented"])
        assertEquals(
            listOf("presented"),
            (envelope["events"] as List<*>)
                .map { event -> (event as Map<*, *>)["type"] },
        )

        for (malformed in listOf(
            null,
            mapOf("version" to 2, "callHandle" to rig.payload.callHandle, "expiresAtMs" to 1L),
            arguments + ("extra" to true),
            arguments + ("expiresAtMs" to 1.5),
        )) {
            val result = CapturingCallBridgeResult()
            bridge.onMethodCall(
                MethodCall("registerOutgoingAuthenticated", malformed),
                result,
            )
            assertEquals("bad_args", result.errorCode)
        }
        assertEquals(1, registrarCalls)
    }

    @Test
    fun `well formed adoption audio and Dart end calls delegate to one controller`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        val bridge = MknoonCallNativeBridge(
            controller = rig.controller,
            messenger = null,
        )
        val idArguments = mapOf("nativeCallId" to rig.payload.nativeCallId.toString())

        assertBridgeSuccess(bridge, "markAdopted", idArguments, expected = true)
        val adoptionSequence = requireNotNull(rig.store.lastDescriptor).highestSequence
        assertBridgeSuccess(
            bridge,
            "acknowledge",
            acknowledgementArguments(rig, adoptionSequence, "ADOPTED"),
            expected = true,
        )
        assertTrue(rig.controller.answerFromTelecom(rig.payload.nativeCallId))
        assertBridgeSuccess(bridge, "activateAudio", idArguments, expected = true)
        assertBridgeSuccess(bridge, "end", idArguments, expected = true)
        assertBridgeSuccess(bridge, "end", idArguments, expected = false)

        assertEquals(1, rig.platform.startMicrophoneCalls)
        assertEquals(1, rig.platform.endCalls)
    }

    @Test
    fun `superseded bridge cannot detach owner or receive newer relay events`() {
        val rig = LifecycleRig()
        val relay = MknoonCallEventRelay()
        val controller = MknoonCallLifecycleController(
            store = rig.store,
            platform = rig.platform,
            eventSink = relay,
            capabilityEnabled = { true },
            recordAudioPermissionGranted = { true },
            nowMs = { NOW_MS },
        )
        assertEquals(MknoonCallPresentationResult.PRESENTED, controller.present(rig.payload))
        var staleFailClosedCalls = 0
        val oldBridge = MknoonCallNativeBridge(
            controller,
            messenger = null,
            relay = relay,
            failCloser = {
                staleFailClosedCalls += 1
                false
            },
        )
        val oldSink = CapturingCallEventSink()
        oldBridge.onListen(null, oldSink)
        val currentBridge = MknoonCallNativeBridge(controller, messenger = null, relay = relay)
        val currentSink = CapturingCallEventSink()
        currentBridge.onListen(null, currentSink)
        currentBridge.onMethodCall(
            MethodCall("attach", mapOf("version" to 1)),
            CapturingCallBridgeResult(),
        )

        oldBridge.dispose()
        val staleResult = CapturingCallBridgeResult()
        oldBridge.onMethodCall(
            MethodCall("failClosed", mapOf("version" to 1)),
            staleResult,
        )
        assertEquals(false, staleResult.value)
        assertEquals(0, staleFailClosedCalls)
        assertTrue(controller.answer(rig.payload.nativeCallId))

        assertTrue(oldSink.values.isEmpty())
        assertEquals(1, currentSink.values.size)
        assertEquals(null, requireNotNull(controller.snapshot()).terminalEvent)
        currentBridge.dispose()
        assertEquals(null, requireNotNull(controller.snapshot()).terminalEvent)
    }

    @Test
    fun `same bridge reattaches and delivers native answer after stream restart`() {
        val rig = LifecycleRig()
        val relay = MknoonCallEventRelay()
        val controller = MknoonCallLifecycleController(
            store = rig.store,
            platform = rig.platform,
            eventSink = relay,
            capabilityEnabled = { true },
            recordAudioPermissionGranted = { true },
            nowMs = { NOW_MS },
        )
        val bridge = MknoonCallNativeBridge(
            controller,
            messenger = null,
            relay = relay,
        )
        val originalSink = CapturingCallEventSink()
        bridge.onListen(null, originalSink)
        bridge.onMethodCall(
            MethodCall("attach", mapOf("version" to 1)),
            CapturingCallBridgeResult(),
        )

        bridge.onCancel(null)
        val restartedSink = CapturingCallEventSink()
        bridge.onListen(null, restartedSink)
        bridge.onMethodCall(
            MethodCall("attach", mapOf("version" to 1)),
            CapturingCallBridgeResult(),
        )

        assertEquals(
            MknoonCallPresentationResult.PRESENTED,
            controller.present(rig.payload),
        )
        assertTrue(controller.answerFromTelecom(rig.payload.nativeCallId))

        assertTrue(originalSink.values.isEmpty())
        assertEquals(2, restartedSink.values.size)
        assertEquals(
            listOf("presented", "answer"),
            restartedSink.values.map { envelope ->
                val events = (envelope as Map<*, *>)["events"] as List<*>
                (events.single() as Map<*, *>)["type"]
            },
        )
    }

    @Test
    fun `bridge generation ownership is serialized through fail closed mutation`() {
        val rig = LifecycleRig()
        val relay = MknoonCallEventRelay()
        val cleanupEntered = CountDownLatch(1)
        val allowCleanup = CountDownLatch(1)
        val bindAttempted = CountDownLatch(1)
        val currentBound = CountDownLatch(1)
        val oldBridge = MknoonCallNativeBridge(
            rig.controller,
            messenger = null,
            relay = relay,
            failCloser = {
                cleanupEntered.countDown()
                assertTrue(allowCleanup.await(1L, TimeUnit.SECONDS))
                true
            },
        )
        val oldResult = CapturingCallBridgeResult()
        val currentBridge = AtomicReference<MknoonCallNativeBridge?>()
        val closeThread = Thread {
            oldBridge.onMethodCall(
                MethodCall("failClosed", mapOf("version" to 1)),
                oldResult,
            )
        }.apply { start() }
        assertTrue(cleanupEntered.await(1L, TimeUnit.SECONDS))
        val bindThread = Thread {
            bindAttempted.countDown()
            currentBridge.set(
                MknoonCallNativeBridge(rig.controller, messenger = null, relay = relay),
            )
            currentBound.countDown()
        }.apply { start() }

        assertTrue(bindAttempted.await(1L, TimeUnit.SECONDS))
        assertFalse(currentBound.await(50L, TimeUnit.MILLISECONDS))
        allowCleanup.countDown()
        closeThread.join(1_000L)
        bindThread.join(1_000L)

        assertEquals(true, oldResult.value)
        assertNotNull(currentBridge.get())
        val staleRetry = CapturingCallBridgeResult()
        oldBridge.onMethodCall(
            MethodCall("failClosed", mapOf("version" to 1)),
            staleRetry,
        )
        assertEquals(false, staleRetry.value)
    }

    @Test
    fun `controller event emission cannot deadlock generation owned fail closed`() {
        val rig = LifecycleRig()
        val relay = MknoonCallEventRelay()
        val controller = MknoonCallLifecycleController(
            store = rig.store,
            platform = rig.platform,
            eventSink = relay,
            capabilityEnabled = { true },
            recordAudioPermissionGranted = { true },
            nowMs = { NOW_MS },
        )
        assertEquals(MknoonCallPresentationResult.PRESENTED, controller.present(rig.payload))
        val routeAppendEntered = CountDownLatch(1)
        val allowRouteAppend = CountDownLatch(1)
        val failClosedEntered = CountDownLatch(1)
        rig.store.onAppend = { type ->
            if (type == PendingNativeCallEventType.ROUTE_CHANGED) {
                routeAppendEntered.countDown()
                assertTrue(allowRouteAppend.await(1L, TimeUnit.SECONDS))
            }
        }
        val bridge = MknoonCallNativeBridge(
            controller,
            messenger = null,
            relay = relay,
            failCloser = {
                failClosedEntered.countDown()
                controller.failClosed()
            },
        )
        bridge.onMethodCall(
            MethodCall("attach", mapOf("version" to 1)),
            CapturingCallBridgeResult(),
        )
        val routeThread = Thread {
            controller.onRouteChanged(rig.payload.nativeCallId, "speaker")
        }.apply { start() }
        assertTrue(routeAppendEntered.await(1L, TimeUnit.SECONDS))
        val failResult = CapturingCallBridgeResult()
        val failThread = Thread {
            bridge.onMethodCall(
                MethodCall("failClosed", mapOf("version" to 1)),
                failResult,
            )
        }.apply { start() }
        assertTrue(failClosedEntered.await(1L, TimeUnit.SECONDS))

        allowRouteAppend.countDown()
        routeThread.join(1_000L)
        failThread.join(1_000L)

        assertFalse(routeThread.isAlive)
        assertFalse(failThread.isAlive)
        assertEquals(true, failResult.value)
        assertEquals(
            PendingNativeCallEventType.NATIVE_FAILURE,
            requireNotNull(controller.snapshot()).terminalEvent?.type,
        )
    }

    @Test
    fun `relay bind drains a claimed old delivery before publishing new owner`() {
        val deliveryClaimed = CountDownLatch(1)
        val allowDelivery = CountDownLatch(1)
        val bindAttempted = CountDownLatch(1)
        val bindFinished = CountDownLatch(1)
        val oldDeliveries = AtomicInteger(0)
        val newDeliveries = AtomicInteger(0)
        val oldCountAtBindReturn = AtomicInteger(-1)
        val relay = MknoonCallEventRelay {
            deliveryClaimed.countDown()
            assertTrue(allowDelivery.await(1L, TimeUnit.SECONDS))
        }
        relay.bind { oldDeliveries.incrementAndGet() }
        val event = PendingNativeCallEvent(
            nativeCallId = java.util.UUID.fromString(CALL_ID),
            sequence = 1L,
            eventId = java.util.UUID.fromString("00000000-0000-4000-8000-000000000498"),
            type = PendingNativeCallEventType.ROUTE_CHANGED,
        )
        val emitThread = Thread { relay.emit(event) }.apply { start() }
        assertTrue(deliveryClaimed.await(1L, TimeUnit.SECONDS))
        val bindThread = Thread {
            bindAttempted.countDown()
            relay.bind { newDeliveries.incrementAndGet() }
            oldCountAtBindReturn.set(oldDeliveries.get())
            bindFinished.countDown()
        }.apply { start() }

        assertTrue(bindAttempted.await(1L, TimeUnit.SECONDS))
        assertFalse(bindFinished.await(50L, TimeUnit.MILLISECONDS))
        assertEquals(0, oldDeliveries.get())
        allowDelivery.countDown()
        emitThread.join(1_000L)
        bindThread.join(1_000L)

        assertEquals(1, oldCountAtBindReturn.get())
        relay.emit(event.copy(sequence = 2L))
        assertEquals(1, oldDeliveries.get())
        assertEquals(1, newDeliveries.get())
    }

    @Test
    fun `explicit fail closed disables capability before terminalizing pre-start ownership`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        var enabled = true
        val bridge = MknoonCallNativeBridge(
            controller = rig.controller,
            messenger = null,
            failCloser = {
                enabled = false
                rig.operations += "capability.false"
                rig.controller.failClosed()
            },
        )
        val result = CapturingCallBridgeResult()

        bridge.onMethodCall(MethodCall("failClosed", mapOf("version" to 1)), result)

        assertEquals(true, result.value)
        assertFalse(enabled)
        assertEquals(
            PendingNativeCallEventType.NATIVE_FAILURE,
            requireNotNull(rig.controller.snapshot()).terminalEvent?.type,
        )
        assertTrue(
            rig.operations.indexOf("capability.false") <
                rig.operations.indexOf("store.append:NATIVE_FAILURE"),
        )
        assertEquals(1, rig.platform.endCalls)
        assertEquals(1, rig.platform.stopForegroundCalls)
        assertEquals(1, rig.platform.cancelNotificationCalls)
    }

    @Test
    fun `normal detach preserves pre-start descriptor for engine recreation`() {
        val rig = LifecycleRig()
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        val relay = MknoonCallEventRelay()
        val bridge = MknoonCallNativeBridge(rig.controller, messenger = null, relay = relay)
        val result = CapturingCallBridgeResult()

        bridge.onMethodCall(MethodCall("detach", mapOf("version" to 1)), result)

        assertEquals(true, result.value)
        assertEquals(null, requireNotNull(rig.controller.snapshot()).terminalEvent)
        assertEquals(0, rig.platform.endCalls)

        val staleAttach = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall("attach", mapOf("version" to 1)), staleAttach)
        assertEquals(null, (staleAttach.value as Map<*, *>)["descriptor"])

        val replacement = MknoonCallNativeBridge(
            rig.controller,
            messenger = null,
            relay = relay,
        )
        val replacementAttach = CapturingCallBridgeResult()
        replacement.onMethodCall(
            MethodCall("attach", mapOf("version" to 1)),
            replacementAttach,
        )
        assertNotNull((replacementAttach.value as Map<*, *>)["descriptor"])
    }

    @Test
    fun `stale terminal receipt handle cannot read a newer calls audio state`() {
        val rig = LifecycleRig()
        val newerPayload = callPayload(java.util.UUID.fromString(OTHER_CALL_ID))
        rig.store.lastDescriptor = descriptorFor(newerPayload)
        rig.store.receiptNativeCallIds[rig.payload.callHandle] = rig.payload.nativeCallId
        assertTrue(
            rig.controller.onRouteChanged(newerPayload.nativeCallId, "speaker"),
        )
        val bridge = MknoonCallNativeBridge(rig.controller, messenger = null)

        val stale = CapturingCallBridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "readAudioState",
                mapOf("version" to 1, "callHandle" to rig.payload.callHandle),
            ),
            stale,
        )
        assertEquals("bad_args", stale.errorCode)

        val current = CapturingCallBridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "readAudioState",
                mapOf("version" to 1, "callHandle" to newerPayload.callHandle),
            ),
            current,
        )
        assertEquals(
            "speaker",
            (current.value as Map<*, *>)["route"],
        )
    }

    private fun acknowledgementArguments(
        rig: LifecycleRig,
        highestConsumedSequence: Long,
        acknowledgement: String,
    ): Map<String, Any> = mapOf(
        "nativeCallId" to rig.payload.nativeCallId.toString(),
        "highestConsumedSequence" to highestConsumedSequence,
        "acknowledgement" to acknowledgement,
    )

    private fun assertBridgeSuccess(
        bridge: MknoonCallNativeBridge,
        method: String,
        arguments: Any?,
        expected: Any?,
    ) {
        val result = CapturingCallBridgeResult()
        bridge.onMethodCall(MethodCall(method, arguments), result)
        assertEquals(null, result.errorCode)
        assertFalse(result.notImplemented)
        assertEquals(expected, result.value)
    }
}

private class CapturingCallEventSink : EventChannel.EventSink {
    val values = mutableListOf<Any?>()

    override fun success(event: Any?) {
        values += event
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

    override fun endOfStream() = Unit
}

private class CapturingCallBridgeResult : MethodChannel.Result {
    var value: Any? = null
    var errorCode: String? = null
    var notImplemented = false

    override fun success(result: Any?) {
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
    }

    override fun notImplemented() {
        notImplemented = true
    }
}
