import 'package:flutter_app/core/database/direct_inbox_event_envelope.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Replays one repository-bounded fair batch of immutable direct-reaction
/// recipient-inbox custody obligations.
///
/// Every entry is isolated from its siblings. Only relay `stored` and
/// `duplicate` outcomes retire the exact `(recipient, event, envelope)` row;
/// every other outcome retains it with bounded retry metadata.
Future<int> drainDirectReactionInboxCustodyOutbox({
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
  OutgoingDirectTextMutationInboxCustodyRepository? mutationCustodyRepository,
}) async {
  final entries = await custodyRepository.loadDirectReactionInboxCustody();
  var completed = 0;
  for (final entry in entries) {
    final classified = classifyDirectInboxEventEnvelope(entry.wireEnvelope);
    final didComplete = switch (classified?.kind) {
      DirectInboxEventEnvelopeKind.reaction =>
        await _attemptDirectReactionInboxCustodyEntry(
          entry: entry,
          custodyRepository: custodyRepository,
          storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
        ),
      DirectInboxEventEnvelopeKind.edit ||
      DirectInboxEventEnvelopeKind.deletion =>
        mutationCustodyRepository == null
            ? false
            : await drainOwnedDirectMutationInboxCustodyOutboxEntry(
                entry: entry,
                custodyRepository: mutationCustodyRepository,
                storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
              ),
      null => false,
    };
    if (didComplete) {
      completed++;
    } else if (classified == null ||
        (classified.isMutation && mutationCustodyRepository == null)) {
      await _recordFailureBestEffort(
        custodyRepository: custodyRepository,
        entry: entry,
        errorCode: DirectReactionInboxCustodyErrorCode.storeFailed,
      );
    }
  }
  return completed;
}

/// Attempts one already-owned edit/deletion event. Manual retry and newly
/// authored deletion hedges reuse this exact CAS path instead of rebuilding or
/// entering the legacy inbox store.
Future<bool> drainOwnedDirectMutationInboxCustodyOutboxEntry({
  required DirectReactionInboxCustodyOutboxEntry entry,
  required DirectMutationInboxCustodyLifecycleRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
}) async {
  final classified = classifyDirectInboxEventEnvelope(entry.wireEnvelope);
  if (classified == null ||
      !classified.isMutation ||
      classified.eventId != entry.eventId) {
    await _recordMutationFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.storeFailed,
    );
    return false;
  }

  InboxStoreOutcome outcome;
  try {
    outcome = await storeInAckCustodyInboxDetailed(
      entry.recipientPeerId,
      entry.wireEnvelope,
      custodyKind: AckCustodyKind.directMutationV109,
    );
  } catch (error) {
    await _recordMutationFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.storeThrew,
    );
    _emitAttempt(
      entry,
      attemptOutcome: 'store_threw',
      error: error,
      mutation: true,
    );
    return false;
  }

  if (!outcome.ackOrExpiryAccepted) {
    final errorCode = outcome.status == InboxStoreStatus.rejectedFull
        ? DirectReactionInboxCustodyErrorCode.storeRejectedFull
        : DirectReactionInboxCustodyErrorCode.storeFailed;
    await _recordMutationFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: errorCode,
    );
    _emitAttempt(entry, attemptOutcome: errorCode, mutation: true);
    return false;
  }

  try {
    final completion = await custodyRepository
        .completeAcceptedDirectTextMutationInboxCustodyIfExact(
          expected: entry,
          relayExpiresAt: outcome.expiresAtMs,
        );
    if (completion.converged) {
      _emitAttempt(
        entry,
        attemptOutcome:
            completion == DirectMutationInboxCustodyCompletionOutcome.completed
            ? outcome.status.name
            : 'converged_elsewhere',
        mutation: true,
      );
      return true;
    }
    await _recordMutationFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.localCompletionFailed,
    );
    _emitAttempt(entry, attemptOutcome: completion.name, mutation: true);
    return false;
  } catch (error) {
    await _recordMutationFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.localCompletionFailed,
    );
    _emitAttempt(
      entry,
      attemptOutcome: 'local_completion_failed',
      error: error,
      mutation: true,
    );
    return false;
  }
}

/// 361: public per-row owner for one exact reaction obligation, used by the
/// restricted linked drain that selects exact v113 fanout rows only.
Future<bool> drainOwnedDirectReactionInboxCustodyOutboxEntry({
  required DirectReactionInboxCustodyOutboxEntry entry,
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
}) => _attemptDirectReactionInboxCustodyEntry(
  entry: entry,
  custodyRepository: custodyRepository,
  storeInAckCustodyInboxDetailed: storeInAckCustodyInboxDetailed,
);

Future<bool> _attemptDirectReactionInboxCustodyEntry({
  required DirectReactionInboxCustodyOutboxEntry entry,
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required StoreInAckCustodyInboxDetailedFn storeInAckCustodyInboxDetailed,
}) async {
  InboxStoreOutcome outcome;
  try {
    outcome = await storeInAckCustodyInboxDetailed(
      entry.recipientPeerId,
      entry.wireEnvelope,
      custodyKind: AckCustodyKind.directReactionV109,
    );
  } catch (error) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.storeThrew,
    );
    _emitAttempt(entry, attemptOutcome: 'store_threw', error: error);
    return false;
  }

  if (!outcome.ackOrExpiryAccepted) {
    final errorCode = outcome.status == InboxStoreStatus.rejectedFull
        ? DirectReactionInboxCustodyErrorCode.storeRejectedFull
        : DirectReactionInboxCustodyErrorCode.storeFailed;
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: errorCode,
    );
    _emitAttempt(entry, attemptOutcome: errorCode);
    return false;
  }

  try {
    final completion = await custodyRepository
        .completeAcceptedDirectReactionInboxCustodyIfExact(expected: entry);
    if (completion.converged) {
      _emitAttempt(
        entry,
        attemptOutcome:
            completion == DirectReactionInboxCustodyCompletionOutcome.completed
            ? outcome.status.name
            : 'converged_elsewhere',
      );
      return true;
    }

    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.localCompletionFailed,
    );
    _emitAttempt(entry, attemptOutcome: 'local_completion_stale');
    return false;
  } catch (error) {
    await _recordFailureBestEffort(
      custodyRepository: custodyRepository,
      entry: entry,
      errorCode: DirectReactionInboxCustodyErrorCode.localCompletionFailed,
    );
    _emitAttempt(
      entry,
      attemptOutcome: 'local_completion_failed',
      error: error,
    );
    return false;
  }
}

Future<void> _recordFailureBestEffort({
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required DirectReactionInboxCustodyOutboxEntry entry,
  required String errorCode,
}) async {
  try {
    await custodyRepository.recordDirectReactionInboxCustodyFailureIfExact(
      expected: entry,
      errorCode: errorCode,
    );
  } catch (error) {
    _emitAttempt(entry, attemptOutcome: 'failure_record_error', error: error);
  }
}

Future<void> _recordMutationFailureBestEffort({
  required DirectMutationInboxCustodyLifecycleRepository custodyRepository,
  required DirectReactionInboxCustodyOutboxEntry entry,
  required String errorCode,
}) async {
  try {
    await custodyRepository.recordDirectTextMutationInboxCustodyFailureIfExact(
      expected: entry,
      errorCode: errorCode,
    );
  } catch (error) {
    _emitAttempt(
      entry,
      attemptOutcome: 'failure_record_error',
      error: error,
      mutation: true,
    );
  }
}

void _emitAttempt(
  DirectReactionInboxCustodyOutboxEntry entry, {
  required String attemptOutcome,
  Object? error,
  bool mutation = false,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: mutation
        ? 'DIRECT_MUTATION_INBOX_CUSTODY_DRAIN_ATTEMPT'
        : 'DIRECT_REACTION_INBOX_CUSTODY_DRAIN_ATTEMPT',
    details: <String, Object?>{
      'id': _shortId(entry.eventId),
      'status': attemptOutcome,
      if (error != null) 'errorType': error.runtimeType.toString(),
    },
  );
}

String _shortId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
