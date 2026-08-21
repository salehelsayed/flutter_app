import 'package:sqflite_common/sqlite_api.dart';

import 'package:flutter_app/core/database/direct_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';

/// Binds the production v108 direct-text custody helpers to one integration
/// database without duplicating their long named callback signatures in every
/// real-repository harness.
final class DirectInboxCustodyDbBindings {
  const DirectInboxCustodyDbBindings(this.db);

  final Database db;

  Future<OutgoingOrdinaryMutationOutcome> stage({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String messageId,
    required String incarnationId,
    required String wireEnvelope,
  }) => dbStageOutgoingDirectTextInboxCustody(
    db,
    expectedRow: expectedRow,
    stagedRow: stagedRow,
    kind: kind,
    recipientPeerId: recipientPeerId,
    messageId: messageId,
    incarnationId: incarnationId,
    wireEnvelope: wireEnvelope,
  );

  Future<List<Map<String, Object?>>> load({int limit = 50}) =>
      dbLoadDirectInboxCustodyOutbox(db, limit: limit);

  Future<Map<String, Object?>?> loadForMessage({
    required String recipientPeerId,
    required String messageId,
  }) => dbLoadDirectInboxCustodyOutboxForMessage(
    db,
    recipientPeerId: recipientPeerId,
    messageId: messageId,
  );

  Future<Map<String, Object?>?> loadOwnerForMessageId({
    required String messageId,
  }) =>
      dbLoadDirectInboxCustodyOutboxOwnerForMessageId(db, messageId: messageId);

  Future<bool> recordFailureIfExact({
    required String recipientPeerId,
    required String messageId,
    required String expectedIncarnationId,
    required String expectedWireEnvelope,
    required String errorCode,
    required String attemptedAt,
  }) => dbRecordDirectInboxCustodyFailureIfExact(
    db,
    recipientPeerId: recipientPeerId,
    messageId: messageId,
    expectedIncarnationId: expectedIncarnationId,
    expectedWireEnvelope: expectedWireEnvelope,
    errorCode: errorCode,
    attemptedAt: attemptedAt,
  );

  Future<DirectInboxCustodyCompletionOutcome> completeAcceptedIfExact({
    required String recipientPeerId,
    required String messageId,
    required String expectedIncarnationId,
    required String expectedWireEnvelope,
    required int? relayExpiresAt,
  }) => dbCompleteAcceptedDirectInboxCustodyIfExact(
    db,
    recipientPeerId: recipientPeerId,
    messageId: messageId,
    expectedIncarnationId: expectedIncarnationId,
    expectedWireEnvelope: expectedWireEnvelope,
    relayExpiresAt: relayExpiresAt,
  );
}
