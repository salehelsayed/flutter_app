import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../db_write_transaction.dart';
import '../direct_event_fanout_contract.dart';
import '../direct_inbox_custody_outbox_contract.dart';
import '../direct_media_blob_custody.dart';
import '../outgoing_transport_mutation.dart';
import '../../media/direct_media_blob_custody.dart';
import '../../media/media_owner_lane.dart';
import '../../media/private_media_policy.dart';
import 'direct_contact_device_bindings_db_helpers.dart';
import 'direct_media_blob_custody_db_helpers.dart';
import 'direct_reaction_inbox_custody_outbox_db_helpers.dart';
import 'messages_db_helpers.dart';

const String _table = 'direct_inbox_custody_outbox';

const int kDirectInboxCustodyOutboxCapacity = 512;
const int kDirectInboxCustodyOutboxMaxLoadBatch = 50;

/// Atomically stages a fresh ordinary message and its immutable relay-inbox
/// custody. No message row is allowed to commit without its companion row.
///
/// [capacity] exists only so a real-DB test can prove the full condition with
/// a small fixture. Production callers use the default constant.
Future<OutgoingOrdinaryMutationOutcome> dbStageOutgoingDirectTextInboxCustody(
  Database db, {
  required Map<String, Object?>? expectedRow,
  required Map<String, Object?> stagedRow,
  required OutgoingOrdinaryAttemptKind kind,
  required String recipientPeerId,
  required String messageId,
  required String incarnationId,
  required String wireEnvelope,
  int capacity = kDirectInboxCustodyOutboxCapacity,
}) {
  final createdAt = stagedRow['created_at'] as String? ?? '';
  final validAuthority =
      capacity >= 0 &&
      kind == OutgoingOrdinaryAttemptKind.fresh &&
      expectedRow == null &&
      recipientPeerId.trim().isNotEmpty &&
      messageId.trim().isNotEmpty &&
      incarnationId.length == 32 &&
      wireEnvelope.trim().isNotEmpty &&
      stagedRow['id'] == messageId &&
      stagedRow['contact_peer_id'] == recipientPeerId &&
      stagedRow['wire_envelope'] == wireEnvelope &&
      createdAt.trim().isNotEmpty &&
      _isEligibleFreshOrdinaryDirectText(stagedRow) &&
      isExactV2DirectChatInitialEnvelope(
        wireEnvelope,
        messageId: messageId,
        senderPeerId: stagedRow['sender_peer_id'],
      );
  if (!validAuthority) {
    return Future<OutgoingOrdinaryMutationOutcome>.value(
      OutgoingOrdinaryMutationOutcome.refused,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final currentMessages = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    final currentMessageAuthority = await txn.query(
      _table,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      limit: 2,
    );
    final currentIncarnation = await txn.query(
      _table,
      where: 'incarnation_id = ?',
      whereArgs: <Object?>[incarnationId],
      limit: 1,
    );

    if (currentMessages.isNotEmpty ||
        currentMessageAuthority.isNotEmpty ||
        currentIncarnation.isNotEmpty) {
      final isExactReplay =
          currentMessages.length == 1 &&
          currentMessageAuthority.length == 1 &&
          currentIncarnation.length == 1 &&
          _messageAttemptMatches(currentMessages.single, stagedRow) &&
          _immutableCustodyMatches(
            currentMessageAuthority.single,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          ) &&
          _immutableCustodyMatches(
            currentIncarnation.single,
            recipientPeerId: recipientPeerId,
            messageId: messageId,
            incarnationId: incarnationId,
            wireEnvelope: wireEnvelope,
          );
      return isExactReplay
          ? OutgoingOrdinaryMutationOutcome.idempotent
          : OutgoingOrdinaryMutationOutcome.refused;
    }

    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count >= capacity) return OutgoingOrdinaryMutationOutcome.refused;

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: expectedRow,
          stagedRow: stagedRow,
          kind: kind,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return OutgoingOrdinaryMutationOutcome.refused;
    }

    await txn.insert(_table, <String, Object?>{
      'recipient_peer_id': recipientPeerId,
      'message_id': messageId,
      'incarnation_id': incarnationId,
      'wire_envelope': wireEnvelope,
      'retry_count': 0,
      'last_attempt_at': null,
      'last_error_code': null,
      'created_at': createdAt,
      'updated_at': createdAt,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
    return OutgoingOrdinaryMutationOutcome.applied;
  });
}

/// Loads a fair bounded batch. SQLite's ascending order places NULL first, so
/// never-attempted rows lead, followed by the oldest recorded attempt.
Future<List<Map<String, Object?>>> dbLoadDirectInboxCustodyOutbox(
  DatabaseExecutor db, {
  int limit = kDirectInboxCustodyOutboxMaxLoadBatch,
}) {
  if (limit <= 0) return Future<List<Map<String, Object?>>>.value(const []);
  final boundedLimit = math.min(limit, kDirectInboxCustodyOutboxMaxLoadBatch);
  return db.rawQuery(
    'SELECT * FROM $_table '
    'ORDER BY last_attempt_at ASC, created_at ASC, '
    'recipient_peer_id ASC, message_id ASC LIMIT ?',
    <Object?>[boundedLimit],
  );
}

Future<Map<String, Object?>?> dbLoadDirectInboxCustodyOutboxForMessage(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String messageId,
}) async {
  final rows = await db.query(
    _table,
    where: 'recipient_peer_id = ? AND message_id = ?',
    whereArgs: <Object?>[recipientPeerId, messageId],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single;
}

/// Loads the immutable v108 owner for [messageId] without trusting the
/// mutable parent message's current recipient projection.
///
/// More than one stored owner is corrupt/ambiguous authority. Throwing keeps
/// retry callers fail-closed instead of allowing a generic transport path to
/// interpret the ambiguity as an absent custody row.
Future<Map<String, Object?>?> dbLoadDirectInboxCustodyOutboxOwnerForMessageId(
  DatabaseExecutor db, {
  required String messageId,
}) async {
  final rows = await db.query(
    _table,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    limit: 2,
  );
  // 361: a fanout-marked generation has no single owner. Selecting one
  // sibling through this contract would let a generic single-target path
  // interpret the batch, so plural AND marked rows both fail closed here;
  // fanout-aware callers use the plural sibling loader instead.
  if (rows.length > 1 ||
      rows.any((row) => row['contact_account_peer_id'] != null)) {
    throw StateError('Ambiguous direct inbox custody owner for message');
  }
  return rows.isEmpty ? null : rows.single;
}

/// Retains the row and records one bounded failure classification only while
/// the caller's exact immutable incarnation still owns the scope.
Future<bool> dbRecordDirectInboxCustodyFailureIfExact(
  DatabaseExecutor db, {
  required String recipientPeerId,
  required String messageId,
  required String expectedIncarnationId,
  required String expectedWireEnvelope,
  required String errorCode,
  required String attemptedAt,
}) async {
  if (!DirectInboxCustodyErrorCode.values.contains(errorCode) ||
      attemptedAt.trim().isEmpty) {
    return false;
  }
  final changed = await db.rawUpdate(
    'UPDATE $_table SET retry_count = retry_count + 1, '
    'last_attempt_at = ?, last_error_code = ?, updated_at = ? '
    'WHERE recipient_peer_id = ? AND message_id = ? '
    'AND incarnation_id = ? AND wire_envelope = ?',
    <Object?>[
      attemptedAt,
      errorCode,
      attemptedAt,
      recipientPeerId,
      messageId,
      expectedIncarnationId,
      expectedWireEnvelope,
    ],
  );
  return changed == 1;
}

/// Atomically projects accepted remote custody without downgrading stronger
/// local truth, then retires only the exact immutable incarnation.
Future<DirectInboxCustodyCompletionOutcome>
dbCompleteAcceptedDirectInboxCustodyIfExact(
  Database db, {
  required String recipientPeerId,
  required String messageId,
  required String expectedIncarnationId,
  required String expectedWireEnvelope,
  required int? relayExpiresAt,
}) {
  if (recipientPeerId.trim().isEmpty ||
      messageId.trim().isEmpty ||
      expectedIncarnationId.length != 32 ||
      expectedWireEnvelope.trim().isEmpty ||
      (relayExpiresAt != null && relayExpiresAt <= 0)) {
    return Future<DirectInboxCustodyCompletionOutcome>.value(
      DirectInboxCustodyCompletionOutcome.stale,
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final custodyRows = await txn.query(
      _table,
      where: 'recipient_peer_id = ? AND message_id = ?',
      whereArgs: <Object?>[recipientPeerId, messageId],
      limit: 1,
    );
    if (custodyRows.isEmpty ||
        !_immutableCustodyMatches(
          custodyRows.single,
          recipientPeerId: recipientPeerId,
          messageId: messageId,
          incarnationId: expectedIncarnationId,
          wireEnvelope: expectedWireEnvelope,
        )) {
      return DirectInboxCustodyCompletionOutcome.stale;
    }
    final custody = custodyRows.single;
    final mediaBlobManifestHash =
        custody['media_blob_manifest_hash'] as String?;
    final mediaBlobExpiresAtMs = (custody['media_blob_expires_at_ms'] as num?)
        ?.toInt();
    final hasStrictBlobBinding =
        mediaBlobManifestHash != null && mediaBlobExpiresAtMs != null;
    if ((mediaBlobManifestHash == null) != (mediaBlobExpiresAtMs == null)) {
      return DirectInboxCustodyCompletionOutcome.stale;
    }
    // 361: a fanout sibling belongs to its LOGICAL contact. 362: a MEDIA
    // fanout sibling additionally carries its own exact per-target blob
    // binding, validated below against only THIS recipient's v114 target
    // rows. Whether this row is the last surviving sibling decides whether
    // the canonical transition may project.
    final fanoutContact = custody['contact_account_peer_id'] as String?;
    final isFanoutSibling = fanoutContact != null;
    final ownerContactPeerId = fanoutContact ?? recipientPeerId;
    var isFinalSurvivingSibling = true;
    if (isFanoutSibling) {
      final siblingCountRows = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM $_table WHERE message_id = ?',
        <Object?>[messageId],
      );
      isFinalSurvivingSibling =
          ((siblingCountRows.single['count'] as num?)?.toInt() ?? 0) == 1;
    }
    List<DirectMediaBlobCustodyRow> strictBlobRows = const [];
    if (hasStrictBlobBinding) {
      if (relayExpiresAt == null ||
          relayExpiresAt <= 0 ||
          relayExpiresAt > mediaBlobExpiresAtMs) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
      // 362: exact-target authority — only THIS recipient's v114 rows own
      // this v108 binding; sibling targets converge through their own exact
      // incarnations and are never selected or transitioned here.
      final rawMessageBlobRows = await txn.query(
        kDirectMediaBlobCustodyTable,
        where:
            'owner_lane = ? AND message_id = ? AND direction = ? '
            'AND recipient_peer_id = ?',
        whereArgs: <Object?>[
          MediaBlobCustodyOwnerLane.direct.dbValue,
          messageId,
          DirectMediaBlobCustodyDirection.outgoing.dbValue,
          recipientPeerId,
        ],
        orderBy: 'attachment_id ASC',
      );
      try {
        strictBlobRows = rawMessageBlobRows
            .map(DirectMediaBlobCustodyRow.fromMap)
            .toList(growable: false);
      } on FormatException {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
      if (strictBlobRows.isEmpty ||
          strictBlobRows.any(
            (row) =>
                row.state != DirectMediaBlobCustodyState.outgoingStored ||
                row.inboxCustodyIncarnationId != expectedIncarnationId ||
                row.expiresAtMs == null,
          )) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
      final manifest = strictBlobRows
          .map(
            (row) => DirectMediaBlobManifestProjection(
              attachmentId: row.attachmentId,
              commitment: DirectMediaBlobCustodyCommitment(
                contentHash: row.contentHash,
                ciphertextSize: row.ciphertextSize,
                expiresAtMs: row.expiresAtMs!,
              ),
            ),
          )
          .toList(growable: false);
      if (computeDirectMediaBlobManifestHash(manifest) !=
              mediaBlobManifestHash ||
          earliestDirectMediaBlobExpiryMs(manifest) != mediaBlobExpiresAtMs) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }
    }

    final messageRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    var outcome = DirectInboxCustodyCompletionOutcome.messageRemoved;
    if (messageRows.isEmpty) {
      // Physical deletion is stronger than accepted relay custody, but the
      // outbox row was the only durable fact preventing a delayed generic
      // whole-row save from recreating the message after completion. Replace
      // that authority inside this same transaction with a scrubbed local
      // tombstone before retiring the exact v108 incarnation. A fanout
      // sibling reconstructs it against the LOGICAL contact — never the
      // delivery transport — and preserves the generation as the no-remint
      // fact any later sibling converges on.
      await txn.insert(
        'messages',
        _removedMessageTombstoneFromCustody(
          custody,
          messageId: messageId,
          recipientPeerId: ownerContactPeerId,
          expectedWireEnvelope: expectedWireEnvelope,
          relayExpiresAt: relayExpiresAt,
          directEventFanoutGenerationId: isFanoutSibling ? messageId : null,
        ),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } else {
      final message = messageRows.single;
      final status = message['status'] as String?;
      final ownsMessage =
          ((message['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
          message['contact_peer_id'] == ownerContactPeerId;
      final userTerminal =
          message['deleted_at'] != null || message['hidden_at'] != null;
      // 361: a nonrepresentative sibling's ciphertext never equals the
      // canonical witness. Completion compares clear kind/message identity
      // plus the persisted generation instead of ciphertext equality.
      final ownsCurrentFanoutGeneration =
          isFanoutSibling &&
          message['direct_event_fanout_generation_id'] == messageId &&
          _exactInitialEnvelopeSenderPeerId(
                expectedWireEnvelope,
                messageId: messageId,
              ) !=
              null;
      final stillProjectsOwnedAttempt = isFanoutSibling
          ? ownsCurrentFanoutGeneration
          : message['wire_envelope'] == expectedWireEnvelope;
      // A direct/LAN receipt commits `delivered` and CLEARS the initial
      // envelope, so the common successful path reaches this transaction with
      // no projected attempt at all. That successor was CAS-derived from this
      // exact owned initial and is still the same generation, so it owns the
      // same lineage. Only the full canonical delivered settlement qualifies:
      // a later edit/send/tombstone or a malformed delivered projection is
      // excluded, exactly like the ordinary settlement CAS.
      final ownsDeliveredSuccessor = _isCanonicalDeliveredSuccessor(message);

      // This transaction is the last point at which the complete bound
      // generation is still provable: it retires the exact v108 owner below,
      // and cleanup later drains every v111 row physically. Persist each
      // already-proven per-attachment commitment digest first so a delete
      // for everyone can still select the protected owner afterwards.
      //
      // Authorship is deliberately independent of [shouldAdvance]: a
      // delivered parent is preserved rather than advanced, yet it is the
      // common accepted case and owns exactly the same lineage. A terminal,
      // superseded or no-longer-owned parent keeps its current completion
      // outcome instead, so a Plan 351 deletion-first tombstone never turns
      // attachments into a completion prerequisite.
      final ownsExactLineage =
          strictBlobRows.isNotEmpty &&
          ownsMessage &&
          !userTerminal &&
          (stillProjectsOwnedAttempt || ownsDeliveredSuccessor) &&
          (isStrictOrdinaryOutgoingDirectPolicy(message) ||
              // 358: the exact disappearing successor of the same token-bearing
              // owners. Protected/View-Once deliberately stay out — they own a
              // different (no-v110) generation lane and must never receive this
              // fingerprint.
              _isStrictDisappearingOutgoingDirectPolicy(message));
      if (ownsExactLineage &&
          !await dbStampExactStrictOutgoingLineageWithinTransaction(
            txn,
            messageId: messageId,
            strictBlobRows: strictBlobRows,
            // 362: a fanout target completion stamps the target-INDEPENDENT
            // v2 generation digest — first accepted target stamps, later
            // targets must agree; legacy single-target completions keep the
            // incumbent exact target-specific digest with a NULL version.
            fingerprintVersion: isFanoutSibling
                ? kDirectMediaBlobFingerprintVersionGeneration
                : null,
          )) {
        return DirectInboxCustodyCompletionOutcome.stale;
      }

      final shouldAdvance =
          ownsMessage &&
          !userTerminal &&
          stillProjectsOwnedAttempt &&
          // 361: only the FINAL surviving sibling of a fanout generation may
          // project the canonical transition; earlier siblings retire their
          // exact row and preserve the message untouched.
          isFinalSurvivingSibling &&
          const <String>{
            'sending',
            'sent',
            'failed',
            'inboxed',
          }.contains(status);
      if (shouldAdvance) {
        final alreadyProjected =
            status == 'inboxed' &&
            message['transport'] == 'inbox' &&
            (relayExpiresAt == null ||
                message['relay_expires_at'] == relayExpiresAt);
        if (alreadyProjected) {
          outcome = DirectInboxCustodyCompletionOutcome.messagePreserved;
        } else {
          final changed = await txn.update(
            'messages',
            <String, Object?>{
              'status': 'inboxed',
              'transport': 'inbox',
              'relay_expires_at': relayExpiresAt,
              'custody_checked_at': null,
            },
            where:
                'id = ? AND contact_peer_id = ? AND is_incoming = 0 '
                'AND status = ? AND deleted_at IS NULL AND hidden_at IS NULL',
            whereArgs: <Object?>[messageId, ownerContactPeerId, status],
          );
          if (changed != 1) {
            throw StateError(
              'direct inbox custody message projection lost its exact row',
            );
          }
          outcome = DirectInboxCustodyCompletionOutcome.messageAdvanced;
        }
      } else {
        // Delivered and user-terminal rows are intentionally stronger than an
        // inbox-custody projection. Identity mismatches and later edit/send
        // attempts with different exact envelopes are also never edited.
        outcome = DirectInboxCustodyCompletionOutcome.messagePreserved;
      }
    }

    final deleted = await txn.delete(
      _table,
      where:
          'recipient_peer_id = ? AND message_id = ? '
          'AND incarnation_id = ? AND wire_envelope = ?',
      whereArgs: <Object?>[
        recipientPeerId,
        messageId,
        expectedIncarnationId,
        expectedWireEnvelope,
      ],
    );
    if (deleted != 1) {
      throw StateError(
        'direct inbox custody completion lost its exact incarnation',
      );
    }
    if (strictBlobRows.isNotEmpty) {
      final completedAt = DateTime.now().toUtc().toIso8601String();
      for (final row in strictBlobRows) {
        final cleanup = row.copyWith(
          state: DirectMediaBlobCustodyState.outgoingCleanupPending,
          updatedAt: completedAt,
        );
        final changed =
            await dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
              txn,
              expected: row,
              next: cleanup,
            );
        if (!changed) {
          throw StateError(
            'direct inbox custody completion lost strict blob authority',
          );
        }
      }
    }
    return outcome;
  });
}

/// Persists the exact per-attachment commitment digest of one already-proven
/// strict outgoing generation, inside the caller's completion transaction.
///
/// Returns false for a missing, extra, crossed or ambiguous physical
/// projection. That answer is only valid before the first write, so every
/// contradiction is prevalidated and the caller leaves all rows untouched.
/// Once a digest has been written, a lost CAS or drifted re-read throws so the
/// shared transaction rolls back the lineage together with the message
/// projection, the exact v108 deletion and every v111 transition.
///
/// Each digest commits to that row's own full public commitment. The v108
/// manifest hash, the generation's earliest expiry and the accepted relay
/// expiry are all generation-level values and can never stand in for it.
///
/// 362: [fingerprintVersion] selects the persisted lineage meaning. NULL is
/// the incumbent exact target-specific commitment digest (expiry included,
/// version column stays NULL). [kDirectMediaBlobFingerprintVersionGeneration]
/// is the sender-local target-INDEPENDENT generation digest of a fanout
/// completion: the first accepted target stamps digest+version together and
/// every later target completion must agree exactly. Null/value/version
/// contradictions refuse.
Future<bool> dbStampExactStrictOutgoingLineageWithinTransaction(
  DatabaseExecutor txn, {
  required String messageId,
  required List<DirectMediaBlobCustodyRow> strictBlobRows,
  int? fingerprintVersion,
}) async {
  if (fingerprintVersion != null &&
      fingerprintVersion != kDirectMediaBlobFingerprintVersionGeneration) {
    return false;
  }
  const columns = <String>[
    'id',
    'content_hash',
    'direct_media_blob_custody_fingerprint',
    'direct_media_blob_custody_fingerprint_version',
  ];
  const where = 'message_id = ? AND owner_lane = ?';
  final whereArgs = <Object?>[messageId, MediaOwnerLane.direct.dbValue];

  final attachments = await txn.query(
    'media_attachments',
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    orderBy: 'id ASC',
  );
  // One physical attachment per strict row and no extras.
  if (attachments.length != strictBlobRows.length) return false;
  final attachmentsById = <String, Map<String, Object?>>{};
  for (final attachment in attachments) {
    final id = attachment['id'];
    if (id is! String || attachmentsById.containsKey(id)) return false;
    attachmentsById[id] = attachment;
  }

  final exactLineage = <String, String>{};
  final unstamped = <String, String>{};
  for (final row in strictBlobRows) {
    final attachment = attachmentsById[row.attachmentId];
    if (attachment == null || attachment['content_hash'] != row.contentHash) {
      return false;
    }
    final String exact;
    if (fingerprintVersion == null) {
      final commitment = DirectMediaBlobCustodyCommitment(
        kind: row.custodyKind,
        contract: row.custodyContract,
        contentHash: row.contentHash,
        ciphertextSize: row.ciphertextSize,
        transportMime: row.transportMime,
        expiresAtMs: row.expiresAtMs!,
      );
      if (!commitment.isValid) return false;
      exact = computeDirectMediaBlobCommitmentFingerprint(
        attachmentId: row.attachmentId,
        commitment: commitment,
      );
    } else {
      try {
        exact = computeDirectMediaBlobGenerationFingerprintV2(
          attachmentId: row.attachmentId,
          custodyKind: row.custodyKind,
          custodyContract: row.custodyContract,
          contentHash: row.contentHash,
          ciphertextSize: row.ciphertextSize,
          transportMime: row.transportMime,
        );
      } on FormatException {
        return false;
      }
    }
    // A well-formed digest that is not this row's own is crossed proof, never
    // lineage to overwrite or adopt — and a digest whose persisted VERSION
    // marks the other meaning is equally crossed.
    final current = attachment['direct_media_blob_custody_fingerprint'];
    final currentVersion =
        (attachment['direct_media_blob_custody_fingerprint_version'] as num?)
            ?.toInt();
    if (current == null) {
      if (currentVersion != null) return false;
      unstamped[row.attachmentId] = exact;
    } else {
      if (current != exact || currentVersion != fingerprintVersion) {
        return false;
      }
    }
    exactLineage[row.attachmentId] = exact;
  }

  for (final entry in unstamped.entries) {
    final changed = await txn.update(
      'media_attachments',
      <String, Object?>{
        'direct_media_blob_custody_fingerprint': entry.value,
        'direct_media_blob_custody_fingerprint_version': fingerprintVersion,
      },
      where:
          '$where AND id = ? '
          'AND direct_media_blob_custody_fingerprint IS NULL',
      whereArgs: <Object?>[...whereArgs, entry.key],
    );
    if (changed != 1) {
      throw StateError(
        'direct inbox custody completion lost its exact attachment lineage',
      );
    }
  }

  final committed = await txn.query(
    'media_attachments',
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    orderBy: 'id ASC',
  );
  if (committed.length != exactLineage.length ||
      committed.any(
        (attachment) =>
            attachment['direct_media_blob_custody_fingerprint'] !=
                exactLineage[attachment['id']] ||
            (attachment['direct_media_blob_custody_fingerprint_version']
                        as num?)
                    ?.toInt() !=
                fingerprintVersion,
      )) {
    throw StateError(
      'direct inbox custody completion lost its exact attachment lineage',
    );
  }
  return true;
}

/// The exact outgoing v1 `disappearing` policy shape whose accepted v108
/// completion may stamp Plan 352's per-attachment lineage.
///
/// This transaction is the last point at which the generation is provable, so
/// the predicate is deliberately narrow: a v1 disappearing initial with one
/// allowed duration, lifecycle `available`, no receiver-local clock (this is
/// the SENDER), and its v110 token already consumed by v108 staging. Any other
/// private mode, a crossed duration, a terminal state or a sender-side clock
/// keeps the incumbent unstamped result.
bool _isStrictDisappearingOutgoingDirectPolicy(Map<String, Object?> row) {
  final durationSeconds = row['private_media_duration_seconds'];
  return ((row['is_incoming'] as num?)?.toInt() ?? 0) == 0 &&
      (row['private_media_policy_version'] as num?)?.toInt() == 1 &&
      row['private_media_mode'] == PrivateMediaMode.disappearing.wireValue &&
      durationSeconds is num &&
      PrivateMediaPolicy.allowedDurationsSeconds.contains(
        durationSeconds.toInt(),
      ) &&
      row['private_media_state'] ==
          PrivateMediaLifecycleState.available.wireValue &&
      row['private_media_received_at_ms'] == null &&
      row['private_media_expires_at_ms'] == null &&
      row['private_media_revealed_at_ms'] == null &&
      row['private_media_terminal_at_ms'] == null &&
      row['private_media_clock_high_water_ms'] == null &&
      row['direct_media_custody_intent_id'] == null;
}

/// Every transport label the ordinary settlement CAS accepts on a delivered
/// row. Duplicated here deliberately: this predicate must not widen when an
/// unrelated caller changes, and the shared settlement file stays untouched.
const _supportedDeliveredTransportLabels = <String>{
  'wifi',
  'local',
  'direct',
  'reuse',
  'relay',
  'inbox',
};

/// True only for the full canonical delivered settlement a live receipt
/// commits from the owned initial attempt.
///
/// Delivery is terminal: it clears the envelope and releases every custody
/// field. Anything else that happens to read `delivered` — a later edit, a
/// tombstone, or a malformed/hand-written projection — is NOT this owner's
/// successor and must never inherit its lineage authorship.
bool _isCanonicalDeliveredSuccessor(Map<String, Object?> row) {
  final transport = row['transport'];
  return row['status'] == 'delivered' &&
      row['wire_envelope'] == null &&
      row['edited_at'] == null &&
      row['relay_expires_at'] == null &&
      row['custody_checked_at'] == null &&
      (transport == null ||
          (transport is String &&
              _supportedDeliveredTransportLabels.contains(transport)));
}

bool _immutableCustodyMatches(
  Map<String, Object?> row, {
  required String recipientPeerId,
  required String messageId,
  required String incarnationId,
  required String wireEnvelope,
}) =>
    row['recipient_peer_id'] == recipientPeerId &&
    row['message_id'] == messageId &&
    row['incarnation_id'] == incarnationId &&
    row['wire_envelope'] == wireEnvelope;

Map<String, Object?> _removedMessageTombstoneFromCustody(
  Map<String, Object?> custody, {
  required String messageId,
  required String recipientPeerId,
  required String expectedWireEnvelope,
  required int? relayExpiresAt,
  String? directEventFanoutGenerationId,
}) {
  final senderPeerId = _exactInitialEnvelopeSenderPeerId(
    expectedWireEnvelope,
    messageId: messageId,
  );
  final createdAt = custody['created_at'];
  final completedAt = custody['updated_at'];
  if (senderPeerId == null ||
      !_isNonBlankString(createdAt) ||
      !_isNonBlankString(completedAt)) {
    throw StateError(
      'direct inbox custody cannot retain exact removed-message authority',
    );
  }
  return <String, Object?>{
    'id': messageId,
    'contact_peer_id': recipientPeerId,
    'sender_peer_id': senderPeerId,
    'text': '',
    'timestamp': createdAt,
    'status': 'inboxed',
    'is_incoming': 0,
    'created_at': createdAt,
    'wire_envelope': null,
    'transport': 'inbox',
    'relay_expires_at': relayExpiresAt,
    'custody_checked_at': null,
    'hidden_at': completedAt,
    'direct_media_custody_intent_id': null,
    // 361: the reconstructed tombstone carries the generation so the scrubbed
    // no-remint fact survives message-only removal.
    'direct_event_fanout_generation_id': ?directEventFanoutGenerationId,
  };
}

String? _exactInitialEnvelopeSenderPeerId(
  String wireEnvelope, {
  required String messageId,
}) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return null;
    final senderPeerId = decoded['senderPeerId'];
    if (!_isNonBlankString(senderPeerId) ||
        !isExactV2DirectChatInitialEnvelope(
          wireEnvelope,
          messageId: messageId,
          senderPeerId: senderPeerId,
        )) {
      return null;
    }
    return senderPeerId as String;
  } on FormatException {
    return null;
  }
}

bool _messageAttemptMatches(
  Map<String, Object?> current,
  Map<String, Object?> staged,
) => staged.entries.every(
  (entry) => _sameDatabaseValue(current[entry.key], entry.value),
);

bool _sameDatabaseValue(Object? left, Object? right) {
  if (left is num && right is num) return left == right;
  return left == right;
}

bool _isEligibleFreshOrdinaryDirectText(Map<String, Object?> row) =>
    _isNonBlankString(row['sender_peer_id']) &&
    _isNonBlankString(row['text']) &&
    _isNonBlankString(row['timestamp']) &&
    row['status'] == 'sending' &&
    _asInt(row['is_incoming']) == 0 &&
    row['edited_at'] == null &&
    row['deleted_at'] == null &&
    row['deleted_by_peer_id'] == null &&
    row['hidden_at'] == null &&
    row['transport'] == null &&
    row['relay_expires_at'] == null &&
    row['custody_checked_at'] == null &&
    row['direct_media_custody_intent_id'] == null &&
    _asInt(row['private_media_policy_version']) == 0 &&
    row['private_media_mode'] == 'ordinary' &&
    row['private_media_duration_seconds'] == null &&
    row['private_media_state'] == 'none' &&
    row['private_media_received_at_ms'] == null &&
    row['private_media_expires_at_ms'] == null &&
    row['private_media_revealed_at_ms'] == null &&
    row['private_media_terminal_at_ms'] == null &&
    row['private_media_clock_high_water_ms'] == null;

/// Validates the cleartext discriminator and encrypted body of one initial
/// direct `chat_message` envelope.
///
/// The frozen v108 custody wire label says "text" for compatibility, but the
/// outer envelope is shared by initial text and ordinary-media messages. Edit
/// events carry a distinct `eventId` and are deliberately excluded.
bool isExactV2DirectChatInitialEnvelope(
  String wireEnvelope, {
  required String messageId,
  required Object? senderPeerId,
}) {
  try {
    final decoded = jsonDecode(wireEnvelope);
    if (decoded is! Map<String, dynamic>) return false;
    final encrypted = decoded['encrypted'];
    return decoded['type'] == 'chat_message' &&
        decoded['version'] == '2' &&
        decoded['id'] == messageId &&
        decoded['senderPeerId'] == senderPeerId &&
        !decoded.containsKey('eventId') &&
        encrypted is Map<String, dynamic> &&
        _isNonBlankString(encrypted['kem']) &&
        _isNonBlankString(encrypted['ciphertext']) &&
        _isNonBlankString(encrypted['nonce']);
  } on FormatException {
    return false;
  }
}

bool _isNonBlankString(Object? value) =>
    value is String && value.trim().isNotEmpty;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

/// Domain separator for the deterministic per-(message,target) incarnation.
const String _fanoutIncarnationDomain =
    'mknoon-direct-event-fanout-incarnation-v1';

/// Mints the one stable 32-character incarnation for `(message, target)`.
///
/// v108 requires one globally unique incarnation per row; fanout requires that
/// the SAME `(message, target)` pair always reproduces the SAME incarnation so
/// a byte-exact stage replay can never contradict the surviving rows.
String computeDirectEventFanoutIncarnation({
  required String messageId,
  required String recipientPeerId,
}) {
  final material =
      '$_fanoutIncarnationDomain\n'
      'message:${messageId.trim()}\n'
      'target:${recipientPeerId.trim()}';
  return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
}

/// Loads EVERY surviving v108 sibling of one logical message generation, in
/// stable target order. Surviving rows are the complete pending set.
Future<List<Map<String, Object?>>>
dbLoadDirectInboxCustodyOutboxRowsForMessageId(
  DatabaseExecutor db, {
  required String messageId,
}) {
  return db.query(
    _table,
    where: 'message_id = ?',
    whereArgs: <Object?>[messageId],
    orderBy: 'recipient_peer_id ASC',
  );
}

/// Loads a fair bounded batch of EXACT v113 blob-free fanout rows only.
///
/// The restricted linked runtime drains through this loader so historical
/// (null logical contact), media-bound, and private rows are never selected.
Future<List<Map<String, Object?>>>
dbLoadDirectInboxCustodyOutboxExactFanoutRows(
  DatabaseExecutor db, {
  int limit = kDirectInboxCustodyOutboxMaxLoadBatch,
}) {
  if (limit <= 0) return Future<List<Map<String, Object?>>>.value(const []);
  final boundedLimit = math.min(limit, kDirectInboxCustodyOutboxMaxLoadBatch);
  return db.rawQuery(
    'SELECT * FROM $_table '
    'WHERE contact_account_peer_id IS NOT NULL '
    'AND media_blob_manifest_hash IS NULL '
    'AND media_blob_expires_at_ms IS NULL '
    'ORDER BY last_attempt_at ASC, created_at ASC, '
    'recipient_peer_id ASC, message_id ASC LIMIT ?',
    <Object?>[boundedLimit],
  );
}

/// Validates that [candidates] covers [snapshot] targets exactly, in the same
/// deterministic order, with no duplicate transport.
bool directEventFanoutCandidatesMatchSnapshot(
  List<DirectEventFanoutTargetCandidate> candidates,
  DirectContactFanoutSnapshot snapshot,
) {
  if (candidates.isEmpty || candidates.length != snapshot.targets.length) {
    return false;
  }
  final seen = <String>{};
  for (var index = 0; index < candidates.length; index++) {
    final candidate = candidates[index];
    if (candidate.recipientPeerId != snapshot.targets[index].peerId ||
        candidate.wireEnvelope.trim().isEmpty ||
        !seen.add(candidate.recipientPeerId)) {
      return false;
    }
  }
  return true;
}

/// Atomically stages one fresh blob-free ordinary direct text message and its
/// COMPLETE all-target v108 sibling batch (Plan 361 / DB v113).
///
/// Survivor-first: ANY surviving sibling for [messageId] is authoritative
/// evidence the atomic batch already exists, and is returned — before roster,
/// capacity, or canonical work — as the complete pending set. With zero
/// survivors, an owned canonical row whose generation still equals [messageId]
/// is terminal and can never be reminted. Otherwise the persisted-contact
/// snapshot is re-read and exactly compared inside this transaction, capacity
/// must admit the WHOLE batch, and the canonical message plus every sibling
/// commit together or not at all.
Future<DbDirectEventFanoutStageResult>
dbStageOutgoingDirectTextFanoutInboxCustody(
  Database db, {
  required Map<String, Object?> stagedRow,
  required String messageId,
  required String contactAccountPeerId,
  required String senderTransportPeerId,
  required DirectContactFanoutSnapshot expectedSnapshot,
  required List<DirectEventFanoutTargetCandidate> candidates,
  int capacity = kDirectInboxCustodyOutboxCapacity,
  Future<void> Function()? beforeSiblingInsertForTest,
}) {
  final createdAt = stagedRow['created_at'] as String? ?? '';
  final validAuthority =
      capacity >= 0 &&
      messageId.trim().isNotEmpty &&
      contactAccountPeerId.trim().isNotEmpty &&
      senderTransportPeerId.trim().isNotEmpty &&
      expectedSnapshot.contactAccountPeerId == contactAccountPeerId &&
      directEventFanoutCandidatesMatchSnapshot(candidates, expectedSnapshot) &&
      stagedRow['id'] == messageId &&
      stagedRow['contact_peer_id'] == contactAccountPeerId &&
      stagedRow['direct_event_fanout_generation_id'] == messageId &&
      stagedRow['wire_envelope'] == candidates.first.wireEnvelope &&
      createdAt.trim().isNotEmpty &&
      _isEligibleFreshOrdinaryDirectText(stagedRow) &&
      candidates.every(
        (candidate) => isExactV2DirectChatInitialEnvelope(
          candidate.wireEnvelope,
          messageId: messageId,
          senderPeerId: senderTransportPeerId,
        ),
      );
  if (!validAuthority) {
    return Future<DbDirectEventFanoutStageResult>.value(
      const DbDirectEventFanoutStageResult.refused(),
    );
  }

  return dbWriteTransaction(db, (txn) async {
    final survivors = await txn.query(
      _table,
      where: 'message_id = ?',
      whereArgs: <Object?>[messageId],
      orderBy: 'recipient_peer_id ASC',
    );
    if (survivors.isNotEmpty) {
      // Surviving rows are the complete pending set. The attempt must agree
      // with them byte-for-byte; roster and capacity are never consulted and
      // no target is appended or recreated.
      for (final row in survivors) {
        final candidate = candidates
            .where((c) => c.recipientPeerId == row['recipient_peer_id'])
            .firstOrNull;
        if (row['contact_account_peer_id'] != contactAccountPeerId ||
            row['incarnation_id'] !=
                computeDirectEventFanoutIncarnation(
                  messageId: messageId,
                  recipientPeerId: row['recipient_peer_id'] as String,
                ) ||
            (candidate != null &&
                candidate.wireEnvelope != row['wire_envelope'])) {
          return const DbDirectEventFanoutStageResult.refused();
        }
      }
      return DbDirectEventFanoutStageResult(
        outcome: DirectEventFanoutStageOutcome.survivorReplay,
        rows: survivors
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false),
      );
    }

    final messageRows = await txn.query(
      'messages',
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
      limit: 1,
    );
    if (messageRows.isNotEmpty) {
      final message = messageRows.single;
      final terminal =
          message['direct_event_fanout_generation_id'] == messageId &&
          message['contact_peer_id'] == contactAccountPeerId &&
          ((message['is_incoming'] as num?)?.toInt() ?? 0) == 0;
      // With zero siblings, an exact matching generation is terminal and
      // idempotent — including after a receipt cleared the witness or a
      // delete-for-me scrubbed the row. Anything else is conflicting bytes.
      return terminal
          ? const DbDirectEventFanoutStageResult(
              outcome: DirectEventFanoutStageOutcome.terminal,
              rows: <Map<String, Object?>>[],
            )
          : const DbDirectEventFanoutStageResult.refused();
    }

    // Re-read the persisted contact + complete v112 facts inside this
    // transaction; a removed contact or ANY drift from the caller's snapshot
    // fails the whole batch all-zero.
    final currentSnapshot = await dbReadDirectContactFanoutSnapshot(
      txn,
      contactAccountPeerId: contactAccountPeerId,
    );
    if (currentSnapshot == null ||
        currentSnapshot.targets.isEmpty ||
        !currentSnapshot.sameSnapshotAs(expectedSnapshot)) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    // Capacity admits the whole batch or nothing.
    final countRows = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table',
    );
    final count = (countRows.single['count'] as num?)?.toInt() ?? 0;
    if (count + candidates.length > capacity) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    // Blob-free only: a message that already owns direct media authority can
    // never ride the event fanout lane.
    final hasMediaTable = (await txn.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'media_attachments' LIMIT 1",
    )).isNotEmpty;
    if (hasMediaTable) {
      final directMedia = await txn.rawQuery(
        'SELECT 1 FROM media_attachments '
        'WHERE message_id = ? AND owner_lane = ? LIMIT 1',
        <Object?>[messageId, MediaOwnerLane.direct.dbValue],
      );
      if (directMedia.isNotEmpty) {
        return const DbDirectEventFanoutStageResult.refused();
      }
    }

    final messageOutcome =
        await dbStageOutgoingOrdinaryAttemptWithinTransaction(
          txn,
          expectedRow: null,
          stagedRow: stagedRow,
          kind: OutgoingOrdinaryAttemptKind.fresh,
        );
    if (messageOutcome != OutgoingOrdinaryMutationOutcome.applied) {
      return const DbDirectEventFanoutStageResult.refused();
    }

    final stagedRows = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      final siblingRow = <String, Object?>{
        'recipient_peer_id': candidate.recipientPeerId,
        'message_id': messageId,
        'incarnation_id': computeDirectEventFanoutIncarnation(
          messageId: messageId,
          recipientPeerId: candidate.recipientPeerId,
        ),
        'wire_envelope': candidate.wireEnvelope,
        'retry_count': 0,
        'last_attempt_at': null,
        'last_error_code': null,
        'contact_account_peer_id': contactAccountPeerId,
        'created_at': createdAt,
        'updated_at': createdAt,
      };
      await beforeSiblingInsertForTest?.call();
      await txn.insert(
        _table,
        siblingRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      stagedRows.add(siblingRow);
    }
    return DbDirectEventFanoutStageResult(
      outcome: DirectEventFanoutStageOutcome.applied,
      rows: stagedRows,
    );
  });
}
