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

    // The six rejections below are content-safe or pre-custody:
    // - blockedSender: the user explicitly blocked the sender; dropping is
    //   the product intent, not silent loss.
    // - notChatMessage: the envelope is not a chat message; there is no
    //   message content to lose.
    // - unknownSender: the mapper runs only after the intro-recovery
    //   pre-step had its chance to resolve the sender (main.dart keeps that
    //   pre-step and returns retryable while an intro is still pending).
    // - duplicate: the content is already committed under the same id.
    // - editMissingOriginal: the use case persists a hidden placeholder for
    //   the edit before this rejection, so the edit content is stored.
    // - ignoredEdit: the receiver already holds an equal-or-newer edit.
    test('blockedSender rejects', () {
      final outcome = map(ChatMessageProcessState.blockedSender);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'blocked_sender');
    });

    test('notChatMessage rejects', () {
      final outcome = map(ChatMessageProcessState.notChatMessage);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'not_chat_message');
    });

    test('unknownSender rejects', () {
      final outcome = map(ChatMessageProcessState.unknownSender);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'unknown_sender');
    });

    test('duplicate rejects', () {
      final outcome = map(ChatMessageProcessState.duplicate);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'duplicate');
    });

    test('editMissingOriginal rejects', () {
      final outcome = map(ChatMessageProcessState.editMissingOriginal);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'edit_missing_original');
    });

    test('ignoredEdit rejects staged replay with ignored_edit reason', () {
      final outcome = map(ChatMessageProcessState.ignoredEdit);
      expect(outcome.disposition, RecoveredInboxChatDisposition.rejected);
      expect(outcome.reasonCode, 'ignored_edit');
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
