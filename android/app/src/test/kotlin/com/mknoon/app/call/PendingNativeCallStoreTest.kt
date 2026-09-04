package com.mknoon.app.call

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingNativeCallStoreTest {
    @Test
    fun `one bounded descriptor returns duplicate for the same wake and busy for another call`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)

        val created = created(store.create(payloadA()))
        assertEquals(PendingNativeCallStore.SCHEMA_VERSION, created.descriptor.schemaVersion)
        assertEquals(PendingNativeCallPhase.PRE_START, created.descriptor.phase)
        assertEquals(NATIVE_CALL_ID_A, created.descriptor.nativeCallId)
        assertEquals(CALL_HANDLE_A, created.descriptor.callHandle)
        assertEquals(WAKE_HANDLE_A, created.descriptor.wakeHandle)
        assertEquals(NOW_MS, created.descriptor.receivedAtMs)
        assertEquals(NOW_MS + 45_000L, created.descriptor.expiresAtMs)
        assertEquals(0L, created.descriptor.highestSequence)
        assertTrue(created.descriptor.events.isEmpty())
        assertNull(created.descriptor.terminalEvent)

        val duplicate = duplicate(store.create(payloadA()))
        assertEquals(created.descriptor, duplicate.descriptor)
        val busy = busy(store.create(payloadB()))
        assertEquals(created.descriptor, busy.activeDescriptor)
        assertEquals(created.descriptor, store.snapshot())
        assertEquals(1, backend.replaceCalls)
        assertTrue(backend.maximumCommittedBytes <= PendingNativeCallStore.MAX_RECORD_BYTES)
        assertEquals(32, PendingNativeCallStore.MAX_EVENTS)
        assertEquals(8 * 1024, PendingNativeCallStore.MAX_RECORD_BYTES)
    }

    @Test
    fun `outgoing direction survives pre-start and adopted journal process recreation`() {
        val backend = InMemoryPendingNativeCallBackend()
        val firstStore = store(backend)

        val created = created(firstStore.createOutgoing(payloadA()))
        assertEquals(PendingNativeCallDirection.OUTGOING, created.descriptor.direction)
        assertEquals(NATIVE_CALL_ID_A, created.descriptor.nativeCallId)
        assertEquals(CALL_HANDLE_A, created.descriptor.callHandle)
        assertEquals(
            PendingNativeCallDirection.OUTGOING,
            requireNotNull(store(backend.reopened()).snapshot()).direction,
        )

        val presented = appended(
            firstStore.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED),
        )
        assertTrue(
            firstStore.acknowledge(
                NATIVE_CALL_ID_A,
                presented.event.sequence,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )

        val journal = requireNotNull(store(backend.reopened()).snapshot())
        assertEquals(PendingNativeCallDirection.OUTGOING, journal.direction)
        assertEquals(PendingNativeCallPhase.JOURNAL, journal.phase)
        assertEquals(NATIVE_CALL_ID_A, journal.nativeCallId)
        assertEquals(CALL_HANDLE_A, journal.callHandle)
        assertEquals("", journal.wakeHandle)
    }

    @Test
    fun `events are ordered monotonic unique and stable across process recreation`() {
        val backend = InMemoryPendingNativeCallBackend()
        val firstStore = store(backend)
        created(firstStore.create(payloadA()))
        val types = listOf(
            PendingNativeCallEventType.PRESENTED,
            PendingNativeCallEventType.ANSWER_REQUESTED,
            PendingNativeCallEventType.AUDIO_ACTIVATED,
            PendingNativeCallEventType.MUTE_CHANGED,
            PendingNativeCallEventType.ROUTE_CHANGED,
        )
        val appended = types.map { type -> appended(firstStore.append(NATIVE_CALL_ID_A, type)).event }

        assertEquals((1L..5L).toList(), appended.map { it.sequence })
        assertEquals(types, appended.map { it.type })
        assertTrue(appended.all { it.nativeCallId == NATIVE_CALL_ID_A })
        assertEquals(appended.size, appended.map { it.eventId }.toSet().size)

        val beforeRestart = requireNotNull(firstStore.snapshot())
        val afterRestart = requireNotNull(store(backend.reopened()).snapshot())
        assertEquals(beforeRestart, afterRestart)
        assertEquals(appended.map { it.eventId }, afterRestart.events.map { it.eventId })
        assertEquals(5L, afterRestart.highestSequence)

        val reopened = store(backend.reopened())
        val next = appended(
            reopened.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.AUDIO_DEACTIVATED),
        )
        assertEquals(6L, next.event.sequence)
        assertEquals(6L, next.descriptor.highestSequence)
        assertEquals((1L..6L).toList(), next.descriptor.events.map { it.sequence })
    }

    @Test
    fun `terminal marker dominates retained answer and presentation history`() {
        val terminalTypes = listOf(
            PendingNativeCallEventType.DECLINE_REQUESTED,
            PendingNativeCallEventType.END_REQUESTED,
            PendingNativeCallEventType.REMOTE_CANCELLED,
            PendingNativeCallEventType.EXPIRED,
            PendingNativeCallEventType.PROVIDER_REMOVED,
            PendingNativeCallEventType.NATIVE_FAILURE,
        )

        for (terminalType in terminalTypes) {
            val backend = InMemoryPendingNativeCallBackend()
            val store = store(backend)
            created(store.create(payloadA()))
            appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
            appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.ANSWER_REQUESTED))
            val terminal = appended(store.append(NATIVE_CALL_ID_A, terminalType))
            val writesAtTerminal = backend.replaceCalls

            assertEquals(listOf(1L, 2L, 3L), terminal.descriptor.events.map { it.sequence })
            assertEquals(terminal.event, terminal.descriptor.terminalEvent)
            assertEquals(terminalType, terminal.descriptor.terminalEvent?.type)
            assertEquals(3L, terminal.descriptor.highestSequence)

            for (dominated in listOf(
                PendingNativeCallEventType.PRESENTED,
                PendingNativeCallEventType.ANSWER_REQUESTED,
                PendingNativeCallEventType.AUDIO_ACTIVATED,
            )) {
                val ignored = ignoredAfterTerminal(store.append(NATIVE_CALL_ID_A, dominated))
                assertEquals(terminal.descriptor, ignored.descriptor)
            }
            assertEquals(writesAtTerminal, backend.replaceCalls)
            assertEquals(terminal.descriptor, store(backend.reopened()).snapshot())
        }
    }

    @Test
    fun `partial acknowledgement replays only later events and sequence never regresses`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        for (type in listOf(
            PendingNativeCallEventType.PRESENTED,
            PendingNativeCallEventType.ANSWER_REQUESTED,
            PendingNativeCallEventType.MUTE_CHANGED,
            PendingNativeCallEventType.ROUTE_CHANGED,
        )) {
            appended(store.append(NATIVE_CALL_ID_A, type))
        }

        assertFalse(
            store.acknowledge(
                NATIVE_CALL_ID_B,
                highestConsumedSequence = 2L,
                acknowledgement = PendingNativeCallAcknowledgement.NONE,
            ),
        )
        assertFalse(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 5L,
                acknowledgement = PendingNativeCallAcknowledgement.NONE,
            ),
        )
        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 2L,
                acknowledgement = PendingNativeCallAcknowledgement.NONE,
            ),
        )

        val replayed = requireNotNull(store(backend.reopened()).snapshot())
        assertEquals(listOf(3L, 4L), replayed.events.map { it.sequence })
        assertEquals(
            listOf(PendingNativeCallEventType.MUTE_CHANGED, PendingNativeCallEventType.ROUTE_CHANGED),
            replayed.events.map { it.type },
        )
        assertEquals(4L, replayed.highestSequence)

        val next = appended(
            store(backend.reopened()).append(
                NATIVE_CALL_ID_A,
                PendingNativeCallEventType.AUDIO_DEACTIVATED,
            ),
        )
        assertEquals(5L, next.event.sequence)
        assertEquals(listOf(3L, 4L, 5L), next.descriptor.events.map { it.sequence })
    }

    @Test
    fun `adoption and terminal acknowledgements require exact call sequence and state`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))

        assertFalse(store.acknowledge(NATIVE_CALL_ID_B, 1L, PendingNativeCallAcknowledgement.ADOPTED))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_A, 0L, PendingNativeCallAcknowledgement.ADOPTED))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_A, 2L, PendingNativeCallAcknowledgement.ADOPTED))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_A, 1L, PendingNativeCallAcknowledgement.TERMINAL))
        assertTrue(store.acknowledge(NATIVE_CALL_ID_A, 1L, PendingNativeCallAcknowledgement.ADOPTED))
        val journal = requireNotNull(store.snapshot())
        assertEquals(PendingNativeCallPhase.JOURNAL, journal.phase)
        assertEquals("", journal.wakeHandle)
        assertTrue(journal.events.isEmpty())
        assertTrue(
            store(backend.reopened()).acknowledge(
                NATIVE_CALL_ID_A,
                1L,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertEquals(0, backend.deleteCalls)

        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.REMOTE_CANCELLED))
        assertTrue(store.acknowledge(NATIVE_CALL_ID_A, 2L, PendingNativeCallAcknowledgement.TERMINAL))
        assertEquals(
            NATIVE_CALL_ID_A,
            store(backend.reopened()).resolveAcknowledgementReceipt(CALL_HANDLE_A),
        )
        assertTrue(store(backend.reopened()).create(payloadA()) is PendingNativeCallCreateResult.Duplicate)
        assertNull(store.snapshot())
        assertTrue(
            store(backend.reopened()).acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertEquals(1, backend.deleteCalls)
        requireNotNull(backend.committedReceiptBytes()) {
            "minimal acknowledgement receipt remains"
        }

        created(store.create(payloadB()))
        appended(store.append(NATIVE_CALL_ID_B, PendingNativeCallEventType.PRESENTED))
        appended(store.append(NATIVE_CALL_ID_B, PendingNativeCallEventType.REMOTE_CANCELLED))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_B, 2L, PendingNativeCallAcknowledgement.ADOPTED))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_B, 1L, PendingNativeCallAcknowledgement.TERMINAL))
        assertFalse(store.acknowledge(NATIVE_CALL_ID_B, 3L, PendingNativeCallAcknowledgement.TERMINAL))
        assertTrue(store.acknowledge(NATIVE_CALL_ID_B, 2L, PendingNativeCallAcknowledgement.TERMINAL))
        assertNull(store.snapshot())
        assertTrue(store.acknowledge(NATIVE_CALL_ID_B, 2L, PendingNativeCallAcknowledgement.TERMINAL))
        assertEquals(2, backend.deleteCalls)
    }

    @Test
    fun `terminal acknowledgement receipt is minimal bounded and expires`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.REMOTE_CANCELLED))
        val pendingBytes = requireNotNull(backend.committedBytes()).size

        assertTrue(store.acknowledge(NATIVE_CALL_ID_A, 2L, PendingNativeCallAcknowledgement.TERMINAL))
        assertNull(backend.committedBytes())
        val receiptBytes = requireNotNull(backend.committedReceiptBytes())
        assertTrue("receipt excludes the full pending descriptor", receiptBytes.size < pendingBytes)
        assertFalse(
            "receipt does not retain the plaintext call handle",
            receiptBytes.toString(Charsets.ISO_8859_1).contains(CALL_HANDLE_A),
        )

        val expiredStore = PendingNativeCallStore(
            backend = backend.reopened(),
            nowMs = { NOW_MS + PendingNativeCallStore.ACKNOWLEDGEMENT_RECEIPT_TTL_MS + 1L },
        )
        assertNull(expiredStore.snapshot())
        assertNull(expiredStore.resolveAcknowledgementReceipt(CALL_HANDLE_A))
        assertFalse(
            expiredStore.acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
    }

    @Test
    fun `terminal acknowledgement retry survives a newer live descriptor`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.REMOTE_CANCELLED))

        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        val callB = created(store.create(payloadB())).descriptor

        assertTrue(
            store(backend.reopened()).acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertEquals(callB, store.snapshot())
        assertEquals(
            NATIVE_CALL_ID_A,
            store.resolveAcknowledgementReceipt(CALL_HANDLE_A),
        )
    }

    @Test
    fun `receipt first crash cut retains terminal custody until verified descriptor deletion`() {
        val seed = InMemoryPendingNativeCallBackend()
        val seedStore = store(seed)
        created(seedStore.create(payloadA()))
        appended(seedStore.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        appended(seedStore.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.REMOTE_CANCELLED))
        val backend = ControllablePendingNativeCallBackend(
            initialBytes = requireNotNull(seed.committedBytes()),
        ).apply { failDelete = true }
        var observedNow = NOW_MS
        val store = PendingNativeCallStore(backend = backend, nowMs = { observedNow })

        assertFalse(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        requireNotNull(store.snapshot())
        requireNotNull(backend.committedReceiptBytes())

        backend.failDelete = false
        observedNow += 1_000L
        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
        assertNull(store.snapshot())
        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                2L,
                PendingNativeCallAcknowledgement.TERMINAL,
            ),
        )
    }

    @Test
    fun `adoption retains later unconsumed intents and final consumption deletes exactly once`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.ANSWER_REQUESTED))

        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 1L,
                acknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        val replayed = requireNotNull(store(backend.reopened()).snapshot())
        assertEquals(PendingNativeCallAcknowledgement.ADOPTED, replayed.handoffAcknowledgement)
        assertEquals(listOf(2L), replayed.events.map { it.sequence })
        assertEquals(0, backend.deleteCalls)

        val reopenedBackend = backend.reopened()
        val reopenedStore = store(reopenedBackend)
        assertTrue(
            reopenedStore.acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 2L,
                acknowledgement = PendingNativeCallAcknowledgement.NONE,
            ),
        )
        val consumedJournal = requireNotNull(reopenedStore.snapshot())
        assertEquals(PendingNativeCallPhase.JOURNAL, consumedJournal.phase)
        assertTrue(consumedJournal.events.isEmpty())
        assertTrue(
            store(reopenedBackend.reopened()).acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 2L,
                acknowledgement = PendingNativeCallAcknowledgement.NONE,
            ),
        )
        assertEquals(0, reopenedBackend.deleteCalls)
    }

    @Test
    fun `journal preserves original expired invite provenance and monotonic replay`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        assertTrue(
            store.acknowledge(
                NATIVE_CALL_ID_A,
                1L,
                PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )

        val afterInviteExpiry = PendingNativeCallStore(
            backend = backend.reopened(),
            nowMs = { NOW_MS + 90_000L },
        )
        val journal = requireNotNull(afterInviteExpiry.snapshot())
        assertEquals(PendingNativeCallPhase.JOURNAL, journal.phase)
        assertEquals(NOW_MS + 45_000L, journal.expiresAtMs)
        assertEquals(1L, journal.highestSequence)
        assertTrue(journal.events.isEmpty())
        val terminal = appended(
            afterInviteExpiry.append(
                NATIVE_CALL_ID_A,
                PendingNativeCallEventType.PROVIDER_REMOVED,
            ),
        )
        assertEquals(2L, terminal.event.sequence)
        assertEquals(PendingNativeCallPhase.JOURNAL, terminal.descriptor.phase)
    }

    @Test
    fun `event and encoded record bounds reject growth without changing the durable snapshot`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        repeat(PendingNativeCallStore.MAX_EVENTS) {
            appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.MUTE_CHANGED))
        }
        val atCapacity = requireNotNull(store.snapshot())
        val durableAtCapacity = requireNotNull(backend.committedBytes()).copyOf()

        assertEquals(PendingNativeCallStore.MAX_EVENTS, atCapacity.events.size)
        assertEquals(PendingNativeCallStore.MAX_EVENTS.toLong(), atCapacity.highestSequence)
        assertTrue(
            store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.ROUTE_CHANGED) ===
                PendingNativeCallAppendResult.CapacityReached,
        )
        assertTrue(durableAtCapacity.contentEquals(requireNotNull(backend.committedBytes())))
        assertTrue(backend.maximumCommittedBytes <= PendingNativeCallStore.MAX_RECORD_BYTES)

        val oversized = InMemoryPendingNativeCallBackend(
            initialBytes = ByteArray(PendingNativeCallStore.MAX_RECORD_BYTES + 1),
        )
        val oversizedStore = store(oversized)
        assertNull(oversizedStore.snapshot())
        assertTrue(
            oversizedStore.create(payloadA()) === PendingNativeCallCreateResult.PersistenceFailure,
        )
        assertEquals(0, oversized.replaceCalls)
    }

    @Test
    fun `terminal event compacts a full nonterminal history and remains replayable`() {
        val backend = InMemoryPendingNativeCallBackend()
        val store = store(backend)
        created(store.create(payloadA()))
        repeat(PendingNativeCallStore.MAX_EVENTS) {
            appended(store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.MUTE_CHANGED))
        }

        val terminal = appended(
            store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.REMOTE_CANCELLED),
        )

        assertEquals(PendingNativeCallStore.MAX_EVENTS.toLong() + 1L, terminal.event.sequence)
        assertEquals(PendingNativeCallEventType.REMOTE_CANCELLED, terminal.event.type)
        val reopened = requireNotNull(store(backend.reopened()).snapshot())
        assertEquals(terminal.event.sequence, reopened.highestSequence)
        assertEquals(terminal.event, reopened.terminalEvent)
        assertEquals(listOf(terminal.event), reopened.events)
        assertTrue(backend.maximumCommittedBytes <= PendingNativeCallStore.MAX_RECORD_BYTES)
        assertTrue(
            store.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.ANSWER_REQUESTED) is
                PendingNativeCallAppendResult.IgnoredAfterTerminal,
        )
    }

    @Test
    fun `read write append and delete persistence failures fail closed`() {
        val createFailure = ControllablePendingNativeCallBackend().apply { failReplace = true }
        assertTrue(
            store(createFailure).create(payloadA()) ===
                PendingNativeCallCreateResult.PersistenceFailure,
        )
        assertNull(createFailure.committedBytes())

        val throwingCreate = ControllablePendingNativeCallBackend().apply { throwOnReplace = true }
        assertTrue(
            store(throwingCreate).create(payloadA()) ===
                PendingNativeCallCreateResult.PersistenceFailure,
        )
        assertNull(throwingCreate.committedBytes())

        val seed = InMemoryPendingNativeCallBackend()
        val seedStore = store(seed)
        created(seedStore.create(payloadA()))
        appended(seedStore.append(NATIVE_CALL_ID_A, PendingNativeCallEventType.PRESENTED))
        val committedBeforeFailure = requireNotNull(seed.committedBytes()).copyOf()
        val mutationFailure = ControllablePendingNativeCallBackend(committedBeforeFailure).apply {
            failReplace = true
        }
        assertTrue(
            store(mutationFailure).append(
                NATIVE_CALL_ID_A,
                PendingNativeCallEventType.ANSWER_REQUESTED,
            ) === PendingNativeCallAppendResult.PersistenceFailure,
        )
        assertTrue(committedBeforeFailure.contentEquals(requireNotNull(mutationFailure.committedBytes())))

        val adoptionFailure = ControllablePendingNativeCallBackend(committedBeforeFailure).apply {
            failReplace = true
        }
        assertFalse(
            store(adoptionFailure).acknowledge(
                NATIVE_CALL_ID_A,
                highestConsumedSequence = 1L,
                acknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
            ),
        )
        assertTrue(
            committedBeforeFailure.contentEquals(requireNotNull(adoptionFailure.committedBytes())),
        )

        val readFailure = ControllablePendingNativeCallBackend(committedBeforeFailure).apply {
            throwOnRead = true
        }
        assertNull(store(readFailure).snapshot())
        assertTrue(
            store(readFailure).create(payloadB()) === PendingNativeCallCreateResult.PersistenceFailure,
        )
        assertEquals(0, readFailure.replaceCalls)
    }

    private fun store(
        backend: PendingNativeCallBackend,
    ): PendingNativeCallStore = PendingNativeCallStore(backend = backend, nowMs = { NOW_MS })

    private fun payloadA(): CallWakePayload = CallWakePayload(
        nativeCallId = NATIVE_CALL_ID_A,
        callHandle = CALL_HANDLE_A,
        wakeHandle = WAKE_HANDLE_A,
        receivedAtMs = NOW_MS,
        expiresAtMs = NOW_MS + 45_000L,
    )

    private fun payloadB(): CallWakePayload = CallWakePayload(
        nativeCallId = NATIVE_CALL_ID_B,
        callHandle = CALL_HANDLE_B,
        wakeHandle = WAKE_HANDLE_B,
        receivedAtMs = NOW_MS,
        expiresAtMs = NOW_MS + 45_000L,
    )

    private fun created(
        result: PendingNativeCallCreateResult,
    ): PendingNativeCallCreateResult.Created {
        assertTrue(result is PendingNativeCallCreateResult.Created)
        return result as PendingNativeCallCreateResult.Created
    }

    private fun duplicate(
        result: PendingNativeCallCreateResult,
    ): PendingNativeCallCreateResult.Duplicate {
        assertTrue(result is PendingNativeCallCreateResult.Duplicate)
        return result as PendingNativeCallCreateResult.Duplicate
    }

    private fun busy(
        result: PendingNativeCallCreateResult,
    ): PendingNativeCallCreateResult.Busy {
        assertTrue(result is PendingNativeCallCreateResult.Busy)
        return result as PendingNativeCallCreateResult.Busy
    }

    private fun appended(
        result: PendingNativeCallAppendResult,
    ): PendingNativeCallAppendResult.Appended {
        assertTrue(result is PendingNativeCallAppendResult.Appended)
        return result as PendingNativeCallAppendResult.Appended
    }

    private fun ignoredAfterTerminal(
        result: PendingNativeCallAppendResult,
    ): PendingNativeCallAppendResult.IgnoredAfterTerminal {
        assertTrue(result is PendingNativeCallAppendResult.IgnoredAfterTerminal)
        return result as PendingNativeCallAppendResult.IgnoredAfterTerminal
    }

    private companion object {
        const val NOW_MS = 1_800_000_000_000L
        const val CALL_HANDLE_A = "00112233-4455-6677-8899-aabbccddeeff"
        const val WAKE_HANDLE_A = "50112233445566778899aabbccddeeff"
        const val CALL_HANDLE_B = "10112233-4455-6677-8899-aabbccddeeff"
        const val WAKE_HANDLE_B = "60112233445566778899aabbccddeeff"
        val NATIVE_CALL_ID_A: UUID = UUID.fromString("00112233-4455-6677-8899-aabbccddeeff")
        val NATIVE_CALL_ID_B: UUID = UUID.fromString("10112233-4455-6677-8899-aabbccddeeff")
    }
}

private open class InMemoryPendingNativeCallBackend(
    initialBytes: ByteArray? = null,
    initialReceiptBytes: ByteArray? = null,
) : PendingNativeCallBackend {
    private var durableBytes: ByteArray? = initialBytes?.copyOf()
    private var durableReceiptBytes: ByteArray? = initialReceiptBytes?.copyOf()
    var replaceCalls: Int = 0
        private set
    var deleteCalls: Int = 0
        private set
    var maximumCommittedBytes: Int = initialBytes?.size ?: 0
        private set

    override fun read(): ByteArray? = durableBytes?.copyOf()

    override fun replace(bytes: ByteArray?): Boolean {
        replaceCalls += 1
        if (bytes == null) deleteCalls += 1
        durableBytes = bytes?.copyOf()
        maximumCommittedBytes = maxOf(maximumCommittedBytes, bytes?.size ?: 0)
        return true
    }

    override fun readAcknowledgementReceipt(): ByteArray? = durableReceiptBytes?.copyOf()

    override fun replaceAcknowledgementReceipt(bytes: ByteArray?): Boolean {
        durableReceiptBytes = bytes?.copyOf()
        return true
    }

    fun committedBytes(): ByteArray? = durableBytes?.copyOf()

    fun committedReceiptBytes(): ByteArray? = durableReceiptBytes?.copyOf()

    fun reopened(): InMemoryPendingNativeCallBackend =
        InMemoryPendingNativeCallBackend(durableBytes, durableReceiptBytes)
}

private class ControllablePendingNativeCallBackend(
    initialBytes: ByteArray? = null,
    initialReceiptBytes: ByteArray? = null,
) : PendingNativeCallBackend {
    private var durableBytes: ByteArray? = initialBytes?.copyOf()
    private var durableReceiptBytes: ByteArray? = initialReceiptBytes?.copyOf()
    var failReplace: Boolean = false
    var failDelete: Boolean = false
    var throwOnRead: Boolean = false
    var throwOnReplace: Boolean = false
    var replaceCalls: Int = 0
        private set

    override fun read(): ByteArray? {
        if (throwOnRead) throw IllegalStateException("injected read failure")
        return durableBytes?.copyOf()
    }

    override fun replace(bytes: ByteArray?): Boolean {
        replaceCalls += 1
        if (throwOnReplace) throw IllegalStateException("injected replace failure")
        if (failReplace || (bytes == null && failDelete)) return false
        durableBytes = bytes?.copyOf()
        return true
    }

    override fun readAcknowledgementReceipt(): ByteArray? {
        if (throwOnRead) throw IllegalStateException("injected receipt read failure")
        return durableReceiptBytes?.copyOf()
    }

    override fun replaceAcknowledgementReceipt(bytes: ByteArray?): Boolean {
        if (throwOnReplace) throw IllegalStateException("injected receipt replace failure")
        if (failReplace || (bytes == null && failDelete)) return false
        durableReceiptBytes = bytes?.copyOf()
        return true
    }

    fun committedBytes(): ByteArray? = durableBytes?.copyOf()

    fun committedReceiptBytes(): ByteArray? = durableReceiptBytes?.copyOf()
}
