import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';

const String _fdcInboxReclassifyDisableRaw = String.fromEnvironment(
  'FDC_INBOX_RECLASSIFY_DISABLE',
);

/// 172 kill-switch (ships ON, i.e. this const is FALSE in production):
/// `--dart-define=FDC_INBOX_RECLASSIFY_DISABLE=1` (1/true/yes/on) reverts the
/// recoverable-class reclassification (unknownSender / editMissingOriginal /
/// unverified duplicate -> retryable) to the legacy terminal rejections.
/// Field escape hatch only, mirroring the FDC-06 ship-on-with-disable
/// pattern (handle_app_paused.dart); the default is locked by the
/// disposition test.
const bool kFdcInboxReclassifyDisabled =
    _fdcInboxReclassifyDisableRaw == '1' ||
    _fdcInboxReclassifyDisableRaw == 'true' ||
    _fdcInboxReclassifyDisableRaw == 'yes' ||
    _fdcInboxReclassifyDisableRaw == 'on';

/// Maps a replayed staged chat message outcome to its staging disposition.
///
/// INV-1: once the receiving side has caused custody transfer (relay copy
/// ACK-deleted, or direct `message:confirm ok:true` sent), no disposition may
/// destroy the staged envelope. Failures that never evaluated the content
/// (transient infrastructure) stay retryable; cryptographic failures are
/// quarantined — kept with reason metadata, excluded from replay. `rejected`
/// is reserved for content-safe outcomes only (see the matrix test for the
/// per-state justification).
///
/// 172: recoverable/transient causes must NEVER be terminal after custody
/// transfer (the 2026-06-28 incident: a contact-row race made a real sender
/// look `unknownSender`, the entry was `markRejected`, and the message —
/// already ACK-deleted off the relay — vanished with zero signal):
/// - `unknownSender` -> retryable (default-safe even when the main.dart
///   intro-recovery pre-step never ran; that pre-step still returns terminal
///   `rejected` for a resolver-confirmed stranger).
/// - `editMissingOriginal` -> retryable (the original may arrive in a later
///   relay page).
/// - `duplicate` -> rejected ONLY when [ChatMessageProcessOutcome
///   .duplicatePriorPersisted] confirms the prior copy is durably persisted;
///   an unverified duplicate claim stays retryable.
/// Every retryable is bounded by `maxInboxReplayAttempts` -> quarantined
/// (kept + surfaced), never silently dropped.
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
    case ChatMessageProcessState.durablySuperseded:
      // Plan 354: a durable same-author private terminal parent already owned
      // this target and the initial receipt was emitted. Replaying it can only
      // repeat that zero-effect decision, so it is terminal, never retryable.
      return (
        disposition: RecoveredInboxChatDisposition.committed,
        reasonCode: 'durably_superseded',
        reasonDetail: null,
      );
    case ChatMessageProcessState.blockedSender:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'blocked_sender',
        reasonDetail: null,
      );
    case ChatMessageProcessState.linkedModalityRefused:
      // 361: an authenticated linked transport carried an unsupported
      // modality — durably rejected with zero apply/receipt/publication.
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'linked_modality_refused',
        reasonDetail: null,
      );
    case ChatMessageProcessState.notChatMessage:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'not_chat_message',
        reasonDetail: null,
      );
    case ChatMessageProcessState.unknownSender:
      if (kFdcInboxReclassifyDisabled) {
        return (
          disposition: RecoveredInboxChatDisposition.rejected,
          reasonCode: 'unknown_sender',
          reasonDetail: null,
        );
      }
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'unknown_sender_recoverable',
        reasonDetail: null,
      );
    case ChatMessageProcessState.duplicate:
      if (outcome.duplicatePriorPersisted || kFdcInboxReclassifyDisabled) {
        return (
          disposition: RecoveredInboxChatDisposition.rejected,
          reasonCode: outcome.duplicatePriorPersisted
              ? 'duplicate_confirmed_visible'
              : 'duplicate',
          reasonDetail: null,
        );
      }
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'duplicate_unverified_retry',
        reasonDetail: null,
      );
    case ChatMessageProcessState.ignoredEdit:
      return (
        disposition: RecoveredInboxChatDisposition.rejected,
        reasonCode: 'ignored_edit',
        reasonDetail: null,
      );
    case ChatMessageProcessState.editMissingOriginal:
      if (kFdcInboxReclassifyDisabled) {
        return (
          disposition: RecoveredInboxChatDisposition.rejected,
          reasonCode: 'edit_missing_original',
          reasonDetail: null,
        );
      }
      return (
        disposition: RecoveredInboxChatDisposition.retryable,
        reasonCode: 'edit_missing_original',
        reasonDetail: null,
      );
  }
}
