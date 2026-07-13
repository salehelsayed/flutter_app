import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';

/// 172 TC-11 — the sibling replay-disposition mappers (reaction + deletion),
/// extracted from the main.dart replay closures so the recoverable-vs-terminal
/// split is test-locked alongside the chat mapper
/// (`mapChatReplayOutcomeToDisposition`).
///
/// INV-1 parity: transient causes (`decryptionFailed`, `unknownSender`) stay
/// retryable — bounded by the attempt cap -> quarantined, never a silent
/// post-ACK drop. The `rejected` classes are genuinely content-safe/security
/// drops and the asymmetry is deliberate (locked by the sibling test):
/// - reaction `senderMismatch` (spoofed author) / `notReaction` (wrong type);
/// - deletion `unauthorized` (not the author) / `notMessageDeletion`.
///
/// OQ-7: `targetUnavailable` / `ignoredMissingMessage` are TERMINAL commits —
/// the target is gone (or already tombstoned); retrying would only churn
/// toward quarantine.
RecoveredInboxReplayOutcome mapReactionReplayResultToDisposition(
  HandleReactionResult result,
) {
  switch (result) {
    case HandleReactionResult.success:
    case HandleReactionResult.targetUnavailable:
      return (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: result.name,
        reasonDetail: null,
      );
    case HandleReactionResult.decryptionFailed:
    case HandleReactionResult.unknownSender:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: result.name,
        reasonDetail: null,
      );
    case HandleReactionResult.senderMismatch:
    case HandleReactionResult.metadataMismatch:
    case HandleReactionResult.blockedSender:
    case HandleReactionResult.notReaction:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: result.name,
        reasonDetail: null,
      );
  }
}

RecoveredInboxReplayOutcome mapMessageDeletionReplayResultToDisposition(
  HandleMessageDeletionResult result,
) {
  switch (result) {
    case HandleMessageDeletionResult.success:
    case HandleMessageDeletionResult.ignoredMissingMessage:
      return (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: result.name,
        reasonDetail: null,
      );
    case HandleMessageDeletionResult.decryptionFailed:
    case HandleMessageDeletionResult.unknownSender:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: result.name,
        reasonDetail: null,
      );
    case HandleMessageDeletionResult.unauthorized:
    case HandleMessageDeletionResult.notMessageDeletion:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: result.name,
        reasonDetail: null,
      );
  }
}
