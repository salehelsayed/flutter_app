import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../secure_storage/secret_storage_references.dart';
import '../db_write_transaction.dart';
import 'group_event_log_db_helpers.dart';

const String kLocalSelfRemovedFreshnessFloorEventType =
    'local_self_removed_freshness_floor';
const String kLocalSelfRemovedAcceptOriginEventType =
    'local_self_removed_accept_origin';
const String kLocalSelfRemovedAcceptBindingEventType =
    'local_self_removed_accept_binding';
const int kSelfRemovedShellMediaPrepareLimit = 100;

const List<String> _membershipInstanceWorkTables = <String>[
  'group_exit_intents',
  'group_rejoin_state',
  'pending_group_broadcasts',
  'group_pending_key_repairs',
  'group_pending_key_distributions',
  'group_pending_membership_messages',
  'group_history_gap_repairs',
  'group_pending_reactions',
  'pending_sibling_devices',
];

enum SelfRemovedGroupShellAuthorityShape {
  absent,
  unmarkedSelfPresent,
  unmarkedSelfAbsent,
  markedSelfPresent,
  markedSelfAbsent,
}

/// Exact database authority used as a compare-and-swap token.
///
/// Instances are produced only by
/// [dbLoadSelfRemovedGroupShellAuthoritySnapshot]. The public DateTime fields
/// are normalized to UTC while the helper retains the original database text
/// privately, so handing the snapshot back to a mutation proves that no
/// authority-bearing cell or exact self `joined_at` changed in between.
class SelfRemovedGroupShellAuthoritySnapshot {
  const SelfRemovedGroupShellAuthoritySnapshot._({
    required this.groupId,
    required this.selfPeerId,
    required this.shape,
    required this.selfRemovedAt,
    required this.lastMembershipEventAt,
    required this.lastMembershipEventId,
    required this.selfJoinedAt,
    required String? selfRemovedAtRaw,
    required String? lastMembershipEventAtRaw,
    required String? selfJoinedAtRaw,
  }) : _selfRemovedAtRaw = selfRemovedAtRaw,
       _lastMembershipEventAtRaw = lastMembershipEventAtRaw,
       _selfJoinedAtRaw = selfJoinedAtRaw;

  final String groupId;
  final String selfPeerId;
  final SelfRemovedGroupShellAuthorityShape shape;
  final DateTime? selfRemovedAt;
  final DateTime? lastMembershipEventAt;
  final String? lastMembershipEventId;
  final DateTime? selfJoinedAt;

  final String? _selfRemovedAtRaw;
  final String? _lastMembershipEventAtRaw;
  final String? _selfJoinedAtRaw;
}

enum SelfRemovalAuthorityCommitDisposition {
  committed,
  refusedStateChanged,
  refusedStaleRemoval,
}

class SelfRemovedGroupShellTerminalizationCounts {
  const SelfRemovedGroupShellTerminalizationCounts({
    required this.pendingRowsDeleted,
    required this.messagesTerminalized,
    required this.uploadsTerminalized,
  });

  final int pendingRowsDeleted;
  final int messagesTerminalized;
  final int uploadsTerminalized;
}

class SelfRemovalAuthorityCommitResult {
  const SelfRemovalAuthorityCommitResult({
    required this.disposition,
    required this.authority,
    required this.terminalization,
  });

  final SelfRemovalAuthorityCommitDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupShellTerminalizationCounts terminalization;

  bool get committed =>
      disposition == SelfRemovalAuthorityCommitDisposition.committed;
}

enum SelfRemovedGroupShellMutationDisposition {
  committed,
  refusedStateChanged,
  refusedFloorMissing,
  refusedOutstandingReferences,
  refusedMediaRemaining,
  refusedTombstoneConflict,
}

class SelfRemovedGroupShellMutationResult {
  const SelfRemovedGroupShellMutationResult({
    required this.disposition,
    required this.authority,
    this.deletedRows = 0,
  });

  final SelfRemovedGroupShellMutationDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final int deletedRows;

  bool get committed =>
      disposition == SelfRemovedGroupShellMutationDisposition.committed;
}

enum SelfRemovedGroupKeyReferenceKind { committed, draft }

class SelfRemovedGroupKeyReference {
  const SelfRemovedGroupKeyReference._({
    required this.kind,
    required this.groupId,
    required this.keyGeneration,
    required this.encryptedKeyReference,
    required this.createdAt,
    required String createdAtRaw,
  }) : _createdAtRaw = createdAtRaw;

  final SelfRemovedGroupKeyReferenceKind kind;
  final String groupId;
  final int keyGeneration;
  final String encryptedKeyReference;
  final DateTime createdAt;
  final String _createdAtRaw;

  String get _exactIdentity =>
      canonicalizeGroupEventLogPayload(<String, Object?>{
        'kind': kind.name,
        'groupId': groupId,
        'keyGeneration': keyGeneration,
        'encryptedKeyReference': encryptedKeyReference,
        'createdAt': _createdAtRaw,
      });
}

class SelfRemovedGroupKeyReferenceLoadResult {
  const SelfRemovedGroupKeyReferenceLoadResult({
    required this.disposition,
    required this.authority,
    required this.references,
  });

  final SelfRemovedGroupShellMutationDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final List<SelfRemovedGroupKeyReference> references;

  bool get loaded =>
      disposition == SelfRemovedGroupShellMutationDisposition.committed;
}

class SelfRemovedGroupFreshnessFloor {
  const SelfRemovedGroupFreshnessFloor({
    required this.entryId,
    required this.sourceEventId,
    required this.sequence,
    required this.groupId,
    required this.selfPeerId,
    required this.selfRemovedAt,
    required this.lastMembershipEventAt,
    required this.lastMembershipEventId,
  });

  final String entryId;
  final String sourceEventId;
  final int sequence;
  final String groupId;
  final String selfPeerId;
  final DateTime selfRemovedAt;
  final DateTime? lastMembershipEventAt;
  final String? lastMembershipEventId;
}

class SelfRemovedGroupFreshnessFloorAppendResult {
  const SelfRemovedGroupFreshnessFloorAppendResult({
    required this.floor,
    required this.inserted,
  });

  final SelfRemovedGroupFreshnessFloor floor;
  final bool inserted;
}

class SelfRemovedGroupMediaParent {
  const SelfRemovedGroupMediaParent({
    required this.messageId,
    required this.timestamp,
  });

  final String messageId;
  final DateTime timestamp;
}

class SelfRemovedGroupMediaParentBatch {
  const SelfRemovedGroupMediaParentBatch({
    required this.parents,
    required this.hasOverflow,
  });

  final List<SelfRemovedGroupMediaParent> parents;
  final bool hasOverflow;
}

class SelfRemovedGroupMediaParentLoadResult {
  const SelfRemovedGroupMediaParentLoadResult({
    required this.disposition,
    required this.authority,
    required this.batch,
  });

  final SelfRemovedGroupShellMutationDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupMediaParentBatch batch;

  bool get loaded =>
      disposition == SelfRemovedGroupShellMutationDisposition.committed;
}

enum SelfRemovedGroupAcceptedReentryPriorShape { marked, absentWithFloor }

/// Durable authority that an accepted post-removal transition may restore.
///
/// The event-log [floor] is the restart-safe token. [markedAuthority] is also
/// returned for an immediate marked-shell rollback, but is deliberately null
/// for an absent-with-floor transition.
class SelfRemovedGroupAcceptedReentryPrior {
  const SelfRemovedGroupAcceptedReentryPrior({
    required this.shape,
    required this.floor,
    this.keyReferences = const <SelfRemovedGroupKeyReference>[],
    this.markedAuthority,
  });

  final SelfRemovedGroupAcceptedReentryPriorShape shape;
  final SelfRemovedGroupFreshnessFloor floor;
  final List<SelfRemovedGroupKeyReference> keyReferences;
  final SelfRemovedGroupShellAuthoritySnapshot? markedAuthority;
}

/// Opaque durable preparation for one post-removal accepted-membership phase.
///
/// The preparation is created only after the exact removal floor and
/// shape-specific origin have committed. It deliberately contains no secure
/// key material; callers use it first to retire the snapshotted old addresses,
/// then to stage the accepted SQL address before writing the primary store.
class SelfRemovedGroupAcceptedReentryPreparation {
  const SelfRemovedGroupAcceptedReentryPreparation._({
    required this.groupId,
    required this.selfPeerId,
    required this.authorizationId,
    required this.bindingNonce,
    required this.originEntryId,
    required this.originSourceEventId,
    required this.prior,
    required this.retiringKeyReferences,
    required String materialFingerprint,
    required String stagedKeyFingerprint,
  }) : _materialFingerprint = materialFingerprint,
       _stagedKeyFingerprint = stagedKeyFingerprint;

  final String groupId;
  final String selfPeerId;
  final String authorizationId;
  final String bindingNonce;
  final String originEntryId;
  final String originSourceEventId;
  final SelfRemovedGroupAcceptedReentryPrior prior;
  final List<SelfRemovedGroupKeyReference> retiringKeyReferences;
  final String _materialFingerprint;
  final String _stagedKeyFingerprint;
}

class SelfRemovedGroupAcceptedReentryPreparationResult {
  const SelfRemovedGroupAcceptedReentryPreparationResult({
    required this.disposition,
    required this.authority,
    this.preparation,
  });

  final SelfRemovedGroupAcceptedReentryDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupAcceptedReentryPreparation? preparation;

  bool get prepared =>
      disposition == SelfRemovedGroupAcceptedReentryDisposition.committed &&
      preparation != null;
}

class SelfRemovedGroupAcceptedReentryStageResult {
  const SelfRemovedGroupAcceptedReentryStageResult({
    required this.disposition,
    required this.authority,
  });

  final SelfRemovedGroupAcceptedReentryDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;

  bool get staged =>
      disposition == SelfRemovedGroupAcceptedReentryDisposition.committed;
}

class SelfRemovedGroupAcceptedReentryBinding {
  const SelfRemovedGroupAcceptedReentryBinding({
    required this.entryId,
    required this.sourceEventId,
    required this.sequence,
    required this.originEntryId,
    required this.authorizationId,
    required this.acceptedStateFingerprint,
    required this.acceptedAt,
    required this.keyGeneration,
    required this.encryptedKeyReference,
    required this.keyCreatedAt,
  });

  final String entryId;
  final String sourceEventId;
  final int sequence;
  final String originEntryId;
  final String authorizationId;
  final String acceptedStateFingerprint;
  final DateTime acceptedAt;
  final int keyGeneration;
  final String encryptedKeyReference;
  final DateTime keyCreatedAt;
}

enum SelfRemovedGroupAcceptedReentryDisposition {
  committed,
  refusedMissingFloor,
  refusedStateChanged,
  refusedInvalidMaterial,
  refusedMalformedAuthority,
  refusedStaleAuthority,
  refusedKeyState,
  refusedEvidenceInvalid,
  refusedBindingCollision,
}

class SelfRemovedGroupAcceptedReentryResult {
  const SelfRemovedGroupAcceptedReentryResult({
    required this.disposition,
    required this.authority,
    required this.terminalization,
    this.acceptedAt,
    this.prior,
    this.binding,
  });

  final SelfRemovedGroupAcceptedReentryDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupShellTerminalizationCounts terminalization;
  final DateTime? acceptedAt;
  final SelfRemovedGroupAcceptedReentryPrior? prior;
  final SelfRemovedGroupAcceptedReentryBinding? binding;

  bool get committed =>
      disposition == SelfRemovedGroupAcceptedReentryDisposition.committed;
}

enum SelfRemovedGroupAcceptedRollbackDisposition {
  rolledBack,
  refusedBindingMissing,
  refusedAuthorizationMismatch,
  refusedStateChanged,
  refusedEvidenceInvalid,
}

enum SelfRemovedGroupAcceptedRollbackQualificationDisposition {
  qualified,
  refusedBindingMissing,
  refusedAuthorizationMismatch,
  refusedStateChanged,
  refusedEvidenceInvalid,
}

/// Opaque read-only proof that one exact accepted binding currently owns a
/// rollback. Production callers must keep this token inside their per-group
/// coordinator from qualification through projection removal and final CAS.
class SelfRemovedGroupAcceptedRollbackQualification {
  const SelfRemovedGroupAcceptedRollbackQualification._({
    required this.groupId,
    required this.selfPeerId,
    required this.authorizationId,
    required String bindingEntryId,
    required String bindingSourceEventId,
    required int bindingSequence,
    required String acceptedStateFingerprint,
    required String floorEntryId,
    required SelfRemovedGroupShellAuthorityShape authorityShape,
    required String? selfRemovedAtRaw,
    required String? lastMembershipEventAtRaw,
    required String? lastMembershipEventId,
    required String? selfJoinedAtRaw,
    required bool alreadyRolledBack,
  }) : _bindingEntryId = bindingEntryId,
       _bindingSourceEventId = bindingSourceEventId,
       _bindingSequence = bindingSequence,
       _acceptedStateFingerprint = acceptedStateFingerprint,
       _floorEntryId = floorEntryId,
       _authorityShape = authorityShape,
       _selfRemovedAtRaw = selfRemovedAtRaw,
       _lastMembershipEventAtRaw = lastMembershipEventAtRaw,
       _lastMembershipEventId = lastMembershipEventId,
       _selfJoinedAtRaw = selfJoinedAtRaw,
       _alreadyRolledBack = alreadyRolledBack;

  final String groupId;
  final String selfPeerId;
  final String authorizationId;
  final String _bindingEntryId;
  final String _bindingSourceEventId;
  final int _bindingSequence;
  final String _acceptedStateFingerprint;
  final String _floorEntryId;
  final SelfRemovedGroupShellAuthorityShape _authorityShape;
  final String? _selfRemovedAtRaw;
  final String? _lastMembershipEventAtRaw;
  final String? _lastMembershipEventId;
  final String? _selfJoinedAtRaw;
  final bool _alreadyRolledBack;
}

class SelfRemovedGroupAcceptedRollbackQualificationResult {
  const SelfRemovedGroupAcceptedRollbackQualificationResult({
    required this.disposition,
    required this.authority,
    this.qualification,
    this.binding,
  });

  final SelfRemovedGroupAcceptedRollbackQualificationDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupAcceptedRollbackQualification? qualification;
  final SelfRemovedGroupAcceptedReentryBinding? binding;

  bool get qualified =>
      disposition ==
          SelfRemovedGroupAcceptedRollbackQualificationDisposition.qualified &&
      qualification != null;
}

class SelfRemovedGroupFreshAcceptedRollbackPreparation {
  const SelfRemovedGroupFreshAcceptedRollbackPreparation._({
    required this.groupId,
    required this.selfPeerId,
    required this.keyGeneration,
    required this.encryptedKeyReference,
    required this.keyCreatedAt,
    required String keyCreatedAtRaw,
    required String stateFingerprint,
    required String expectedMembershipAtRaw,
    required String? expectedMetadataAtRaw,
    required String selfJoinedAtRaw,
  }) : _keyCreatedAtRaw = keyCreatedAtRaw,
       _stateFingerprint = stateFingerprint,
       _expectedMembershipAtRaw = expectedMembershipAtRaw,
       _expectedMetadataAtRaw = expectedMetadataAtRaw,
       _selfJoinedAtRaw = selfJoinedAtRaw;

  final String groupId;
  final String selfPeerId;
  final int keyGeneration;
  final String encryptedKeyReference;
  final DateTime keyCreatedAt;
  final String _keyCreatedAtRaw;
  final String _stateFingerprint;
  final String _expectedMembershipAtRaw;
  final String? _expectedMetadataAtRaw;
  final String _selfJoinedAtRaw;
}

class SelfRemovedGroupFreshAcceptedRollbackPreparationResult {
  const SelfRemovedGroupFreshAcceptedRollbackPreparationResult({
    required this.disposition,
    required this.authority,
    this.preparation,
  });

  final SelfRemovedGroupAcceptedRollbackQualificationDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupFreshAcceptedRollbackPreparation? preparation;

  bool get prepared =>
      disposition ==
          SelfRemovedGroupAcceptedRollbackQualificationDisposition.qualified &&
      preparation != null;
}

enum SelfRemovedGroupAcceptedRetryAuthorizationDisposition {
  authorized,
  refusedBindingMissing,
  refusedAuthorizationMismatch,
  refusedStateChanged,
  refusedEvidenceInvalid,
}

class SelfRemovedGroupAcceptedRollbackResult {
  const SelfRemovedGroupAcceptedRollbackResult({
    required this.disposition,
    required this.authority,
    required this.terminalization,
    this.prior,
    this.binding,
  });

  final SelfRemovedGroupAcceptedRollbackDisposition disposition;
  final SelfRemovedGroupShellAuthoritySnapshot authority;
  final SelfRemovedGroupShellTerminalizationCounts terminalization;
  final SelfRemovedGroupAcceptedReentryPrior? prior;
  final SelfRemovedGroupAcceptedReentryBinding? binding;

  bool get rolledBack =>
      disposition == SelfRemovedGroupAcceptedRollbackDisposition.rolledBack;
}

Future<SelfRemovedGroupShellAuthoritySnapshot>
dbLoadSelfRemovedGroupShellAuthoritySnapshot(
  DatabaseExecutor db, {
  required String groupId,
  required String selfPeerId,
}) async {
  if (groupId.trim().isEmpty || selfPeerId.trim().isEmpty) {
    throw ArgumentError('groupId and selfPeerId are required');
  }

  final groupRows = await db.query(
    'groups',
    columns: <String>[
      'id',
      'self_removed_at',
      'last_membership_event_at',
      'last_membership_event_id',
    ],
    where: 'id = ?',
    whereArgs: <Object?>[groupId],
    limit: 1,
  );
  if (groupRows.isEmpty) {
    return SelfRemovedGroupShellAuthoritySnapshot._(
      groupId: groupId,
      selfPeerId: selfPeerId,
      shape: SelfRemovedGroupShellAuthorityShape.absent,
      selfRemovedAt: null,
      lastMembershipEventAt: null,
      lastMembershipEventId: null,
      selfJoinedAt: null,
      selfRemovedAtRaw: null,
      lastMembershipEventAtRaw: null,
      selfJoinedAtRaw: null,
    );
  }

  final group = groupRows.single;
  final memberRows = await db.query(
    'group_members',
    columns: const <String>['joined_at'],
    where: 'group_id = ? AND peer_id = ?',
    whereArgs: <Object?>[groupId, selfPeerId],
    limit: 1,
  );
  final markerRaw = group['self_removed_at'] as String?;
  final watermarkRaw = group['last_membership_event_at'] as String?;
  final joinedAtRaw = memberRows.isEmpty
      ? null
      : memberRows.single['joined_at'] as String;
  final marked = markerRaw != null;
  final selfPresent = joinedAtRaw != null;

  return SelfRemovedGroupShellAuthoritySnapshot._(
    groupId: groupId,
    selfPeerId: selfPeerId,
    shape: switch ((marked, selfPresent)) {
      (false, true) => SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent,
      (false, false) => SelfRemovedGroupShellAuthorityShape.unmarkedSelfAbsent,
      (true, true) => SelfRemovedGroupShellAuthorityShape.markedSelfPresent,
      (true, false) => SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
    },
    selfRemovedAt: _parseUtcColumn(markerRaw, 'groups.self_removed_at'),
    lastMembershipEventAt: _parseUtcColumn(
      watermarkRaw,
      'groups.last_membership_event_at',
    ),
    lastMembershipEventId: group['last_membership_event_id'] as String?,
    selfJoinedAt: _parseUtcColumn(joinedAtRaw, 'group_members.joined_at'),
    selfRemovedAtRaw: markerRaw,
    lastMembershipEventAtRaw: watermarkRaw,
    selfJoinedAtRaw: joinedAtRaw,
  );
}

Future<SelfRemovalAuthorityCommitResult> dbCommitSelfRemovalAuthority(
  Database db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  required DateTime removalAt,
  required String removalEventId,
}) async {
  if (removalEventId.trim().isEmpty) {
    throw ArgumentError.value(removalEventId, 'removalEventId');
  }
  final normalizedRemovalAt = removalAt.toUtc();
  if (expected.shape !=
      SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent) {
    return SelfRemovalAuthorityCommitResult(
      disposition: SelfRemovalAuthorityCommitDisposition.refusedStateChanged,
      authority: expected,
      terminalization: _zeroTerminalization,
    );
  }
  if (_isStaleMembershipAuthority(
    eventAt: normalizedRemovalAt,
    eventId: removalEventId,
    lastAt: expected.lastMembershipEventAt,
    lastId: expected.lastMembershipEventId,
  )) {
    return SelfRemovalAuthorityCommitResult(
      disposition: SelfRemovalAuthorityCommitDisposition.refusedStaleRemoval,
      authority: expected,
      terminalization: _zeroTerminalization,
    );
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
      );
      if (!_sameAuthority(current, expected) ||
          current.shape !=
              SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent) {
        return SelfRemovalAuthorityCommitResult(
          disposition:
              SelfRemovalAuthorityCommitDisposition.refusedStateChanged,
          authority: current,
          terminalization: _zeroTerminalization,
        );
      }
      if (_isStaleMembershipAuthority(
        eventAt: normalizedRemovalAt,
        eventId: removalEventId,
        lastAt: current.lastMembershipEventAt,
        lastId: current.lastMembershipEventId,
      )) {
        return SelfRemovalAuthorityCommitResult(
          disposition:
              SelfRemovalAuthorityCommitDisposition.refusedStaleRemoval,
          authority: current,
          terminalization: _zeroTerminalization,
        );
      }

      final removalIso = normalizedRemovalAt.toIso8601String();
      final groupUpdated = await txn.rawUpdate(
        'UPDATE groups SET self_removed_at = ?, '
        'last_membership_event_at = ?, last_membership_event_id = ? '
        'WHERE id = ? AND self_removed_at IS NULL '
        'AND last_membership_event_at IS ? '
        'AND last_membership_event_id IS ?',
        <Object?>[
          removalIso,
          removalIso,
          removalEventId,
          expected.groupId,
          expected._lastMembershipEventAtRaw,
          expected.lastMembershipEventId,
        ],
      );
      if (groupUpdated != 1) throw const _AuthorityCasLost();

      final selfDeleted = await txn.delete(
        'group_members',
        where: 'group_id = ? AND peer_id = ? AND joined_at = ?',
        whereArgs: <Object?>[
          expected.groupId,
          expected.selfPeerId,
          expected._selfJoinedAtRaw,
        ],
      );
      if (selfDeleted != 1) throw const _AuthorityCasLost();

      final terminalization = await dbTerminalizeSelfRemovedMembershipInstance(
        txn,
        expected.groupId,
      );
      final committed = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
      );
      return SelfRemovalAuthorityCommitResult(
        disposition: SelfRemovalAuthorityCommitDisposition.committed,
        authority: committed,
        terminalization: terminalization,
      );
    });
  } on _AuthorityCasLost {
    final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
      db,
      groupId: expected.groupId,
      selfPeerId: expected.selfPeerId,
    );
    return SelfRemovalAuthorityCommitResult(
      disposition: SelfRemovalAuthorityCommitDisposition.refusedStateChanged,
      authority: current,
      terminalization: _zeroTerminalization,
    );
  }
}

/// Clears executable work owned by the ended membership instance.
///
/// The caller owns the surrounding transaction. Retained evidence is not
/// touched: in particular `stored` reaction replay rows survive.
Future<SelfRemovedGroupShellTerminalizationCounts>
dbTerminalizeSelfRemovedMembershipInstance(
  DatabaseExecutor txn,
  String groupId,
) async {
  var pendingRowsDeleted = 0;
  for (final table in _membershipInstanceWorkTables) {
    if (!await _membershipWorkTableExists(txn, table)) continue;
    pendingRowsDeleted += await txn.delete(
      table,
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
    );
  }
  pendingRowsDeleted += await txn.delete(
    'group_reaction_replay_outbox',
    where: "group_id = ? AND delivery_status IN ('pending', 'failed')",
    whereArgs: <Object?>[groupId],
  );

  final uploadsTerminalized = await txn.rawUpdate(
    "UPDATE media_attachments SET download_status = 'upload_failed' "
    "WHERE owner_lane = 'group' AND download_status = 'upload_pending' "
    'AND EXISTS (SELECT 1 FROM group_messages parent '
    'WHERE parent.id = media_attachments.message_id '
    'AND parent.group_id = ? AND parent.is_incoming = 0)',
    <Object?>[groupId],
  );

  final messagesTerminalized = await txn.rawUpdate(
    "UPDATE group_messages SET status = 'send_failed', "
    'wire_envelope = NULL, inbox_retry_payload = NULL, '
    'next_eligible_at = NULL '
    'WHERE group_id = ? AND is_incoming = 0 AND ('
    "status IN ('sending', 'pending', 'failed', 'queued_offline', "
    "'send_failed') OR (status = 'sent' AND inbox_stored = 0 "
    'AND inbox_retry_payload IS NOT NULL))',
    <Object?>[groupId],
  );

  return SelfRemovedGroupShellTerminalizationCounts(
    pendingRowsDeleted: pendingRowsDeleted,
    messagesTerminalized: messagesTerminalized,
    uploadsTerminalized: uploadsTerminalized,
  );
}

/// Commits the restart-safe floor and shape-specific origin before any old
/// key material is retired or accepted primary material is written.
Future<SelfRemovedGroupAcceptedReentryPreparationResult>
dbPrepareSelfRemovedGroupAcceptedReentry(
  Database db, {
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> rosterRows,
  required Map<String, Object?> stagedKeyRow,
  required String selfPeerId,
  required String authorizationId,
  required String signedMembershipWatermark,
  required String signedIssuedAt,
  required String bindingNonce,
  DateTime? createdAt,
}) async {
  final groupId = groupRow['id'];
  if (groupId is! String || groupId.trim().isEmpty) {
    throw ArgumentError.value(groupId, 'groupRow.id');
  }
  if (selfPeerId.trim().isEmpty) {
    throw ArgumentError.value(selfPeerId, 'selfPeerId');
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );

      SelfRemovedGroupFreshnessFloor? retainedFloor;
      SelfRemovedGroupFreshnessFloor? cutoffFloor;
      SelfRemovedGroupAcceptedReentryPriorShape? priorShape;
      switch (current.shape) {
        case SelfRemovedGroupShellAuthorityShape.markedSelfAbsent:
          cutoffFloor = await dbLoadLatestSelfRemovedGroupFreshnessFloor(
            txn,
            groupId,
          );
          priorShape = SelfRemovedGroupAcceptedReentryPriorShape.marked;
        case SelfRemovedGroupShellAuthorityShape.absent:
          retainedFloor = await dbLoadLatestSelfRemovedGroupFreshnessFloor(
            txn,
            groupId,
          );
          if (retainedFloor == null) {
            return _acceptedPreparationRefusal(
              SelfRemovedGroupAcceptedReentryDisposition.refusedMissingFloor,
              current,
            );
          }
          cutoffFloor = retainedFloor;
          priorShape =
              SelfRemovedGroupAcceptedReentryPriorShape.absentWithFloor;
        case SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent:
        case SelfRemovedGroupShellAuthorityShape.unmarkedSelfAbsent:
        case SelfRemovedGroupShellAuthorityShape.markedSelfPresent:
          return _acceptedPreparationRefusal(
            SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
            current,
          );
      }

      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }
      if (cutoffFloor != null &&
          (cutoffFloor.groupId != groupId ||
              cutoffFloor.selfPeerId != selfPeerId ||
              !await _hasExactFreshnessFloor(txn, cutoffFloor))) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }

      final material = await _validateAcceptedReentryMaterial(
        txn,
        groupId: groupId,
        groupRow: groupRow,
        rosterRows: rosterRows,
        stagedKeyRow: stagedKeyRow,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        signedMembershipWatermark: signedMembershipWatermark,
        signedIssuedAt: signedIssuedAt,
        bindingNonce: bindingNonce,
        current: current,
        retainedFloor: cutoffFloor,
      );
      final floor =
          retainedFloor ??
          (await dbAppendSelfRemovedGroupFreshnessFloorInTransaction(
            txn,
            expected: current,
            createdAt: createdAt,
          )).floor;
      if (floor.groupId != groupId ||
          floor.selfPeerId != selfPeerId ||
          !await _hasExactFreshnessFloor(txn, floor)) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }

      final prior = SelfRemovedGroupAcceptedReentryPrior(
        shape: priorShape,
        floor: floor,
        keyReferences:
            priorShape == SelfRemovedGroupAcceptedReentryPriorShape.marked
            ? material.priorReferences
                  .where((reference) => !_isAcceptedStagingReference(reference))
                  .toList(growable: false)
            : const <SelfRemovedGroupKeyReference>[],
        markedAuthority:
            priorShape == SelfRemovedGroupAcceptedReentryPriorShape.marked
            ? current
            : null,
      );
      final origin = await _appendAcceptedReentryOrigin(
        txn,
        prior: prior,
        authorizationId: authorizationId,
        selfPeerId: selfPeerId,
        createdAt: createdAt,
      );
      final preparation = SelfRemovedGroupAcceptedReentryPreparation._(
        groupId: groupId,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        bindingNonce: bindingNonce,
        originEntryId: origin.entryId,
        originSourceEventId: origin.sourceEventId,
        prior: prior,
        retiringKeyReferences: material.priorReferences,
        materialFingerprint: _acceptedPreparationMaterialFingerprint(material),
        stagedKeyFingerprint: _hashCanonicalValue(material.stagedKeyRow),
      );
      return SelfRemovedGroupAcceptedReentryPreparationResult(
        disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
        authority: current,
        preparation: preparation,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedPreparationRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on _AcceptedReentryRefusal catch (error) {
    return _acceptedPreparationRefusal(
      error.disposition,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedPreparationRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedPreparationRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

/// Atomically replaces the exact old key/draft SQL addresses with the one
/// accepted address. Primary secure material must not be written until this
/// call succeeds.
Future<SelfRemovedGroupAcceptedReentryStageResult>
dbStageSelfRemovedGroupAcceptedReentryKey(
  Database db, {
  required SelfRemovedGroupAcceptedReentryPreparation preparation,
  required Map<String, Object?> stagedKeyRow,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      );
      if (!await _acceptedPreparationEvidenceIsExact(
        txn,
        preparation: preparation,
        current: current,
      )) {
        throw const _AcceptedReentryStateChanged();
      }
      if (_hashCanonicalValue(stagedKeyRow) !=
          preparation._stagedKeyFingerprint) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
        );
      }
      final stagedReference = await _acceptedStagedReference(
        txn,
        preparation.groupId,
        stagedKeyRow,
      );
      final currentReferences = await _loadRawKeyReferences(
        txn,
        preparation.groupId,
      );
      if (_sameReferences(currentReferences, <SelfRemovedGroupKeyReference>[
        stagedReference,
      ])) {
        return SelfRemovedGroupAcceptedReentryStageResult(
          disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
          authority: current,
        );
      }
      if (!_sameReferences(
        currentReferences,
        preparation.retiringKeyReferences,
      )) {
        throw const _AcceptedReentryStateChanged();
      }

      await txn.delete(
        'group_key_rotation_drafts',
        where: 'group_id = ?',
        whereArgs: <Object?>[preparation.groupId],
      );
      await txn.delete(
        'group_keys',
        where: 'group_id = ?',
        whereArgs: <Object?>[preparation.groupId],
      );
      await txn.insert(
        'group_keys',
        stagedKeyRow,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      final stagedReferences = await _loadRawKeyReferences(
        txn,
        preparation.groupId,
      );
      if (!_sameReferences(stagedReferences, <SelfRemovedGroupKeyReference>[
        stagedReference,
      ])) {
        throw const _AcceptedReentryStateChanged();
      }
      return SelfRemovedGroupAcceptedReentryStageResult(
        disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
        authority: current,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on _AcceptedReentryRefusal catch (error) {
    return _acceptedStageRefusal(
      error.disposition,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  }
}

/// Atomically materializes an authenticated accepted membership over a
/// previously removed local membership instance.
///
/// This intentionally does not handle a truly fresh group. The only admitted
/// prior shapes are an exact marked/self-absent shell or an absent group with
/// a retained, well-formed removal freshness floor.
Future<SelfRemovedGroupAcceptedReentryResult>
dbCommitSelfRemovedGroupAcceptedReentry(
  Database db, {
  required SelfRemovedGroupAcceptedReentryPreparation preparation,
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> rosterRows,
  required Map<String, Object?> stagedKeyRow,
  required String selfPeerId,
  required String authorizationId,
  required String signedMembershipWatermark,
  required String signedIssuedAt,
  required String bindingNonce,
  DateTime? createdAt,
}) async {
  final groupId = groupRow['id'];
  if (groupId is! String || groupId.trim().isEmpty) {
    throw ArgumentError.value(groupId, 'groupRow.id');
  }
  if (selfPeerId.trim().isEmpty) {
    throw ArgumentError.value(selfPeerId, 'selfPeerId');
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );

      if (preparation.groupId != groupId ||
          preparation.selfPeerId != selfPeerId ||
          preparation.authorizationId != authorizationId ||
          preparation.bindingNonce != bindingNonce) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
        );
      }
      if (!await _acceptedPreparationEvidenceIsExact(
        txn,
        preparation: preparation,
        current: current,
      )) {
        throw const _AcceptedReentryStateChanged();
      }

      final material = await _validateAcceptedReentryMaterial(
        txn,
        groupId: groupId,
        groupRow: groupRow,
        rosterRows: rosterRows,
        stagedKeyRow: stagedKeyRow,
        selfPeerId: selfPeerId,
        authorizationId: authorizationId,
        signedMembershipWatermark: signedMembershipWatermark,
        signedIssuedAt: signedIssuedAt,
        bindingNonce: bindingNonce,
        current: current,
        retainedFloor: preparation.prior.floor,
        expectedPriorReferences: preparation.retiringKeyReferences,
      );
      if (_acceptedPreparationMaterialFingerprint(material) !=
              preparation._materialFingerprint ||
          _hashCanonicalValue(material.stagedKeyRow) !=
              preparation._stagedKeyFingerprint) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
        );
      }
      final stagedReference = await _acceptedStagedReference(
        txn,
        groupId,
        material.stagedKeyRow,
      );
      if (!_sameReferences(
        await _loadRawKeyReferences(txn, groupId),
        <SelfRemovedGroupKeyReference>[stagedReference],
      )) {
        throw const _AcceptedReentryStateChanged();
      }
      final origin = await _loadAcceptedOriginEvidence(
        txn,
        groupId: groupId,
        entryId: preparation.originEntryId,
      );

      final terminalization = await dbTerminalizeSelfRemovedMembershipInstance(
        txn,
        groupId,
      );
      await _materializeAcceptedReentryState(
        txn,
        prior: preparation.prior,
        expectedMarkedAuthority: current,
        material: material,
      );

      final acceptedState = await _loadAcceptedStateFingerprint(txn, groupId);
      final bindingPayload = _acceptedBindingPayload(
        material: material,
        prior: preparation.prior,
        origin: origin,
        authorizationId: authorizationId,
        bindingNonce: bindingNonce,
        state: acceptedState,
      );
      final bindingSourceEventId = _acceptedBindingSourceEventId(
        origin.entryId,
        bindingNonce,
      );

      GroupEventLogAppendResult bindingAppend;
      try {
        bindingAppend = await dbAppendGroupEventLogEntryInTransaction(
          txn,
          groupId: groupId,
          eventType: kLocalSelfRemovedAcceptBindingEventType,
          sourcePeerId: selfPeerId,
          sourceEventId: bindingSourceEventId,
          sourceTimestamp: material.acceptedAtRaw,
          payload: bindingPayload,
          createdAt: createdAt,
        );
      } on GroupEventLogTamperException {
        throw const _AcceptedReentryBindingCollision();
      }
      if (!bindingAppend.inserted) {
        throw const _AcceptedReentryBindingCollision();
      }

      final committed = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (committed.shape !=
              SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent ||
          committed._lastMembershipEventAtRaw != material.acceptedAtRaw ||
          committed.lastMembershipEventId != null) {
        throw const _AcceptedReentryStateChanged();
      }
      final binding = _acceptedBindingFromEventRow(bindingAppend.row).binding;
      return SelfRemovedGroupAcceptedReentryResult(
        disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
        authority: committed,
        terminalization: terminalization,
        acceptedAt: material.acceptedAt,
        prior: preparation.prior,
        binding: binding,
      );
    });
  } on _AcceptedReentryBindingCollision {
    return _acceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedBindingCollision,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on _AcceptedReentryStateChanged {
    return _acceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on _AcceptedReentryRefusal catch (error) {
    return _acceptedReentryRefusal(
      error.disposition,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

/// Prepares an exact no-floor fresh materialization rollback while retaining
/// its SQL key address for strict external deletion.
Future<SelfRemovedGroupFreshAcceptedRollbackPreparationResult>
dbPrepareFreshAcceptedMaterializationRollback(
  Database db, {
  required String groupId,
  required String selfPeerId,
  required int keyGeneration,
  required DateTime expectedMembershipAt,
  required DateTime? expectedMetadataAt,
}) async {
  if (groupId.trim().isEmpty ||
      selfPeerId.trim().isEmpty ||
      keyGeneration < 0) {
    throw ArgumentError('fresh accepted rollback tuple is invalid');
  }
  final expectedMembershipAtRaw = expectedMembershipAt
      .toUtc()
      .toIso8601String();
  final expectedMetadataAtRaw = expectedMetadataAt?.toUtc().toIso8601String();

  SelfRemovedGroupFreshAcceptedRollbackPreparationResult refusal(
    SelfRemovedGroupAcceptedRollbackQualificationDisposition disposition,
    SelfRemovedGroupShellAuthoritySnapshot authority,
  ) => SelfRemovedGroupFreshAcceptedRollbackPreparationResult(
    disposition: disposition,
    authority: authority,
  );

  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (current.shape !=
              SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent ||
          current._lastMembershipEventAtRaw != expectedMembershipAtRaw ||
          current.lastMembershipEventId != null ||
          await dbLoadLatestSelfRemovedGroupFreshnessFloor(txn, groupId) !=
              null) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
        );
      }
      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedEvidenceInvalid,
          current,
        );
      }
      final groupRows = await txn.query(
        'groups',
        columns: <String>['last_metadata_event_at', 'is_dissolved'],
        where:
            'id = ? AND self_removed_at IS NULL '
            'AND last_membership_event_at = ? '
            'AND last_membership_event_id IS NULL',
        whereArgs: <Object?>[groupId, expectedMembershipAtRaw],
        limit: 1,
      );
      if (groupRows.length != 1 ||
          groupRows.single['is_dissolved'] != 0 ||
          groupRows.single['last_metadata_event_at'] != expectedMetadataAtRaw) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
        );
      }
      final selfRows = await txn.query(
        'group_members',
        columns: <String>['joined_at'],
        where: 'group_id = ? AND peer_id = ?',
        whereArgs: <Object?>[groupId, selfPeerId],
        limit: 2,
      );
      final state = await _loadAcceptedStateFingerprint(txn, groupId);
      if (selfRows.length != 1 ||
          state.keyRows.length != 1 ||
          state.draftRows.isNotEmpty) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
        );
      }
      final keyRow = state.keyRows.single;
      final keyReference = keyRow['encrypted_key'];
      final keyCreatedAtRaw = keyRow['created_at'];
      if (keyRow['group_id'] != groupId ||
          keyRow['key_generation'] != keyGeneration ||
          keyReference is! String ||
          !isSecureStoreReference(keyReference) ||
          keyCreatedAtRaw is! String ||
          selfRows.single['joined_at'] is! String) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
        );
      }
      return SelfRemovedGroupFreshAcceptedRollbackPreparationResult(
        disposition:
            SelfRemovedGroupAcceptedRollbackQualificationDisposition.qualified,
        authority: current,
        preparation: SelfRemovedGroupFreshAcceptedRollbackPreparation._(
          groupId: groupId,
          selfPeerId: selfPeerId,
          keyGeneration: keyGeneration,
          encryptedKeyReference: keyReference,
          keyCreatedAt: _parseRequiredUtcColumn(
            keyCreatedAtRaw,
            'freshAcceptedRollback.keyCreatedAt',
          ),
          keyCreatedAtRaw: keyCreatedAtRaw,
          stateFingerprint: state.fingerprint,
          expectedMembershipAtRaw: expectedMembershipAtRaw,
          expectedMetadataAtRaw: expectedMetadataAtRaw,
          selfJoinedAtRaw: selfRows.single['joined_at'] as String,
        ),
      );
    });
  } on GroupEventLogTamperException {
    return refusal(
      SelfRemovedGroupAcceptedRollbackQualificationDisposition
          .refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return refusal(
      SelfRemovedGroupAcceptedRollbackQualificationDisposition
          .refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

/// Atomically removes the exact fresh group/roster/key fingerprint prepared
/// above. Primary and mirror material must already have been deleted.
Future<SelfRemovedGroupAcceptedRollbackResult>
dbCommitFreshAcceptedMaterializationRollback(
  Database db, {
  required SelfRemovedGroupFreshAcceptedRollbackPreparation preparation,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      );
      final groupRows = await txn.query(
        'groups',
        columns: <String>['last_metadata_event_at', 'is_dissolved'],
        where:
            'id = ? AND self_removed_at IS NULL '
            'AND last_membership_event_at = ? '
            'AND last_membership_event_id IS NULL',
        whereArgs: <Object?>[
          preparation.groupId,
          preparation._expectedMembershipAtRaw,
        ],
        limit: 1,
      );
      final selfRows = await txn.query(
        'group_members',
        columns: <String>['joined_at'],
        where: 'group_id = ? AND peer_id = ?',
        whereArgs: <Object?>[preparation.groupId, preparation.selfPeerId],
        limit: 2,
      );
      final state =
          current.shape ==
              SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent
          ? await _loadAcceptedStateFingerprint(txn, preparation.groupId)
          : null;
      final keyIsExact =
          state != null &&
          state.keyRows.length == 1 &&
          state.draftRows.isEmpty &&
          state.keyRows.single['key_generation'] == preparation.keyGeneration &&
          state.keyRows.single['encrypted_key'] ==
              preparation.encryptedKeyReference &&
          state.keyRows.single['created_at'] == preparation._keyCreatedAtRaw;
      if (current._lastMembershipEventAtRaw !=
              preparation._expectedMembershipAtRaw ||
          current.lastMembershipEventId != null ||
          await dbLoadLatestSelfRemovedGroupFreshnessFloor(
                txn,
                preparation.groupId,
              ) !=
              null ||
          groupRows.length != 1 ||
          groupRows.single['is_dissolved'] != 0 ||
          groupRows.single['last_metadata_event_at'] !=
              preparation._expectedMetadataAtRaw ||
          selfRows.length != 1 ||
          selfRows.single['joined_at'] != preparation._selfJoinedAtRaw ||
          state?.fingerprint != preparation._stateFingerprint ||
          !keyIsExact) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
          current,
        );
      }
      final terminalization = await dbTerminalizeSelfRemovedMembershipInstance(
        txn,
        preparation.groupId,
      );
      await txn.delete(
        'group_members',
        where: 'group_id = ?',
        whereArgs: <Object?>[preparation.groupId],
      );
      await txn.delete(
        'group_key_rotation_drafts',
        where: 'group_id = ?',
        whereArgs: <Object?>[preparation.groupId],
      );
      await txn.delete(
        'group_keys',
        where: 'group_id = ?',
        whereArgs: <Object?>[preparation.groupId],
      );
      final deleted = await txn.delete(
        'groups',
        where:
            'id = ? AND self_removed_at IS NULL '
            'AND last_membership_event_at = ? '
            'AND last_membership_event_id IS NULL',
        whereArgs: <Object?>[
          preparation.groupId,
          preparation._expectedMembershipAtRaw,
        ],
      );
      if (deleted != 1) throw const _AcceptedReentryStateChanged();
      final absent = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      );
      return SelfRemovedGroupAcceptedRollbackResult(
        disposition: SelfRemovedGroupAcceptedRollbackDisposition.rolledBack,
        authority: absent,
        terminalization: terminalization,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedRollbackRefusal(
      SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedRollbackRefusal(
      SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  }
}

/// Read-only qualification for accepted rollback. The newest full-state
/// binding is selected before its separate authorization is compared.
Future<SelfRemovedGroupAcceptedRollbackQualificationResult>
dbQualifySelfRemovedGroupAcceptedRollback(
  Database db, {
  required String groupId,
  required String selfPeerId,
  required String authorizationId,
}) async {
  if (groupId.trim().isEmpty ||
      selfPeerId.trim().isEmpty ||
      authorizationId.trim().isEmpty) {
    throw ArgumentError('accepted rollback authority tuple is invalid');
  }

  SelfRemovedGroupAcceptedRollbackQualificationResult refusal(
    SelfRemovedGroupAcceptedRollbackQualificationDisposition disposition,
    SelfRemovedGroupShellAuthoritySnapshot authority, {
    SelfRemovedGroupAcceptedReentryBinding? binding,
  }) => SelfRemovedGroupAcceptedRollbackQualificationResult(
    disposition: disposition,
    authority: authority,
    binding: binding,
  );

  try {
    return await dbWriteTransaction(db, (txn) async {
      final bindingRows = await txn.query(
        'group_event_log',
        where: 'group_id = ? AND event_type = ?',
        whereArgs: <Object?>[groupId, kLocalSelfRemovedAcceptBindingEventType],
        orderBy: 'sequence DESC',
      );
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (bindingRows.isEmpty) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedBindingMissing,
          current,
        );
      }
      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedEvidenceInvalid,
          current,
        );
      }

      if (current.shape !=
          SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent) {
        if (current.shape ==
                SelfRemovedGroupShellAuthorityShape.markedSelfAbsent ||
            current.shape == SelfRemovedGroupShellAuthorityShape.absent) {
          _AcceptedBindingEvidence? selected;
          _FreshnessFloorEvidence? floor;
          var malformedEvidenceSeen = false;
          for (final row in bindingRows) {
            try {
              final candidate = _acceptedBindingFromEventRow(row);
              final candidateOrigin = await _loadAcceptedOriginEvidence(
                txn,
                groupId: groupId,
                entryId: candidate.originEntryId,
              );
              final candidateFloor = await _loadFreshnessFloorEvidence(
                txn,
                groupId: groupId,
                entryId: candidate.floorEntryId,
              );
              if (_bindingEvidenceMatchesOriginAndFloor(
                    candidate,
                    candidateOrigin,
                    candidateFloor,
                  ) &&
                  await _currentStateMatchesRecordedPrior(
                    txn,
                    current: current,
                    binding: candidate,
                    floor: candidateFloor,
                  )) {
                selected = candidate;
                floor = candidateFloor;
                break;
              }
            } on GroupEventLogTamperException {
              malformedEvidenceSeen = true;
            } on FormatException {
              malformedEvidenceSeen = true;
            }
          }
          if (selected != null && floor != null) {
            if (selected.authorizationId != authorizationId) {
              return refusal(
                SelfRemovedGroupAcceptedRollbackQualificationDisposition
                    .refusedAuthorizationMismatch,
                current,
                binding: selected.binding,
              );
            }
            return _acceptedRollbackQualificationSuccess(
              current: current,
              binding: selected,
              floor: floor,
              authorizationId: authorizationId,
              alreadyRolledBack: true,
            );
          }
          if (malformedEvidenceSeen) {
            return refusal(
              SelfRemovedGroupAcceptedRollbackQualificationDisposition
                  .refusedEvidenceInvalid,
              current,
            );
          }
        }
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
        );
      }

      final state = await _loadAcceptedStateFingerprint(txn, groupId);
      _AcceptedBindingEvidence? selected;
      var malformedBindingSeen = false;
      for (final row in bindingRows) {
        try {
          final candidate = _acceptedBindingFromEventRow(row);
          if (candidate.stateFingerprint == state.fingerprint) {
            selected = candidate;
            break;
          }
        } on GroupEventLogTamperException {
          malformedBindingSeen = true;
        } on FormatException {
          malformedBindingSeen = true;
        }
      }
      if (selected == null) {
        return refusal(
          malformedBindingSeen
              ? SelfRemovedGroupAcceptedRollbackQualificationDisposition
                    .refusedEvidenceInvalid
              : SelfRemovedGroupAcceptedRollbackQualificationDisposition
                    .refusedBindingMissing,
          current,
        );
      }
      if (selected.authorizationId != authorizationId) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedAuthorizationMismatch,
          current,
          binding: selected.binding,
        );
      }
      if (selected.groupHash != state.groupHash ||
          selected.rosterHash != state.rosterHash ||
          selected.keyHash != state.keyHash ||
          selected.draftHash != state.draftHash ||
          selected.selfPeerId != selfPeerId ||
          selected.acceptedAtRaw != current._lastMembershipEventAtRaw ||
          current.lastMembershipEventId != null) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
          binding: selected.binding,
        );
      }
      final origin = await _loadAcceptedOriginEvidence(
        txn,
        groupId: groupId,
        entryId: selected.originEntryId,
      );
      final floor = await _loadFreshnessFloorEvidence(
        txn,
        groupId: groupId,
        entryId: selected.floorEntryId,
      );
      if (!_bindingEvidenceMatchesOriginAndFloor(selected, origin, floor)) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedEvidenceInvalid,
          current,
          binding: selected.binding,
        );
      }
      final selfRows = await txn.query(
        'group_members',
        where: 'group_id = ? AND peer_id = ? AND joined_at = ?',
        whereArgs: <Object?>[groupId, selfPeerId, selected.selfJoinedAtRaw],
        limit: 1,
      );
      if (selfRows.length != 1 ||
          !_acceptedBindingKeyTupleStillPresent(selected, state)) {
        return refusal(
          SelfRemovedGroupAcceptedRollbackQualificationDisposition
              .refusedStateChanged,
          current,
          binding: selected.binding,
        );
      }
      return _acceptedRollbackQualificationSuccess(
        current: current,
        binding: selected,
        floor: floor,
        authorizationId: authorizationId,
        alreadyRolledBack: false,
      );
    });
  } on GroupEventLogTamperException {
    return refusal(
      SelfRemovedGroupAcceptedRollbackQualificationDisposition
          .refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return refusal(
      SelfRemovedGroupAcceptedRollbackQualificationDisposition
          .refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

/// Authorizes a duplicate native retry without changing accepted authority.
Future<SelfRemovedGroupAcceptedRetryAuthorizationDisposition>
dbAuthorizeSelfRemovedGroupAcceptedReentryRetry(
  Database db, {
  required String groupId,
  required String selfPeerId,
  required String authorizationId,
  required String signedMembershipWatermark,
  required String signedIssuedAt,
  required int keyGeneration,
}) async {
  if (groupId.trim().isEmpty ||
      selfPeerId.trim().isEmpty ||
      authorizationId.trim().isEmpty ||
      signedMembershipWatermark.trim().isEmpty ||
      signedIssuedAt.trim().isEmpty ||
      keyGeneration < 0) {
    throw ArgumentError('accepted retry authority tuple is invalid');
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final bindingRows = await txn.query(
        'group_event_log',
        where: 'group_id = ? AND event_type = ?',
        whereArgs: <Object?>[groupId, kLocalSelfRemovedAcceptBindingEventType],
        orderBy: 'sequence DESC',
      );
      if (bindingRows.isEmpty) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedBindingMissing;
      }
      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedEvidenceInvalid;
      }

      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (current.shape !=
          SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedStateChanged;
      }

      final state = await _loadAcceptedStateFingerprint(txn, groupId);
      _AcceptedBindingEvidence? selected;
      var malformedBindingSeen = false;
      for (final row in bindingRows) {
        try {
          final candidate = _acceptedBindingFromEventRow(row);
          if (candidate.stateFingerprint == state.fingerprint) {
            selected = candidate;
            break;
          }
        } on GroupEventLogTamperException {
          malformedBindingSeen = true;
        } on FormatException {
          malformedBindingSeen = true;
        }
      }
      if (selected == null) {
        return malformedBindingSeen
            ? SelfRemovedGroupAcceptedRetryAuthorizationDisposition
                  .refusedEvidenceInvalid
            : SelfRemovedGroupAcceptedRetryAuthorizationDisposition
                  .refusedBindingMissing;
      }

      // Select the newest full-state match before comparing the still-pending
      // authorization so an older matching invite can never shadow it.
      if (selected.authorizationId != authorizationId) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedAuthorizationMismatch;
      }
      if (selected.groupHash != state.groupHash ||
          selected.rosterHash != state.rosterHash ||
          selected.keyHash != state.keyHash ||
          selected.draftHash != state.draftHash ||
          selected.selfPeerId != selfPeerId ||
          selected.signedMembershipWatermarkRaw != signedMembershipWatermark ||
          selected.signedIssuedAtRaw != signedIssuedAt ||
          selected.keyGeneration != keyGeneration ||
          selected.acceptedAtRaw != current._lastMembershipEventAtRaw ||
          current.lastMembershipEventId != null) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedStateChanged;
      }

      final origin = await _loadAcceptedOriginEvidence(
        txn,
        groupId: groupId,
        entryId: selected.originEntryId,
      );
      final floor = await _loadFreshnessFloorEvidence(
        txn,
        groupId: groupId,
        entryId: selected.floorEntryId,
      );
      if (!_bindingEvidenceMatchesOriginAndFloor(selected, origin, floor)) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedEvidenceInvalid;
      }

      final selfRows = await txn.query(
        'group_members',
        where: 'group_id = ? AND peer_id = ? AND joined_at = ?',
        whereArgs: <Object?>[groupId, selfPeerId, selected.selfJoinedAtRaw],
        limit: 1,
      );
      if (selfRows.length != 1 ||
          !_acceptedBindingKeyTupleStillPresent(selected, state)) {
        return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
            .refusedStateChanged;
      }
      return SelfRemovedGroupAcceptedRetryAuthorizationDisposition.authorized;
    });
  } on GroupEventLogTamperException {
    return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
        .refusedEvidenceInvalid;
  } on FormatException {
    return SelfRemovedGroupAcceptedRetryAuthorizationDisposition
        .refusedEvidenceInvalid;
  }
}

SelfRemovedGroupAcceptedRollbackQualificationResult
_acceptedRollbackQualificationSuccess({
  required SelfRemovedGroupShellAuthoritySnapshot current,
  required _AcceptedBindingEvidence binding,
  required _FreshnessFloorEvidence floor,
  required String authorizationId,
  required bool alreadyRolledBack,
}) => SelfRemovedGroupAcceptedRollbackQualificationResult(
  disposition:
      SelfRemovedGroupAcceptedRollbackQualificationDisposition.qualified,
  authority: current,
  binding: binding.binding,
  qualification: SelfRemovedGroupAcceptedRollbackQualification._(
    groupId: current.groupId,
    selfPeerId: current.selfPeerId,
    authorizationId: authorizationId,
    bindingEntryId: binding.binding.entryId,
    bindingSourceEventId: binding.binding.sourceEventId,
    bindingSequence: binding.binding.sequence,
    acceptedStateFingerprint: binding.stateFingerprint,
    floorEntryId: floor.floor.entryId,
    authorityShape: current.shape,
    selfRemovedAtRaw: current._selfRemovedAtRaw,
    lastMembershipEventAtRaw: current._lastMembershipEventAtRaw,
    lastMembershipEventId: current.lastMembershipEventId,
    selfJoinedAtRaw: current._selfJoinedAtRaw,
    alreadyRolledBack: alreadyRolledBack,
  ),
);

bool _acceptedRollbackQualificationMatches({
  required SelfRemovedGroupAcceptedRollbackQualification qualification,
  required SelfRemovedGroupShellAuthoritySnapshot current,
  required _AcceptedBindingEvidence binding,
  required _FreshnessFloorEvidence floor,
  required bool alreadyRolledBack,
}) =>
    qualification.groupId == current.groupId &&
    qualification.selfPeerId == current.selfPeerId &&
    qualification.authorizationId == binding.authorizationId &&
    qualification._bindingEntryId == binding.binding.entryId &&
    qualification._bindingSourceEventId == binding.binding.sourceEventId &&
    qualification._bindingSequence == binding.binding.sequence &&
    qualification._acceptedStateFingerprint == binding.stateFingerprint &&
    qualification._floorEntryId == floor.floor.entryId &&
    qualification._authorityShape == current.shape &&
    qualification._selfRemovedAtRaw == current._selfRemovedAtRaw &&
    qualification._lastMembershipEventAtRaw ==
        current._lastMembershipEventAtRaw &&
    qualification._lastMembershipEventId == current.lastMembershipEventId &&
    qualification._selfJoinedAtRaw == current._selfJoinedAtRaw &&
    qualification._alreadyRolledBack == alreadyRolledBack;

/// Rolls an accepted post-removal transition back to the exact shape encoded
/// by its newest full-state-matching binding.
Future<SelfRemovedGroupAcceptedRollbackResult>
dbRollbackSelfRemovedGroupAcceptedReentry(
  Database db, {
  required String groupId,
  required String selfPeerId,
  required String authorizationId,
  SelfRemovedGroupAcceptedRollbackQualification? qualification,
}) async {
  if (groupId.trim().isEmpty || selfPeerId.trim().isEmpty) {
    throw ArgumentError('groupId and selfPeerId are required');
  }
  if (qualification != null &&
      (qualification.groupId != groupId ||
          qualification.selfPeerId != selfPeerId ||
          qualification.authorizationId != authorizationId)) {
    throw ArgumentError('accepted rollback qualification tuple mismatch');
  }

  try {
    return await dbWriteTransaction(db, (txn) async {
      final bindingRows = await txn.query(
        'group_event_log',
        where: 'group_id = ? AND event_type = ?',
        whereArgs: <Object?>[groupId, kLocalSelfRemovedAcceptBindingEventType],
        orderBy: 'sequence DESC',
      );
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (bindingRows.isEmpty) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedBindingMissing,
          current,
        );
      }
      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
          current,
        );
      }
      if (current.shape !=
          SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent) {
        if (current.shape ==
                SelfRemovedGroupShellAuthorityShape.markedSelfAbsent ||
            current.shape == SelfRemovedGroupShellAuthorityShape.absent) {
          _AcceptedBindingEvidence? alreadyRolledBack;
          _FreshnessFloorEvidence? alreadyRolledBackFloor;
          var malformedPriorEvidenceSeen = false;
          for (final row in bindingRows) {
            try {
              final candidate = _acceptedBindingFromEventRow(row);
              final origin = await _loadAcceptedOriginEvidence(
                txn,
                groupId: groupId,
                entryId: candidate.originEntryId,
              );
              final floor = await _loadFreshnessFloorEvidence(
                txn,
                groupId: groupId,
                entryId: candidate.floorEntryId,
              );
              if (_bindingEvidenceMatchesOriginAndFloor(
                    candidate,
                    origin,
                    floor,
                  ) &&
                  await _currentStateMatchesRecordedPrior(
                    txn,
                    current: current,
                    binding: candidate,
                    floor: floor,
                  )) {
                alreadyRolledBack = candidate;
                alreadyRolledBackFloor = floor;
                break;
              }
            } on GroupEventLogTamperException {
              malformedPriorEvidenceSeen = true;
            } on FormatException {
              malformedPriorEvidenceSeen = true;
            }
          }
          if (alreadyRolledBack != null && alreadyRolledBackFloor != null) {
            if (alreadyRolledBack.authorizationId != authorizationId) {
              return _acceptedRollbackRefusal(
                SelfRemovedGroupAcceptedRollbackDisposition
                    .refusedAuthorizationMismatch,
                current,
                binding: alreadyRolledBack.binding,
              );
            }
            if (qualification != null &&
                !_acceptedRollbackQualificationMatches(
                  qualification: qualification,
                  current: current,
                  binding: alreadyRolledBack,
                  floor: alreadyRolledBackFloor,
                  alreadyRolledBack: true,
                )) {
              return _acceptedRollbackRefusal(
                SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
                current,
                binding: alreadyRolledBack.binding,
              );
            }
            return SelfRemovedGroupAcceptedRollbackResult(
              disposition:
                  SelfRemovedGroupAcceptedRollbackDisposition.rolledBack,
              authority: current,
              terminalization: _zeroTerminalization,
              prior: SelfRemovedGroupAcceptedReentryPrior(
                shape: alreadyRolledBack.priorShape,
                floor: alreadyRolledBackFloor.floor,
                keyReferences: <SelfRemovedGroupKeyReference>[
                  ...alreadyRolledBack.priorKeyRows,
                  ...alreadyRolledBack.priorDraftRows,
                ],
                markedAuthority:
                    alreadyRolledBack.priorShape ==
                        SelfRemovedGroupAcceptedReentryPriorShape.marked
                    ? current
                    : null,
              ),
              binding: alreadyRolledBack.binding,
            );
          }
          if (malformedPriorEvidenceSeen) {
            return _acceptedRollbackRefusal(
              SelfRemovedGroupAcceptedRollbackDisposition
                  .refusedEvidenceInvalid,
              current,
            );
          }
        }
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
          current,
        );
      }

      final state = await _loadAcceptedStateFingerprint(txn, groupId);
      _AcceptedBindingEvidence? selected;
      var malformedBindingSeen = false;
      for (final row in bindingRows) {
        try {
          final candidate = _acceptedBindingFromEventRow(row);
          if (candidate.stateFingerprint == state.fingerprint) {
            selected = candidate;
            break;
          }
        } on GroupEventLogTamperException {
          malformedBindingSeen = true;
        } on FormatException {
          malformedBindingSeen = true;
        }
      }
      if (selected == null) {
        return _acceptedRollbackRefusal(
          malformedBindingSeen
              ? SelfRemovedGroupAcceptedRollbackDisposition
                    .refusedEvidenceInvalid
              : SelfRemovedGroupAcceptedRollbackDisposition
                    .refusedBindingMissing,
          current,
        );
      }

      // Authorization is checked only after the newest full-state match is
      // selected. An older matching authorization must never shadow it.
      if (selected.authorizationId != authorizationId) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition
              .refusedAuthorizationMismatch,
          current,
          binding: selected.binding,
        );
      }
      if (selected.groupHash != state.groupHash ||
          selected.rosterHash != state.rosterHash ||
          selected.keyHash != state.keyHash ||
          selected.draftHash != state.draftHash ||
          selected.selfPeerId != selfPeerId ||
          selected.acceptedAtRaw != current._lastMembershipEventAtRaw ||
          current.lastMembershipEventId != null) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
          current,
          binding: selected.binding,
        );
      }

      final origin = await _loadAcceptedOriginEvidence(
        txn,
        groupId: groupId,
        entryId: selected.originEntryId,
      );
      final floorEvidence = await _loadFreshnessFloorEvidence(
        txn,
        groupId: groupId,
        entryId: selected.floorEntryId,
      );
      if (!_bindingEvidenceMatchesOriginAndFloor(
        selected,
        origin,
        floorEvidence,
      )) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
          current,
          binding: selected.binding,
        );
      }

      final selfRows = await txn.query(
        'group_members',
        where: 'group_id = ? AND peer_id = ? AND joined_at = ?',
        whereArgs: <Object?>[groupId, selfPeerId, selected.selfJoinedAtRaw],
        limit: 1,
      );
      if (selfRows.length != 1 ||
          !_acceptedBindingKeyTupleStillPresent(selected, state)) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
          current,
          binding: selected.binding,
        );
      }
      if (qualification != null &&
          !_acceptedRollbackQualificationMatches(
            qualification: qualification,
            current: current,
            binding: selected,
            floor: floorEvidence,
            alreadyRolledBack: false,
          )) {
        return _acceptedRollbackRefusal(
          SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
          current,
          binding: selected.binding,
        );
      }

      final terminalization = await dbTerminalizeSelfRemovedMembershipInstance(
        txn,
        groupId,
      );
      if (selected.priorShape ==
          SelfRemovedGroupAcceptedReentryPriorShape.marked) {
        final updated = await txn.rawUpdate(
          'UPDATE groups SET self_removed_at = ?, '
          'last_membership_event_at = ?, last_membership_event_id = ? '
          'WHERE id = ? AND self_removed_at IS NULL '
          'AND last_membership_event_at = ? '
          'AND last_membership_event_id IS NULL',
          <Object?>[
            floorEvidence.selfRemovedAtRaw,
            floorEvidence.lastMembershipEventAtRaw,
            floorEvidence.floor.lastMembershipEventId,
            groupId,
            selected.acceptedAtRaw,
          ],
        );
        if (updated != 1) throw const _AcceptedReentryStateChanged();
        final deletedSelf = await txn.delete(
          'group_members',
          where: 'group_id = ? AND peer_id = ? AND joined_at = ?',
          whereArgs: <Object?>[groupId, selfPeerId, selected.selfJoinedAtRaw],
        );
        if (deletedSelf != 1) throw const _AcceptedReentryStateChanged();
      } else {
        await txn.delete(
          'group_members',
          where: 'group_id = ?',
          whereArgs: <Object?>[groupId],
        );
        final deletedGroup = await txn.rawDelete(
          'DELETE FROM groups WHERE id = ? AND self_removed_at IS NULL '
          'AND last_membership_event_at = ? '
          'AND last_membership_event_id IS NULL '
          'AND EXISTS (SELECT 1 FROM group_keys key '
          'WHERE key.group_id = groups.id AND key.key_generation = ? '
          'AND key.encrypted_key = ? AND key.created_at = ?)',
          <Object?>[
            groupId,
            selected.acceptedAtRaw,
            selected.keyGeneration,
            selected.keyReference,
            selected.keyCreatedAtRaw,
          ],
        );
        if (deletedGroup != 1) throw const _AcceptedReentryStateChanged();
        await txn.delete(
          'group_key_rotation_drafts',
          where: 'group_id = ?',
          whereArgs: <Object?>[groupId],
        );
      }

      final restored = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      final expectedShape =
          selected.priorShape ==
              SelfRemovedGroupAcceptedReentryPriorShape.marked
          ? SelfRemovedGroupShellAuthorityShape.markedSelfAbsent
          : SelfRemovedGroupShellAuthorityShape.absent;
      if (restored.shape != expectedShape) {
        throw const _AcceptedReentryStateChanged();
      }
      final prior = SelfRemovedGroupAcceptedReentryPrior(
        shape: selected.priorShape,
        floor: floorEvidence.floor,
        keyReferences: <SelfRemovedGroupKeyReference>[
          ...selected.priorKeyRows,
          ...selected.priorDraftRows,
        ],
        markedAuthority:
            selected.priorShape ==
                SelfRemovedGroupAcceptedReentryPriorShape.marked
            ? restored
            : null,
      );
      return SelfRemovedGroupAcceptedRollbackResult(
        disposition: SelfRemovedGroupAcceptedRollbackDisposition.rolledBack,
        authority: restored,
        terminalization: terminalization,
        prior: prior,
        binding: selected.binding,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedRollbackRefusal(
      SelfRemovedGroupAcceptedRollbackDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedRollbackRefusal(
      SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedRollbackRefusal(
      SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

/// Deletes a prepared accepted address only while its original marked/floor
/// predicate and durable origin still match. Primary and mirrors must already
/// have been deleted by the caller.
Future<SelfRemovedGroupAcceptedReentryStageResult>
dbFinalizeSelfRemovedGroupAcceptedReentryStaging(
  Database db, {
  required SelfRemovedGroupAcceptedReentryPreparation preparation,
  required Map<String, Object?> stagedKeyRow,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      );
      if (!await _acceptedPreparationEvidenceIsExact(
            txn,
            preparation: preparation,
            current: current,
          ) ||
          _hashCanonicalValue(stagedKeyRow) !=
              preparation._stagedKeyFingerprint) {
        throw const _AcceptedReentryStateChanged();
      }
      final expected = await _acceptedStagedReference(
        txn,
        preparation.groupId,
        stagedKeyRow,
      );
      await _deleteExactAcceptedStagedReference(
        txn,
        current: current,
        expected: expected,
      );
      return SelfRemovedGroupAcceptedReentryStageResult(
        disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
        authority: current,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: preparation.groupId,
        selfPeerId: preparation.selfPeerId,
      ),
    );
  }
}

/// Final SQL leg of exact rollback. The accepted address remains enumerable
/// across the authority CAS and every external deletion; only this exact
/// marker/floor-bound transaction removes it.
Future<SelfRemovedGroupAcceptedReentryStageResult>
dbFinalizeSelfRemovedGroupAcceptedRollbackKey(
  Database db, {
  required String groupId,
  required String selfPeerId,
  required SelfRemovedGroupAcceptedReentryBinding binding,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      if (!await _hasValidGroupEventLogChain(txn, groupId)) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }
      final rows = await txn.query(
        'group_event_log',
        where: 'id = ? AND group_id = ? AND event_type = ?',
        whereArgs: <Object?>[
          binding.entryId,
          groupId,
          kLocalSelfRemovedAcceptBindingEventType,
        ],
        limit: 1,
      );
      if (rows.length != 1) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }
      final evidence = _acceptedBindingFromEventRow(rows.single);
      if (evidence.binding.sourceEventId != binding.sourceEventId ||
          evidence.binding.acceptedStateFingerprint !=
              binding.acceptedStateFingerprint ||
          evidence.binding.authorizationId != binding.authorizationId ||
          evidence.binding.encryptedKeyReference !=
              binding.encryptedKeyReference ||
          evidence.selfPeerId != selfPeerId) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
        );
      }
      final origin = await _loadAcceptedOriginEvidence(
        txn,
        groupId: groupId,
        entryId: evidence.originEntryId,
      );
      final floor = await _loadFreshnessFloorEvidence(
        txn,
        groupId: groupId,
        entryId: evidence.floorEntryId,
      );
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: groupId,
        selfPeerId: selfPeerId,
      );
      if (!_bindingEvidenceMatchesOriginAndFloor(evidence, origin, floor) ||
          !await _currentStateMatchesRecordedPrior(
            txn,
            current: current,
            binding: evidence,
            floor: floor,
          )) {
        throw const _AcceptedReentryStateChanged();
      }
      final expected = SelfRemovedGroupKeyReference._(
        kind: SelfRemovedGroupKeyReferenceKind.committed,
        groupId: groupId,
        keyGeneration: evidence.keyGeneration,
        encryptedKeyReference: evidence.keyReference,
        createdAt: _parseRequiredUtcColumn(
          evidence.keyCreatedAtRaw,
          'acceptedBinding.keyCreatedAt',
        ),
        createdAtRaw: evidence.keyCreatedAtRaw,
      );
      await _deleteExactAcceptedStagedReference(
        txn,
        current: current,
        expected: expected,
      );
      return SelfRemovedGroupAcceptedReentryStageResult(
        disposition: SelfRemovedGroupAcceptedReentryDisposition.committed,
        authority: current,
      );
    });
  } on _AcceptedReentryStateChanged {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStateChanged,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on _AcceptedReentryRefusal catch (error) {
    return _acceptedStageRefusal(
      error.disposition,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on GroupEventLogTamperException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  } on FormatException {
    return _acceptedStageRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedEvidenceInvalid,
      await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: selfPeerId,
      ),
    );
  }
}

Future<void> _deleteExactAcceptedStagedReference(
  DatabaseExecutor txn, {
  required SelfRemovedGroupShellAuthoritySnapshot current,
  required SelfRemovedGroupKeyReference expected,
}) async {
  final references = await _loadRawKeyReferences(txn, expected.groupId);
  if (references.isEmpty) return;
  if (!_sameReferences(references, <SelfRemovedGroupKeyReference>[expected]) ||
      (current.shape != SelfRemovedGroupShellAuthorityShape.markedSelfAbsent &&
          current.shape != SelfRemovedGroupShellAuthorityShape.absent)) {
    throw const _AcceptedReentryStateChanged();
  }
  final deleted = await txn.delete(
    'group_keys',
    where:
        'group_id = ? AND key_generation = ? AND encrypted_key = ? '
        'AND created_at = ?',
    whereArgs: <Object?>[
      expected.groupId,
      expected.keyGeneration,
      expected.encryptedKeyReference,
      expected._createdAtRaw,
    ],
  );
  if (deleted != 1) throw const _AcceptedReentryStateChanged();
}

Future<SelfRemovedGroupFreshnessFloorAppendResult>
dbAppendSelfRemovedGroupFreshnessFloor(
  Database db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  DateTime? createdAt,
}) {
  return dbWriteTransaction(db, (txn) {
    return dbAppendSelfRemovedGroupFreshnessFloorInTransaction(
      txn,
      expected: expected,
      createdAt: createdAt,
    );
  });
}

Future<SelfRemovedGroupFreshnessFloorAppendResult>
dbAppendSelfRemovedGroupFreshnessFloorInTransaction(
  DatabaseExecutor txn, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  DateTime? createdAt,
}) async {
  final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
    txn,
    groupId: expected.groupId,
    selfPeerId: expected.selfPeerId,
  );
  if (!_sameAuthority(current, expected) ||
      current.shape != SelfRemovedGroupShellAuthorityShape.markedSelfAbsent) {
    throw const SelfRemovedGroupShellStateChangedException();
  }

  final payload = _freshnessFloorPayload(current);
  final sourceEventId = _freshnessFloorSourceEventId(payload);
  final append = await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: current.groupId,
    eventType: kLocalSelfRemovedFreshnessFloorEventType,
    sourcePeerId: current.selfPeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: current._selfRemovedAtRaw!,
    payload: payload,
    createdAt: createdAt,
  );
  return SelfRemovedGroupFreshnessFloorAppendResult(
    floor: _freshnessFloorFromEventRow(append.row),
    inserted: append.inserted,
  );
}

Future<SelfRemovedGroupFreshnessFloor?>
dbLoadLatestSelfRemovedGroupFreshnessFloor(
  DatabaseExecutor db,
  String groupId,
) async {
  final rows = await db.query(
    'group_event_log',
    where: 'group_id = ? AND event_type = ?',
    whereArgs: <Object?>[groupId, kLocalSelfRemovedFreshnessFloorEventType],
    orderBy: 'sequence DESC',
    limit: 1,
  );
  return rows.isEmpty ? null : _freshnessFloorFromEventRow(rows.single);
}

Future<SelfRemovedGroupKeyReferenceLoadResult>
dbLoadRawSelfRemovedGroupKeyReferences(
  DatabaseExecutor db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
}) async {
  final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
    db,
    groupId: expected.groupId,
    selfPeerId: expected.selfPeerId,
  );
  if (!_sameAuthority(current, expected) ||
      current.shape != SelfRemovedGroupShellAuthorityShape.markedSelfAbsent) {
    return SelfRemovedGroupKeyReferenceLoadResult(
      disposition: SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
      authority: current,
      references: const <SelfRemovedGroupKeyReference>[],
    );
  }

  final references = await _loadRawKeyReferences(db, current.groupId);
  return SelfRemovedGroupKeyReferenceLoadResult(
    disposition: SelfRemovedGroupShellMutationDisposition.committed,
    authority: current,
    references: references,
  );
}

Future<SelfRemovedGroupShellMutationResult>
dbFinalizeSelfRemovedGroupKeyReferences(
  Database db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  required List<SelfRemovedGroupKeyReference> expectedReferences,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
      );
      if (!_sameAuthority(current, expected) ||
          current.shape !=
              SelfRemovedGroupShellAuthorityShape.markedSelfAbsent) {
        return SelfRemovedGroupShellMutationResult(
          disposition:
              SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
          authority: current,
        );
      }

      final stored = await _loadRawKeyReferences(txn, current.groupId);
      if (!_sameReferences(stored, expectedReferences)) {
        return SelfRemovedGroupShellMutationResult(
          disposition: SelfRemovedGroupShellMutationDisposition
              .refusedOutstandingReferences,
          authority: current,
        );
      }

      var deleted = 0;
      for (final reference in stored) {
        final table =
            reference.kind == SelfRemovedGroupKeyReferenceKind.committed
            ? 'group_keys'
            : 'group_key_rotation_drafts';
        final count = await txn.delete(
          table,
          where:
              'group_id = ? AND key_generation = ? AND encrypted_key = ? '
              'AND created_at = ?',
          whereArgs: <Object?>[
            reference.groupId,
            reference.keyGeneration,
            reference.encryptedKeyReference,
            reference._createdAtRaw,
          ],
        );
        if (count != 1) throw const _AuthorityCasLost();
        deleted += count;
      }
      return SelfRemovedGroupShellMutationResult(
        disposition: SelfRemovedGroupShellMutationDisposition.committed,
        authority: current,
        deletedRows: deleted,
      );
    });
  } on _AuthorityCasLost {
    final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
      db,
      groupId: expected.groupId,
      selfPeerId: expected.selfPeerId,
    );
    return SelfRemovedGroupShellMutationResult(
      disposition: SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
      authority: current,
    );
  }
}

Future<SelfRemovedGroupMediaParentLoadResult>
dbLoadSelfRemovedGroupMediaParents(
  DatabaseExecutor db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  int limit = kSelfRemovedShellMediaPrepareLimit,
}) async {
  if (limit < 1 || limit > kSelfRemovedShellMediaPrepareLimit) {
    throw RangeError.range(
      limit,
      1,
      kSelfRemovedShellMediaPrepareLimit,
      'limit',
    );
  }
  final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
    db,
    groupId: expected.groupId,
    selfPeerId: expected.selfPeerId,
  );
  if (!_sameAuthority(current, expected) ||
      current.shape != SelfRemovedGroupShellAuthorityShape.markedSelfAbsent) {
    return SelfRemovedGroupMediaParentLoadResult(
      disposition: SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
      authority: current,
      batch: const SelfRemovedGroupMediaParentBatch(
        parents: <SelfRemovedGroupMediaParent>[],
        hasOverflow: false,
      ),
    );
  }

  final rows = await db.rawQuery(
    'SELECT parent.id, parent.timestamp FROM group_messages parent '
    'WHERE parent.group_id = ? AND EXISTS ('
    'SELECT 1 FROM media_attachments attachment '
    "WHERE attachment.owner_lane = 'group' "
    'AND attachment.message_id = parent.id AND NOT EXISTS ('
    'SELECT 1 FROM group_media_deletion_journal journal '
    'WHERE journal.attachment_id = attachment.id '
    'AND journal.group_id = parent.group_id '
    'AND journal.message_id = parent.id '
    "AND journal.operation_intent = 'delete_for_me')) "
    'ORDER BY parent.timestamp ASC, parent.id ASC LIMIT ?',
    <Object?>[current.groupId, limit + 1],
  );
  final parents = rows
      .take(limit)
      .map((row) {
        return SelfRemovedGroupMediaParent(
          messageId: row['id'] as String,
          timestamp: _parseRequiredUtcColumn(
            row['timestamp'] as String,
            'group_messages.timestamp',
          ),
        );
      })
      .toList(growable: false);
  return SelfRemovedGroupMediaParentLoadResult(
    disposition: SelfRemovedGroupShellMutationDisposition.committed,
    authority: current,
    batch: SelfRemovedGroupMediaParentBatch(
      parents: parents,
      hasOverflow: rows.length > limit,
    ),
  );
}

/// Performs the final floor-bound, group-last SQL purge.
///
/// Media-bearing parents must already have passed the bounded canonical
/// delete-for-me preparation. Journal-owned attachment rows are intentionally
/// not touched here; their existing reconciler remains their sole owner.
Future<SelfRemovedGroupShellMutationResult> dbPurgeSelfRemovedGroupShell(
  Database db, {
  required SelfRemovedGroupShellAuthoritySnapshot expected,
  required SelfRemovedGroupFreshnessFloor floor,
  required DateTime deletedAt,
}) async {
  try {
    return await dbWriteTransaction(db, (txn) async {
      final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: expected.groupId,
        selfPeerId: expected.selfPeerId,
      );
      if (!_sameAuthority(current, expected) ||
          current.shape !=
              SelfRemovedGroupShellAuthorityShape.markedSelfAbsent) {
        return SelfRemovedGroupShellMutationResult(
          disposition:
              SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
          authority: current,
        );
      }
      if (!_floorMatchesAuthority(floor, current) ||
          !await _hasExactFreshnessFloor(txn, floor)) {
        return SelfRemovedGroupShellMutationResult(
          disposition:
              SelfRemovedGroupShellMutationDisposition.refusedFloorMissing,
          authority: current,
        );
      }

      final references = await _loadRawKeyReferences(txn, current.groupId);
      if (references.isNotEmpty) {
        return SelfRemovedGroupShellMutationResult(
          disposition: SelfRemovedGroupShellMutationDisposition
              .refusedOutstandingReferences,
          authority: current,
        );
      }

      final mediaParents = await txn.rawQuery(
        'SELECT 1 FROM group_messages parent WHERE parent.group_id = ? '
        'AND EXISTS (SELECT 1 FROM media_attachments attachment '
        "WHERE attachment.owner_lane = 'group' "
        'AND attachment.message_id = parent.id) LIMIT 1',
        <Object?>[current.groupId],
      );
      if (mediaParents.isNotEmpty) {
        return SelfRemovedGroupShellMutationResult(
          disposition:
              SelfRemovedGroupShellMutationDisposition.refusedMediaRemaining,
          authority: current,
        );
      }

      final tombstoneConflict = await txn.rawQuery(
        'SELECT 1 FROM group_messages message '
        'JOIN group_message_local_deletions tombstone '
        'ON tombstone.message_id = message.id '
        'WHERE message.group_id = ? AND tombstone.group_id <> ? LIMIT 1',
        <Object?>[current.groupId, current.groupId],
      );
      if (tombstoneConflict.isNotEmpty) {
        return SelfRemovedGroupShellMutationResult(
          disposition:
              SelfRemovedGroupShellMutationDisposition.refusedTombstoneConflict,
          authority: current,
        );
      }

      final deletedAtIso = deletedAt.toUtc().toIso8601String();
      await txn.rawInsert(
        'INSERT OR IGNORE INTO group_message_local_deletions '
        '(message_id, group_id, deleted_at, created_at) '
        'SELECT id, group_id, ?, ? FROM group_messages WHERE group_id = ?',
        <Object?>[deletedAtIso, deletedAtIso, current.groupId],
      );
      final deletedMessages = await txn.delete(
        'group_messages',
        where: 'group_id = ?',
        whereArgs: <Object?>[current.groupId],
      );
      final remainingMessages = await txn.rawQuery(
        'SELECT 1 FROM group_messages WHERE group_id = ? LIMIT 1',
        <Object?>[current.groupId],
      );
      if (remainingMessages.isNotEmpty) throw const _AuthorityCasLost();

      await _clearMembershipInstancePendingWork(txn, current.groupId);
      await txn.delete(
        'group_members',
        where: 'group_id = ?',
        whereArgs: <Object?>[current.groupId],
      );

      final groupDeleted = await txn.rawDelete(
        'DELETE FROM groups WHERE id = ? AND self_removed_at = ? '
        'AND last_membership_event_at IS ? '
        'AND last_membership_event_id IS ? '
        'AND NOT EXISTS (SELECT 1 FROM group_members member '
        'WHERE member.group_id = groups.id) '
        'AND NOT EXISTS (SELECT 1 FROM group_keys key '
        'WHERE key.group_id = groups.id) '
        'AND NOT EXISTS (SELECT 1 FROM group_key_rotation_drafts draft '
        'WHERE draft.group_id = groups.id)',
        <Object?>[
          current.groupId,
          current._selfRemovedAtRaw,
          current._lastMembershipEventAtRaw,
          current.lastMembershipEventId,
        ],
      );
      if (groupDeleted != 1) throw const _AuthorityCasLost();

      final absent = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        txn,
        groupId: current.groupId,
        selfPeerId: current.selfPeerId,
      );
      return SelfRemovedGroupShellMutationResult(
        disposition: SelfRemovedGroupShellMutationDisposition.committed,
        authority: absent,
        deletedRows: deletedMessages + groupDeleted,
      );
    });
  } on _AuthorityCasLost {
    final current = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
      db,
      groupId: expected.groupId,
      selfPeerId: expected.selfPeerId,
    );
    return SelfRemovedGroupShellMutationResult(
      disposition: SelfRemovedGroupShellMutationDisposition.refusedStateChanged,
      authority: current,
    );
  }
}

class SelfRemovedGroupShellStateChangedException implements Exception {
  const SelfRemovedGroupShellStateChangedException();

  @override
  String toString() => 'SelfRemovedGroupShellStateChangedException';
}

const SelfRemovedGroupShellTerminalizationCounts _zeroTerminalization =
    SelfRemovedGroupShellTerminalizationCounts(
      pendingRowsDeleted: 0,
      messagesTerminalized: 0,
      uploadsTerminalized: 0,
    );

Future<int> _clearMembershipInstancePendingWork(
  DatabaseExecutor txn,
  String groupId,
) async {
  var deleted = 0;
  for (final table in _membershipInstanceWorkTables) {
    if (!await _membershipWorkTableExists(txn, table)) continue;
    deleted += await txn.delete(
      table,
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
    );
  }
  deleted += await txn.delete(
    'group_reaction_replay_outbox',
    where: "group_id = ? AND delivery_status IN ('pending', 'failed')",
    whereArgs: <Object?>[groupId],
  );
  return deleted;
}

Future<bool> _membershipWorkTableExists(
  DatabaseExecutor db,
  String table,
) async {
  final rows = await db.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    <Object?>[table],
  );
  return rows.isNotEmpty;
}

Future<List<SelfRemovedGroupKeyReference>> _loadRawKeyReferences(
  DatabaseExecutor db,
  String groupId,
) async {
  final committedRows = await db.query(
    'group_keys',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
    orderBy: 'key_generation ASC',
  );
  final draftRows = await db.query(
    'group_key_rotation_drafts',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
    orderBy: 'key_generation ASC',
  );
  return <SelfRemovedGroupKeyReference>[
    ...committedRows.map(
      (row) =>
          _keyReferenceFromRow(row, SelfRemovedGroupKeyReferenceKind.committed),
    ),
    ...draftRows.map(
      (row) =>
          _keyReferenceFromRow(row, SelfRemovedGroupKeyReferenceKind.draft),
    ),
  ];
}

SelfRemovedGroupKeyReference _keyReferenceFromRow(
  Map<String, Object?> row,
  SelfRemovedGroupKeyReferenceKind kind,
) {
  final createdAtRaw = row['created_at'] as String;
  return SelfRemovedGroupKeyReference._(
    kind: kind,
    groupId: row['group_id'] as String,
    keyGeneration: (row['key_generation'] as num).toInt(),
    encryptedKeyReference: row['encrypted_key'] as String,
    createdAt: _parseRequiredUtcColumn(createdAtRaw, '${kind.name}.created_at'),
    createdAtRaw: createdAtRaw,
  );
}

bool _sameReferences(
  List<SelfRemovedGroupKeyReference> first,
  List<SelfRemovedGroupKeyReference> second,
) {
  if (first.length != second.length) return false;
  final firstIds = first.map((entry) => entry._exactIdentity).toList()..sort();
  final secondIds = second.map((entry) => entry._exactIdentity).toList()
    ..sort();
  for (var index = 0; index < firstIds.length; index++) {
    if (firstIds[index] != secondIds[index]) return false;
  }
  return true;
}

Map<String, Object?> _freshnessFloorPayload(
  SelfRemovedGroupShellAuthoritySnapshot authority,
) {
  return <String, Object?>{
    'schemaVersion': 1,
    'groupId': authority.groupId,
    'selfPeerId': authority.selfPeerId,
    'selfRemovedAt': authority._selfRemovedAtRaw,
    'lastMembershipEventAt': authority._lastMembershipEventAtRaw,
    'lastMembershipEventId': authority.lastMembershipEventId,
  };
}

String _freshnessFloorSourceEventId(Map<String, Object?> payload) {
  final digest = sha256
      .convert(utf8.encode(canonicalizeGroupEventLogPayload(payload)))
      .toString();
  return '$kLocalSelfRemovedFreshnessFloorEventType:$digest';
}

SelfRemovedGroupFreshnessFloor _freshnessFloorFromEventRow(
  Map<String, Object?> row,
) {
  if (row['event_type'] != kLocalSelfRemovedFreshnessFloorEventType) {
    throw GroupEventLogTamperException('unexpected freshness-floor event type');
  }
  final decoded = jsonDecode(row['canonical_payload'] as String);
  if (decoded is! Map<String, dynamic> ||
      decoded['schemaVersion'] != 1 ||
      decoded['groupId'] is! String ||
      decoded['selfPeerId'] is! String ||
      decoded['selfRemovedAt'] is! String ||
      (decoded['lastMembershipEventAt'] != null &&
          decoded['lastMembershipEventAt'] is! String) ||
      (decoded['lastMembershipEventId'] != null &&
          decoded['lastMembershipEventId'] is! String)) {
    throw GroupEventLogTamperException('malformed freshness-floor payload');
  }
  final payload = Map<String, Object?>.from(decoded);
  final expectedSourceId = _freshnessFloorSourceEventId(payload);
  if (row['group_id'] != decoded['groupId'] ||
      row['source_peer_id'] != decoded['selfPeerId'] ||
      row['source_timestamp'] != decoded['selfRemovedAt'] ||
      row['source_event_id'] != expectedSourceId) {
    throw GroupEventLogTamperException('freshness-floor identity mismatch');
  }
  return SelfRemovedGroupFreshnessFloor(
    entryId: row['id'] as String,
    sourceEventId: row['source_event_id'] as String,
    sequence: (row['sequence'] as num).toInt(),
    groupId: decoded['groupId'] as String,
    selfPeerId: decoded['selfPeerId'] as String,
    selfRemovedAt: _parseRequiredUtcColumn(
      decoded['selfRemovedAt'] as String,
      'freshnessFloor.selfRemovedAt',
    ),
    lastMembershipEventAt: _parseUtcColumn(
      decoded['lastMembershipEventAt'] as String?,
      'freshnessFloor.lastMembershipEventAt',
    ),
    lastMembershipEventId: decoded['lastMembershipEventId'] as String?,
  );
}

bool _floorMatchesAuthority(
  SelfRemovedGroupFreshnessFloor floor,
  SelfRemovedGroupShellAuthoritySnapshot authority,
) {
  return floor.groupId == authority.groupId &&
      floor.selfPeerId == authority.selfPeerId &&
      floor.selfRemovedAt.isAtSameMomentAs(authority.selfRemovedAt!) &&
      _sameNullableInstant(
        floor.lastMembershipEventAt,
        authority.lastMembershipEventAt,
      ) &&
      floor.lastMembershipEventId == authority.lastMembershipEventId;
}

Future<bool> _hasExactFreshnessFloor(
  DatabaseExecutor db,
  SelfRemovedGroupFreshnessFloor floor,
) async {
  final rows = await db.query(
    'group_event_log',
    where: 'id = ? AND group_id = ? AND event_type = ?',
    whereArgs: <Object?>[
      floor.entryId,
      floor.groupId,
      kLocalSelfRemovedFreshnessFloorEventType,
    ],
    limit: 1,
  );
  if (rows.isEmpty) return false;
  final stored = _freshnessFloorFromEventRow(rows.single);
  return stored.entryId == floor.entryId &&
      stored.sourceEventId == floor.sourceEventId &&
      stored.sequence == floor.sequence &&
      stored.groupId == floor.groupId &&
      stored.selfPeerId == floor.selfPeerId &&
      stored.selfRemovedAt.isAtSameMomentAs(floor.selfRemovedAt) &&
      _sameNullableInstant(
        stored.lastMembershipEventAt,
        floor.lastMembershipEventAt,
      ) &&
      stored.lastMembershipEventId == floor.lastMembershipEventId;
}

bool _sameAuthority(
  SelfRemovedGroupShellAuthoritySnapshot first,
  SelfRemovedGroupShellAuthoritySnapshot second,
) {
  return first.groupId == second.groupId &&
      first.selfPeerId == second.selfPeerId &&
      first.shape == second.shape &&
      first._selfRemovedAtRaw == second._selfRemovedAtRaw &&
      first._lastMembershipEventAtRaw == second._lastMembershipEventAtRaw &&
      first.lastMembershipEventId == second.lastMembershipEventId &&
      first._selfJoinedAtRaw == second._selfJoinedAtRaw;
}

bool _isStaleMembershipAuthority({
  required DateTime eventAt,
  required String eventId,
  required DateTime? lastAt,
  required String? lastId,
}) {
  final current = lastAt?.toUtc();
  if (current == null) return false;
  final normalized = eventAt.toUtc();
  if (normalized.isAfter(current)) return false;
  if (normalized.isBefore(current)) return true;
  if (lastId != null) return eventId.compareTo(lastId) <= 0;
  return true;
}

DateTime? _parseUtcColumn(String? value, String column) {
  if (value == null) return null;
  return _parseRequiredUtcColumn(value, column);
}

DateTime _parseRequiredUtcColumn(String value, String column) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('Invalid UTC timestamp in $column');
  }
  return parsed.toUtc();
}

bool _sameNullableInstant(DateTime? first, DateTime? second) {
  if (first == null || second == null) return first == second;
  return first.isAtSameMomentAs(second);
}

SelfRemovedGroupAcceptedReentryResult _acceptedReentryRefusal(
  SelfRemovedGroupAcceptedReentryDisposition disposition,
  SelfRemovedGroupShellAuthoritySnapshot authority,
) {
  return SelfRemovedGroupAcceptedReentryResult(
    disposition: disposition,
    authority: authority,
    terminalization: _zeroTerminalization,
  );
}

SelfRemovedGroupAcceptedReentryPreparationResult _acceptedPreparationRefusal(
  SelfRemovedGroupAcceptedReentryDisposition disposition,
  SelfRemovedGroupShellAuthoritySnapshot authority,
) {
  return SelfRemovedGroupAcceptedReentryPreparationResult(
    disposition: disposition,
    authority: authority,
  );
}

SelfRemovedGroupAcceptedReentryStageResult _acceptedStageRefusal(
  SelfRemovedGroupAcceptedReentryDisposition disposition,
  SelfRemovedGroupShellAuthoritySnapshot authority,
) {
  return SelfRemovedGroupAcceptedReentryStageResult(
    disposition: disposition,
    authority: authority,
  );
}

SelfRemovedGroupAcceptedRollbackResult _acceptedRollbackRefusal(
  SelfRemovedGroupAcceptedRollbackDisposition disposition,
  SelfRemovedGroupShellAuthoritySnapshot authority, {
  SelfRemovedGroupAcceptedReentryBinding? binding,
}) {
  return SelfRemovedGroupAcceptedRollbackResult(
    disposition: disposition,
    authority: authority,
    terminalization: _zeroTerminalization,
    binding: binding,
  );
}

class _AcceptedReentryMaterial {
  const _AcceptedReentryMaterial({
    required this.groupId,
    required this.groupRow,
    required this.rosterRows,
    required this.stagedKeyRow,
    required this.priorReferences,
    required this.selfPeerId,
    required this.selfJoinedAtRaw,
    required this.signedMembershipWatermarkRaw,
    required this.signedIssuedAtRaw,
    required this.acceptedAt,
    required this.acceptedAtRaw,
    required this.keyGeneration,
    required this.keyReference,
    required this.keyCreatedAtRaw,
  });

  final String groupId;
  final Map<String, Object?> groupRow;
  final List<Map<String, Object?>> rosterRows;
  final Map<String, Object?> stagedKeyRow;
  final List<SelfRemovedGroupKeyReference> priorReferences;
  final String selfPeerId;
  final String selfJoinedAtRaw;
  final String signedMembershipWatermarkRaw;
  final String signedIssuedAtRaw;
  final DateTime acceptedAt;
  final String acceptedAtRaw;
  final int keyGeneration;
  final String keyReference;
  final String keyCreatedAtRaw;
}

String _acceptedPreparationMaterialFingerprint(
  _AcceptedReentryMaterial material,
) {
  return _hashCanonicalValue(<String, Object?>{
    'group': material.groupRow,
    'roster': material.rosterRows,
    'stagedKey': material.stagedKeyRow,
    'priorReferences': material.priorReferences
        .map((reference) => reference._exactIdentity)
        .toList(growable: false),
    'selfPeerId': material.selfPeerId,
    'selfJoinedAt': material.selfJoinedAtRaw,
    'signedMembershipWatermark': material.signedMembershipWatermarkRaw,
    'signedIssuedAt': material.signedIssuedAtRaw,
    'acceptedAt': material.acceptedAtRaw,
  });
}

Future<SelfRemovedGroupKeyReference> _acceptedStagedReference(
  DatabaseExecutor db,
  String groupId,
  Map<String, Object?> row,
) async {
  final columns = await _loadTableColumns(db, 'group_keys');
  final stagedGroupId = row['group_id'];
  final generation = row['key_generation'];
  final encryptedKey = row['encrypted_key'];
  final createdAtRaw = row['created_at'];
  if (!_hasExactRowColumns(row, columns) ||
      stagedGroupId != groupId ||
      generation is! int ||
      generation < 0 ||
      encryptedKey is! String ||
      !isSecureStoreReference(encryptedKey) ||
      encryptedKey.length <= secureStoreReferencePrefix.length ||
      createdAtRaw is! String) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }
  final createdAt = _parseRequiredUtcColumn(
    createdAtRaw,
    'acceptedKey.created_at',
  );
  return SelfRemovedGroupKeyReference._(
    kind: SelfRemovedGroupKeyReferenceKind.committed,
    groupId: groupId,
    keyGeneration: generation,
    encryptedKeyReference: encryptedKey,
    createdAt: createdAt,
    createdAtRaw: createdAtRaw,
  );
}

bool _isAcceptedStagingReference(SelfRemovedGroupKeyReference reference) {
  if (!isSecureStoreReference(reference.encryptedKeyReference)) return false;
  final storeKey = secureStoreKeyFromReference(reference.encryptedKeyReference);
  final prefix =
      'group_key_material:${Uri.encodeComponent(reference.groupId)}:';
  return storeKey.startsWith(prefix) && storeKey.contains(':accepted:');
}

Future<bool> _acceptedPreparationEvidenceIsExact(
  DatabaseExecutor db, {
  required SelfRemovedGroupAcceptedReentryPreparation preparation,
  required SelfRemovedGroupShellAuthoritySnapshot current,
}) async {
  if (!await _hasValidGroupEventLogChain(db, preparation.groupId) ||
      !await _hasExactFreshnessFloor(db, preparation.prior.floor)) {
    return false;
  }
  final origin = await _loadAcceptedOriginEvidence(
    db,
    groupId: preparation.groupId,
    entryId: preparation.originEntryId,
  );
  if (origin.entryId != preparation.originEntryId ||
      origin.sourceEventId != preparation.originSourceEventId ||
      origin.groupId != preparation.groupId ||
      origin.selfPeerId != preparation.selfPeerId ||
      origin.authorizationId != preparation.authorizationId ||
      origin.floorEntryId != preparation.prior.floor.entryId ||
      origin.floorSourceEventId != preparation.prior.floor.sourceEventId ||
      origin.priorShape != preparation.prior.shape) {
    return false;
  }
  return switch (preparation.prior.shape) {
    SelfRemovedGroupAcceptedReentryPriorShape.marked =>
      preparation.prior.markedAuthority != null &&
          _sameAuthority(current, preparation.prior.markedAuthority!) &&
          current.shape == SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
    SelfRemovedGroupAcceptedReentryPriorShape.absentWithFloor =>
      current.shape == SelfRemovedGroupShellAuthorityShape.absent,
  };
}

Future<_AcceptedReentryMaterial> _validateAcceptedReentryMaterial(
  DatabaseExecutor txn, {
  required String groupId,
  required Map<String, Object?> groupRow,
  required List<Map<String, Object?>> rosterRows,
  required Map<String, Object?> stagedKeyRow,
  required String selfPeerId,
  required String authorizationId,
  required String signedMembershipWatermark,
  required String signedIssuedAt,
  required String bindingNonce,
  required SelfRemovedGroupShellAuthoritySnapshot current,
  required SelfRemovedGroupFreshnessFloor? retainedFloor,
  List<SelfRemovedGroupKeyReference>? expectedPriorReferences,
}) async {
  if (authorizationId.trim().isEmpty || bindingNonce.trim().isEmpty) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }

  final signedWatermark = _parseAcceptedAuthorityInstant(
    signedMembershipWatermark,
    'signedMembershipWatermark',
  );
  final issuedAt = _parseAcceptedAuthorityInstant(
    signedIssuedAt,
    'signedIssuedAt',
  );
  final floorInstants = <DateTime>[
    if (current.selfRemovedAt != null) current.selfRemovedAt!,
    if (current.lastMembershipEventAt != null) current.lastMembershipEventAt!,
    if (retainedFloor != null) retainedFloor.selfRemovedAt,
    if (retainedFloor?.lastMembershipEventAt != null)
      retainedFloor!.lastMembershipEventAt!,
  ];
  if (floorInstants.isEmpty) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedMissingFloor,
    );
  }
  var greatestFloor = floorInstants.first;
  for (final instant in floorInstants.skip(1)) {
    if (instant.isAfter(greatestFloor)) greatestFloor = instant;
  }
  if (signedWatermark.isBefore(greatestFloor) ||
      !issuedAt.isAfter(greatestFloor)) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStaleAuthority,
    );
  }
  final acceptedAt = signedWatermark.isAfter(issuedAt)
      ? signedWatermark
      : issuedAt;
  final acceptedAtRaw = acceptedAt.toUtc().toIso8601String();

  final groupColumns = await _loadTableColumns(txn, 'groups');
  final memberColumns = await _loadTableColumns(txn, 'group_members');
  final keyColumns = await _loadTableColumns(txn, 'group_keys');
  if (!_hasExactRowColumns(groupRow, groupColumns) ||
      !_hasExactRowColumns(stagedKeyRow, keyColumns) ||
      rosterRows.isEmpty ||
      rosterRows.any((row) => !_hasExactRowColumns(row, memberColumns))) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }

  final normalizedGroup = Map<String, Object?>.from(groupRow);
  if (normalizedGroup['id'] != groupId ||
      !_hasValidAcceptedGroupTimestamps(normalizedGroup)) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }
  normalizedGroup['self_removed_at'] = null;
  normalizedGroup['last_membership_event_at'] = acceptedAtRaw;
  normalizedGroup['last_membership_event_id'] = null;

  final peerIds = <String>{};
  String? selfJoinedAtRaw;
  DateTime? selfJoinedAt;
  final normalizedRoster = <Map<String, Object?>>[];
  for (final row in rosterRows) {
    final groupValue = row['group_id'];
    final peerId = row['peer_id'];
    final joinedAt = row['joined_at'];
    if (groupValue != groupId ||
        peerId is! String ||
        peerId.trim().isEmpty ||
        !peerIds.add(peerId) ||
        joinedAt is! String) {
      throw const _AcceptedReentryRefusal(
        SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
      );
    }
    late final DateTime parsedJoinedAt;
    try {
      parsedJoinedAt = _parseRequiredUtcColumn(
        joinedAt,
        'acceptedRoster.joined_at',
      );
    } on FormatException {
      throw const _AcceptedReentryRefusal(
        SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
      );
    }
    if (peerId == selfPeerId) {
      if (selfJoinedAtRaw != null) {
        throw const _AcceptedReentryRefusal(
          SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
        );
      }
      selfJoinedAtRaw = joinedAt;
      selfJoinedAt = parsedJoinedAt;
    }
    normalizedRoster.add(Map<String, Object?>.from(row));
  }
  if (selfJoinedAtRaw == null) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }
  if (!selfJoinedAt!.isAfter(greatestFloor)) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedStaleAuthority,
    );
  }

  final stagedGroupId = stagedKeyRow['group_id'];
  final stagedGeneration = stagedKeyRow['key_generation'];
  final stagedReference = stagedKeyRow['encrypted_key'];
  final stagedCreatedAt = stagedKeyRow['created_at'];
  if (stagedGroupId != groupId ||
      stagedGeneration is! int ||
      stagedGeneration < 0 ||
      stagedReference is! String ||
      !isSecureStoreReference(stagedReference) ||
      stagedReference.length <= secureStoreReferencePrefix.length ||
      stagedCreatedAt is! String) {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }
  try {
    _parseRequiredUtcColumn(stagedCreatedAt, 'acceptedKey.created_at');
  } on FormatException {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
    );
  }

  final priorReferences =
      expectedPriorReferences ?? await _loadRawKeyReferences(txn, groupId);
  for (final reference in priorReferences) {
    if (!isSecureStoreReference(reference.encryptedKeyReference)) {
      throw const _AcceptedReentryRefusal(
        SelfRemovedGroupAcceptedReentryDisposition.refusedKeyState,
      );
    }
  }

  return _AcceptedReentryMaterial(
    groupId: groupId,
    groupRow: normalizedGroup,
    rosterRows: List<Map<String, Object?>>.unmodifiable(normalizedRoster),
    stagedKeyRow: Map<String, Object?>.from(stagedKeyRow),
    priorReferences: List<SelfRemovedGroupKeyReference>.unmodifiable(
      priorReferences,
    ),
    selfPeerId: selfPeerId,
    selfJoinedAtRaw: selfJoinedAtRaw,
    signedMembershipWatermarkRaw: signedMembershipWatermark,
    signedIssuedAtRaw: signedIssuedAt,
    acceptedAt: acceptedAt,
    acceptedAtRaw: acceptedAtRaw,
    keyGeneration: stagedGeneration,
    keyReference: stagedReference,
    keyCreatedAtRaw: stagedCreatedAt,
  );
}

DateTime _parseAcceptedAuthorityInstant(String value, String field) {
  try {
    return _parseRequiredUtcColumn(value, field);
  } on FormatException {
    throw const _AcceptedReentryRefusal(
      SelfRemovedGroupAcceptedReentryDisposition.refusedMalformedAuthority,
    );
  }
}

Future<Set<String>> _loadTableColumns(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'] as String).toSet();
}

bool _hasExactRowColumns(Map<String, Object?> row, Set<String> columns) {
  return row.length == columns.length && row.keys.toSet().containsAll(columns);
}

bool _hasValidAcceptedGroupTimestamps(Map<String, Object?> row) {
  for (final column in const <String>[
    'created_at',
    'dissolved_at',
    'archived_at',
    'last_membership_event_at',
    'self_removed_at',
    'last_metadata_event_at',
    'last_backlog_expired_at',
    'last_backlog_retained_at',
  ]) {
    final value = row[column];
    if (value == null && column != 'created_at') continue;
    if (value is! String) return false;
    try {
      _parseRequiredUtcColumn(value, 'acceptedGroup.$column');
    } on FormatException {
      return false;
    }
  }
  return true;
}

Future<void> _materializeAcceptedReentryState(
  DatabaseExecutor txn, {
  required SelfRemovedGroupAcceptedReentryPrior prior,
  required SelfRemovedGroupShellAuthoritySnapshot expectedMarkedAuthority,
  required _AcceptedReentryMaterial material,
}) async {
  if (prior.shape == SelfRemovedGroupAcceptedReentryPriorShape.marked) {
    final updated = await txn.update(
      'groups',
      material.groupRow,
      where:
          'id = ? AND self_removed_at = ? '
          'AND last_membership_event_at IS ? '
          'AND last_membership_event_id IS ? '
          'AND NOT EXISTS (SELECT 1 FROM group_members member '
          'WHERE member.group_id = groups.id AND member.peer_id = ?)',
      whereArgs: <Object?>[
        material.groupId,
        expectedMarkedAuthority._selfRemovedAtRaw,
        expectedMarkedAuthority._lastMembershipEventAtRaw,
        expectedMarkedAuthority.lastMembershipEventId,
        material.selfPeerId,
      ],
    );
    if (updated != 1) throw const _AcceptedReentryStateChanged();
  } else {
    await txn.insert(
      'groups',
      material.groupRow,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  await txn.delete(
    'group_members',
    where: 'group_id = ?',
    whereArgs: <Object?>[material.groupId],
  );
  for (final row in material.rosterRows) {
    await txn.insert(
      'group_members',
      row,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  await txn.delete(
    'group_key_rotation_drafts',
    where: 'group_id = ?',
    whereArgs: <Object?>[material.groupId],
  );
  // The accepted key row was persisted before primary secure material. Keep
  // that exact address in place; the surrounding transaction only activates
  // it by materializing group/self/roster and the durable binding.
}

class _AcceptedOriginEvidence {
  const _AcceptedOriginEvidence({
    required this.entryId,
    required this.sourceEventId,
    required this.sequence,
    required this.groupId,
    required this.selfPeerId,
    required this.authorizationId,
    required this.floorEntryId,
    required this.floorSourceEventId,
    required this.priorShape,
    required this.floorSelfRemovedAtRaw,
  });

  final String entryId;
  final String sourceEventId;
  final int sequence;
  final String groupId;
  final String selfPeerId;
  final String authorizationId;
  final String floorEntryId;
  final String floorSourceEventId;
  final SelfRemovedGroupAcceptedReentryPriorShape priorShape;
  final String floorSelfRemovedAtRaw;
}

Future<_AcceptedOriginEvidence> _appendAcceptedReentryOrigin(
  DatabaseExecutor txn, {
  required SelfRemovedGroupAcceptedReentryPrior prior,
  required String authorizationId,
  required String selfPeerId,
  required DateTime? createdAt,
}) async {
  final floorEvidence = await _loadFreshnessFloorEvidence(
    txn,
    groupId: prior.floor.groupId,
    entryId: prior.floor.entryId,
  );
  final payload = <String, Object?>{
    'schemaVersion': 1,
    'groupId': prior.floor.groupId,
    'selfPeerId': selfPeerId,
    'authorizationId': authorizationId,
    'floorEntryId': prior.floor.entryId,
    'floorSourceEventId': prior.floor.sourceEventId,
    'priorShape': prior.shape.name,
    'floorSelfRemovedAt': floorEvidence.selfRemovedAtRaw,
  };
  final sourceEventId = _acceptedOriginSourceEventId(payload);
  final append = await dbAppendGroupEventLogEntryInTransaction(
    txn,
    groupId: prior.floor.groupId,
    eventType: kLocalSelfRemovedAcceptOriginEventType,
    sourcePeerId: selfPeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: floorEvidence.selfRemovedAtRaw,
    payload: payload,
    createdAt: createdAt,
  );
  return _acceptedOriginFromEventRow(append.row);
}

String _acceptedOriginSourceEventId(Map<String, Object?> payload) {
  final digest = sha256
      .convert(utf8.encode(canonicalizeGroupEventLogPayload(payload)))
      .toString();
  return '$kLocalSelfRemovedAcceptOriginEventType:$digest';
}

_AcceptedOriginEvidence _acceptedOriginFromEventRow(Map<String, Object?> row) {
  if (row['event_type'] != kLocalSelfRemovedAcceptOriginEventType) {
    throw GroupEventLogTamperException('unexpected accepted-origin type');
  }
  final decoded = jsonDecode(row['canonical_payload'] as String);
  if (decoded is! Map<String, dynamic> ||
      decoded['schemaVersion'] != 1 ||
      decoded['groupId'] is! String ||
      decoded['selfPeerId'] is! String ||
      decoded['authorizationId'] is! String ||
      decoded['floorEntryId'] is! String ||
      decoded['floorSourceEventId'] is! String ||
      decoded['priorShape'] is! String ||
      decoded['floorSelfRemovedAt'] is! String) {
    throw GroupEventLogTamperException('malformed accepted-origin payload');
  }
  final shape = _parseAcceptedPriorShape(decoded['priorShape'] as String);
  final payload = Map<String, Object?>.from(decoded);
  final expectedSourceId = _acceptedOriginSourceEventId(payload);
  if (row['group_id'] != decoded['groupId'] ||
      row['source_peer_id'] != decoded['selfPeerId'] ||
      row['source_event_id'] != expectedSourceId ||
      row['source_timestamp'] != decoded['floorSelfRemovedAt']) {
    throw GroupEventLogTamperException('accepted-origin identity mismatch');
  }
  _parseRequiredUtcColumn(
    decoded['floorSelfRemovedAt'] as String,
    'acceptedOrigin.floorSelfRemovedAt',
  );
  return _AcceptedOriginEvidence(
    entryId: row['id'] as String,
    sourceEventId: row['source_event_id'] as String,
    sequence: (row['sequence'] as num).toInt(),
    groupId: decoded['groupId'] as String,
    selfPeerId: decoded['selfPeerId'] as String,
    authorizationId: decoded['authorizationId'] as String,
    floorEntryId: decoded['floorEntryId'] as String,
    floorSourceEventId: decoded['floorSourceEventId'] as String,
    priorShape: shape,
    floorSelfRemovedAtRaw: decoded['floorSelfRemovedAt'] as String,
  );
}

SelfRemovedGroupAcceptedReentryPriorShape _parseAcceptedPriorShape(
  String value,
) {
  for (final shape in SelfRemovedGroupAcceptedReentryPriorShape.values) {
    if (shape.name == value) return shape;
  }
  throw GroupEventLogTamperException('unknown accepted prior shape');
}

class _AcceptedStateFingerprint {
  const _AcceptedStateFingerprint({
    required this.groupRow,
    required this.rosterRows,
    required this.keyRows,
    required this.draftRows,
    required this.groupHash,
    required this.rosterHash,
    required this.keyHash,
    required this.draftHash,
    required this.fingerprint,
  });

  final Map<String, Object?> groupRow;
  final List<Map<String, Object?>> rosterRows;
  final List<Map<String, Object?>> keyRows;
  final List<Map<String, Object?>> draftRows;
  final String groupHash;
  final String rosterHash;
  final String keyHash;
  final String draftHash;
  final String fingerprint;
}

Future<_AcceptedStateFingerprint> _loadAcceptedStateFingerprint(
  DatabaseExecutor db,
  String groupId,
) async {
  final groupRows = await db.query(
    'groups',
    where: 'id = ?',
    whereArgs: <Object?>[groupId],
    limit: 2,
  );
  if (groupRows.length != 1) throw const _AcceptedReentryStateChanged();
  final rosterRows = await db.query(
    'group_members',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
  );
  final keyRows = await db.query(
    'group_keys',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
  );
  final draftRows = await db.query(
    'group_key_rotation_drafts',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
  );
  final canonicalRoster = _sortRowsCanonically(rosterRows);
  final canonicalKeys = _sortRowsCanonically(keyRows);
  final canonicalDrafts = _sortRowsCanonically(draftRows);
  final groupRow = Map<String, Object?>.from(groupRows.single);
  final groupHash = _hashCanonicalValue(groupRow);
  final rosterHash = _hashCanonicalValue(canonicalRoster);
  final keyHash = _hashCanonicalValue(canonicalKeys);
  final draftHash = _hashCanonicalValue(canonicalDrafts);
  final fingerprint = _hashCanonicalValue(<String, Object?>{
    'schemaVersion': 1,
    'group': groupRow,
    'roster': canonicalRoster,
    'keys': canonicalKeys,
    'drafts': canonicalDrafts,
  });
  return _AcceptedStateFingerprint(
    groupRow: groupRow,
    rosterRows: canonicalRoster,
    keyRows: canonicalKeys,
    draftRows: canonicalDrafts,
    groupHash: groupHash,
    rosterHash: rosterHash,
    keyHash: keyHash,
    draftHash: draftHash,
    fingerprint: fingerprint,
  );
}

List<Map<String, Object?>> _sortRowsCanonically(
  List<Map<String, Object?>> rows,
) {
  final copied = rows.map(Map<String, Object?>.from).toList();
  copied.sort(
    (first, second) =>
        _canonicalValue(first).compareTo(_canonicalValue(second)),
  );
  return List<Map<String, Object?>>.unmodifiable(copied);
}

String _canonicalValue(Object? value) {
  return canonicalizeGroupEventLogPayload(<String, Object?>{'value': value});
}

String _hashCanonicalValue(Object? value) {
  return sha256.convert(utf8.encode(_canonicalValue(value))).toString();
}

Future<bool> _hasValidGroupEventLogChain(
  DatabaseExecutor db,
  String groupId,
) async {
  final rows = await db.query(
    'group_event_log',
    where: 'group_id = ?',
    whereArgs: <Object?>[groupId],
    orderBy: 'sequence ASC',
  );
  var expectedSequence = 1;
  String? previousHash;
  for (final row in rows) {
    final sequence = row['sequence'];
    final eventType = row['event_type'];
    final sourcePeerId = row['source_peer_id'];
    final sourceEventId = row['source_event_id'];
    final sourceTimestamp = row['source_timestamp'];
    final canonicalPayload = row['canonical_payload'];
    final createdAt = row['created_at'];
    final storedPreviousHash = row['previous_entry_hash'];
    final storedHash = row['entry_hash'];
    if (row['group_id'] != groupId ||
        sequence is! int ||
        sequence != expectedSequence ||
        eventType is! String ||
        sourcePeerId is! String ||
        sourceEventId is! String ||
        sourceTimestamp is! String ||
        canonicalPayload is! String ||
        createdAt is! String ||
        (storedPreviousHash != null && storedPreviousHash is! String) ||
        storedPreviousHash != previousHash ||
        storedHash is! String) {
      return false;
    }
    final recomputed = sha256
        .convert(
          utf8.encode(
            canonicalizeGroupEventLogPayload(<String, Object?>{
              'groupId': groupId,
              'sequence': sequence,
              'eventType': eventType,
              'sourcePeerId': sourcePeerId,
              'sourceEventId': sourceEventId,
              'sourceTimestamp': sourceTimestamp,
              'canonicalPayload': canonicalPayload,
              'previousEntryHash': storedPreviousHash,
              'createdAt': createdAt,
            }),
          ),
        )
        .toString();
    if (recomputed != storedHash) return false;
    previousHash = storedHash;
    expectedSequence++;
  }
  return true;
}

Map<String, Object?> _acceptedBindingPayload({
  required _AcceptedReentryMaterial material,
  required SelfRemovedGroupAcceptedReentryPrior prior,
  required _AcceptedOriginEvidence origin,
  required String authorizationId,
  required String bindingNonce,
  required _AcceptedStateFingerprint state,
}) {
  return <String, Object?>{
    'schemaVersion': 1,
    'groupId': material.groupId,
    'selfPeerId': material.selfPeerId,
    'authorizationId': authorizationId,
    'originEntryId': origin.entryId,
    'originSourceEventId': origin.sourceEventId,
    'floorEntryId': prior.floor.entryId,
    'floorSourceEventId': prior.floor.sourceEventId,
    'priorShape': prior.shape.name,
    'bindingNonce': bindingNonce,
    'signedMembershipWatermark': material.signedMembershipWatermarkRaw,
    'signedIssuedAt': material.signedIssuedAtRaw,
    'acceptedAt': material.acceptedAtRaw,
    'lastMembershipEventId': null,
    'selfJoinedAt': material.selfJoinedAtRaw,
    'keyGeneration': material.keyGeneration,
    'keyReference': material.keyReference,
    'keyCreatedAt': material.keyCreatedAtRaw,
    'priorKeyRows': prior.keyReferences
        .where(
          (reference) =>
              reference.kind == SelfRemovedGroupKeyReferenceKind.committed,
        )
        .map(_keyReferencePayload)
        .toList(growable: false),
    'priorDraftRows': prior.keyReferences
        .where(
          (reference) =>
              reference.kind == SelfRemovedGroupKeyReferenceKind.draft,
        )
        .map(_keyReferencePayload)
        .toList(growable: false),
    'groupHash': state.groupHash,
    'rosterHash': state.rosterHash,
    'keyHash': state.keyHash,
    'draftHash': state.draftHash,
    'acceptedStateFingerprint': state.fingerprint,
  };
}

Map<String, Object?> _keyReferencePayload(
  SelfRemovedGroupKeyReference reference,
) {
  return <String, Object?>{
    'groupId': reference.groupId,
    'keyGeneration': reference.keyGeneration,
    'keyReference': reference.encryptedKeyReference,
    'createdAt': reference._createdAtRaw,
  };
}

String _acceptedBindingSourceEventId(
  String originEntryId,
  String bindingNonce,
) {
  final identity = canonicalizeGroupEventLogPayload(<String, Object?>{
    'originEntryId': originEntryId,
    'bindingNonce': bindingNonce,
  });
  final digest = sha256.convert(utf8.encode(identity)).toString();
  return '$kLocalSelfRemovedAcceptBindingEventType:$digest';
}

class _AcceptedBindingEvidence {
  const _AcceptedBindingEvidence({
    required this.binding,
    required this.groupId,
    required this.selfPeerId,
    required this.authorizationId,
    required this.originEntryId,
    required this.originSourceEventId,
    required this.floorEntryId,
    required this.floorSourceEventId,
    required this.priorShape,
    required this.bindingNonce,
    required this.signedMembershipWatermarkRaw,
    required this.signedIssuedAtRaw,
    required this.acceptedAtRaw,
    required this.selfJoinedAtRaw,
    required this.keyGeneration,
    required this.keyReference,
    required this.keyCreatedAtRaw,
    required this.priorKeyRows,
    required this.priorDraftRows,
    required this.groupHash,
    required this.rosterHash,
    required this.keyHash,
    required this.draftHash,
    required this.stateFingerprint,
  });

  final SelfRemovedGroupAcceptedReentryBinding binding;
  final String groupId;
  final String selfPeerId;
  final String authorizationId;
  final String originEntryId;
  final String originSourceEventId;
  final String floorEntryId;
  final String floorSourceEventId;
  final SelfRemovedGroupAcceptedReentryPriorShape priorShape;
  final String bindingNonce;
  final String signedMembershipWatermarkRaw;
  final String signedIssuedAtRaw;
  final String acceptedAtRaw;
  final String selfJoinedAtRaw;
  final int keyGeneration;
  final String keyReference;
  final String keyCreatedAtRaw;
  final List<SelfRemovedGroupKeyReference> priorKeyRows;
  final List<SelfRemovedGroupKeyReference> priorDraftRows;
  final String groupHash;
  final String rosterHash;
  final String keyHash;
  final String draftHash;
  final String stateFingerprint;
}

_AcceptedBindingEvidence _acceptedBindingFromEventRow(
  Map<String, Object?> row,
) {
  if (row['event_type'] != kLocalSelfRemovedAcceptBindingEventType) {
    throw GroupEventLogTamperException('unexpected accepted-binding type');
  }
  final decoded = jsonDecode(row['canonical_payload'] as String);
  if (decoded is! Map<String, dynamic> ||
      decoded['schemaVersion'] != 1 ||
      decoded['groupId'] is! String ||
      decoded['selfPeerId'] is! String ||
      decoded['authorizationId'] is! String ||
      decoded['originEntryId'] is! String ||
      decoded['originSourceEventId'] is! String ||
      decoded['floorEntryId'] is! String ||
      decoded['floorSourceEventId'] is! String ||
      decoded['priorShape'] is! String ||
      decoded['bindingNonce'] is! String ||
      decoded['signedMembershipWatermark'] is! String ||
      decoded['signedIssuedAt'] is! String ||
      decoded['acceptedAt'] is! String ||
      decoded['lastMembershipEventId'] != null ||
      decoded['selfJoinedAt'] is! String ||
      decoded['keyGeneration'] is! int ||
      decoded['keyReference'] is! String ||
      decoded['keyCreatedAt'] is! String ||
      decoded['priorKeyRows'] is! List<dynamic> ||
      decoded['priorDraftRows'] is! List<dynamic> ||
      decoded['groupHash'] is! String ||
      decoded['rosterHash'] is! String ||
      decoded['keyHash'] is! String ||
      decoded['draftHash'] is! String ||
      decoded['acceptedStateFingerprint'] is! String) {
    throw GroupEventLogTamperException('malformed accepted-binding payload');
  }
  final originEntryId = decoded['originEntryId'] as String;
  final bindingNonce = decoded['bindingNonce'] as String;
  final keyGeneration = decoded['keyGeneration'] as int;
  final keyReference = decoded['keyReference'] as String;
  if ((decoded['groupId'] as String).isEmpty ||
      (decoded['selfPeerId'] as String).isEmpty ||
      (decoded['authorizationId'] as String).isEmpty ||
      originEntryId.isEmpty ||
      bindingNonce.isEmpty ||
      keyGeneration < 0 ||
      keyReference.length <= secureStoreReferencePrefix.length) {
    throw GroupEventLogTamperException('empty accepted-binding identity');
  }
  final expectedSourceId = _acceptedBindingSourceEventId(
    originEntryId,
    bindingNonce,
  );
  if (row['group_id'] != decoded['groupId'] ||
      row['source_peer_id'] != decoded['selfPeerId'] ||
      row['source_event_id'] != expectedSourceId ||
      row['source_timestamp'] != decoded['acceptedAt']) {
    throw GroupEventLogTamperException('accepted-binding identity mismatch');
  }
  final acceptedAt = _parseRequiredUtcColumn(
    decoded['acceptedAt'] as String,
    'acceptedBinding.acceptedAt',
  );
  final signedWatermark = _parseRequiredUtcColumn(
    decoded['signedMembershipWatermark'] as String,
    'acceptedBinding.signedMembershipWatermark',
  );
  final signedIssuedAt = _parseRequiredUtcColumn(
    decoded['signedIssuedAt'] as String,
    'acceptedBinding.signedIssuedAt',
  );
  final expectedAcceptedAt = signedWatermark.isAfter(signedIssuedAt)
      ? signedWatermark
      : signedIssuedAt;
  if (!expectedAcceptedAt.isAtSameMomentAs(acceptedAt)) {
    throw GroupEventLogTamperException('accepted-binding authority mismatch');
  }
  _parseRequiredUtcColumn(
    decoded['selfJoinedAt'] as String,
    'acceptedBinding.selfJoinedAt',
  );
  final keyCreatedAt = _parseRequiredUtcColumn(
    decoded['keyCreatedAt'] as String,
    'acceptedBinding.keyCreatedAt',
  );
  if (!isSecureStoreReference(keyReference)) {
    throw GroupEventLogTamperException(
      'accepted-binding key is not a reference',
    );
  }
  final groupId = decoded['groupId'] as String;
  final priorKeys = _keyReferencesFromBindingPayload(
    decoded['priorKeyRows'] as List<dynamic>,
    groupId: groupId,
    kind: SelfRemovedGroupKeyReferenceKind.committed,
  );
  final priorDrafts = _keyReferencesFromBindingPayload(
    decoded['priorDraftRows'] as List<dynamic>,
    groupId: groupId,
    kind: SelfRemovedGroupKeyReferenceKind.draft,
  );
  final binding = SelfRemovedGroupAcceptedReentryBinding(
    entryId: row['id'] as String,
    sourceEventId: row['source_event_id'] as String,
    sequence: (row['sequence'] as num).toInt(),
    originEntryId: originEntryId,
    authorizationId: decoded['authorizationId'] as String,
    acceptedStateFingerprint: decoded['acceptedStateFingerprint'] as String,
    acceptedAt: acceptedAt,
    keyGeneration: keyGeneration,
    encryptedKeyReference: keyReference,
    keyCreatedAt: keyCreatedAt,
  );
  return _AcceptedBindingEvidence(
    binding: binding,
    groupId: groupId,
    selfPeerId: decoded['selfPeerId'] as String,
    authorizationId: decoded['authorizationId'] as String,
    originEntryId: originEntryId,
    originSourceEventId: decoded['originSourceEventId'] as String,
    floorEntryId: decoded['floorEntryId'] as String,
    floorSourceEventId: decoded['floorSourceEventId'] as String,
    priorShape: _parseAcceptedPriorShape(decoded['priorShape'] as String),
    bindingNonce: bindingNonce,
    signedMembershipWatermarkRaw:
        decoded['signedMembershipWatermark'] as String,
    signedIssuedAtRaw: decoded['signedIssuedAt'] as String,
    acceptedAtRaw: decoded['acceptedAt'] as String,
    selfJoinedAtRaw: decoded['selfJoinedAt'] as String,
    keyGeneration: keyGeneration,
    keyReference: keyReference,
    keyCreatedAtRaw: decoded['keyCreatedAt'] as String,
    priorKeyRows: priorKeys,
    priorDraftRows: priorDrafts,
    groupHash: decoded['groupHash'] as String,
    rosterHash: decoded['rosterHash'] as String,
    keyHash: decoded['keyHash'] as String,
    draftHash: decoded['draftHash'] as String,
    stateFingerprint: decoded['acceptedStateFingerprint'] as String,
  );
}

List<SelfRemovedGroupKeyReference> _keyReferencesFromBindingPayload(
  List<dynamic> rows, {
  required String groupId,
  required SelfRemovedGroupKeyReferenceKind kind,
}) {
  if (kind == SelfRemovedGroupKeyReferenceKind.draft && rows.length > 1) {
    throw GroupEventLogTamperException('multiple prior key drafts');
  }
  final references = <SelfRemovedGroupKeyReference>[];
  final identities = <String>{};
  final generations = <int>{};
  for (final value in rows) {
    if (value is! Map<String, dynamic> ||
        value['groupId'] != groupId ||
        value['keyGeneration'] is! int ||
        (value['keyGeneration'] as int) < 0 ||
        value['keyReference'] is! String ||
        value['createdAt'] is! String ||
        !isSecureStoreReference(value['keyReference'] as String) ||
        (value['keyReference'] as String).length <=
            secureStoreReferencePrefix.length ||
        !generations.add(value['keyGeneration'] as int)) {
      throw GroupEventLogTamperException('malformed prior key reference');
    }
    final createdAtRaw = value['createdAt'] as String;
    final reference = SelfRemovedGroupKeyReference._(
      kind: kind,
      groupId: groupId,
      keyGeneration: value['keyGeneration'] as int,
      encryptedKeyReference: value['keyReference'] as String,
      createdAt: _parseRequiredUtcColumn(
        createdAtRaw,
        'acceptedBinding.priorKey.createdAt',
      ),
      createdAtRaw: createdAtRaw,
    );
    if (!identities.add(reference._exactIdentity)) {
      throw GroupEventLogTamperException('duplicate prior key reference');
    }
    references.add(reference);
  }
  return List<SelfRemovedGroupKeyReference>.unmodifiable(references);
}

class _FreshnessFloorEvidence {
  const _FreshnessFloorEvidence({
    required this.floor,
    required this.selfRemovedAtRaw,
    required this.lastMembershipEventAtRaw,
  });

  final SelfRemovedGroupFreshnessFloor floor;
  final String selfRemovedAtRaw;
  final String? lastMembershipEventAtRaw;
}

Future<_FreshnessFloorEvidence> _loadFreshnessFloorEvidence(
  DatabaseExecutor db, {
  required String groupId,
  required String entryId,
}) async {
  final rows = await db.query(
    'group_event_log',
    where: 'id = ? AND group_id = ? AND event_type = ?',
    whereArgs: <Object?>[
      entryId,
      groupId,
      kLocalSelfRemovedFreshnessFloorEventType,
    ],
    limit: 1,
  );
  if (rows.isEmpty) {
    throw GroupEventLogTamperException('accepted binding floor is missing');
  }
  final row = rows.single;
  final floor = _freshnessFloorFromEventRow(row);
  final decoded = jsonDecode(row['canonical_payload'] as String);
  if (decoded is! Map<String, dynamic>) {
    throw GroupEventLogTamperException('malformed accepted binding floor');
  }
  return _FreshnessFloorEvidence(
    floor: floor,
    selfRemovedAtRaw: decoded['selfRemovedAt'] as String,
    lastMembershipEventAtRaw: decoded['lastMembershipEventAt'] as String?,
  );
}

Future<_AcceptedOriginEvidence> _loadAcceptedOriginEvidence(
  DatabaseExecutor db, {
  required String groupId,
  required String entryId,
}) async {
  final rows = await db.query(
    'group_event_log',
    where: 'id = ? AND group_id = ? AND event_type = ?',
    whereArgs: <Object?>[
      entryId,
      groupId,
      kLocalSelfRemovedAcceptOriginEventType,
    ],
    limit: 1,
  );
  if (rows.isEmpty) {
    throw GroupEventLogTamperException('accepted binding origin is missing');
  }
  return _acceptedOriginFromEventRow(rows.single);
}

bool _bindingEvidenceMatchesOriginAndFloor(
  _AcceptedBindingEvidence binding,
  _AcceptedOriginEvidence origin,
  _FreshnessFloorEvidence floor,
) {
  return binding.groupId == origin.groupId &&
      binding.groupId == floor.floor.groupId &&
      binding.selfPeerId == origin.selfPeerId &&
      binding.selfPeerId == floor.floor.selfPeerId &&
      binding.authorizationId == origin.authorizationId &&
      binding.originEntryId == origin.entryId &&
      binding.originSourceEventId == origin.sourceEventId &&
      binding.floorEntryId == origin.floorEntryId &&
      binding.floorEntryId == floor.floor.entryId &&
      binding.floorSourceEventId == origin.floorSourceEventId &&
      binding.floorSourceEventId == floor.floor.sourceEventId &&
      binding.priorShape == origin.priorShape &&
      origin.floorSelfRemovedAtRaw == floor.selfRemovedAtRaw &&
      _bindingAuthorityIsNewerThanFloor(binding, floor.floor);
}

bool _bindingAuthorityIsNewerThanFloor(
  _AcceptedBindingEvidence binding,
  SelfRemovedGroupFreshnessFloor floor,
) {
  final signedWatermark = _parseRequiredUtcColumn(
    binding.signedMembershipWatermarkRaw,
    'acceptedBinding.signedMembershipWatermark',
  );
  final signedIssuedAt = _parseRequiredUtcColumn(
    binding.signedIssuedAtRaw,
    'acceptedBinding.signedIssuedAt',
  );
  var greatestFloor = floor.selfRemovedAt;
  final membershipFloor = floor.lastMembershipEventAt;
  if (membershipFloor != null && membershipFloor.isAfter(greatestFloor)) {
    greatestFloor = membershipFloor;
  }
  return !signedWatermark.isBefore(greatestFloor) &&
      signedIssuedAt.isAfter(greatestFloor);
}

Future<bool> _currentStateMatchesRecordedPrior(
  DatabaseExecutor db, {
  required SelfRemovedGroupShellAuthoritySnapshot current,
  required _AcceptedBindingEvidence binding,
  required _FreshnessFloorEvidence floor,
}) async {
  if (binding.groupId != current.groupId ||
      binding.selfPeerId != current.selfPeerId ||
      !await _hasExactFreshnessFloor(db, floor.floor)) {
    return false;
  }
  final references = await _loadRawKeyReferences(db, current.groupId);
  final acceptedReference = SelfRemovedGroupKeyReference._(
    kind: SelfRemovedGroupKeyReferenceKind.committed,
    groupId: binding.groupId,
    keyGeneration: binding.keyGeneration,
    encryptedKeyReference: binding.keyReference,
    createdAt: _parseRequiredUtcColumn(
      binding.keyCreatedAtRaw,
      'acceptedBinding.keyCreatedAt',
    ),
    createdAtRaw: binding.keyCreatedAtRaw,
  );
  final acceptedAddressIsRetainedOrPurged =
      references.isEmpty ||
      _sameReferences(references, <SelfRemovedGroupKeyReference>[
        acceptedReference,
      ]);
  if (!acceptedAddressIsRetainedOrPurged) return false;
  if (binding.priorShape == SelfRemovedGroupAcceptedReentryPriorShape.marked) {
    return current.shape ==
            SelfRemovedGroupShellAuthorityShape.markedSelfAbsent &&
        current._selfRemovedAtRaw == floor.selfRemovedAtRaw &&
        current._lastMembershipEventAtRaw == floor.lastMembershipEventAtRaw &&
        current.lastMembershipEventId == floor.floor.lastMembershipEventId;
  }
  return current.shape == SelfRemovedGroupShellAuthorityShape.absent;
}

bool _acceptedBindingKeyTupleStillPresent(
  _AcceptedBindingEvidence binding,
  _AcceptedStateFingerprint state,
) {
  if (state.keyRows.length != 1 || state.draftRows.isNotEmpty) return false;
  final key = state.keyRows.single;
  return key['group_id'] == binding.groupId &&
      key['key_generation'] == binding.keyGeneration &&
      key['encrypted_key'] == binding.keyReference &&
      key['created_at'] == binding.keyCreatedAtRaw;
}

class _AcceptedReentryRefusal implements Exception {
  const _AcceptedReentryRefusal(this.disposition);

  final SelfRemovedGroupAcceptedReentryDisposition disposition;
}

class _AcceptedReentryStateChanged implements Exception {
  const _AcceptedReentryStateChanged();
}

class _AcceptedReentryBindingCollision implements Exception {
  const _AcceptedReentryBindingCollision();
}

class _AuthorityCasLost implements Exception {
  const _AuthorityCasLost();
}
