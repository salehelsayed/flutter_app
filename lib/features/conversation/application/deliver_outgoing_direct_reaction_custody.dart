import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_reaction_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';

const int directReactionImmediateInboxTimeoutMs = 3000;

class DirectReactionImmediateDeliveryResult {
  const DirectReactionImmediateDeliveryResult({
    required this.liveAccepted,
    required this.inboxAccepted,
  });

  final bool liveAccepted;
  final bool inboxAccepted;

  bool get delivered => liveAccepted || inboxAccepted;
}

/// Races one live delivery with exactly one typed durable-inbox handoff.
///
/// The immutable local row is retired only after the relay reports `stored` or
/// `duplicate`. A live ACK is strictly a latency result and never owns custody.
Future<DirectReactionImmediateDeliveryResult>
deliverOutgoingDirectReactionCustody({
  required P2PService p2pService,
  required StoreInInboxDetailedFn storeInInboxDetailed,
  required OutgoingDirectReactionInboxCustodyRepository custodyRepository,
  required DirectReactionInboxCustodyOutboxEntry custody,
  required String flowPrefix,
}) async {
  Future<bool> attemptInbox() async {
    emitFlowEvent(
      layer: 'FL',
      event: '${flowPrefix}_CONCURRENT_INBOX_BEGIN',
      details: const {},
    );
    late InboxStoreOutcome outcome;
    var storeThrew = false;
    try {
      outcome = await storeInInboxDetailed(
        custody.recipientPeerId,
        custody.wireEnvelope,
        timeoutMs: directReactionImmediateInboxTimeoutMs,
      );
    } catch (error) {
      storeThrew = true;
      outcome = InboxStoreOutcome(
        status: InboxStoreStatus.failed,
        errorCode: 'STORE_ERROR',
        errorMessage: error.runtimeType.toString(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: '${flowPrefix}_INBOX_STORE_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }

    if (outcome.accepted) {
      try {
        final completion = await custodyRepository
            .completeAcceptedDirectReactionInboxCustodyIfExact(
              expected: custody,
            );
        if (!completion.converged) {
          try {
            await custodyRepository
                .recordDirectReactionInboxCustodyFailureIfExact(
                  expected: custody,
                  errorCode: DirectReactionInboxCustodyErrorCode
                      .localCompletionFailed,
                );
          } catch (_) {
            // The conflicting exact tuple remains owned by its current bytes.
          }
        }
      } catch (error) {
        try {
          await custodyRepository
              .recordDirectReactionInboxCustodyFailureIfExact(
                expected: custody,
                errorCode:
                    DirectReactionInboxCustodyErrorCode.localCompletionFailed,
              );
        } catch (_) {
          // The immutable row was already committed; lifecycle retry remains
          // authoritative even if best-effort failure metadata cannot update.
        }
        emitFlowEvent(
          layer: 'FL',
          event: '${flowPrefix}_CUSTODY_COMPLETION_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
      return true;
    }

    final errorCode = storeThrew
        ? DirectReactionInboxCustodyErrorCode.storeThrew
        : outcome.status == InboxStoreStatus.rejectedFull
        ? DirectReactionInboxCustodyErrorCode.storeRejectedFull
        : DirectReactionInboxCustodyErrorCode.storeFailed;
    try {
      await custodyRepository.recordDirectReactionInboxCustodyFailureIfExact(
        expected: custody,
        errorCode: errorCode,
      );
    } catch (_) {
      // The exact encrypted obligation is already durable. A later drain may
      // retry it even when this diagnostic metadata update fails.
    }
    return false;
  }

  Future<bool> attemptLive() async {
    try {
      return await p2pService.sendMessage(
        custody.recipientPeerId,
        custody.wireEnvelope,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: '${flowPrefix}_LIVE_SEND_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return false;
    }
  }

  // Calling both async functions starts both legs before either is joined.
  final inboxAttempt = attemptInbox();
  final liveAttempt = attemptLive();
  final results = await Future.wait<bool>(<Future<bool>>[
    liveAttempt,
    inboxAttempt,
  ]);
  return DirectReactionImmediateDeliveryResult(
    liveAccepted: results[0],
    inboxAccepted: results[1],
  );
}
