import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Result of the narrow per-message custody path used by failed-message retry.
///
/// [found] is deliberately separate from [completed]: a failed remote store is
/// still handled by this path and must not fall through to re-encryption.
final class DirectInboxCustodyDrainAttempt {
  const DirectInboxCustodyDrainAttempt({
    required this.found,
    required this.completed,
  });

  static const notFound = DirectInboxCustodyDrainAttempt(
    found: false,
    completed: false,
  );

  final bool found;
  final bool completed;
}

/// Replays one fair, repository-bounded batch of immutable direct-text inbox
/// custody obligations.
///
/// Each row is isolated from the next. Remote `stored` and `duplicate` are the
/// only accepting outcomes; all other outcomes retain the exact incarnation
/// and record bounded retry metadata.
Future<int> drainDirectInboxCustodyOutbox({
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
}) async {
  final entries = await custodyRepository.loadDirectInboxCustody();
  var completed = 0;
  for (final entry in entries) {
    final result = await drainOwnedDirectInboxCustodyOutboxEntry(
      entry: entry,
      custodyRepository: custodyRepository,
      storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
      storeInMediaExpiryBoundedInboxDetailed:
          storeInMediaExpiryBoundedInboxDetailed,
    );
    if (result.completed) completed++;
  }
  return completed;
}

/// Attempts the exact pending custody row for one direct message.
///
/// Callers must use [DirectInboxCustodyDrainAttempt.found] as the routing
/// discriminator. A found-but-retained row owns retry even when the store or
/// local completion fails.
Future<DirectInboxCustodyDrainAttempt> drainDirectInboxCustodyOutboxForMessage({
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
  required String recipientPeerId,
  required String messageId,
}) async {
  final entry = await custodyRepository.loadDirectInboxCustodyOwnerForMessageId(
    messageId: messageId,
  );
  if (entry != null && entry.recipientPeerId != recipientPeerId) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DIRECT_INBOX_CUSTODY_PARENT_RECIPIENT_DRIFT',
      details: <String, Object?>{
        'id': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
      },
    );
  }
  if (entry == null) return DirectInboxCustodyDrainAttempt.notFound;
  return drainOwnedDirectInboxCustodyOutboxEntry(
    entry: entry,
    custodyRepository: custodyRepository,
    storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
    storeInMediaExpiryBoundedInboxDetailed:
        storeInMediaExpiryBoundedInboxDetailed,
  );
}

/// Replays one already-resolved immutable owner row. The stored entry supplies
/// both the exact bytes and recipient; no mutable parent projection is used.
Future<DirectInboxCustodyDrainAttempt> drainOwnedDirectInboxCustodyOutboxEntry({
  required DirectInboxCustodyOutboxEntry entry,
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  StoreInMediaExpiryBoundedInboxDetailedFn?
  storeInMediaExpiryBoundedInboxDetailed,
}) async {
  InboxStoreOutcome outcome;
  try {
    final blobExpiry = entry.mediaBlobExpiresAtMs;
    final blobHash = entry.mediaBlobManifestHash;
    final hasStrictBlobBinding = blobExpiry != null && blobHash != null;
    final malformedBlobBinding = (blobExpiry == null) != (blobHash == null);
    if (malformedBlobBinding ||
        (hasStrictBlobBinding &&
            (blobExpiry <= 0 ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(blobHash)))) {
      return const DirectInboxCustodyDrainAttempt(
        found: true,
        completed: false,
      );
    }
    if (hasStrictBlobBinding) {
      final store = storeInMediaExpiryBoundedInboxDetailed;
      if (store == null) {
        return const DirectInboxCustodyDrainAttempt(
          found: true,
          completed: false,
        );
      }
      outcome = await store(
        entry.recipientPeerId,
        entry.wireEnvelope,
        custodyExpiresAtOrBeforeMs: blobExpiry,
      );
    } else {
      outcome = await storeInAckCustodyInboxDetailed(
        entry.recipientPeerId,
        entry.wireEnvelope,
        custodyKind: AckCustodyKind.directTextV108,
      );
    }
  } catch (error) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectInboxCustodyErrorCode.storeThrew,
    );
    _emitAttempt(entry, attemptOutcome: 'store_threw', error: error);
    return const DirectInboxCustodyDrainAttempt(found: true, completed: false);
  }

  if (!outcome.ackOrExpiryAccepted) {
    final errorCode = outcome.status == InboxStoreStatus.rejectedFull
        ? DirectInboxCustodyErrorCode.storeRejectedFull
        : DirectInboxCustodyErrorCode.storeFailed;
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: errorCode,
    );
    _emitAttempt(entry, attemptOutcome: errorCode);
    return const DirectInboxCustodyDrainAttempt(found: true, completed: false);
  }

  if (entry.mediaBlobExpiresAtMs != null &&
      (outcome.expiresAtMs == null ||
          outcome.expiresAtMs! <= 0 ||
          outcome.expiresAtMs! > entry.mediaBlobExpiresAtMs!)) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectInboxCustodyErrorCode.storeFailed,
    );
    return const DirectInboxCustodyDrainAttempt(found: true, completed: false);
  }

  try {
    final completion = await custodyRepository
        .completeAcceptedDirectInboxCustodyIfExact(
          expected: entry,
          relayExpiresAt: outcome.expiresAtMs,
        );
    var completed = completion.completed;
    if (!completed) {
      // Another drain may have completed and removed this exact row between
      // our accepted STORE and local CAS. Absence is convergence, not a failed
      // retry that may later re-mint the logical message. A surviving same-key
      // row (including a replacement incarnation) remains authoritative.
      completed =
          await custodyRepository.loadDirectInboxCustodyOwnerForMessageId(
            messageId: entry.messageId,
          ) ==
          null;
    }
    _emitAttempt(
      entry,
      attemptOutcome: completion.completed
          ? outcome.status.name
          : completed
          ? 'converged_elsewhere'
          : 'concurrent_replacement',
    );
    return DirectInboxCustodyDrainAttempt(found: true, completed: completed);
  } catch (error) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectInboxCustodyErrorCode.localCompletionFailed,
    );
    _emitAttempt(
      entry,
      attemptOutcome: 'local_completion_failed',
      error: error,
    );
    return const DirectInboxCustodyDrainAttempt(found: true, completed: false);
  }
}

Future<void> _recordFailureBestEffort({
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required DirectInboxCustodyOutboxEntry entry,
  required String errorCode,
}) async {
  try {
    await custodyRepository.recordDirectInboxCustodyFailureIfExact(
      expected: entry,
      errorCode: errorCode,
    );
  } catch (error) {
    _emitAttempt(entry, attemptOutcome: 'failure_record_error', error: error);
  }
}

void _emitAttempt(
  DirectInboxCustodyOutboxEntry entry, {
  required String attemptOutcome,
  Object? error,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_INBOX_CUSTODY_DRAIN_ATTEMPT',
    details: <String, Object?>{
      'id': _shortId(entry.messageId),
      'status': attemptOutcome,
      if (error != null) 'errorType': error.runtimeType.toString(),
    },
  );
}

String _shortId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
