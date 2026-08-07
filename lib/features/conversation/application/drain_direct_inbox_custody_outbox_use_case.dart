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
  required StoreInInboxDetailedFn storeInInboxDetailed,
}) async {
  final entries = await custodyRepository.loadDirectInboxCustody();
  var completed = 0;
  for (final entry in entries) {
    final result = await _attemptDirectInboxCustodyEntry(
      entry: entry,
      custodyRepository: custodyRepository,
      storeInInboxDetailed: storeInInboxDetailed,
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
  required StoreInInboxDetailedFn storeInInboxDetailed,
  required String recipientPeerId,
  required String messageId,
}) async {
  final entry = await custodyRepository.loadDirectInboxCustodyForMessage(
    recipientPeerId: recipientPeerId,
    messageId: messageId,
  );
  if (entry == null) return DirectInboxCustodyDrainAttempt.notFound;
  return _attemptDirectInboxCustodyEntry(
    entry: entry,
    custodyRepository: custodyRepository,
    storeInInboxDetailed: storeInInboxDetailed,
  );
}

Future<DirectInboxCustodyDrainAttempt> _attemptDirectInboxCustodyEntry({
  required DirectInboxCustodyOutboxEntry entry,
  required OutgoingDirectTextInboxCustodyRepository custodyRepository,
  required StoreInInboxDetailedFn storeInInboxDetailed,
}) async {
  InboxStoreOutcome outcome;
  try {
    outcome = await storeInInboxDetailed(
      entry.recipientPeerId,
      entry.wireEnvelope,
    );
  } catch (error) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectInboxCustodyErrorCode.storeThrew,
    );
    _emitAttempt(entry, attemptOutcome: 'store_threw', error: error);
    return const DirectInboxCustodyDrainAttempt(found: true, completed: false);
  }

  if (!outcome.accepted) {
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
          await custodyRepository.loadDirectInboxCustodyForMessage(
            recipientPeerId: entry.recipientPeerId,
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
