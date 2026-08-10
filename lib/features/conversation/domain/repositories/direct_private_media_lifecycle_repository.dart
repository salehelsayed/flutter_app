import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';

import '../models/conversation_message.dart';
import '../models/direct_reaction_inbox_custody_outbox_entry.dart';

/// Direct-parent CAS/query authority consumed by the lane adapter.
///
/// Every mutation is an affected-row result. Zero is a normal lost race; no
/// caller may fall back to [MessageRepository.saveMessage].
abstract class DirectPrivateMediaLifecycleRepository {
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  );

  Future<bool> claimPrivateMediaOpening(String messageId, {required int nowMs});

  Future<bool> markPrivateMediaViewing(String messageId, {required int nowMs});

  Future<bool> rollbackPrivateMediaOpening(String messageId);

  Future<bool> consumePrivateMedia(String messageId, {required int nowMs});

  Future<bool> advancePrivateMediaClock(String messageId, {required int nowMs});

  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  });

  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  });

  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  });

  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  });

  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  });

  Future<int?> loadNextPrivateMediaExpiryAtMs();
}

/// Update-only persistence authority for an outgoing protected/View-Once
/// Delete-for-Everyone tombstone.
///
/// Both operations require the exact private parent to remain present. They
/// never insert a missing row, so a concurrent contact deletion or physical
/// failed-message removal remains authoritative. Implementations also preserve
/// an already-hidden parent and every private lifecycle column.
abstract interface class DirectPrivateDeleteForEveryoneRepository {
  /// Replaces the still-present original with the first durable `sending`
  /// deletion tombstone. Returns the authoritative persisted row, or null when
  /// removal/conflicting terminal intent won the race.
  ///
  /// 356: newly authored deletions no longer take this route — they commit the
  /// same tombstone predicate inside the atomic v109 transaction below. This
  /// stays as the unchanged tombstone-only boundary, and both paths share one
  /// within-transaction body so they can never disagree about which parents a
  /// deletion may replace.
  Future<ConversationMessage?> commitPrivateDeleteForEveryoneTombstone({
    required ConversationMessage expectedMessage,
    required ConversationMessage tombstone,
  });

  /// Replaces a missing/legacy cached deletion envelope on the exact failed
  /// tombstone without inserting a physically removed parent.
  Future<ConversationMessage?> stagePrivateDeleteForEveryoneRetryEnvelope({
    required ConversationMessage tombstone,
    required String? expectedEnvelope,
    required String envelope,
  });

  /// Settles only the transport/visibility columns of the exact tombstone.
  /// Returns the authoritative persisted row, or null when it was physically
  /// removed. Callers must never fall back to an insertion-capable full save.
  Future<ConversationMessage?> settlePrivateDeleteForEveryoneTombstone({
    required ConversationMessage tombstone,
    required String expectedEnvelope,
  });
}

/// Result of the one atomic private tombstone + physical v109 transaction.
///
/// [message] is the committed parent as the transaction saw it, so a caller
/// never has to re-read a row that its own terminal cleanup may already have
/// changed. [custody] is the exact retained event; a refusal returns neither.
class OutgoingDirectPrivateDeletionCustodyStageResult {
  const OutgoingDirectPrivateDeletionCustodyStageResult({
    required this.outcome,
    this.message,
    this.custody,
  });

  const OutgoingDirectPrivateDeletionCustodyStageResult.refused()
    : outcome = OutgoingOrdinaryMutationOutcome.refused,
      message = null,
      custody = null;

  final OutgoingOrdinaryMutationOutcome outcome;
  final ConversationMessage? message;
  final DirectReactionInboxCustodyOutboxEntry? custody;

  bool get authorizesTransport => outcome.authorizesTransport;
}

/// Optional fail-closed staging capability for a newly authored v1
/// Protected/View-Once delete-for-everyone event.
///
/// 356: this adds ONE transaction to the incumbent private delete boundary. It
/// is not a new durable owner — the retained event lives in the same physical
/// v109 outbox every other direct mutation uses, and its load/failure/
/// completion lifecycle stays with
/// `DirectMutationInboxCustodyLifecycleRepository`.
abstract interface class OutgoingDirectPrivateDeletionInboxCustodyRepository {
  /// True only when the atomic stage is configured. An eligible private
  /// deletion must fail closed when this is false; it must never fall back to
  /// the legacy tombstone-only commit while minting an event id.
  bool get supportsDirectPrivateDeletionInboxCustody;

  Future<OutgoingDirectPrivateDeletionCustodyStageResult>
  stageOutgoingDirectPrivateDeletionInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage tombstone,
    required String recipientPeerId,
    required String eventId,
    required String wireEnvelope,
  });
}

/// Durable CAS authority for transitions owned by one exact in-memory lease.
///
/// The parent direction/mode and attachment identity/path are part of the
/// write predicate, rather than only a pre-write read, so a concurrent row
/// replacement cannot inherit another operation's reveal authority.
abstract class DirectPrivateMediaExactOpeningLeaseRepository {
  Future<bool> claimExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });

  Future<bool> markExactPrivateMediaViewing(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });

  Future<bool> rollbackExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
  });

  Future<bool> consumeExactPrivateMedia(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });
}

/// Optional exact-CAS authority required only for operation-aware settlement
/// recovery after an indeterminate terminalization write.
abstract class DirectPrivateMediaIndeterminateQuarantineRepository {
  Future<bool> quarantineIndeterminatePrivateMediaAvailable(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });
}
