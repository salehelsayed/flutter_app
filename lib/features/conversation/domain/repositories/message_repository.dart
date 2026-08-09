import '../models/conversation_message.dart';
import '../models/direct_inbox_custody_outbox_entry.dart';
import '../models/direct_reaction_inbox_custody_outbox_entry.dart';
import '../models/media_attachment.dart';
import '../models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/core/database/incoming_ordinary_text_mutation.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';

/// Repository interface for managing conversation messages.
abstract class MessageRepository {
  /// Saves a message to the database.
  ///
  /// If a message with the same ID exists, it will be replaced.
  Future<void> saveMessage(ConversationMessage message);

  /// Retrieves all messages for a contact, ordered by timestamp ASC.
  ///
  /// Returns an empty list if no messages exist.
  Future<List<ConversationMessage>> getMessagesForContact(String contactPeerId);

  /// Retrieves the most recent message for a contact.
  ///
  /// Returns null if no messages exist for the contact.
  Future<ConversationMessage?> getLatestMessageForContact(String contactPeerId);

  /// Updates the delivery status of a message.
  Future<void> updateMessageStatus(String id, String status);

  /// Retrieves a single message by ID.
  ///
  /// Returns null if no message with the given ID exists.
  Future<ConversationMessage?> getMessage(String id);

  /// Checks if a message with the given ID exists.
  Future<bool> messageExists(String id);

  /// Returns true if an incoming message with the same logical content already
  /// exists (F8 content dedup — the 1:1 twin of the group-side check).
  ///
  /// Keyed on `(contactPeerId, senderPeerId, text, timestamp)` over incoming
  /// rows. Catches a divergent-id re-delivery that PRESERVES the original wire
  /// timestamp, which the id-only [getMessage]/[messageExists] gate misses and
  /// which would otherwise persist a second row (two-stacked-card condition).
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  );

  /// Returns true if an incoming message with the same wire-stamped `dedupKey`
  /// already exists (F8 tier-2). Unlike [existsByContent] (timestamp-exact),
  /// this survives retry/redelivery that re-mints BOTH id and timestamp,
  /// including one Forward action's random operation token. Keyed on
  /// `(contactPeerId, senderPeerId, dedupKey)` over incoming rows.
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  );

  /// Returns the total number of messages for a contact.
  Future<int> getMessageCountForContact(String contactPeerId);

  /// Marks all unread incoming messages for a contact as read.
  Future<int> markConversationAsRead(String contactPeerId);

  /// Returns the number of unread incoming messages for a contact.
  Future<int> getUnreadCountForContact(String contactPeerId);

  /// Returns the total number of unread incoming messages across all contacts.
  Future<int> getTotalUnreadCount();

  /// Returns the total unread count excluding archived contacts.
  Future<int> getTotalUnreadCountExcludingArchived();

  /// Deletes all messages for a contact. Returns the count of deleted rows.
  Future<int> deleteMessagesForContact(String contactPeerId);

  /// Deletes a single message by ID. Returns the count of deleted rows.
  Future<int> deleteMessage(String id);

  /// Retrieves all outgoing messages with status='failed'.
  ///
  /// Used by the retry service to find messages that need re-sending.
  Future<List<ConversationMessage>> getFailedOutgoingMessages();

  /// Retrieves all outgoing messages with status='sending'.
  ///
  /// Used by the pause handler to mark in-flight messages as failed
  /// before the OS freezes the process.
  Future<List<ConversationMessage>> getSendingOutgoingMessages();

  /// Transitions a message's status only if its current status matches [fromStatus].
  ///
  /// Returns the number of rows updated (0 if the row already advanced past
  /// [fromStatus], e.g., a concurrent send completed 'sending' -> 'delivered'
  /// before the pause handler could transition it to 'failed').
  ///
  /// Implementations MUST also emit on [MessageRepositoryChangeSource.messageChanges]
  /// when a row is successfully updated, so open UI screens react.
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  });

  /// Retrieves outgoing messages with status='sent' and a non-null wire_envelope
  /// that are older than [olderThan].
  ///
  /// These are messages written to the stream but not ACK'd by the peer.
  /// Used by the unacked retry service to store them in the relay inbox.
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  });

  /// Transitions all outgoing messages with status='sending' that are older
  /// than [olderThan] to status='failed', so the retry service picks them up.
  ///
  /// Returns the count of rows updated.
  Future<int> recoverStuckSendingMessages({required Duration olderThan});

  /// Updates the wire_envelope column for a message by ID.
  ///
  /// Used by sendChatMessage to persist the serialized envelope before the
  /// transport race, so a crash during the race leaves a retryable DB row.
  Future<void> updateWireEnvelope(String id, String envelope);

  /// Retrieves outgoing messages with status='sending' that are older than
  /// [olderThan] and have not yet been transitioned by [recoverStuckSendingMessages].
  ///
  /// NOTE: Currently unused by production code -- the retrier goes through
  /// recoverStuckSendingMessages -> retryFailedMessages instead. Kept as a
  /// diagnostic hook and for potential future recovery strategies.
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  });

  /// Retrieves a page of messages for a contact, ordered by timestamp ASC.
  ///
  /// Returns at most [limit] messages. When [beforeTimestamp] is null,
  /// returns the most recent page. When provided, returns messages older
  /// than that cursor.
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  });
}

/// Post-transaction publication seam for strict incoming direct media.
///
/// The database transaction is owned by the media repository because it spans
/// the parent, every attachment, and v111. This companion publishes only after
/// that transaction commits, preserving the normal message stream contract.
abstract interface class IncomingDirectMessagePublicationRepository {
  Future<StrictIncomingMediaPublicationDisposition>
  publishIncomingDirectMediaMessage({
    required ConversationMessage message,
    required List<MediaAttachment> attachments,
  });
}

/// Durable disposition of one strict incoming media publication attempt.
enum StrictIncomingMediaPublicationDisposition {
  /// The exact committed parent and its attachments reached the stream.
  published,

  /// A durable author tombstone won between the strict DB commit and this
  /// callback. Nothing stale is published, and this is not an error: the
  /// caller still owes exactly one initial message receipt.
  durablySuperseded,
}

/// Optional, fail-closed authority for ordinary outgoing attempt and transport
/// mutations. It intentionally lives beside (not on) [MessageRepository] so
/// unrelated repository fakes do not acquire new abstract methods.
abstract interface class OutgoingTransportMutationRepository {
  /// Durably stages one text-only attempt before any P2P or inbox work.
  ///
  /// Fresh attempts are insert-only. Every other kind is update-only and binds
  /// [expected] as the exact caller-observed predecessor.
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttempt({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
  });

  /// Atomically owns status, transport, envelope, relay expiry, custody-check,
  /// and (for an ordinary deletion tombstone) its delivered visibility.
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryTransport({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  });

  /// Tombstone-specific settlement with atomic delivered visibility derivation.
  Future<OutgoingOrdinaryMutationResult> settleOutgoingOrdinaryDeleteTombstone({
    required String messageId,
    required String expectedContactPeerId,
    required String? expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
    required OutgoingOrdinarySettlementMode mode,
  });

  /// Clears only the exact cached envelope invalidated by media-key rotation.
  Future<OutgoingOrdinaryMutationResult> invalidateOutgoingOrdinaryEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
  });

  /// Exact sent -> failed exception for an unsafe legacy envelope. This is not
  /// an edge in the normal transport settlement table.
  Future<OutgoingOrdinaryMutationResult>
  quarantineUnsafeLegacyOutgoingEnvelope({
    required String messageId,
    required String expectedContactPeerId,
    required String expectedEnvelope,
    required bool isDeleteTombstone,
  });
}

/// Optional, fail-closed companion authority for newly authored ordinary
/// direct-text inbox custody. It stays beside [MessageRepository] so unrelated
/// repository fakes and every excluded event kind need no implementation.
abstract interface class OutgoingDirectTextInboxCustodyRepository {
  /// True only when the complete atomic stage/drain/completion surface is
  /// configured. Eligible fresh text must fail closed when this is false; it
  /// must never fall back to live-only ordinary staging.
  bool get supportsDirectTextInboxCustody;

  /// Commits the exact fresh message attempt and immutable custody row in one
  /// SQLCipher transaction. Only [OutgoingOrdinaryAttemptKind.fresh] with a
  /// null [expected] predecessor may mint custody.
  Future<OutgoingOrdinaryMutationResult> stageOutgoingDirectTextInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String incarnationId,
    required String wireEnvelope,
  });

  /// Loads at most 50 rows, with never-attempted rows first and then the
  /// oldest attempt. A caller-supplied larger limit is clamped by storage.
  Future<List<DirectInboxCustodyOutboxEntry>> loadDirectInboxCustody({
    int limit = 50,
  });

  /// Loads the pending exact-event owner for one outgoing direct message.
  Future<DirectInboxCustodyOutboxEntry?> loadDirectInboxCustodyForMessage({
    required String recipientPeerId,
    required String messageId,
  });

  /// Resolves ownership by immutable message identity alone. The returned
  /// row supplies the authoritative stored recipient for replay; callers must
  /// not scope this lookup with the mutable parent message's contact field.
  Future<DirectInboxCustodyOutboxEntry?>
  loadDirectInboxCustodyOwnerForMessageId({required String messageId});

  /// Records one retained failure only if [expected]'s immutable incarnation
  /// still owns its recipient/message scope.
  Future<bool> recordDirectInboxCustodyFailureIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required String errorCode,
  });

  /// After `stored` or `duplicate`, atomically preserves stronger local truth,
  /// otherwise projects `inboxed`, and retires only [expected]'s incarnation.
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  });
}

class OutgoingDirectTextMutationCustodyStageResult {
  const OutgoingDirectTextMutationCustodyStageResult({
    required this.outcome,
    required this.message,
    required this.custody,
  });

  const OutgoingDirectTextMutationCustodyStageResult.refused({this.message})
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      custody = null;

  final OutgoingOrdinaryMutationOutcome outcome;
  final ConversationMessage? message;
  final DirectReactionInboxCustodyOutboxEntry? custody;

  bool get authorizesTransport => outcome.authorizesTransport;
}

/// The shared load/failure/completion lifecycle for one exact direct mutation
/// event in the physical v109 outbox.
///
/// Deliberately independent of which owner staged the event: a text parent and
/// a strict-media parent retain byte-identical obligations and must converge
/// through the same drain. Method names keep their original `Text` spelling so
/// the frozen v109 file/table/migration identity stays untouched.
abstract interface class DirectMutationInboxCustodyLifecycleRepository {
  bool get supportsDirectMutationInboxCustodyLifecycle;

  Future<DirectReactionInboxCustodyOutboxEntry?>
  loadDirectTextMutationInboxCustodyForEvent({
    required String recipientPeerId,
    required String eventId,
  });

  Future<bool> recordDirectTextMutationInboxCustodyFailureIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required String errorCode,
  });

  Future<DirectMutationInboxCustodyCompletionOutcome>
  completeAcceptedDirectTextMutationInboxCustodyIfExact({
    required DirectReactionInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  });
}

/// Optional fail-closed authority for newly authored ordinary direct-text
/// edit/delete events stored in the shared physical v109 outbox.
abstract interface class OutgoingDirectTextMutationInboxCustodyRepository
    implements DirectMutationInboxCustodyLifecycleRepository {
  bool get supportsDirectTextMutationInboxCustody;

  Future<OutgoingDirectTextMutationCustodyStageResult>
  stageOutgoingDirectTextMutationInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage staged,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String eventId,
    required String wireEnvelope,
  });
}

class IncomingOrdinaryTextApplyResult {
  const IncomingOrdinaryTextApplyResult({
    required this.outcome,
    required this.message,
  });

  final IncomingOrdinaryTextMutationOutcome outcome;
  final ConversationMessage? message;

  bool get isDurable => outcome.isDurable;
  bool get changed => outcome.changed;
}

/// Optional narrow transaction boundary for ordinary incoming initial, edit,
/// and deletion projections that share one target message id.
abstract interface class IncomingOrdinaryTextApplyRepository {
  Future<IncomingOrdinaryTextApplyResult> applyIncomingOrdinaryTextMutation({
    required ConversationMessage incoming,
    required IncomingOrdinaryTextMutationKind kind,
  });
}

class IncomingDirectDeletionApplyResult {
  const IncomingDirectDeletionApplyResult({
    required this.outcome,
    required this.message,
  });

  final IncomingDirectDeletionOutcome outcome;
  final ConversationMessage? message;

  bool get isDurable => outcome.isDurable;
  bool get changed => outcome.changed;
}

/// Optional transactional owner for one authenticated current incoming
/// deletion event, whatever its target turns out to be at commit time.
///
/// The target is re-read inside the transaction, so an independently
/// dispatched initial/media stream cannot route this event from a stale
/// pre-read classification. Legacy event-less deletion payloads keep their
/// existing owners.
abstract interface class IncomingDirectDeletionApplyRepository {
  bool get supportsIncomingDirectDeletionApply;

  Future<IncomingDirectDeletionApplyResult> applyIncomingDirectMessageDeletion({
    required String messageId,
    required String senderPeerId,
    required String deletedAt,
    required String? transport,
  });
}

/// Optional change stream for repository-backed message mutations.
///
/// Screens can use this to react to background status changes, such as retry
/// success, without polling or reloading the full conversation/feed snapshot.
abstract class MessageRepositoryChangeSource {
  Stream<ConversationMessage> get messageChanges;
}

/// Exact column-only custody boundary for a key-rotating outgoing private
/// media retry. Implementations requalify the visible direct parent and its
/// convention-relative pending attachment in the same transaction as the
/// envelope clear, without rewriting lifecycle or deletion state.
abstract interface class OutgoingDirectPrivateEnvelopeCustodyRepository {
  Future<bool> invalidateWireEnvelopeBeforePrivateUpload({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  });

  /// Returns an envelope-less manual upload attempt to retryable `failed`
  /// status only while the exact protected/view-once parent and convention-
  /// owned pending attachment still exist. This never rewrites lifecycle,
  /// deletion, attachment, or envelope state.
  Future<bool> markOutgoingDirectPrivateUploadHandoffFailed({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  });

  /// Persists the final encrypted envelope only while the exact outgoing
  /// protected/view-once parent and its single attachment still carry the
  /// matching completion/pending custody described by the caller.
  Future<OutgoingDirectPrivateEnvelopeHandoffOutcome>
  commitOutgoingDirectPrivateWireEnvelope({
    required String messageId,
    required MediaAttachment completedAttachment,
    required String expectedPendingLocalPath,
    required String envelope,
    required bool hasOwnedPendingCompletion,
  });

  /// Settles only transport-owned columns after network/inbox work. The
  /// implementation repeats the exact visible private-parent, handoff
  /// envelope and lifecycle predicates in one DB CAS. Live media requires its
  /// exact single attachment; a cleaned terminal parent requires zero.
  /// Concurrent hide/delete/removal is reported as a no-op and must never
  /// trigger a generic full-row fallback.
  Future<OutgoingDirectPrivateTransportSettlementOutcome>
  settleOutgoingDirectPrivateTransport({
    required String messageId,

    /// Exact live attachment identity, or null only for a durably consumed
    /// parent whose terminal cleanup has removed its sole direct attachment.
    required String? attachmentId,
    required String expectedEnvelope,
    required String status,
    required String? transport,
    required int? relayExpiresAt,
  });
}

/// Exact, post-commit signal for physical direct-message removals.
///
/// A removal cannot ride [MessageRepositoryChangeSource.messageChanges]: that
/// stream carries rows which UI consumers upsert, while a physically removed
/// row has no safe synthetic [ConversationMessage] representation. A null
/// [DirectMessageRemoval.messageId] means every parent in the exact contact
/// scope was removed.
class DirectMessageRemoval {
  const DirectMessageRemoval({
    required this.contactPeerId,
    required this.messageId,
  });

  final String contactPeerId;
  final String? messageId;
}

/// Optional repository capability for consumers that must react immediately
/// to successful physical deletes while retaining polling only as a backstop.
abstract class MessageRepositoryRemovalSource {
  Stream<DirectMessageRemoval> get messageRemovals;
}

/// Optional read-marking event stream (194).
///
/// Emits a contact `peerId` whenever a [MessageRepository.markConversationAsRead]
/// call actually flips >=1 incoming row to read. Deliberately a lightweight
/// conversation-level signal (a `String` peerId, NOT a [ConversationMessage]) —
/// riding [MessageRepositoryChangeSource.messageChanges] would force every
/// message-change listener to special-case a synthetic "read" message. Surfaces
/// that project unread state per contact (e.g. the Orbit inner circle) subscribe
/// to this to clear an indicator even when the read happened on another surface
/// (notification tap, feed-side open) that never traverses their own nav hooks.
///
/// Contract: fires ONLY when the marked-row count is `> 0` (INV-5), so a
/// re-mark of an already-read conversation is silent and cannot loop listeners.
abstract class ConversationReadEventSource {
  Stream<String> get conversationReadStream;
}
