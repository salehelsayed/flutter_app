import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';

/// The atomic delete-prepare transaction seam
/// ([dbPrepareGroupMediaDeleteForMe] bound over the identity DB in main).
typedef GroupMediaDeletePrepareFn =
    Future<GroupMediaDeletePrepareResult> Function({
      required String groupId,
      required String messageId,
      required String operationId,
    });

/// Runs after the local tombstone/journal transaction and before ordinary
/// file/key cleanup. `false` means at least one strict incoming blob still
/// lacks a verified relay source, so its journal entry must remain retryable.
typedef TerminalizeDeletedStrictGroupMediaCustody =
    Future<bool> Function({required String groupId, required String messageId});

/// 235: the production whole-message Delete-for-me coordinator.
///
/// One confirmed delete = ONE operation UUID shared by every journaled
/// attachment of that message, prepared in ONE SQL transaction (no file/key
/// I/O before commit), followed by one post-commit cleanup pass. Double
/// invocations coalesce behind a `(groupId, messageId)` single-flight guard;
/// a call after commit observes the tombstoned/absent parent and is an
/// idempotent no-op.
class DeleteGroupMediaForMeUseCase implements GroupMediaDeleteForMeCoordinator {
  DeleteGroupMediaForMeUseCase({
    required this.prepare,
    required this.runCleanup,
    this.terminalizeStrictCustody,
    String Function()? operationIdFactory,
  }) : operationIdFactory = operationIdFactory ?? (() => const Uuid().v4());

  final GroupMediaDeletePrepareFn prepare;

  /// One bounded reconciliation pass
  /// ([GroupMediaDeletionJournalReconciler.runBounded]); errors are isolated
  /// per item inside — a cleanup failure never un-deletes the message.
  final Future<void> Function() runCleanup;

  final TerminalizeDeletedStrictGroupMediaCustody? terminalizeStrictCustody;

  final String Function() operationIdFactory;

  final Set<String> _inFlight = <String>{};

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    final flightKey = '$groupId:$messageId';
    if (!_inFlight.add(flightKey)) return;
    try {
      final result = await prepare(
        groupId: groupId,
        messageId: messageId,
        operationId: operationIdFactory(),
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_DELETE_FOR_ME',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'outcome': result.outcome.name,
          'journaled': result.journaledAttachments,
        },
      );
      if (result.prepared) {
        final terminalize = terminalizeStrictCustody;
        if (terminalize != null) {
          try {
            final cleanupIsSafe = await terminalize(
              groupId: groupId,
              messageId: messageId,
            );
            if (!cleanupIsSafe) {
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_MEDIA_DELETE_STRICT_CUSTODY_DEFERRED',
                details: {'reason': 'source_not_yet_verified'},
              );
              return;
            }
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_MEDIA_DELETE_STRICT_CUSTODY_DEFERRED',
              details: {'error': e.runtimeType.toString()},
            );
            return;
          }
        }
        try {
          await runCleanup();
        } catch (e) {
          // The journal is durable; cold start / resume reconciliation
          // finishes the saga.
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_MEDIA_DELETE_CLEANUP_DEFERRED',
            details: {'error': e.runtimeType.toString()},
          );
        }
      }
    } finally {
      _inFlight.remove(flightKey);
    }
  }
}
