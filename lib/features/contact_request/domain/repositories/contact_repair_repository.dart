/// Task 12b durable state for the reply-once existing-contact repair.
///
/// The SQL primary key on (peer, signed request ID) is the duplicate guard;
/// every state change is a compare-and-set on the job's claim token, so two
/// callbacks, two repository handles or a stale worker converge on one reply.
library;

/// Relationship memory for one peer. A row exists for every contact added or
/// deleted after DB v121, and for every contact that existed at the upgrade.
enum ContactRelationshipState { active, withdrawn, declined }

final class ContactRelationshipConsent {
  const ContactRelationshipConsent({
    required this.state,
    required this.revision,
  });

  final ContactRelationshipState state;

  /// Monotonic; bumped by every delete, decline and explicit (re-)add.
  final int revision;
}

/// One authenticated, fresh, signed `new_request` asking for a reply.
final class ContactRepairClaim {
  const ContactRepairClaim({
    required this.peerId,
    required this.requestId,
    required this.requestDigest,
    required this.signedAtMs,
    required this.authorityFingerprint,
    required this.localAuthorityFingerprint,
    required this.relationshipRevision,
    required this.wallNowMs,
  });

  final String peerId;
  final String requestId;

  /// Digest of the exact canonical signed payload.
  final String requestDigest;
  final int signedAtMs;

  /// Fingerprint of the STORED Ed25519 key the request was verified with.
  final String authorityFingerprint;

  /// Fingerprint of our own account key at claim time.
  final String localAuthorityFingerprint;

  /// Relationship revision captured before intro routing.
  final int relationshipRevision;
  final int wallNowMs;
}

enum ContactRepairClaimStatus {
  /// A new reply reservation was committed.
  reserved,

  /// The same signed request (same digest) was already claimed.
  duplicate,

  /// The same signed request ID arrived with a different signed body.
  conflict,

  /// The signed time is outside the freshness window.
  stale,

  /// The wall clock is behind the persisted high-water: defer automatic work.
  clockAnomaly,

  /// Authority, relationship or consent changed, or the peer is blocked.
  refused,

  /// A queue or guard capacity is full. Retryable; nothing was reserved.
  overflow,
}

final class ContactRepairClaimOutcome {
  const ContactRepairClaimOutcome(this.status, {this.replyId, this.dueAtMs});

  final ContactRepairClaimStatus status;
  final String? replyId;
  final int? dueAtMs;

  bool get queued =>
      status == ContactRepairClaimStatus.reserved ||
      status == ContactRepairClaimStatus.duplicate;
}

enum ContactRepairJobState {
  buildable,
  ready,
  sending,
  completed,
  exhausted,
  expired,
  cancelled,
}

final class ContactRepairJob {
  const ContactRepairJob({
    required this.peerId,
    required this.requestId,
    required this.replyId,
    required this.state,
    required this.authorityFingerprint,
    required this.localAuthorityFingerprint,
    required this.relationshipRevision,
    required this.attempts,
    required this.dueAtMs,
    this.claimToken,
    this.envelopeJson,
    this.grantGeneration,
  });

  final String peerId;
  final String requestId;
  final String replyId;
  final ContactRepairJobState state;
  final String authorityFingerprint;
  final String localAuthorityFingerprint;
  final int relationshipRevision;
  final int attempts;
  final int dueAtMs;
  final String? claimToken;
  final String? envelopeJson;
  final int? grantGeneration;
}

abstract interface class ContactRepairRepository {
  Future<ContactRelationshipConsent?> readConsent(String peerId);

  /// The signed digest already recorded for this request ID, if any. A
  /// different digest under the same ID is a conflict and must be rejected
  /// before any incoming state is applied.
  Future<String?> lookupRequestDigest({
    required String peerId,
    required String requestId,
  });

  /// Atomically rechecks the stored authority, relationship and capacity,
  /// paces the peer, and reserves one reply for [claim].
  Future<ContactRepairClaimOutcome> claimReply(ContactRepairClaim claim);

  /// Records that [peerId], an existing contact, sent a valid signed marker.
  Future<void> recordPeerSupportsMarked(String peerId);

  Future<bool> peerSupportsMarked(String peerId);

  /// Claims up to [limit] due jobs for [claimToken] (state -> sending and one
  /// attempt consumed), never exceeding the global transmit cap.
  Future<List<ContactRepairJob>> takeDueJobs({
    required String claimToken,
    required int wallNowMs,
    required int limit,
  });

  /// Commits the immutable envelope once, before its first send.
  Future<bool> commitEnvelope({
    required ContactRepairJob job,
    required String claimToken,
    required String envelopeJson,
    required int? grantGeneration,
  });

  /// True while [claimToken] still owns the job in `sending`.
  Future<bool> stillOwns({
    required ContactRepairJob job,
    required String claimToken,
  });

  Future<bool> completeJob({
    required ContactRepairJob job,
    required String claimToken,
  });

  /// Returns the job to its queue at [dueAtMs], or marks it exhausted when
  /// its attempts are used up.
  Future<bool> releaseForRetry({
    required ContactRepairJob job,
    required String claimToken,
    required int dueAtMs,
  });

  Future<bool> cancelJob({
    required ContactRepairJob job,
    required String claimToken,
  });

  /// Re-queues every `sending` job not owned by [newClaimToken], fencing any
  /// previous owner's later compare-and-set. Returns the number re-queued.
  Future<int> takeOverInFlight({required String newClaimToken});

  /// Earliest due time of a queued job, if any.
  Future<int?> nextDueAtMs();

  /// Deletes terminal guards that can no longer be fresh and expires queued
  /// jobs whose request went stale. Bounded per call.
  Future<int> collectGarbage({required int wallNowMs});
}
