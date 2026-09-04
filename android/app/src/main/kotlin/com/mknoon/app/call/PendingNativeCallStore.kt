package com.mknoon.app.call

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal interface PendingNativeCallBackend {
    fun read(): ByteArray?

    /** A null value is the exact durable delete operation. */
    fun replace(bytes: ByteArray?): Boolean

    fun readAcknowledgementReceipt(): ByteArray? = null

    fun replaceAcknowledgementReceipt(bytes: ByteArray?): Boolean = false
}

internal enum class PendingNativeCallAcknowledgement {
    NONE,
    ADOPTED,
    TERMINAL,
}

internal enum class PendingNativeCallPhase {
    PRE_START,
    JOURNAL,
}

internal enum class PendingNativeCallDirection {
    INCOMING,
    OUTGOING,
}

private data class PendingNativeCallAcknowledgementReceipt(
    val nativeCallId: UUID,
    val callHandleDigest: ByteArray,
    val highestConsumedSequence: Long,
    val expiresAtMs: Long,
) {
    override fun equals(other: Any?): Boolean =
        other is PendingNativeCallAcknowledgementReceipt &&
            nativeCallId == other.nativeCallId &&
            callHandleDigest.contentEquals(other.callHandleDigest) &&
            highestConsumedSequence == other.highestConsumedSequence &&
            expiresAtMs == other.expiresAtMs

    override fun hashCode(): Int {
        var result = nativeCallId.hashCode()
        result = 31 * result + callHandleDigest.contentHashCode()
        result = 31 * result + highestConsumedSequence.hashCode()
        result = 31 * result + expiresAtMs.hashCode()
        return result
    }
}

internal enum class PendingNativeCallEventType {
    PRESENTED,
    ANSWER_REQUESTED,
    DECLINE_REQUESTED,
    END_REQUESTED,
    REMOTE_CANCELLED,
    EXPIRED,
    PROVIDER_REMOVED,
    MUTE_CHANGED,
    ROUTE_CHANGED,
    AUDIO_ACTIVATED,
    AUDIO_DEACTIVATED,
    NATIVE_FAILURE,
}

internal data class PendingNativeCallEvent(
    val nativeCallId: UUID,
    val sequence: Long,
    val eventId: UUID,
    val type: PendingNativeCallEventType,
)

internal data class PendingNativeCallDescriptor(
    val nativeCallId: UUID,
    val callHandle: String,
    val wakeHandle: String,
    val receivedAtMs: Long,
    val expiresAtMs: Long,
    val highestSequence: Long,
    val terminalEvent: PendingNativeCallEvent?,
    val events: List<PendingNativeCallEvent>,
    val handoffAcknowledgement: PendingNativeCallAcknowledgement =
        PendingNativeCallAcknowledgement.NONE,
    val phase: PendingNativeCallPhase = PendingNativeCallPhase.PRE_START,
    val answerRequested: Boolean = false,
    val lastAcknowledgement: PendingNativeCallAcknowledgement? = null,
    val lastAcknowledgedSequence: Long = 0L,
    val direction: PendingNativeCallDirection = PendingNativeCallDirection.INCOMING,
    val schemaVersion: Int = PENDING_NATIVE_CALL_SCHEMA_VERSION,
)

internal sealed interface PendingNativeCallCreateResult {
    data class Created(
        val descriptor: PendingNativeCallDescriptor,
    ) : PendingNativeCallCreateResult

    data class Duplicate(
        val descriptor: PendingNativeCallDescriptor,
    ) : PendingNativeCallCreateResult

    data class Busy(
        val activeDescriptor: PendingNativeCallDescriptor,
    ) : PendingNativeCallCreateResult

    object PersistenceFailure : PendingNativeCallCreateResult
}

internal sealed interface PendingNativeCallAppendResult {
    data class Appended(
        val descriptor: PendingNativeCallDescriptor,
        val event: PendingNativeCallEvent,
    ) : PendingNativeCallAppendResult

    data class IgnoredAfterTerminal(
        val descriptor: PendingNativeCallDescriptor,
    ) : PendingNativeCallAppendResult

    object NotFound : PendingNativeCallAppendResult
    object CapacityReached : PendingNativeCallAppendResult
    object PersistenceFailure : PendingNativeCallAppendResult
}

internal class PendingNativeCallStore(
    private val backend: PendingNativeCallBackend,
    private val nowMs: () -> Long,
) : MknoonCallLifecycleStore {
    companion object {
        const val SCHEMA_VERSION = PENDING_NATIVE_CALL_SCHEMA_VERSION
        const val MAX_EVENTS = 32
        const val MAX_RECORD_BYTES = 8 * 1024
        const val MAX_ACKNOWLEDGEMENT_RECEIPTS = 32
        const val ACKNOWLEDGEMENT_RECEIPT_TTL_MS = 10 * 60 * 1_000L

        private val processLock = Any()
    }

    constructor(
        context: Context,
        nowMs: () -> Long = { System.currentTimeMillis() },
    ) : this(
        backend = AndroidProtectedPendingNativeCallBackend(context),
        nowMs = nowMs,
    )

    override fun create(payload: CallWakePayload): PendingNativeCallCreateResult =
        create(payload, PendingNativeCallDirection.INCOMING)

    override fun createOutgoing(payload: CallWakePayload): PendingNativeCallCreateResult =
        create(payload, PendingNativeCallDirection.OUTGOING)

    private fun create(
        payload: CallWakePayload,
        direction: PendingNativeCallDirection,
    ): PendingNativeCallCreateResult =
        synchronized(processLock) {
            if (!validPayload(payload)) {
                return@synchronized PendingNativeCallCreateResult.PersistenceFailure
            }
            when (val receipt = readReceipt()) {
                ReceiptState.Invalid -> {
                    return@synchronized PendingNativeCallCreateResult.PersistenceFailure
                }
                is ReceiptState.Valid -> if (receipt.receipts.any { it.matches(payload) }) {
                    return@synchronized PendingNativeCallCreateResult.Duplicate(
                        payload.toReceiptDuplicateDescriptor(direction),
                    )
                }
                ReceiptState.Empty -> Unit
            }
            when (val state = readState()) {
                StoredState.Empty -> {
                    createReplacingState(payload, direction)
                }

                is StoredState.Valid -> {
                    if (state.descriptor.matches(payload, direction)) {
                        PendingNativeCallCreateResult.Duplicate(state.descriptor)
                    } else {
                        PendingNativeCallCreateResult.Busy(state.descriptor)
                    }
                }

                StoredState.Invalid -> PendingNativeCallCreateResult.PersistenceFailure
            }
        }

    override fun append(
        nativeCallId: UUID,
        type: PendingNativeCallEventType,
    ): PendingNativeCallAppendResult = synchronized(processLock) {
        val descriptor = when (val state = readState()) {
            StoredState.Empty -> return@synchronized PendingNativeCallAppendResult.NotFound
            StoredState.Invalid -> return@synchronized PendingNativeCallAppendResult.PersistenceFailure
            is StoredState.Valid -> state.descriptor
        }
        if (descriptor.nativeCallId != nativeCallId) {
            return@synchronized PendingNativeCallAppendResult.NotFound
        }
        if (descriptor.terminalEvent != null) {
            return@synchronized PendingNativeCallAppendResult.IgnoredAfterTerminal(descriptor)
        }
        val terminal = type.isTerminal()
        if (
            descriptor.highestSequence == Long.MAX_VALUE ||
            (!terminal && descriptor.events.size >= MAX_EVENTS)
        ) {
            return@synchronized PendingNativeCallAppendResult.CapacityReached
        }
        val eventId = uniqueEventId(descriptor.events)
            ?: return@synchronized PendingNativeCallAppendResult.PersistenceFailure
        val event = PendingNativeCallEvent(
            nativeCallId = nativeCallId,
            sequence = descriptor.highestSequence + 1L,
            eventId = eventId,
            type = type,
        )
        val compactForEventBound = terminal && descriptor.events.size >= MAX_EVENTS
        val updated = descriptor.copy(
            highestSequence = event.sequence,
            terminalEvent = event.takeIf { terminal },
            events = if (compactForEventBound) listOf(event) else descriptor.events + event,
            answerRequested = descriptor.answerRequested ||
                type == PendingNativeCallEventType.ANSWER_REQUESTED,
        )
        when (commit(updated)) {
            CommitResult.COMMITTED -> PendingNativeCallAppendResult.Appended(updated, event)
            CommitResult.TOO_LARGE -> {
                if (!terminal || updated.events.size == 1) {
                    PendingNativeCallAppendResult.CapacityReached
                } else {
                    val compacted = updated.copy(events = listOf(event))
                    when (commit(compacted)) {
                        CommitResult.COMMITTED ->
                            PendingNativeCallAppendResult.Appended(compacted, event)
                        CommitResult.TOO_LARGE -> PendingNativeCallAppendResult.CapacityReached
                        CommitResult.FAILED -> PendingNativeCallAppendResult.PersistenceFailure
                    }
                }
            }
            CommitResult.FAILED -> PendingNativeCallAppendResult.PersistenceFailure
        }
    }

    override fun snapshot(): PendingNativeCallDescriptor? = synchronized(processLock) {
        readReceipt()
        (readState() as? StoredState.Valid)?.descriptor
    }

    override fun resolveAcknowledgementReceipt(callHandle: String): UUID? =
        synchronized(processLock) {
            val digest = callHandleDigest(callHandle) ?: return@synchronized null
            (readReceipt() as? ReceiptState.Valid)?.receipts?.firstOrNull {
                MessageDigest.isEqual(it.callHandleDigest, digest)
            }?.nativeCallId
        }

    override fun acknowledge(
        nativeCallId: UUID,
        highestConsumedSequence: Long,
        acknowledgement: PendingNativeCallAcknowledgement,
    ): Boolean = synchronized(processLock) {
        if (highestConsumedSequence < 0L) return@synchronized false
        val committedReceipt = (readReceipt() as? ReceiptState.Valid)?.receipts?.firstOrNull {
            it.nativeCallId == nativeCallId &&
                it.highestConsumedSequence == highestConsumedSequence
        }
        val descriptor = (readState() as? StoredState.Valid)?.descriptor
        if (
            acknowledgement == PendingNativeCallAcknowledgement.TERMINAL &&
            committedReceipt != null &&
            descriptor?.nativeCallId != nativeCallId
        ) {
            return@synchronized true
        }
        if (descriptor == null) return@synchronized false
        if (descriptor.nativeCallId != nativeCallId) return@synchronized false
        if (
            descriptor.lastAcknowledgement == acknowledgement &&
            descriptor.lastAcknowledgedSequence == highestConsumedSequence
        ) {
            return@synchronized true
        }
        when (acknowledgement) {
            PendingNativeCallAcknowledgement.NONE -> {
                val acknowledgedThrough = descriptor.events.firstOrNull()
                    ?.sequence
                    ?.minus(1L)
                    ?: descriptor.highestSequence
                if (
                    highestConsumedSequence <= acknowledgedThrough ||
                    highestConsumedSequence > descriptor.highestSequence ||
                    descriptor.terminalEvent?.let {
                        highestConsumedSequence >= it.sequence
                    } == true
                ) {
                    return@synchronized false
                }
                val updated = descriptor.copy(
                    events = descriptor.events.filter { it.sequence > highestConsumedSequence },
                    lastAcknowledgement = PendingNativeCallAcknowledgement.NONE,
                    lastAcknowledgedSequence = highestConsumedSequence,
                )
                commit(updated) == CommitResult.COMMITTED
            }

            PendingNativeCallAcknowledgement.ADOPTED -> {
                val acknowledgedThrough = descriptor.events.firstOrNull()
                    ?.sequence
                    ?.minus(1L)
                    ?: descriptor.highestSequence
                if (
                    descriptor.terminalEvent != null ||
                    descriptor.handoffAcknowledgement != PendingNativeCallAcknowledgement.NONE ||
                    highestConsumedSequence <= acknowledgedThrough ||
                    highestConsumedSequence > descriptor.highestSequence
                ) {
                    return@synchronized false
                }
                val updated = descriptor.copy(
                    events = descriptor.events.filter { it.sequence > highestConsumedSequence },
                    handoffAcknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
                    phase = PendingNativeCallPhase.JOURNAL,
                    wakeHandle = "",
                    lastAcknowledgement = PendingNativeCallAcknowledgement.ADOPTED,
                    lastAcknowledgedSequence = highestConsumedSequence,
                )
                commit(updated) == CommitResult.COMMITTED
            }

            PendingNativeCallAcknowledgement.TERMINAL -> {
                if (
                    descriptor.terminalEvent == null ||
                    descriptor.terminalEvent.sequence != descriptor.highestSequence ||
                    highestConsumedSequence != descriptor.highestSequence
                ) {
                    return@synchronized false
                }
                val observedNow = safeNow() ?: return@synchronized false
                val receipt = PendingNativeCallAcknowledgementReceipt(
                    nativeCallId = nativeCallId,
                    callHandleDigest = callHandleDigest(descriptor.callHandle)
                        ?: return@synchronized false,
                    highestConsumedSequence = highestConsumedSequence,
                    expiresAtMs = saturatingAdd(
                        observedNow,
                        ACKNOWLEDGEMENT_RECEIPT_TTL_MS,
                    ),
                )
                commitReceipt(receipt) && deleteCommitted()
            }
        }
    }

    private fun createReplacingState(
        payload: CallWakePayload,
        direction: PendingNativeCallDirection,
    ): PendingNativeCallCreateResult {
        val descriptor = PendingNativeCallDescriptor(
            nativeCallId = payload.nativeCallId,
            callHandle = payload.callHandle,
            wakeHandle = payload.wakeHandle,
            receivedAtMs = payload.receivedAtMs,
            expiresAtMs = payload.expiresAtMs,
            highestSequence = 0L,
            terminalEvent = null,
            events = emptyList(),
            direction = direction,
        )
        return when (commit(descriptor)) {
            CommitResult.COMMITTED -> PendingNativeCallCreateResult.Created(descriptor)
            CommitResult.TOO_LARGE,
            CommitResult.FAILED,
            -> PendingNativeCallCreateResult.PersistenceFailure
        }
    }

    private fun validPayload(payload: CallWakePayload): Boolean {
        val canonicalCallId = runCatching { UUID.fromString(payload.callHandle) }.getOrNull()
        if (
            !CANONICAL_CALL_HANDLE.matches(payload.callHandle) ||
            !CALL_RANDOM_ID.matches(payload.wakeHandle) ||
            canonicalCallId != payload.nativeCallId ||
            payload.receivedAtMs < 0L ||
            payload.expiresAtMs <= payload.receivedAtMs
        ) {
            return false
        }
        val observedNow = try {
            nowMs()
        } catch (_: Exception) {
            return false
        }
        return observedNow >= 0L &&
            payload.receivedAtMs <= observedNow &&
            payload.expiresAtMs > observedNow &&
            payload.expiresAtMs - observedNow <= CallPayloadParser.MAX_FUTURE_SKEW_MS
    }

    private fun readState(): StoredState {
        val bytes = try {
            backend.read()
        } catch (_: Exception) {
            return StoredState.Invalid
        } ?: return StoredState.Empty
        if (bytes.isEmpty() || bytes.size > MAX_RECORD_BYTES) return StoredState.Invalid
        val descriptor = PendingNativeCallCodec.decode(bytes) ?: return StoredState.Invalid
        return StoredState.Valid(descriptor)
    }

    private fun commit(descriptor: PendingNativeCallDescriptor): CommitResult {
        val encoded = PendingNativeCallCodec.encode(descriptor) ?: return CommitResult.FAILED
        if (encoded.size > MAX_RECORD_BYTES) return CommitResult.TOO_LARGE
        val replaced = try {
            backend.replace(encoded)
        } catch (_: Exception) {
            false
        }
        if (!replaced) return CommitResult.FAILED
        val verified = (readState() as? StoredState.Valid)?.descriptor
        return if (verified == descriptor) CommitResult.COMMITTED else CommitResult.FAILED
    }

    private fun deleteCommitted(): Boolean {
        val deleted = try {
            backend.replace(null)
        } catch (_: Exception) {
            false
        }
        if (!deleted) return false
        return try {
            backend.read() == null
        } catch (_: Exception) {
            false
        }
    }

    private fun readReceipt(): ReceiptState {
        val encoded = try {
            backend.readAcknowledgementReceipt()
        } catch (_: Exception) {
            return ReceiptState.Invalid
        } ?: return ReceiptState.Empty
        val receipts = PendingNativeCallAcknowledgementReceiptCodec.decode(encoded)
            ?: return ReceiptState.Invalid
        val observedNow = safeNow() ?: return ReceiptState.Invalid
        val liveReceipts = receipts.filter { it.expiresAtMs > observedNow }
        if (liveReceipts.isEmpty()) {
            return if (replaceReceiptsCommitted(emptyList())) {
                ReceiptState.Empty
            } else {
                ReceiptState.Invalid
            }
        }
        if (liveReceipts != receipts && !replaceReceiptsCommitted(liveReceipts)) {
            return ReceiptState.Invalid
        }
        return ReceiptState.Valid(liveReceipts)
    }

    private fun commitReceipt(receipt: PendingNativeCallAcknowledgementReceipt): Boolean {
        val existing = when (val state = readReceipt()) {
            ReceiptState.Empty -> emptyList()
            ReceiptState.Invalid -> return false
            is ReceiptState.Valid -> state.receipts
        }
        if (existing.any { it.sameAcknowledgementAs(receipt) }) return true
        if (existing.size >= MAX_ACKNOWLEDGEMENT_RECEIPTS) return false
        return replaceReceiptsCommitted(existing + receipt)
    }

    private fun replaceReceiptsCommitted(
        receipts: List<PendingNativeCallAcknowledgementReceipt>,
    ): Boolean {
        val encoded = if (receipts.isEmpty()) {
            null
        } else {
            PendingNativeCallAcknowledgementReceiptCodec.encode(receipts) ?: return false
        }
        val replaced = try {
            backend.replaceAcknowledgementReceipt(encoded)
        } catch (_: Exception) {
            false
        }
        if (!replaced) return false
        val verifiedBytes = try {
            backend.readAcknowledgementReceipt()
        } catch (_: Exception) {
            return false
        }
        if (receipts.isEmpty()) return verifiedBytes == null
        val verified = verifiedBytes?.let(PendingNativeCallAcknowledgementReceiptCodec::decode)
        return verified == receipts
    }

    private fun safeNow(): Long? = try {
        nowMs().takeIf { it >= 0L }
    } catch (_: Exception) {
        null
    }

    private fun uniqueEventId(events: List<PendingNativeCallEvent>): UUID? {
        val existing = events.mapTo(mutableSetOf()) { it.eventId }
        repeat(4) {
            val candidate = try {
                UUID.randomUUID()
            } catch (_: Exception) {
                return null
            }
            if (candidate !in existing) return candidate
        }
        return null
    }

    private sealed interface StoredState {
        object Empty : StoredState
        data class Valid(val descriptor: PendingNativeCallDescriptor) : StoredState
        object Invalid : StoredState
    }

    private sealed interface ReceiptState {
        object Empty : ReceiptState
        data class Valid(
            val receipts: List<PendingNativeCallAcknowledgementReceipt>,
        ) : ReceiptState
        object Invalid : ReceiptState
    }

    private enum class CommitResult {
        COMMITTED,
        TOO_LARGE,
        FAILED,
    }
}

/**
 * Credential-protected encrypted backend for the one native pre-start record.
 * Plaintext never leaves app-private memory and there is deliberately no
 * in-memory success fallback when Keystore or durable storage is unavailable.
 */
internal class AndroidProtectedPendingNativeCallBackend(
    context: Context,
    private val keyAlias: String = KEY_ALIAS,
    fileName: String = FILE_NAME,
) : PendingNativeCallBackend {
    companion object {
        const val FILE_NAME = "pending_native_call_v1.bin"
        const val ACKNOWLEDGEMENT_RECEIPT_FILE_NAME = "pending_native_call_ack_v1.bin"
        const val KEY_ALIAS = "mknoon_pending_native_call_v1"

        private const val ENVELOPE_MAGIC = 0x4d4b5043
        private const val ENVELOPE_VERSION = 1
        private const val GCM_IV_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private const val MAX_ENCRYPTED_RECORD_BYTES =
            PendingNativeCallStore.MAX_RECORD_BYTES + 128
        private val AAD = "mknoon.pending-native-call.v1"
            .toByteArray(Charsets.UTF_8)
        private val ACKNOWLEDGEMENT_RECEIPT_AAD =
            "mknoon.pending-native-call-ack.v1".toByteArray(Charsets.UTF_8)
        private val keyLock = Any()
    }

    private val applicationContext = context.applicationContext
    private val directory = applicationContext.noBackupFilesDir
    private val atomicFile = AtomicFile(File(directory, fileName))
    private val acknowledgementReceiptFile = AtomicFile(
        File(directory, ACKNOWLEDGEMENT_RECEIPT_FILE_NAME),
    )
    private val backendLock = Any()

    init {
        require(fileName.isNotBlank() && !fileName.contains('/') && !fileName.contains('\\'))
        require(keyAlias.isNotBlank())
    }

    override fun read(): ByteArray? = synchronized(backendLock) {
        readProtected(atomicFile, AAD)
    }

    override fun replace(bytes: ByteArray?): Boolean = synchronized(backendLock) {
        try {
            requireCredentialProtectedStorage()
            if (bytes == null) {
                deleteDurably(atomicFile)
            } else {
                writeDurably(atomicFile, AAD, bytes)
            }
        } catch (_: Exception) {
            false
        }
    }

    override fun readAcknowledgementReceipt(): ByteArray? = synchronized(backendLock) {
        readProtected(acknowledgementReceiptFile, ACKNOWLEDGEMENT_RECEIPT_AAD)
    }

    override fun replaceAcknowledgementReceipt(bytes: ByteArray?): Boolean =
        synchronized(backendLock) {
            try {
                requireCredentialProtectedStorage()
                if (bytes == null) {
                    deleteDurably(acknowledgementReceiptFile)
                } else {
                    writeDurably(
                        acknowledgementReceiptFile,
                        ACKNOWLEDGEMENT_RECEIPT_AAD,
                        bytes,
                    )
                }
            } catch (_: Exception) {
                false
            }
        }

    private fun readProtected(target: AtomicFile, aad: ByteArray): ByteArray? {
        requireCredentialProtectedStorage()
        if (!atomicFileExists(target)) return null
        rejectOversizedEncryptedFile(target)
        val encrypted = target.readFully()
        if (encrypted.isEmpty() || encrypted.size > MAX_ENCRYPTED_RECORD_BYTES) {
            throw IOException("pending call ciphertext bounds invalid")
        }
        return decrypt(encrypted, aad)
    }

    private fun writeDurably(
        target: AtomicFile,
        aad: ByteArray,
        plaintext: ByteArray,
    ): Boolean {
        if (plaintext.isEmpty() || plaintext.size > PendingNativeCallStore.MAX_RECORD_BYTES) {
            return false
        }
        check(directory.exists() || directory.mkdirs())
        val encrypted = encrypt(plaintext, aad)
        if (encrypted.size > MAX_ENCRYPTED_RECORD_BYTES) return false
        var stream: FileOutputStream? = null
        try {
            stream = target.startWrite()
            stream.write(encrypted)
            stream.flush()
            stream.fd.sync()
            target.finishWrite(stream)
            stream = null
            syncDirectory()
        } catch (error: Exception) {
            stream?.let { active -> runCatching { target.failWrite(active) } }
            throw error
        }
        val readback = readProtected(target, aad)
        return readback != null && MessageDigest.isEqual(plaintext, readback)
    }

    private fun deleteDurably(target: AtomicFile): Boolean {
        target.delete()
        syncDirectory()
        return !atomicFileExists(target)
    }

    private fun encrypt(plaintext: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        if (iv.size != GCM_IV_BYTES) {
            throw GeneralSecurityException("unexpected GCM IV length")
        }
        val ciphertext = cipher.doFinal(plaintext)
        return ByteArrayOutputStream().use { buffer ->
            DataOutputStream(buffer).use { output ->
                output.writeInt(ENVELOPE_MAGIC)
                output.writeInt(ENVELOPE_VERSION)
                output.writeInt(iv.size)
                output.writeInt(ciphertext.size)
                output.write(iv)
                output.write(ciphertext)
            }
            buffer.toByteArray()
        }
    }

    private fun decrypt(envelope: ByteArray, aad: ByteArray): ByteArray {
        val input = DataInputStream(ByteArrayInputStream(envelope))
        if (
            input.readInt() != ENVELOPE_MAGIC ||
            input.readInt() != ENVELOPE_VERSION
        ) {
            throw GeneralSecurityException("pending call ciphertext header invalid")
        }
        val ivLength = input.readInt()
        val ciphertextLength = input.readInt()
        if (
            ivLength != GCM_IV_BYTES ||
            ciphertextLength <= GCM_TAG_BITS / 8 ||
            ciphertextLength > PendingNativeCallStore.MAX_RECORD_BYTES + GCM_TAG_BITS / 8 ||
            input.available() != ivLength + ciphertextLength
        ) {
            throw GeneralSecurityException("pending call ciphertext shape invalid")
        }
        val iv = ByteArray(ivLength).also(input::readFully)
        val ciphertext = ByteArray(ciphertextLength).also(input::readFully)
        if (input.available() != 0) {
            throw GeneralSecurityException("pending call ciphertext trailing bytes")
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(aad)
        val plaintext = cipher.doFinal(ciphertext)
        if (plaintext.isEmpty() || plaintext.size > PendingNativeCallStore.MAX_RECORD_BYTES) {
            throw GeneralSecurityException("pending call plaintext bounds invalid")
        }
        return plaintext
    }

    private fun getOrCreateKey(): SecretKey = synchronized(keyLock) {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null)
        if (existing != null) {
            return@synchronized existing as? SecretKey
                ?: throw GeneralSecurityException("pending call key type invalid")
        }
        if (keyStore.containsAlias(keyAlias)) {
            throw GeneralSecurityException("pending call key entry invalid")
        }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        generator.generateKey()
    }

    private fun atomicFileExists(target: AtomicFile): Boolean =
        target.baseFile.exists() || File(target.baseFile.path + ".bak").exists()

    private fun rejectOversizedEncryptedFile(target: AtomicFile) {
        val backup = File(target.baseFile.path + ".bak")
        if (
            (target.baseFile.exists() && target.baseFile.length() > MAX_ENCRYPTED_RECORD_BYTES) ||
            (backup.exists() && backup.length() > MAX_ENCRYPTED_RECORD_BYTES)
        ) {
            throw IOException("pending call ciphertext file too large")
        }
    }

    private fun requireCredentialProtectedStorage() {
        check(!applicationContext.isDeviceProtectedStorage) {
            "pending call storage must be credential protected"
        }
    }

    private fun syncDirectory() {
        val descriptor = Os.open(
            directory.absolutePath,
            OsConstants.O_RDONLY,
            0,
        )
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }
}

private object PendingNativeCallCodec {
    private const val RECORD_MAGIC = 0x4d4b4e43
    private const val MAX_STRING_BYTES = 64

    fun encode(descriptor: PendingNativeCallDescriptor): ByteArray? {
        if (!descriptor.isStructurallyValid()) return null
        return try {
            ByteArrayOutputStream().use { buffer ->
                DataOutputStream(buffer).use { output ->
                    output.writeInt(RECORD_MAGIC)
                    output.writeInt(descriptor.schemaVersion)
                    output.writeUuid(descriptor.nativeCallId)
                    output.writeUtf8(descriptor.callHandle)
                    output.writeUtf8(descriptor.wakeHandle)
                    output.writeLong(descriptor.receivedAtMs)
                    output.writeLong(descriptor.expiresAtMs)
                    output.writeLong(descriptor.highestSequence)
                    output.writeUtf8(descriptor.handoffAcknowledgement.name)
                    output.writeUtf8(descriptor.phase.name)
                    output.writeUtf8(descriptor.direction.name)
                    output.writeBoolean(descriptor.answerRequested)
                    output.writeUtf8(descriptor.lastAcknowledgement?.name.orEmpty())
                    output.writeLong(descriptor.lastAcknowledgedSequence)
                    output.writeLong(descriptor.terminalEvent?.sequence ?: 0L)
                    output.writeInt(descriptor.events.size)
                    for (event in descriptor.events) {
                        output.writeUuid(event.nativeCallId)
                        output.writeLong(event.sequence)
                        output.writeUuid(event.eventId)
                        output.writeUtf8(event.type.name)
                    }
                }
                buffer.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    fun decode(bytes: ByteArray): PendingNativeCallDescriptor? {
        if (bytes.isEmpty() || bytes.size > PendingNativeCallStore.MAX_RECORD_BYTES) return null
        return try {
            val input = DataInputStream(ByteArrayInputStream(bytes))
            if (input.readInt() != RECORD_MAGIC) return null
            val schemaVersion = input.readInt()
            if (schemaVersion !in 1..PENDING_NATIVE_CALL_SCHEMA_VERSION) return null
            val nativeCallId = input.readUuid()
            val callHandle = input.readUtf8()
            val wakeHandle = input.readUtf8()
            val receivedAtMs = input.readLong()
            val expiresAtMs = input.readLong()
            val highestSequence = input.readLong()
            val handoffAcknowledgement = input.readUtf8().let { name ->
                PendingNativeCallAcknowledgement.entries
                    .singleOrNull { it.name == name }
                    ?: return null
            }
            val phase = if (schemaVersion >= 2) {
                input.readUtf8().let { name ->
                    PendingNativeCallPhase.entries.singleOrNull { it.name == name }
                        ?: return null
                }
            } else if (handoffAcknowledgement == PendingNativeCallAcknowledgement.ADOPTED) {
                PendingNativeCallPhase.JOURNAL
            } else {
                PendingNativeCallPhase.PRE_START
            }
            val direction = if (schemaVersion >= 4) {
                input.readUtf8().let { name ->
                    PendingNativeCallDirection.entries.singleOrNull { it.name == name }
                        ?: return null
                }
            } else {
                PendingNativeCallDirection.INCOMING
            }
            val answerRequested = if (schemaVersion >= 3) input.readBoolean() else false
            val lastAcknowledgement = if (schemaVersion >= 3) {
                input.readUtf8().let { name ->
                    if (name.isEmpty()) null else PendingNativeCallAcknowledgement.entries
                        .singleOrNull { it.name == name } ?: return null
                }
            } else {
                null
            }
            val lastAcknowledgedSequence = if (schemaVersion >= 3) input.readLong() else 0L
            val terminalSequence = input.readLong()
            val eventCount = input.readInt()
            if (eventCount < 0 || eventCount > PendingNativeCallStore.MAX_EVENTS) return null
            val events = ArrayList<PendingNativeCallEvent>(eventCount)
            repeat(eventCount) {
                val eventNativeCallId = input.readUuid()
                val sequence = input.readLong()
                val eventId = input.readUuid()
                val typeName = input.readUtf8()
                val type = PendingNativeCallEventType.entries
                    .singleOrNull { it.name == typeName }
                    ?: return null
                events += PendingNativeCallEvent(
                    nativeCallId = eventNativeCallId,
                    sequence = sequence,
                    eventId = eventId,
                    type = type,
                )
            }
            if (input.available() != 0) return null
            val terminalEvent = when (terminalSequence) {
                0L -> null
                else -> events.singleOrNull { it.sequence == terminalSequence } ?: return null
            }
            PendingNativeCallDescriptor(
                nativeCallId = nativeCallId,
                callHandle = callHandle,
                wakeHandle = if (phase == PendingNativeCallPhase.JOURNAL) "" else wakeHandle,
                receivedAtMs = receivedAtMs,
                expiresAtMs = expiresAtMs,
                highestSequence = highestSequence,
                terminalEvent = terminalEvent,
                events = events.toList(),
                handoffAcknowledgement = handoffAcknowledgement,
                phase = phase,
                answerRequested = answerRequested || events.any {
                    it.type == PendingNativeCallEventType.ANSWER_REQUESTED
                },
                lastAcknowledgement = lastAcknowledgement,
                lastAcknowledgedSequence = lastAcknowledgedSequence,
                direction = direction,
                schemaVersion = PENDING_NATIVE_CALL_SCHEMA_VERSION,
            ).takeIf { it.isStructurallyValid() }
        } catch (_: Exception) {
            null
        }
    }

    private fun DataOutputStream.writeUuid(value: UUID) {
        writeLong(value.mostSignificantBits)
        writeLong(value.leastSignificantBits)
    }

    private fun DataInputStream.readUuid(): UUID = UUID(readLong(), readLong())

    private fun DataOutputStream.writeUtf8(value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        require(bytes.size <= MAX_STRING_BYTES)
        writeInt(bytes.size)
        write(bytes)
    }

    private fun DataInputStream.readUtf8(): String {
        val length = readInt()
        if (length < 0 || length > MAX_STRING_BYTES || length > available()) {
            throw IOException("pending call string bounds invalid")
        }
        val bytes = ByteArray(length).also(::readFully)
        val value = bytes.toString(Charsets.UTF_8)
        if (!value.toByteArray(Charsets.UTF_8).contentEquals(bytes)) {
            throw IOException("pending call string encoding invalid")
        }
        return value
    }
}

private object PendingNativeCallAcknowledgementReceiptCodec {
    private const val RECORD_MAGIC = 0x4d4b4152
    private const val SCHEMA_VERSION = 2
    private const val LEGACY_SCHEMA_VERSION = 1
    private const val DIGEST_BYTES = 32

    fun encode(receipts: List<PendingNativeCallAcknowledgementReceipt>): ByteArray? {
        if (
            receipts.isEmpty() ||
            receipts.size > PendingNativeCallStore.MAX_ACKNOWLEDGEMENT_RECEIPTS ||
            receipts.any { !it.isStructurallyValid() } ||
            receipts.map { it.nativeCallId }.toSet().size != receipts.size
        ) {
            return null
        }
        return try {
            ByteArrayOutputStream().use { buffer ->
                DataOutputStream(buffer).use { output ->
                    output.writeInt(RECORD_MAGIC)
                    output.writeInt(SCHEMA_VERSION)
                    output.writeInt(receipts.size)
                    receipts.forEach { receipt ->
                        output.writeLong(receipt.nativeCallId.mostSignificantBits)
                        output.writeLong(receipt.nativeCallId.leastSignificantBits)
                        output.write(receipt.callHandleDigest)
                        output.writeLong(receipt.highestConsumedSequence)
                        output.writeLong(receipt.expiresAtMs)
                    }
                }
                buffer.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    fun decode(bytes: ByteArray): List<PendingNativeCallAcknowledgementReceipt>? {
        return try {
            val input = DataInputStream(ByteArrayInputStream(bytes))
            if (input.readInt() != RECORD_MAGIC) return null
            val schemaVersion = input.readInt()
            val count = when (schemaVersion) {
                LEGACY_SCHEMA_VERSION -> 1
                SCHEMA_VERSION -> input.readInt().takeIf {
                    it in 1..PendingNativeCallStore.MAX_ACKNOWLEDGEMENT_RECEIPTS
                } ?: return null
                else -> return null
            }
            val receipts = List(count) {
                PendingNativeCallAcknowledgementReceipt(
                    nativeCallId = UUID(input.readLong(), input.readLong()),
                    callHandleDigest = ByteArray(DIGEST_BYTES).also(input::readFully),
                    highestConsumedSequence = input.readLong(),
                    expiresAtMs = input.readLong(),
                )
            }
            if (input.available() != 0) return null
            receipts.takeIf {
                it.all { receipt -> receipt.isStructurallyValid() } &&
                    it.map { receipt -> receipt.nativeCallId }.toSet().size == it.size
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun PendingNativeCallAcknowledgementReceipt.isStructurallyValid(): Boolean =
        callHandleDigest.size == DIGEST_BYTES &&
            highestConsumedSequence > 0L &&
            expiresAtMs > 0L
}

private fun PendingNativeCallDescriptor.matches(
    payload: CallWakePayload,
    expectedDirection: PendingNativeCallDirection,
): Boolean =
    nativeCallId == payload.nativeCallId &&
        callHandle == payload.callHandle &&
        direction == expectedDirection &&
        expiresAtMs == payload.expiresAtMs &&
        (
            expectedDirection == PendingNativeCallDirection.OUTGOING ||
                (
                    (phase != PendingNativeCallPhase.PRE_START || wakeHandle == payload.wakeHandle) &&
                        receivedAtMs == payload.receivedAtMs
                )
        )

private fun PendingNativeCallAcknowledgementReceipt.matches(payload: CallWakePayload): Boolean {
    val digest = callHandleDigest(payload.callHandle) ?: return false
    return nativeCallId == payload.nativeCallId &&
        MessageDigest.isEqual(callHandleDigest, digest)
}

private fun PendingNativeCallAcknowledgementReceipt.sameAcknowledgementAs(
    other: PendingNativeCallAcknowledgementReceipt,
): Boolean = nativeCallId == other.nativeCallId &&
    highestConsumedSequence == other.highestConsumedSequence &&
    MessageDigest.isEqual(callHandleDigest, other.callHandleDigest)

private fun CallWakePayload.toReceiptDuplicateDescriptor(
    direction: PendingNativeCallDirection,
): PendingNativeCallDescriptor =
    PendingNativeCallDescriptor(
        nativeCallId = nativeCallId,
        callHandle = callHandle,
        wakeHandle = wakeHandle,
        receivedAtMs = receivedAtMs,
        expiresAtMs = expiresAtMs,
        highestSequence = 0L,
        terminalEvent = null,
        events = emptyList(),
        direction = direction,
    )

private fun callHandleDigest(callHandle: String): ByteArray? {
    if (!CANONICAL_CALL_HANDLE.matches(callHandle)) return null
    return try {
        MessageDigest.getInstance("SHA-256").digest(callHandle.toByteArray(Charsets.UTF_8))
    } catch (_: Exception) {
        null
    }
}

private fun saturatingAdd(left: Long, right: Long): Long =
    if (right > 0L && left > Long.MAX_VALUE - right) Long.MAX_VALUE else left + right

private fun PendingNativeCallDescriptor.isStructurallyValid(): Boolean {
    val canonicalCallId = runCatching { UUID.fromString(callHandle) }.getOrNull()
    if (
        schemaVersion != PENDING_NATIVE_CALL_SCHEMA_VERSION ||
        !CANONICAL_CALL_HANDLE.matches(callHandle) ||
        canonicalCallId != nativeCallId ||
        receivedAtMs < 0L ||
        expiresAtMs <= receivedAtMs ||
        highestSequence < 0L ||
        lastAcknowledgedSequence < 0L ||
        lastAcknowledgedSequence > highestSequence ||
        handoffAcknowledgement == PendingNativeCallAcknowledgement.TERMINAL ||
        lastAcknowledgement == PendingNativeCallAcknowledgement.TERMINAL ||
        events.size > PendingNativeCallStore.MAX_EVENTS
    ) {
        return false
    }
    when (phase) {
        PendingNativeCallPhase.PRE_START -> if (
            handoffAcknowledgement != PendingNativeCallAcknowledgement.NONE ||
            !CALL_RANDOM_ID.matches(wakeHandle) ||
            expiresAtMs - receivedAtMs > CallPayloadParser.MAX_FUTURE_SKEW_MS
        ) {
            return false
        }
        PendingNativeCallPhase.JOURNAL -> if (
            handoffAcknowledgement != PendingNativeCallAcknowledgement.ADOPTED ||
            wakeHandle.isNotEmpty()
        ) {
            return false
        }
    }
    if (lastAcknowledgement == null && lastAcknowledgedSequence != 0L) return false
    if (lastAcknowledgement != null && lastAcknowledgedSequence <= 0L) return false
    if (events.isEmpty()) return terminalEvent == null
    if (events.first().sequence <= 0L || events.last().sequence != highestSequence) return false
    if (events.any { it.nativeCallId != nativeCallId }) return false
    if (events.map { it.eventId }.toSet().size != events.size) return false
    for (index in 1 until events.size) {
        if (events[index].sequence != events[index - 1].sequence + 1L) return false
    }
    val terminalEvents = events.filter { it.type.isTerminal() }
    return if (terminalEvent == null) {
        terminalEvents.isEmpty()
    } else {
        terminalEvents == listOf(terminalEvent) &&
            terminalEvent == events.last() &&
            terminalEvent.sequence == highestSequence
    }
}

private fun PendingNativeCallEventType.isTerminal(): Boolean = when (this) {
    PendingNativeCallEventType.DECLINE_REQUESTED,
    PendingNativeCallEventType.END_REQUESTED,
    PendingNativeCallEventType.REMOTE_CANCELLED,
    PendingNativeCallEventType.EXPIRED,
    PendingNativeCallEventType.PROVIDER_REMOVED,
    PendingNativeCallEventType.NATIVE_FAILURE,
    -> true

    PendingNativeCallEventType.PRESENTED,
    PendingNativeCallEventType.ANSWER_REQUESTED,
    PendingNativeCallEventType.MUTE_CHANGED,
    PendingNativeCallEventType.ROUTE_CHANGED,
    PendingNativeCallEventType.AUDIO_ACTIVATED,
    PendingNativeCallEventType.AUDIO_DEACTIVATED,
    -> false
}

private const val PENDING_NATIVE_CALL_SCHEMA_VERSION = 4
