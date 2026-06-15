import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';

/// Maps a replayed staged chat message outcome to its staging disposition.
///
/// INV-1: once the receiving side has caused custody transfer (relay copy
/// ACK-deleted, or direct `message:confirm ok:true` sent), no disposition may
/// destroy the staged envelope. Failures that never evaluated the content
/// (transient infrastructure) stay retryable; cryptographic failures are
/// quarantined — kept with reason metadata, excluded from replay. `rejected`
/// is reserved for pre-custody or content-safe outcomes (see the matrix test
/// for the per-state justification).
///
/// The unknown-sender intro-recovery pre-step stays in the main.dart closure;
/// this mapper handles the final outcome only.
RecoveredInboxReplayOutcome mapChatReplayOutcomeToDisposition(
  ChatMessageProcessOutcome outcome,
) {
  switch (outcome.state) {
    case ChatMessageProcessState.stored:
      return (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: 'stored',
        reasonDetail: null,
      );
    case ChatMessageProcessState.missingMlKemSecret:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'missing_mlkem_secret',
        reasonDetail: outcome.reasonDetail,
      );
    case ChatMessageProcessState.accountMigrationBlocked:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'account_migration_blocked',
        reasonDetail: outcome.reasonDetail,
      );
    case ChatMessageProcessState.error:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'listener_error',
        reasonDetail: outcome.reasonDetail,
      );
    case ChatMessageProcessState.decryptionDeferred:
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'decryption_deferred',
        reasonDetail: outcome.reasonDetail,
      );
    case ChatMessageProcessState.decryptionFailed:
      return (
        disposition: RecoveredInboxChatDisposition.quarantined,
        reasonCode: 'decryption_failed',
        reasonDetail: outcome.reasonDetail,
      );
    case ChatMessageProcessState.blockedSender:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'blocked_sender',
        reasonDetail: null,
      );
    case ChatMessageProcessState.notChatMessage:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'not_chat_message',
        reasonDetail: null,
      );
    case ChatMessageProcessState.unknownSender:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'unknown_sender',
        reasonDetail: null,
      );
    case ChatMessageProcessState.duplicate:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'duplicate',
        reasonDetail: null,
      );
    case ChatMessageProcessState.ignoredEdit:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'ignored_edit',
        reasonDetail: null,
      );
    case ChatMessageProcessState.editMissingOriginal:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'edit_missing_original',
        reasonDetail: null,
      );
  }
}
