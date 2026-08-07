import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

/// Replays one repository-bounded fair batch of immutable direct-reaction
/// recipient-inbox custody obligations.
///
/// Every entry is isolated from its siblings. Only relay `stored` and
/// `duplicate` outcomes retire the exact `(recipient, event, envelope)` row;
/// every other outcome retains it with bounded retry metadata.
Future<int> drainDirectReactionInboxCustodyOutbox({
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required StoreInInboxDetailedFn storeInInboxDetailed,
}) async {
  final entries = await custodyRepository.loadDirectReactionInboxCustody();
  var completed = 0;
  for (final entry in entries) {
    if (await _attemptDirectReactionInboxCustodyEntry(
      entry: entry,
      custodyRepository: custodyRepository,
      storeInInboxDetailed: storeInInboxDetailed,
    )) {
      completed++;
    }
  }
  return completed;
}

Future<bool> _attemptDirectReactionInboxCustodyEntry({
  required DirectReactionInboxCustodyOutboxEntry entry,
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
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
      errorCode: DirectReactionInboxCustodyErrorCode.storeThrew,
    );
    _emitAttempt(entry, attemptOutcome: 'store_threw', error: error);
    return false;
  }

  if (!outcome.accepted) {
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

void _emitAttempt(
  DirectReactionInboxCustodyOutboxEntry entry, {
  required String attemptOutcome,
  Object? error,
}) {
  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_REACTION_INBOX_CUSTODY_DRAIN_ATTEMPT',
    details: <String, Object?>{
      'id': _shortId(entry.eventId),
      'status': attemptOutcome,
      if (error != null) 'errorType': error.runtimeType.toString(),
    },
  );
}

String _shortId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
