import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Public result vocabulary for every outgoing direct-private upload
/// completion. Callers must carry the returned result through transport
/// handoff; a deferred or transport-only result is not a failed upload.
enum OutgoingDirectPrivateMutationOutcome {
  committed,
  deferredActiveLease,
  transportOnlyTerminalCustody,
  refused,
}

/// Result vocabulary for an outgoing direct-private mutation that is not an
/// upload completion (failure/cancel/rearm or another metadata-only save).
///
/// Unlike a completion, these intents are never queued. An active viewer
/// lease must remain byte-identical and the caller may retry only after
/// settlement; a terminal parent is a permanent local-mutation no-op.
enum OutgoingDirectPrivateNonCompletionMutationOutcome {
  applied,
  notAppliedActiveLease,
  terminalNoOp,
  refused,
  notPrivateParent,
}

/// Result of preparing the first convention-owned pending row for an outgoing
/// protected/view-once upload.
///
/// [notPrivateParent] deliberately preserves the generic persistence path for
/// ordinary, incoming, and disappearing media. Every protected/view-once or
/// unknown-policy result is final: callers must never fall through to an
/// insertion-capable generic save after [refused].
enum OutgoingDirectPrivatePendingPreparationOutcome {
  inserted,
  refused,
  notPrivateParent,
}

/// Durable result of the final private transport-envelope handoff.
enum OutgoingDirectPrivateEnvelopeHandoffOutcome {
  committed,
  idempotent,
  refused;

  bool get authorizesTransport => this == committed || this == idempotent;
}

/// Result of the post-network, column-only private transport settlement.
///
/// [preservedUserIntent] means a concurrent hide/delete/removal won before the
/// settlement compare-and-set. It is a successful no-op for mutation routing:
/// callers must not fall back to a stale full-row save.
enum OutgoingDirectPrivateTransportSettlementOutcome {
  committed,
  idempotent,
  preservedUserIntent,
  refused;

  bool get accepted => this != refused;
}

/// Typed failure used only when a legacy generic [saveAttachment]-style call
/// reaches the private first-preparation boundary. New private callers use the
/// batch preparation API and consume its outcome directly; this exception
/// prevents older callers from mistaking a refusal for a successful void save.
class OutgoingDirectPrivatePendingPreparationRefused implements Exception {
  const OutgoingDirectPrivatePendingPreparationRefused(this.outcome);

  final OutgoingDirectPrivatePendingPreparationOutcome outcome;

  @override
  String toString() =>
      'OutgoingDirectPrivatePendingPreparationRefused(${outcome.name})';
}

/// Internal durable classification returned by the repository's DB seam.
///
/// [notPrivateParent] is intentionally distinct from [refused] so the generic
/// repository save can preserve ordinary direct-media behavior while refusing
/// every private-parent fallback.
enum OutgoingDirectPrivateCompletionQualification {
  notPrivateParent,
  availablePending,
  activeLeasePending,
  identicalCommittedCandidate,
  transportOnlyTerminalCustody,
  refused,
}

/// Exact completion identity retained while a sender's local viewer lease is
/// active. Equality deliberately covers every persisted security/identity
/// field required by the upload-completion contract; it never relies on
/// [MediaAttachment]'s id-only equality.
class OutgoingDirectPrivateCompletionFingerprint {
  const OutgoingDirectPrivateCompletionFingerprint({
    required this.messageId,
    required this.attachmentId,
    required this.ownerLane,
    required this.expectedPendingLocalPath,
    required this.canonicalLocalPath,
    required this.downloadStatus,
    required this.mime,
    required this.size,
    required this.contentHash,
    required this.thumbnailHash,
    required this.encryptionKeyBase64,
    required this.encryptionNonce,
    required this.encryptionScheme,
  });

  factory OutgoingDirectPrivateCompletionFingerprint.fromAttachment(
    MediaAttachment attachment, {
    required String expectedPendingLocalPath,
  }) {
    return OutgoingDirectPrivateCompletionFingerprint(
      messageId: attachment.messageId,
      attachmentId: attachment.id,
      ownerLane: attachment.ownerLane,
      expectedPendingLocalPath: expectedPendingLocalPath,
      canonicalLocalPath: attachment.localPath,
      downloadStatus: attachment.downloadStatus,
      mime: attachment.mime,
      size: attachment.size,
      contentHash: attachment.contentHash,
      thumbnailHash: attachment.thumbnailHash,
      encryptionKeyBase64: attachment.encryptionKeyBase64,
      encryptionNonce: attachment.encryptionNonce,
      encryptionScheme: attachment.encryptionScheme,
    );
  }

  final String messageId;
  final String attachmentId;
  final MediaOwnerLane? ownerLane;
  final String expectedPendingLocalPath;
  final String? canonicalLocalPath;
  final String downloadStatus;
  final String mime;
  final int size;
  final String? contentHash;
  final String? thumbnailHash;
  final String? encryptionKeyBase64;
  final String? encryptionNonce;
  final String? encryptionScheme;

  bool get isStructurallyComplete =>
      messageId.isNotEmpty &&
      attachmentId.isNotEmpty &&
      ownerLane == MediaOwnerLane.direct &&
      expectedPendingLocalPath.isNotEmpty &&
      canonicalLocalPath != null &&
      canonicalLocalPath!.isNotEmpty &&
      downloadStatus == 'done' &&
      mime.isNotEmpty &&
      size > 0 &&
      contentHash != null &&
      contentHash!.isNotEmpty &&
      encryptionKeyBase64 != null &&
      encryptionKeyBase64!.isNotEmpty &&
      encryptionNonce != null &&
      encryptionNonce!.isNotEmpty &&
      encryptionScheme != null &&
      encryptionScheme!.isNotEmpty;

  bool matchesHydratedAttachment(MediaAttachment attachment) {
    return messageId == attachment.messageId &&
        attachmentId == attachment.id &&
        ownerLane == attachment.ownerLane &&
        canonicalLocalPath == attachment.localPath &&
        downloadStatus == attachment.downloadStatus &&
        mime == attachment.mime &&
        size == attachment.size &&
        contentHash == attachment.contentHash &&
        thumbnailHash == attachment.thumbnailHash &&
        encryptionKeyBase64 == attachment.encryptionKeyBase64 &&
        encryptionNonce == attachment.encryptionNonce &&
        encryptionScheme == attachment.encryptionScheme;
  }

  @override
  bool operator ==(Object other) {
    return other is OutgoingDirectPrivateCompletionFingerprint &&
        messageId == other.messageId &&
        attachmentId == other.attachmentId &&
        ownerLane == other.ownerLane &&
        expectedPendingLocalPath == other.expectedPendingLocalPath &&
        canonicalLocalPath == other.canonicalLocalPath &&
        downloadStatus == other.downloadStatus &&
        mime == other.mime &&
        size == other.size &&
        contentHash == other.contentHash &&
        thumbnailHash == other.thumbnailHash &&
        encryptionKeyBase64 == other.encryptionKeyBase64 &&
        encryptionNonce == other.encryptionNonce &&
        encryptionScheme == other.encryptionScheme;
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    attachmentId,
    ownerLane,
    expectedPendingLocalPath,
    canonicalLocalPath,
    downloadStatus,
    mime,
    size,
    contentHash,
    thumbnailHash,
    encryptionKeyBase64,
    encryptionNonce,
    encryptionScheme,
  );
}

class OutgoingDirectPrivateMutationResult {
  const OutgoingDirectPrivateMutationResult({
    required this.outcome,
    required this.fingerprint,
    this.appliesToPrivateParent = true,
  });

  final OutgoingDirectPrivateMutationOutcome outcome;
  final OutgoingDirectPrivateCompletionFingerprint fingerprint;

  /// False only when the durable parent is ordinary direct media. Generic
  /// repository persistence may continue only in that case.
  final bool appliesToPrivateParent;

  bool get authorizesTransportHandoff =>
      outcome == OutgoingDirectPrivateMutationOutcome.committed ||
      outcome == OutgoingDirectPrivateMutationOutcome.deferredActiveLease ||
      outcome ==
          OutgoingDirectPrivateMutationOutcome.transportOnlyTerminalCustody;
}

typedef OutgoingDirectPrivateCompletionClassifier =
    Future<OutgoingDirectPrivateCompletionQualification> Function(
      MediaAttachment attachment,
      OutgoingDirectPrivateCompletionFingerprint fingerprint,
    );

typedef OutgoingDirectPrivateCompletionCommitter =
    Future<bool> Function(
      MediaAttachment attachment,
      OutgoingDirectPrivateCompletionFingerprint fingerprint,
    );

typedef OutgoingDirectPrivateRollbackCommitter =
    Future<bool> Function(
      MediaAttachment attachment,
      OutgoingDirectPrivateCompletionFingerprint fingerprint, {
      required String mode,
    });

/// One repository-owned, process-local completion authority.
///
/// The repository supplies all durable callbacks. This class owns only the
/// bounded one-slot-per-attachment deferred/custody records and linearizes
/// classification, commit, token publication, settlement, and discard under
/// that repository's exact attachment lifecycle lock.
class OutgoingDirectPrivateMutationCoordinator {
  OutgoingDirectPrivateMutationCoordinator({
    required MediaAttachmentLifecycleLock lifecycleLock,
    required OutgoingDirectPrivateCompletionClassifier classifyCompletion,
    required OutgoingDirectPrivateCompletionCommitter commitAvailable,
    required OutgoingDirectPrivateRollbackCommitter commitRollback,
  }) : _lifecycleLock = lifecycleLock,
       _classifyCompletion = classifyCompletion,
       _commitAvailable = commitAvailable,
       _commitRollback = commitRollback;

  final MediaAttachmentLifecycleLock _lifecycleLock;
  final OutgoingDirectPrivateCompletionClassifier _classifyCompletion;
  final OutgoingDirectPrivateCompletionCommitter _commitAvailable;
  final OutgoingDirectPrivateRollbackCommitter _commitRollback;

  final Map<String, _DeferredCompletion> _deferredByAttachment = {};
  final Map<String, OutgoingDirectPrivateCompletionFingerprint>
  _terminalCustodyByAttachment = {};

  MediaAttachmentLifecycleLock get lifecycleLock => _lifecycleLock;

  Future<OutgoingDirectPrivateMutationResult> commitCompletion({
    required MediaAttachment attachment,
    required String expectedPendingLocalPath,
  }) {
    final fingerprint =
        OutgoingDirectPrivateCompletionFingerprint.fromAttachment(
          attachment,
          expectedPendingLocalPath: expectedPendingLocalPath,
        );
    return _lifecycleLock.synchronized(attachment.id, () async {
      final qualification = await _classifyCompletion(attachment, fingerprint);
      if (qualification ==
          OutgoingDirectPrivateCompletionQualification.notPrivateParent) {
        return OutgoingDirectPrivateMutationResult(
          outcome: OutgoingDirectPrivateMutationOutcome.refused,
          fingerprint: fingerprint,
          appliesToPrivateParent: false,
        );
      }
      if (!fingerprint.isStructurallyComplete) {
        return OutgoingDirectPrivateMutationResult(
          outcome: OutgoingDirectPrivateMutationOutcome.refused,
          fingerprint: fingerprint,
        );
      }
      switch (qualification) {
        case OutgoingDirectPrivateCompletionQualification.notPrivateParent:
          throw StateError('ordinary parent classification escaped guard');
        case OutgoingDirectPrivateCompletionQualification.availablePending:
          if (await _commitAvailable(attachment, fingerprint)) {
            _discardExact(fingerprint);
            return OutgoingDirectPrivateMutationResult(
              outcome: OutgoingDirectPrivateMutationOutcome.committed,
              fingerprint: fingerprint,
            );
          }
          // The DB commit repeats every positive predicate in its own write
          // transaction. Losing that qualification is a permanent refusal;
          // no bounded retry is allowed.
          return OutgoingDirectPrivateMutationResult(
            outcome: OutgoingDirectPrivateMutationOutcome.refused,
            fingerprint: fingerprint,
          );
        case OutgoingDirectPrivateCompletionQualification.activeLeasePending:
          final existing = _deferredByAttachment[attachment.id];
          if (existing != null && existing.fingerprint != fingerprint) {
            return OutgoingDirectPrivateMutationResult(
              outcome: OutgoingDirectPrivateMutationOutcome.refused,
              fingerprint: fingerprint,
            );
          }
          final terminal = _terminalCustodyByAttachment[attachment.id];
          if (terminal != null && terminal != fingerprint) {
            return OutgoingDirectPrivateMutationResult(
              outcome: OutgoingDirectPrivateMutationOutcome.refused,
              fingerprint: fingerprint,
            );
          }
          _deferredByAttachment[attachment.id] = _DeferredCompletion(
            fingerprint,
            attachment,
          );
          return OutgoingDirectPrivateMutationResult(
            outcome: OutgoingDirectPrivateMutationOutcome.deferredActiveLease,
            fingerprint: fingerprint,
          );
        case OutgoingDirectPrivateCompletionQualification
            .identicalCommittedCandidate:
          _discardExact(fingerprint);
          return OutgoingDirectPrivateMutationResult(
            outcome: OutgoingDirectPrivateMutationOutcome.committed,
            fingerprint: fingerprint,
          );
        case OutgoingDirectPrivateCompletionQualification
            .transportOnlyTerminalCustody:
          final deferred = _deferredByAttachment[attachment.id];
          final existing = _terminalCustodyByAttachment[attachment.id];
          if ((deferred != null && deferred.fingerprint != fingerprint) ||
              (existing != null && existing != fingerprint)) {
            return OutgoingDirectPrivateMutationResult(
              outcome: OutgoingDirectPrivateMutationOutcome.refused,
              fingerprint: fingerprint,
            );
          }
          // This is an authorization fingerprint, not a deferred local-write
          // token: rollback never consumes it and it can mutate no local row
          // or key. Durable envelope handoff/terminal cleanup owns removal.
          _terminalCustodyByAttachment[attachment.id] = fingerprint;
          return OutgoingDirectPrivateMutationResult(
            outcome: OutgoingDirectPrivateMutationOutcome
                .transportOnlyTerminalCustody,
            fingerprint: fingerprint,
          );
        case OutgoingDirectPrivateCompletionQualification.refused:
          return OutgoingDirectPrivateMutationResult(
            outcome: OutgoingDirectPrivateMutationOutcome.refused,
            fingerprint: fingerprint,
          );
      }
    });
  }

  /// Returns null when no exact deferred completion exists, allowing the lane
  /// adapter to use its ordinary exact rollback CAS. Otherwise this owns both
  /// token settlement and the combined rollback/finalize commit.
  Future<bool?> rollbackOpeningWithDeferredCompletion({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
    required String mode,
    required Future<bool> Function(
      OutgoingDirectPrivateCompletionFingerprint fingerprint,
    )
    authorizeCanonicalFile,
  }) {
    return _lifecycleLock.synchronized(attachmentId, () async {
      final deferred = _deferredByAttachment[attachmentId];
      if (deferred == null ||
          deferred.fingerprint.messageId != messageId ||
          deferred.fingerprint.expectedPendingLocalPath !=
              expectedPendingLocalPath) {
        return null;
      }
      if (!await authorizeCanonicalFile(deferred.fingerprint)) {
        _deferredByAttachment.remove(attachmentId);
        return false;
      }
      try {
        return await _commitRollback(
          deferred.attachment,
          deferred.fingerprint,
          mode: mode,
        );
      } finally {
        _deferredByAttachment.remove(attachmentId);
      }
    });
  }

  Future<OutgoingDirectPrivateCompletionFingerprint?>
  loadOwnedCompletionFingerprint({
    required String messageId,
    required String attachmentId,
    required String expectedPendingLocalPath,
  }) {
    return _lifecycleLock.synchronized(attachmentId, () async {
      final deferred = _deferredByAttachment[attachmentId]?.fingerprint;
      final fingerprint =
          deferred ?? _terminalCustodyByAttachment[attachmentId];
      if (fingerprint == null ||
          fingerprint.messageId != messageId ||
          fingerprint.expectedPendingLocalPath != expectedPendingLocalPath) {
        return null;
      }
      return fingerprint;
    });
  }

  /// Converts an exact deferred viewer-era completion into transport-only
  /// custody after the parent becomes terminal.
  ///
  /// The resulting fingerprint can authorize the already-completed upload's
  /// envelope handoff, but it can no longer participate in an opening
  /// rollback/finalize write. This closes the serialization where first-frame
  /// consumption wins after upload completion and before envelope handoff.
  Future<bool> terminalizeDeferredCompletionForCustody({
    required String messageId,
    required String attachmentId,
  }) {
    return _lifecycleLock.synchronized(attachmentId, () async {
      final deferred = _deferredByAttachment[attachmentId];
      if (deferred != null) {
        if (deferred.fingerprint.messageId != messageId) return false;
        final existing = _terminalCustodyByAttachment[attachmentId];
        if (existing != null && existing != deferred.fingerprint) {
          return false;
        }
        _terminalCustodyByAttachment[attachmentId] = deferred.fingerprint;
        _deferredByAttachment.remove(attachmentId);
        return true;
      }
      return _terminalCustodyByAttachment[attachmentId]?.messageId == messageId;
    });
  }

  Future<void> discardCompletion({
    required String messageId,
    required String attachmentId,
  }) {
    return _lifecycleLock.synchronized(attachmentId, () async {
      final deferred = _deferredByAttachment[attachmentId];
      if (deferred?.fingerprint.messageId == messageId) {
        _deferredByAttachment.remove(attachmentId);
      }
      final custody = _terminalCustodyByAttachment[attachmentId];
      if (custody?.messageId == messageId) {
        _terminalCustodyByAttachment.remove(attachmentId);
      }
    });
  }

  void _discardExact(OutgoingDirectPrivateCompletionFingerprint fingerprint) {
    final deferred = _deferredByAttachment[fingerprint.attachmentId];
    if (deferred?.fingerprint == fingerprint) {
      _deferredByAttachment.remove(fingerprint.attachmentId);
    }
    if (_terminalCustodyByAttachment[fingerprint.attachmentId] == fingerprint) {
      _terminalCustodyByAttachment.remove(fingerprint.attachmentId);
    }
  }
}

class _DeferredCompletion {
  const _DeferredCompletion(this.fingerprint, this.attachment);

  final OutgoingDirectPrivateCompletionFingerprint fingerprint;
  final MediaAttachment attachment;
}
