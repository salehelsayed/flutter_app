import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapChatReplayOutcomeToDisposition', () {
    RecoveredInboxReplayOutcome map(
      ChatMessageProcessState state, {
      String? reasonDetail,
    }) {
      return mapChatReplayOutcomeToDisposition(
        ChatMessageProcessOutcome(state: state, reasonDetail: reasonDetail),
      );
    }

    test('stored commits the staged entry', () {
      final outcome = map(ChatMessageProcessState.stored);
      expect(outcome.disposition, RecoveredInboxChatDisposition.committed);
      expect(outcome.reasonCode, 'stored');
    });

    test('missingMlKemSecret stays retryable with detail', () {
      final outcome = map(
        ChatMessageProcessState.missingMlKemSecret,
        reasonDetail: 'secret unavailable',
      );
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'missing_mlkem_secret');
      expect(outcome.reasonDetail, 'secret unavailable');
    });

    test('accountMigrationBlocked stays retryable', () {
      final outcome = map(ChatMessageProcessState.accountMigrationBlocked);
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'account_migration_blocked');
    });

    test('error stays retryable with detail', () {
      final outcome = map(ChatMessageProcessState.error, reasonDetail: 'boom');
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'listener_error');
      expect(outcome.reasonDetail, 'boom');
    });

    test('decryptionDeferred stays retryable (transient infra failure)', () {
      final outcome = map(ChatMessageProcessState.decryptionDeferred);
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'decryption_deferred');
    });

    test('decryptionFailed quarantines instead of rejecting (INV-1: the staged '
        'entry is the only remaining copy after custody transfer)', () {
      final outcome = map(ChatMessageProcessState.decryptionFailed);
      expect(outcome.disposition, RecoveredInboxChatDisposition.quarantined);
      expect(outcome.reasonCode, 'decryption_failed');
    });

    // 172 INV-1: after custody transfer (relay copy ACK-deleted) the staged
    // row is the ONLY surviving copy, so a RECOVERABLE/TRANSIENT cause must
    // never be terminal `rejected` — it stays retryable (bounded by the
    // attempt cap -> quarantined, never silently dropped). Only content-safe
    // or policy drops stay terminal:
    // - blockedSender: the user explicitly blocked the sender; dropping is
    //   the product intent, not silent loss.
    // - notChatMessage: the envelope is not a chat message; there is no
    //   message content to lose.
    // - duplicate (prior persisted): the content is already committed.
    // - ignoredEdit: the receiver already holds an equal-or-newer edit.
    test('blockedSender rejects (content-safe policy drop, TC-04 lock)', () {
      final outcome = map(ChatMessageProcessState.blockedSender);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'blocked_sender');
    });

    test('notChatMessage rejects (content-safe, TC-04 lock)', () {
      final outcome = map(ChatMessageProcessState.notChatMessage);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'not_chat_message');
    });

    // 172 TC-01 — the 2026-06-28 incident class: a contact-row race (or a
    // resolver that never ran) makes a REAL sender look unknown; terminal
    // rejection after the ACK is permanent invisible loss. With no resolver
    // context the mapper must stay recoverable; the main.dart pre-step still
    // returns terminal `rejected` for a resolver-confirmed stranger.
    test('172 TC-01: unknownSender maps to retryable (recoverable), '
        'not rejected', () {
      final outcome = map(ChatMessageProcessState.unknownSender);
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'unknown_sender_recoverable');
    });

    // 172 TC-03 — `duplicate` is terminal ONLY when the prior copy is
    // verifiably persisted (the listener asserts that after the use case's
    // repo-checked duplicate returns). An UNVERIFIED duplicate claim (any
    // synthetic producer / future drift) must stay recoverable.
    test('172 TC-03: duplicate stays rejected only when the prior message '
        'is actually persisted', () {
      final confirmed = mapChatReplayOutcomeToDisposition(
        const ChatMessageProcessOutcome(
          state: ChatMessageProcessState.duplicate,
          duplicatePriorPersisted: true,
        ),
      );
      expect(confirmed.disposition, RecoveredInboxChatDisposition.rejected);
      expect(confirmed.reasonCode, 'duplicate_confirmed_visible');

      final unverified = map(ChatMessageProcessState.duplicate);
      expect(unverified.disposition, RecoveredInboxChatDisposition.retryable);
      expect(unverified.reasonCode, 'duplicate_unverified_retry');
    });

    // 172 TC-02 — the original may arrive in a later relay page; terminal
    // rejection races the pagination order.
    test('172 TC-02: editMissingOriginal maps to retryable '
        '(original may arrive later)', () {
      final outcome = map(ChatMessageProcessState.editMissingOriginal);
      expect(outcome.disposition, RecoveredInboxChatDisposition.retryable);
      expect(outcome.reasonCode, 'edit_missing_original');
    });

    test('ignoredEdit rejects staged replay with ignored_edit reason '
        '(content-safe, TC-04 lock)', () {
      final outcome = map(ChatMessageProcessState.ignoredEdit);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'ignored_edit');
    });

    // 172 TC-04 — preservation lock against over-reclassification: the
    // content-safe set must stay terminal (no retry storm, INV-3).
    test('172 TC-04: content-safe drops stay terminal rejected', () {
      for (final state in [
        ChatMessageProcessState.blockedSender,
        ChatMessageProcessState.notChatMessage,
        ChatMessageProcessState.ignoredEdit,
      ]) {
        final outcome = map(state);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.rejected,
          reason: '$state must stay a terminal content-safe drop',
        );
      }
    });

    // 172: the reclassification SHIPS ON — the kill-switch dart-define must
    // stay unset in production builds (mirrors the kFdcPauseFlushEnabled
    // ship-ON lock).
    test('172 kill-switch lock: reclassification ships enabled', () {
      expect(kFdcInboxReclassifyDisabled, isFalse);
    });

    test('matrix covers every ChatMessageProcessState', () {
      for (final state in ChatMessageProcessState.values) {
        // Throws (non-exhaustive switch) or returns — every state must map.
        final outcome = mapChatReplayOutcomeToDisposition(
          ChatMessageProcessOutcome(state: state),
        );
        expect(outcome.reasonCode, isNotEmpty, reason: 'state: $state');
      }
    });
  });
}
