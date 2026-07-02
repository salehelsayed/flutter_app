import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_message_deletion_use_case.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_sibling_dispositions.dart';
import 'package:flutter_test/flutter_test.dart';

// 172 TC-11 — sibling-surface parity locks (INV-1). The reaction and deletion
// replay paths already applied the recoverable->retryable parity the chat
// mapper only gained in 172; these locks pin that split so a future edit can
// neither demote a transient cause to terminal `rejected` (silent post-ACK
// loss) nor promote a content-safe/security drop to retryable (retry storm,
// INV-3). The `rejected` classes are deliberate asymmetries:
// senderMismatch/unauthorized are security drops, notReaction/
// notMessageDeletion are wrong-type envelopes.
void main() {
  group('mapReactionReplayResultToDisposition', () {
    test('success and targetUnavailable commit (OQ-7 terminal)', () {
      for (final result in [
        HandleReactionResult.success,
        HandleReactionResult.targetUnavailable,
      ]) {
        final outcome = mapReactionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.committed,
          reason: '$result',
        );
        expect(outcome.reasonCode, result.name);
      }
    });

    test('transient causes stay retryable (recoverable parity, INV-1)', () {
      for (final result in [
        HandleReactionResult.decryptionFailed,
        HandleReactionResult.unknownSender,
      ]) {
        final outcome = mapReactionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.retryable,
          reason: '$result must never be a terminal post-ACK drop',
        );
      }
    });

    test('security/wrong-type drops stay terminal rejected (locked '
        'asymmetry)', () {
      for (final result in [
        HandleReactionResult.senderMismatch,
        HandleReactionResult.notReaction,
      ]) {
        final outcome = mapReactionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.rejected,
          reason: '$result is a content-safe drop, not loss',
        );
      }
    });
  });

  group('mapMessageDeletionReplayResultToDisposition', () {
    test('success and ignoredMissingMessage commit (OQ-7 terminal)', () {
      for (final result in [
        HandleMessageDeletionResult.success,
        HandleMessageDeletionResult.ignoredMissingMessage,
      ]) {
        final outcome = mapMessageDeletionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.committed,
          reason: '$result',
        );
      }
    });

    test('transient causes stay retryable (recoverable parity, INV-1)', () {
      for (final result in [
        HandleMessageDeletionResult.decryptionFailed,
        HandleMessageDeletionResult.unknownSender,
      ]) {
        final outcome = mapMessageDeletionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.retryable,
          reason: '$result must never be a terminal post-ACK drop',
        );
      }
    });

    test('security/wrong-type drops stay terminal rejected (locked '
        'asymmetry)', () {
      for (final result in [
        HandleMessageDeletionResult.unauthorized,
        HandleMessageDeletionResult.notMessageDeletion,
      ]) {
        final outcome = mapMessageDeletionReplayResultToDisposition(result);
        expect(
          outcome.disposition,
          RecoveredInboxChatDisposition.rejected,
          reason: '$result is a content-safe drop, not loss',
        );
      }
    });
  });
}
