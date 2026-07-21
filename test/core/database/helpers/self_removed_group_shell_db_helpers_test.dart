import 'package:flutter_app/core/database/helpers/group_history_gap_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_distributions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_key_repairs_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_membership_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_pending_reactions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_sibling_devices_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _createdAt = '2026-07-01T00:00:00.000Z';
const _joinedAt = '2026-07-02T00:00:00.000Z';
const _oldWatermark = '2026-07-03T00:00:00.000Z';
const _removedAt = '2026-07-04T00:00:00.000Z';

Map<String, Object?> _acceptedGroupRow(
  String groupId, {
  String name = 'Accepted group',
}) {
  return <String, Object?>{
    'id': groupId,
    'name': name,
    'type': 'chat',
    'topic_name': '/mknoon/groups/$groupId',
    'description': 'accepted description',
    'avatar_blob_id': null,
    'avatar_mime': null,
    'avatar_path': null,
    'created_at': _createdAt,
    'created_by': 'admin-peer',
    'my_role': 'member',
    'is_muted': 1,
    'is_dissolved': 0,
    'dissolved_at': null,
    'dissolved_by': null,
    'is_archived': 0,
    'archived_at': null,
    'last_metadata_event_at': '2026-07-05T01:00:00.000Z',
    'last_backlog_expired_at': null,
    'last_backlog_retained_at': '2026-07-05T02:00:00.000Z',
    // The helper must replace all three authority cells from signed proof.
    'last_membership_event_at': '1999-01-01T00:00:00.000Z',
    'last_membership_event_id': 'must-not-survive',
    'self_removed_at': _removedAt,
  };
}

Map<String, Object?> _acceptedMemberRow({
  required String groupId,
  required String peerId,
  required String joinedAt,
}) {
  return <String, Object?>{
    'group_id': groupId,
    'peer_id': peerId,
    'username': peerId,
    'role': peerId == 'self-peer' ? 'reader' : 'writer',
    'public_key': 'public-$peerId',
    'ml_kem_public_key': null,
    'joined_at': joinedAt,
    'permissions_json': '{}',
    'devices_json': '[]',
  };
}

Map<String, Object?> _acceptedKeyRow(
  String groupId, {
  int generation = 9,
  String reference = 'secure:accepted-key-9',
}) {
  return <String, Object?>{
    'group_id': groupId,
    'key_generation': generation,
    'encrypted_key': reference,
    'created_at': '2026-07-05T03:00:00.000Z',
  };
}

List<Map<String, Object?>> _acceptedRoster(
  String groupId, {
  String selfJoinedAt = '2026-07-05T04:00:00.000Z',
}) {
  return <Map<String, Object?>>[
    _acceptedMemberRow(
      groupId: groupId,
      peerId: 'self-peer',
      joinedAt: selfJoinedAt,
    ),
    _acceptedMemberRow(
      groupId: groupId,
      peerId: 'other-peer',
      joinedAt: '2026-07-05T04:00:01.000Z',
    ),
  ];
}

Future<SelfRemovedGroupAcceptedReentryResult> _commitAcceptedReentry(
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
  const zero = SelfRemovedGroupShellTerminalizationCounts(
    pendingRowsDeleted: 0,
    messagesTerminalized: 0,
    uploadsTerminalized: 0,
  );
  final prepared = await dbPrepareSelfRemovedGroupAcceptedReentry(
    db,
    groupRow: groupRow,
    rosterRows: rosterRows,
    stagedKeyRow: stagedKeyRow,
    selfPeerId: selfPeerId,
    authorizationId: authorizationId,
    signedMembershipWatermark: signedMembershipWatermark,
    signedIssuedAt: signedIssuedAt,
    bindingNonce: bindingNonce,
    createdAt: createdAt,
  );
  if (!prepared.prepared) {
    return SelfRemovedGroupAcceptedReentryResult(
      disposition: prepared.disposition,
      authority: prepared.authority,
      terminalization: zero,
    );
  }
  final preparation = prepared.preparation!;
  final staged = await dbStageSelfRemovedGroupAcceptedReentryKey(
    db,
    preparation: preparation,
    stagedKeyRow: stagedKeyRow,
  );
  if (!staged.staged) {
    return SelfRemovedGroupAcceptedReentryResult(
      disposition: staged.disposition,
      authority: staged.authority,
      terminalization: zero,
    );
  }
  return dbCommitSelfRemovedGroupAcceptedReentry(
    db,
    preparation: preparation,
    groupRow: groupRow,
    rosterRows: rosterRows,
    stagedKeyRow: stagedKeyRow,
    selfPeerId: selfPeerId,
    authorizationId: authorizationId,
    signedMembershipWatermark: signedMembershipWatermark,
    signedIssuedAt: signedIssuedAt,
    bindingNonce: bindingNonce,
    createdAt: createdAt,
  );
}

Future<void> _insertGroup(
  Database db,
  String groupId, {
  String? watermark = _oldWatermark,
  String? watermarkId = 'event-old',
}) {
  return db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': 'Group $groupId',
    'type': 'chat',
    'topic_name': '/mknoon/groups/$groupId',
    'created_at': _createdAt,
    'created_by': 'admin-peer',
    'my_role': 'member',
    'last_membership_event_at': watermark,
    'last_membership_event_id': watermarkId,
  });
}

Future<void> _insertMember(
  Database db, {
  required String groupId,
  required String peerId,
  String joinedAt = _joinedAt,
}) {
  return db.insert('group_members', <String, Object?>{
    'group_id': groupId,
    'peer_id': peerId,
    'role': 'reader',
    'joined_at': joinedAt,
  });
}

Future<void> _insertGroupMessage(
  Database db, {
  required String id,
  String groupId = 'group-1',
  String status = 'pending',
  int isIncoming = 0,
  int inboxStored = 0,
  String? wireEnvelope = '{"wire":true}',
  String? inboxRetryPayload = '{"inbox":true}',
  int? nextEligibleAt = 123456,
  String timestamp = '2026-07-03T01:00:00.000Z',
}) {
  return db.insert('group_messages', <String, Object?>{
    'id': id,
    'group_id': groupId,
    'sender_peer_id': isIncoming == 1 ? 'other-peer' : 'self-peer',
    'text': id,
    'timestamp': timestamp,
    'key_generation': 7,
    'status': status,
    'is_incoming': isIncoming,
    'created_at': timestamp,
    'wire_envelope': wireEnvelope,
    'inbox_stored': inboxStored,
    'inbox_retry_payload': inboxRetryPayload,
    'retry_attempt_count': 3,
    'next_eligible_at': nextEligibleAt,
  });
}

Future<void> _insertAttachment(
  Database db, {
  required String id,
  required String messageId,
  String status = 'upload_pending',
  String ownerLane = 'group',
}) {
  return db.insert('media_attachments', <String, Object?>{
    'id': id,
    'message_id': messageId,
    'mime': 'image/jpeg',
    'size': 42,
    'media_type': 'image',
    'local_path': '/media/$id.jpg',
    'download_status': status,
    'created_at': _createdAt,
    'owner_lane': ownerLane,
  });
}

Future<void> _seedMembershipInstanceWork(Database db, String groupId) async {
  await db.insert('group_exit_intents', <String, Object?>{
    'group_id': groupId,
    'intent_id': 'exit-intent-$groupId',
    'self_peer_id': 'self-peer',
    'self_joined_at': _joinedAt,
    'state': 'queued',
    'pending_broadcast_id': 'exit-notice-$groupId',
    'revision': 0,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_rejoin_state', <String, Object?>{
    'group_id': groupId,
    'rejoin_attempt_count': 1,
    'next_eligible_at': 123,
  });
  await db.insert('pending_group_broadcasts', <String, Object?>{
    'id': 'broadcast-$groupId',
    'group_id': groupId,
    'kind': 'member_removed',
    'sys_text': 'pending',
    'event_at': _oldWatermark,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_key_repairs', <String, Object?>{
    'id': 'repair-$groupId',
    'group_id': groupId,
    'message_id': 'repair-message-$groupId',
    'payload_type': 'group_message',
    'key_epoch': 7,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_key_distributions', <String, Object?>{
    'id': 'distribution-$groupId',
    'group_id': groupId,
    'peer_id': 'distribution-peer-$groupId',
    'key_epoch': 7,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_membership_messages', <String, Object?>{
    'id': 'membership-$groupId',
    'group_id': groupId,
    'sender_peer_id': 'admin-peer',
    'message_id': 'membership-message-$groupId',
    'payload_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_history_gap_repairs', <String, Object?>{
    'group_id': groupId,
    'gap_id': 'gap-$groupId',
    'missing_after_message_id': 'after-$groupId',
    'missing_before_message_id': 'before-$groupId',
    'expected_range_hash': 'hash-$groupId',
    'expected_head_message_id': 'head-$groupId',
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_reactions', <String, Object?>{
    'id': 'pending-reaction-$groupId',
    'group_id': groupId,
    'message_id': 'reaction-message-$groupId',
    'sender_peer_id': 'reaction-peer',
    'reaction_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('pending_sibling_devices', <String, Object?>{
    'group_id': groupId,
    'member_peer_id': 'sibling-peer',
    'device_id': 'sibling-device-$groupId',
    'transport_peer_id': 'transport-peer',
    'device_signing_public_key': 'signing-key',
    'verified_account_signing_public_key': 'account-key',
    'announced_at': _createdAt,
  });
}

Future<void> _insertReplay(
  Database db, {
  required String id,
  required String groupId,
  required String status,
}) {
  return db.insert('group_reaction_replay_outbox', <String, Object?>{
    'reaction_id': id,
    'group_id': groupId,
    'message_id': 'message-$id',
    'sender_peer_id': 'sender-peer',
    'emoji': '👍',
    'action': 'add',
    'inbox_retry_payload': '{}',
    'delivery_status': status,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
}

Future<int> _countForGroup(Database db, String table, String groupId) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM $table WHERE group_id = ?',
    <Object?>[groupId],
  );
  return (rows.single['count'] as num).toInt();
}

typedef _GuardedWriteAddress = ({String table, String column, Object value});

Future<List<_GuardedWriteAddress>> _attemptEveryGuardedWrite(
  Database db, {
  required String groupId,
  required String suffix,
}) async {
  final keyRepairId = 'guard-key-repair-$suffix';
  final distributionId = 'guard-distribution-$suffix';
  final membershipId = 'guard-membership-$suffix';
  final gapId = 'guard-gap-$suffix';
  final reactionId = 'guard-reaction-$suffix';
  final replayId = 'guard-replay-$suffix';
  final broadcastId = 'guard-broadcast-$suffix';
  final deviceId = 'guard-device-$suffix';
  final memberPeerId = 'guard-member-$suffix';
  final messageId = 'guard-message-$suffix';
  const keyGeneration = 99;

  await dbRecordGroupRejoinFailure(db, groupId, nextEligibleAtMs: 1000);
  await dbInsertPendingGroupBroadcast(db, <String, Object?>{
    'id': broadcastId,
    'group_id': groupId,
    'kind': 'member_removed',
    'sys_text': 'guarded',
    'event_at': _removedAt,
    'source_message_id': 'guard-source-$suffix',
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await dbUpsertGroupPendingKeyRepair(db, <String, Object?>{
    'id': keyRepairId,
    'group_id': groupId,
    'message_id': 'guard-repair-message-$suffix',
    'payload_type': 'group_message',
    'key_epoch': keyGeneration,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  final distribution = <String, Object?>{
    'id': distributionId,
    'group_id': groupId,
    'peer_id': 'guard-distribution-peer-$suffix',
    'key_epoch': keyGeneration,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  };
  await dbUpsertGroupPendingKeyDistribution(db, distribution);
  await dbReopenGroupPendingKeyDistributionForRedelivery(db, distribution);
  await dbUpsertGroupPendingMembershipMessage(db, <String, Object?>{
    'id': membershipId,
    'group_id': groupId,
    'sender_peer_id': 'admin-peer',
    'message_id': 'guard-membership-message-$suffix',
    'payload_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await dbUpsertGroupHistoryGapRepair(db, <String, Object?>{
    'group_id': groupId,
    'gap_id': gapId,
    'missing_after_message_id': 'guard-after-$suffix',
    'missing_before_message_id': 'guard-before-$suffix',
    'expected_range_hash': 'guard-hash-$suffix',
    'expected_head_message_id': 'guard-head-$suffix',
    'candidate_source_peer_ids_json': '[]',
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await dbUpsertGroupPendingReaction(db, <String, Object?>{
    'id': reactionId,
    'group_id': groupId,
    'message_id': 'guard-reaction-message-$suffix',
    'sender_peer_id': 'guard-reaction-peer',
    'reaction_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await dbUpsertPendingSiblingDevice(db, <String, Object?>{
    'group_id': groupId,
    'member_peer_id': 'guard-sibling-peer',
    'device_id': deviceId,
    'transport_peer_id': 'guard-transport-peer',
    'device_signing_public_key': 'guard-signing-key',
    'verified_account_signing_public_key': 'guard-account-key',
    'announced_at': _createdAt,
  });
  await dbUpsertGroupReactionReplayOutboxEntry(db, <String, Object?>{
    'reaction_id': replayId,
    'group_id': groupId,
    'message_id': 'guard-replay-message-$suffix',
    'sender_peer_id': 'guard-replay-peer',
    'emoji': '👍',
    'action': 'add',
    'inbox_retry_payload': '{}',
    'delivery_status': 'pending',
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await dbInsertGroupMember(db, <String, Object?>{
    'group_id': groupId,
    'peer_id': memberPeerId,
    'role': 'reader',
    'joined_at': _removedAt,
  });
  await dbInsertGroupKey(db, <String, Object?>{
    'group_id': groupId,
    'key_generation': keyGeneration,
    'encrypted_key': 'secure:guard-key-$suffix',
    'created_at': _createdAt,
  });
  await dbUpsertPendingGroupKeyRotation(db, <String, Object?>{
    'group_id': groupId,
    'key_generation': keyGeneration,
    'encrypted_key': 'secure:guard-draft-$suffix',
    'created_at': _createdAt,
  });
  await dbInsertGroupMessage(db, <String, Object?>{
    'id': messageId,
    'group_id': groupId,
    'sender_peer_id': 'guard-sender-peer',
    'text': 'guarded message',
    'timestamp': _removedAt,
    'key_generation': keyGeneration,
    'status': 'sent',
    'is_incoming': 1,
    'created_at': _removedAt,
  });

  return <_GuardedWriteAddress>[
    (table: 'group_rejoin_state', column: 'group_id', value: groupId),
    (table: 'pending_group_broadcasts', column: 'id', value: broadcastId),
    (table: 'group_pending_key_repairs', column: 'id', value: keyRepairId),
    (
      table: 'group_pending_key_distributions',
      column: 'id',
      value: distributionId,
    ),
    (
      table: 'group_pending_membership_messages',
      column: 'id',
      value: membershipId,
    ),
    (table: 'group_history_gap_repairs', column: 'gap_id', value: gapId),
    (table: 'group_pending_reactions', column: 'id', value: reactionId),
    (table: 'pending_sibling_devices', column: 'device_id', value: deviceId),
    (
      table: 'group_reaction_replay_outbox',
      column: 'reaction_id',
      value: replayId,
    ),
    (table: 'group_members', column: 'peer_id', value: memberPeerId),
    (table: 'group_keys', column: 'key_generation', value: keyGeneration),
    (
      table: 'group_key_rotation_drafts',
      column: 'key_generation',
      value: keyGeneration,
    ),
    (table: 'group_messages', column: 'id', value: messageId),
  ];
}

Future<void> _expectGuardedWritesAbsent(
  Database db,
  List<_GuardedWriteAddress> addresses,
) async {
  for (final address in addresses) {
    final rows = await db.query(
      address.table,
      columns: <String>[address.column],
      where: '${address.column} = ?',
      whereArgs: <Object?>[address.value],
    );
    expect(rows, isEmpty, reason: '${address.table}.${address.column}');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await runProductionOnCreate(db, 103);
  });

  tearDown(() => db.close());

  test(
    'self-removal commit revalidates and atomically sets marker watermark while deleting only target self and retaining keys',
    () async {
      await _insertGroup(db, 'group-1');
      await _insertGroup(db, 'group-other');
      await _insertMember(db, groupId: 'group-1', peerId: 'self-peer');
      await _insertMember(db, groupId: 'group-1', peerId: 'remaining-peer');
      await db.insert('group_keys', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 7,
        'encrypted_key': 'secure:group-key-7',
        'created_at': _createdAt,
      });
      await db.insert('group_key_rotation_drafts', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 8,
        'encrypted_key': 'secure:group-key-8',
        'created_at': _createdAt,
      });
      await _seedMembershipInstanceWork(db, 'group-1');
      await _seedMembershipInstanceWork(db, 'group-other');
      await _insertReplay(
        db,
        id: 'replay-pending',
        groupId: 'group-1',
        status: 'pending',
      );
      await _insertReplay(
        db,
        id: 'replay-failed',
        groupId: 'group-1',
        status: 'failed',
      );
      await _insertReplay(
        db,
        id: 'replay-stored',
        groupId: 'group-1',
        status: 'stored',
      );

      await _insertGroupMessage(db, id: 'sending', status: 'sending');
      await _insertGroupMessage(db, id: 'failed', status: 'failed');
      await _insertGroupMessage(db, id: 'terminal', status: 'send_failed');
      await _insertGroupMessage(
        db,
        id: 'repush',
        status: 'sent',
        wireEnvelope: null,
      );
      await _insertGroupMessage(
        db,
        id: 'settled',
        status: 'sent',
        inboxStored: 1,
        inboxRetryPayload: null,
        nextEligibleAt: null,
      );
      await _insertGroupMessage(
        db,
        id: 'incoming',
        status: 'pending',
        isIncoming: 1,
      );
      await _insertAttachment(db, id: 'upload-sending', messageId: 'sending');
      await _insertAttachment(db, id: 'upload-settled', messageId: 'settled');
      await _insertAttachment(db, id: 'upload-incoming', messageId: 'incoming');

      final snapshot = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      expect(
        snapshot.shape,
        SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent,
      );

      // A stale compare-and-swap token cannot partially mark or clean work.
      await db.update(
        'group_members',
        <String, Object?>{'joined_at': '2026-07-02T00:00:01.000Z'},
        where: 'group_id = ? AND peer_id = ?',
        whereArgs: <Object?>['group-1', 'self-peer'],
      );
      final refused = await dbCommitSelfRemovalAuthority(
        db,
        expected: snapshot,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed',
      );
      expect(
        refused.disposition,
        SelfRemovalAuthorityCommitDisposition.refusedStateChanged,
      );
      expect(
        (await db.query(
          'groups',
          where: 'id = ?',
          whereArgs: ['group-1'],
        )).single['self_removed_at'],
        isNull,
      );
      expect(await _countForGroup(db, 'group_rejoin_state', 'group-1'), 1);

      final fresh = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );

      // A cleanup fault after the marker/self writes proves the entire B3 SQL
      // unit rolls back, including its exact authority cells.
      await db.execute('''
        CREATE TRIGGER abort_self_removal_cleanup
        BEFORE DELETE ON pending_group_broadcasts
        WHEN OLD.group_id = 'group-1'
        BEGIN
          SELECT RAISE(ABORT, 'injected cleanup failure');
        END
      ''');
      await expectLater(
        dbCommitSelfRemovalAuthority(
          db,
          expected: fresh,
          removalAt: DateTime.parse(_removedAt),
          removalEventId: 'event-removed',
        ),
        throwsA(isA<DatabaseException>()),
      );
      await db.execute('DROP TRIGGER abort_self_removal_cleanup');
      final afterRollback = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      expect(
        afterRollback.shape,
        SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent,
      );
      expect(
        afterRollback.lastMembershipEventAt,
        DateTime.parse(_oldWatermark),
      );
      expect(await _countForGroup(db, 'group_rejoin_state', 'group-1'), 1);

      final committed = await dbCommitSelfRemovalAuthority(
        db,
        expected: afterRollback,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed',
      );

      expect(committed.committed, isTrue);
      expect(
        committed.authority.shape,
        SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
      );
      expect(committed.authority.selfRemovedAt, DateTime.parse(_removedAt));
      expect(
        committed.authority.lastMembershipEventAt,
        DateTime.parse(_removedAt),
      );
      expect(committed.authority.lastMembershipEventId, 'event-removed');
      expect(committed.terminalization.messagesTerminalized, 4);
      expect(committed.terminalization.uploadsTerminalized, 2);

      final members = await db.query(
        'group_members',
        where: 'group_id = ?',
        whereArgs: <Object?>['group-1'],
      );
      expect(members.map((row) => row['peer_id']), <Object?>['remaining-peer']);
      expect(await _countForGroup(db, 'group_keys', 'group-1'), 1);
      expect(
        await _countForGroup(db, 'group_key_rotation_drafts', 'group-1'),
        1,
      );

      for (final table in const <String>[
        'group_exit_intents',
        'group_rejoin_state',
        'pending_group_broadcasts',
        'group_pending_key_repairs',
        'group_pending_key_distributions',
        'group_pending_membership_messages',
        'group_history_gap_repairs',
        'group_pending_reactions',
        'pending_sibling_devices',
      ]) {
        expect(await _countForGroup(db, table, 'group-1'), 0, reason: table);
        expect(
          await _countForGroup(db, table, 'group-other'),
          1,
          reason: table,
        );
      }
      final replayRows = await db.query(
        'group_reaction_replay_outbox',
        where: 'group_id = ?',
        whereArgs: <Object?>['group-1'],
      );
      expect(replayRows.map((row) => row['reaction_id']), ['replay-stored']);

      for (final id in const <String>[
        'sending',
        'failed',
        'terminal',
        'repush',
      ]) {
        final row = (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: <Object?>[id],
        )).single;
        expect(row['status'], 'send_failed', reason: id);
        expect(row['wire_envelope'], isNull, reason: id);
        expect(row['inbox_retry_payload'], isNull, reason: id);
        expect(row['next_eligible_at'], isNull, reason: id);
      }
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['settled'],
        )).single['status'],
        'sent',
      );
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: ['incoming'],
        )).single['status'],
        'pending',
      );
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['upload-sending'],
        )).single['download_status'],
        'upload_failed',
      );
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['upload-settled'],
        )).single['download_status'],
        'upload_failed',
      );
      expect(
        (await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['upload-incoming'],
        )).single['download_status'],
        'upload_pending',
      );
    },
  );

  test('PB264-13 Plan-263 terminalization retires exact exit work', () async {
    Future<void> seedExactExitWork(String groupId) async {
      await db.insert('group_exit_intents', <String, Object?>{
        'group_id': groupId,
        'intent_id': 'exit-intent-$groupId',
        'self_peer_id': 'self-peer',
        'self_joined_at': _joinedAt,
        'state': 'leave_notice_pending',
        'pending_broadcast_id': 'exit-notice-$groupId',
        'source_event_id': 'exit-source-$groupId',
        'event_at': '2026-07-03T01:00:00.000Z',
        'revision': 1,
        'created_at': _createdAt,
        'updated_at': _createdAt,
      });
      await db.insert('pending_group_broadcasts', <String, Object?>{
        'id': 'exit-notice-$groupId',
        'group_id': groupId,
        'kind': 'member_removed_exit_intent',
        'sys_text': '{"signed":true}',
        'recipient_peer_ids': '["other-peer"]',
        'event_at': '2026-07-03T01:00:00.000Z',
        'source_message_id': 'exit-source-$groupId',
        'created_at': _createdAt,
        'updated_at': _createdAt,
      });
    }

    for (final groupId in const ['group-target', 'group-unrelated']) {
      await _insertGroup(db, groupId);
      await _insertMember(db, groupId: groupId, peerId: 'self-peer');
      await seedExactExitWork(groupId);
    }

    final authority = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
      db,
      groupId: 'group-target',
      selfPeerId: 'self-peer',
    );
    final committed = await dbCommitSelfRemovalAuthority(
      db,
      expected: authority,
      removalAt: DateTime.parse(_removedAt),
      removalEventId: 'event-target-removed',
    );

    expect(committed.committed, isTrue);
    expect(committed.terminalization.pendingRowsDeleted, 2);
    expect(await _countForGroup(db, 'group_exit_intents', 'group-target'), 0);
    expect(
      await _countForGroup(db, 'pending_group_broadcasts', 'group-target'),
      0,
    );
    expect(
      await _countForGroup(db, 'group_exit_intents', 'group-unrelated'),
      1,
    );
    expect(
      await _countForGroup(db, 'pending_group_broadcasts', 'group-unrelated'),
      1,
    );
    expect(
      (await db.query(
        'pending_group_broadcasts',
        where: 'group_id = ?',
        whereArgs: ['group-unrelated'],
      )).single['id'],
      'exit-notice-group-unrelated',
    );
  });

  test(
    'marked or absent parent refuses every terminalized pending-work upsert',
    () async {
      await _insertGroup(db, 'group-1');
      await _insertMember(db, groupId: 'group-1', peerId: 'self-peer');
      await db.insert('group_keys', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 7,
        'encrypted_key': 'secure:group-key-7',
        'created_at': _createdAt,
      });
      await db.insert('group_key_rotation_drafts', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 8,
        'encrypted_key': 'secure:group-key-8',
        'created_at': _createdAt,
      });
      await _insertGroupMessage(
        db,
        id: 'media-a',
        status: 'sent',
        inboxStored: 1,
        inboxRetryPayload: null,
        wireEnvelope: null,
        nextEligibleAt: null,
        timestamp: '2026-07-03T01:00:00.000Z',
      );
      await _insertGroupMessage(
        db,
        id: 'media-b',
        status: 'sent',
        inboxStored: 1,
        inboxRetryPayload: null,
        wireEnvelope: null,
        nextEligibleAt: null,
        timestamp: '2026-07-03T02:00:00.000Z',
      );
      await _insertAttachment(db, id: 'attachment-a', messageId: 'media-a');
      await _insertAttachment(db, id: 'attachment-b', messageId: 'media-b');

      final active = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      final commit = await dbCommitSelfRemovalAuthority(
        db,
        expected: active,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed',
      );
      expect(commit.committed, isTrue);
      final marked = commit.authority;

      final markedAttempts = await _attemptEveryGuardedWrite(
        db,
        groupId: 'group-1',
        suffix: 'marked',
      );
      await _expectGuardedWritesAbsent(db, markedAttempts);

      final references = await dbLoadRawSelfRemovedGroupKeyReferences(
        db,
        expected: marked,
      );
      expect(references.loaded, isTrue);
      expect(
        references.references.map((reference) => reference.kind),
        <SelfRemovedGroupKeyReferenceKind>[
          SelfRemovedGroupKeyReferenceKind.committed,
          SelfRemovedGroupKeyReferenceKind.draft,
        ],
      );

      final bounded = await dbLoadSelfRemovedGroupMediaParents(
        db,
        expected: marked,
        limit: 1,
      );
      expect(bounded.loaded, isTrue);
      expect(bounded.batch.parents.single.messageId, 'media-a');
      expect(bounded.batch.hasOverflow, isTrue);

      final floorFirst = await dbAppendSelfRemovedGroupFreshnessFloor(
        db,
        expected: marked,
        createdAt: DateTime.utc(2026, 7, 4, 0, 0, 1),
      );
      final floorReplay = await dbAppendSelfRemovedGroupFreshnessFloor(
        db,
        expected: marked,
        createdAt: DateTime.utc(2026, 7, 4, 0, 0, 2),
      );
      expect(floorFirst.inserted, isTrue);
      expect(floorReplay.inserted, isFalse);
      expect(floorReplay.floor.entryId, floorFirst.floor.entryId);
      expect(
        (await dbLoadLatestSelfRemovedGroupFreshnessFloor(
          db,
          'group-1',
        ))!.entryId,
        floorFirst.floor.entryId,
      );

      final referencesBlockPurge = await dbPurgeSelfRemovedGroupShell(
        db,
        expected: marked,
        floor: floorFirst.floor,
        deletedAt: DateTime.utc(2026, 7, 5),
      );
      expect(
        referencesBlockPurge.disposition,
        SelfRemovedGroupShellMutationDisposition.refusedOutstandingReferences,
      );

      final finalized = await dbFinalizeSelfRemovedGroupKeyReferences(
        db,
        expected: marked,
        expectedReferences: references.references,
      );
      expect(finalized.committed, isTrue);
      expect(finalized.deletedRows, 2);

      final mediaBlocksPurge = await dbPurgeSelfRemovedGroupShell(
        db,
        expected: marked,
        floor: floorFirst.floor,
        deletedAt: DateTime.utc(2026, 7, 5),
      );
      expect(
        mediaBlocksPurge.disposition,
        SelfRemovedGroupShellMutationDisposition.refusedMediaRemaining,
      );

      // Stand in for two successful canonical delete-for-me preparations: the
      // journal/attachment rows survive while their media-bearing parents end.
      for (final fixture in const <(String, String)>[
        ('attachment-a', 'media-a'),
        ('attachment-b', 'media-b'),
      ]) {
        await db.insert('group_media_deletion_journal', <String, Object?>{
          'attachment_id': fixture.$1,
          'operation_id': 'operation-${fixture.$1}',
          'message_id': fixture.$2,
          'group_id': 'group-1',
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/jpeg',
          'canonical_relative_path': 'media/${fixture.$1}.jpg',
          'created_at': _createdAt,
        });
        await db.delete(
          'group_messages',
          where: 'id = ? AND group_id = ?',
          whereArgs: <Object?>[fixture.$2, 'group-1'],
        );
      }
      await _insertGroupMessage(
        db,
        id: 'non-media',
        status: 'sent',
        inboxStored: 1,
        inboxRetryPayload: null,
        wireEnvelope: null,
        nextEligibleAt: null,
      );
      await db.insert('group_message_local_deletions', <String, Object?>{
        'message_id': 'non-media',
        'group_id': 'different-group',
        'deleted_at': _createdAt,
        'created_at': _createdAt,
      });
      await db.insert('pending_group_invites', <String, Object?>{
        'group_id': 'group-1',
        'invite_id': 'invite-1',
        'payload_json': '{}',
        'group_name': 'Group group-1',
        'group_type': 'chat',
        'sender_peer_id': 'admin-peer',
        'sender_username': 'Admin',
        'created_by': 'admin-peer',
        'created_at': _createdAt,
        'received_at': _createdAt,
        'expires_at': '2026-08-01T00:00:00.000Z',
      });

      final tombstoneBlocksPurge = await dbPurgeSelfRemovedGroupShell(
        db,
        expected: marked,
        floor: floorFirst.floor,
        deletedAt: DateTime.utc(2026, 7, 5),
      );
      expect(
        tombstoneBlocksPurge.disposition,
        SelfRemovedGroupShellMutationDisposition.refusedTombstoneConflict,
      );
      await db.delete(
        'group_message_local_deletions',
        where: 'message_id = ?',
        whereArgs: <Object?>['non-media'],
      );

      final purge = await dbPurgeSelfRemovedGroupShell(
        db,
        expected: marked,
        floor: floorFirst.floor,
        deletedAt: DateTime.utc(2026, 7, 5),
      );
      expect(purge.committed, isTrue);
      expect(purge.authority.shape, SelfRemovedGroupShellAuthorityShape.absent);
      expect(
        await db.query('groups', where: 'id = ?', whereArgs: ['group-1']),
        isEmpty,
      );
      expect(await _countForGroup(db, 'group_messages', 'group-1'), 0);
      expect(await _countForGroup(db, 'pending_group_invites', 'group-1'), 1);
      expect(await _countForGroup(db, 'group_event_log', 'group-1'), 1);
      expect(
        await _countForGroup(db, 'group_media_deletion_journal', 'group-1'),
        2,
      );
      expect(await db.query('media_attachments'), hasLength(2));
      expect(
        await _countForGroup(db, 'group_message_local_deletions', 'group-1'),
        1,
      );

      final absent = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      expect(absent.shape, SelfRemovedGroupShellAuthorityShape.absent);

      final absentAttempts = await _attemptEveryGuardedWrite(
        db,
        groupId: 'group-1',
        suffix: 'absent',
      );
      await _expectGuardedWritesAbsent(db, absentAttempts);
    },
  );

  test(
    'accepted re-entry atomically binds marked and absent floor materialization with canonical authority',
    () async {
      final freshRefusal = await _commitAcceptedReentry(
        db,
        groupRow: const <String, Object?>{'id': 'fresh-group'},
        rosterRows: const <Map<String, Object?>>[],
        stagedKeyRow: const <String, Object?>{},
        selfPeerId: 'self-peer',
        authorizationId: 'invite-1',
        signedMembershipWatermark: '2026-07-06T00:00:00.000Z',
        signedIssuedAt: '2026-07-05T00:00:00.000Z',
        bindingNonce: 'nonce-1',
      );
      expect(
        freshRefusal.disposition,
        SelfRemovedGroupAcceptedReentryDisposition.refusedMissingFloor,
      );

      await _insertGroup(db, 'group-marked');
      await _insertMember(db, groupId: 'group-marked', peerId: 'self-peer');
      final activeMarked = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-marked',
        selfPeerId: 'self-peer',
      );
      final removal = await dbCommitSelfRemovalAuthority(
        db,
        expected: activeMarked,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed-marked',
      );
      expect(removal.committed, isTrue);

      final malformed = await _commitAcceptedReentry(
        db,
        groupRow: _acceptedGroupRow('group-marked'),
        rosterRows: _acceptedRoster('group-marked'),
        stagedKeyRow: _acceptedKeyRow('group-marked'),
        selfPeerId: 'self-peer',
        authorizationId: 'invite-marked',
        signedMembershipWatermark: 'not-a-time',
        signedIssuedAt: '2026-07-05T00:00:00.000Z',
        bindingNonce: 'nonce-malformed',
      );
      expect(
        malformed.disposition,
        SelfRemovedGroupAcceptedReentryDisposition.refusedMalformedAuthority,
      );
      final malformedRoster = _acceptedRoster('group-marked');
      malformedRoster[1] = <String, Object?>{
        ...malformedRoster[1],
        'joined_at': 'not-a-time',
      };
      final malformedRosterResult = await _commitAcceptedReentry(
        db,
        groupRow: _acceptedGroupRow('group-marked'),
        rosterRows: malformedRoster,
        stagedKeyRow: _acceptedKeyRow('group-marked'),
        selfPeerId: 'self-peer',
        authorizationId: 'invite-marked-malformed-roster',
        signedMembershipWatermark: '2026-07-07T00:00:00.000Z',
        signedIssuedAt: '2026-07-06T00:00:00.000Z',
        bindingNonce: 'nonce-malformed-roster',
      );
      expect(
        malformedRosterResult.disposition,
        SelfRemovedGroupAcceptedReentryDisposition.refusedInvalidMaterial,
        reason:
            'every accepted roster generation must retain Plan-263 time validation',
      );
      final stale = await _commitAcceptedReentry(
        db,
        groupRow: _acceptedGroupRow('group-marked'),
        rosterRows: _acceptedRoster('group-marked'),
        stagedKeyRow: _acceptedKeyRow('group-marked'),
        selfPeerId: 'self-peer',
        authorizationId: 'invite-marked',
        signedMembershipWatermark: _removedAt,
        signedIssuedAt: _removedAt,
        bindingNonce: 'nonce-stale',
      );
      expect(
        stale.disposition,
        SelfRemovedGroupAcceptedReentryDisposition.refusedStaleAuthority,
      );
      expect(await _countForGroup(db, 'group_event_log', 'group-marked'), 0);

      // Seed old-membership work after B3 using raw SQL. Accepted material
      // must terminalize it in the same transaction as group/roster/key/B.
      await _seedMembershipInstanceWork(db, 'group-marked');
      await _insertGroupMessage(
        db,
        id: 'marked-old-send',
        groupId: 'group-marked',
      );
      final markedCommit = await _commitAcceptedReentry(
        db,
        groupRow: _acceptedGroupRow('group-marked'),
        rosterRows: _acceptedRoster('group-marked'),
        stagedKeyRow: _acceptedKeyRow('group-marked'),
        selfPeerId: 'self-peer',
        authorizationId: 'invite-marked',
        signedMembershipWatermark: '2026-07-07T00:00:00.000Z',
        signedIssuedAt: '2026-07-06T00:00:00.000Z',
        bindingNonce: 'nonce-marked',
        createdAt: DateTime.utc(2026, 7, 7, 0, 0, 1),
      );
      expect(markedCommit.committed, isTrue);
      expect(
        markedCommit.prior!.shape,
        SelfRemovedGroupAcceptedReentryPriorShape.marked,
      );
      expect(markedCommit.prior!.keyReferences, isEmpty);
      expect(markedCommit.acceptedAt, DateTime.utc(2026, 7, 7));
      expect(markedCommit.binding!.authorizationId, 'invite-marked');
      expect(markedCommit.binding!.keyGeneration, 9);
      expect(
        markedCommit.binding!.encryptedKeyReference,
        'secure:accepted-key-9',
      );
      expect(
        markedCommit.authority.shape,
        SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent,
      );
      expect(markedCommit.authority.lastMembershipEventId, isNull);
      expect(
        markedCommit.authority.lastMembershipEventAt,
        DateTime.utc(2026, 7, 7),
      );
      final markedGroup = (await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: <Object?>['group-marked'],
      )).single;
      expect(markedGroup['name'], 'Accepted group');
      expect(markedGroup['self_removed_at'], isNull);
      expect(markedGroup['last_membership_event_id'], isNull);
      expect(await _countForGroup(db, 'group_members', 'group-marked'), 2);
      expect(await _countForGroup(db, 'group_keys', 'group-marked'), 1);
      expect(await _countForGroup(db, 'group_rejoin_state', 'group-marked'), 0);
      expect(
        (await db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: <Object?>['marked-old-send'],
        )).single['status'],
        'send_failed',
      );
      final markedEvents = await db.query(
        'group_event_log',
        where: 'group_id = ?',
        whereArgs: <Object?>['group-marked'],
        orderBy: 'sequence ASC',
      );
      expect(markedEvents.map((row) => row['event_type']), <Object?>[
        kLocalSelfRemovedFreshnessFloorEventType,
        kLocalSelfRemovedAcceptOriginEventType,
        kLocalSelfRemovedAcceptBindingEventType,
      ]);

      final markedRollback = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-marked',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-marked',
      );
      expect(markedRollback.rolledBack, isTrue);
      expect(
        markedRollback.authority.shape,
        SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
      );
      expect(await _countForGroup(db, 'group_keys', 'group-marked'), 1);
      expect(
        (await db.query(
          'group_keys',
          where: 'group_id = ?',
          whereArgs: <Object?>['group-marked'],
        )).single['encrypted_key'],
        'secure:accepted-key-9',
      );
      final markedFinalize =
          await dbFinalizeSelfRemovedGroupAcceptedRollbackKey(
            db,
            groupId: 'group-marked',
            selfPeerId: 'self-peer',
            binding: markedRollback.binding!,
          );
      expect(markedFinalize.staged, isTrue);
      expect(await _countForGroup(db, 'group_keys', 'group-marked'), 0);
      final markedRollbackReplay =
          await dbRollbackSelfRemovedGroupAcceptedReentry(
            db,
            groupId: 'group-marked',
            selfPeerId: 'self-peer',
            authorizationId: 'invite-marked',
          );
      expect(markedRollbackReplay.rolledBack, isTrue);
      expect(
        markedRollbackReplay.binding!.entryId,
        markedCommit.binding!.entryId,
      );

      // Build the second supported prior shape through the real floor-bound
      // group-last purge, then prove accepted rollback removes its key row.
      await _insertGroup(db, 'group-absent');
      await _insertMember(db, groupId: 'group-absent', peerId: 'self-peer');
      final activeAbsent = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-absent',
        selfPeerId: 'self-peer',
      );
      final absentRemoval = await dbCommitSelfRemovalAuthority(
        db,
        expected: activeAbsent,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed-absent',
      );
      final absentFloor = await dbAppendSelfRemovedGroupFreshnessFloor(
        db,
        expected: absentRemoval.authority,
      );
      final purge = await dbPurgeSelfRemovedGroupShell(
        db,
        expected: absentRemoval.authority,
        floor: absentFloor.floor,
        deletedAt: DateTime.utc(2026, 7, 5),
      );
      expect(purge.committed, isTrue);

      final absentCommit = await _commitAcceptedReentry(
        db,
        groupRow: _acceptedGroupRow('group-absent'),
        rosterRows: _acceptedRoster('group-absent'),
        stagedKeyRow: _acceptedKeyRow(
          'group-absent',
          reference: 'secure:accepted-absent-key',
        ),
        selfPeerId: 'self-peer',
        authorizationId: 'invite-absent',
        // Equal floor watermark is allowed; issuedAt is the strict advance.
        signedMembershipWatermark: _removedAt,
        signedIssuedAt: '2026-07-08T00:00:00.000Z',
        bindingNonce: 'nonce-absent',
      );
      expect(absentCommit.committed, isTrue);
      expect(
        absentCommit.prior!.shape,
        SelfRemovedGroupAcceptedReentryPriorShape.absentWithFloor,
      );
      expect(absentCommit.acceptedAt, DateTime.utc(2026, 7, 8));
      expect(absentCommit.authority.lastMembershipEventId, isNull);
      final absentRollback = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-absent',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-absent',
      );
      expect(absentRollback.rolledBack, isTrue);
      expect(
        absentRollback.authority.shape,
        SelfRemovedGroupShellAuthorityShape.absent,
      );
      expect(await _countForGroup(db, 'group_keys', 'group-absent'), 1);
      final absentFinalize =
          await dbFinalizeSelfRemovedGroupAcceptedRollbackKey(
            db,
            groupId: 'group-absent',
            selfPeerId: 'self-peer',
            binding: absentRollback.binding!,
          );
      expect(absentFinalize.staged, isTrue);
      expect(await _countForGroup(db, 'group_keys', 'group-absent'), 0);
      final absentRollbackReplay =
          await dbRollbackSelfRemovedGroupAcceptedReentry(
            db,
            groupId: 'group-absent',
            selfPeerId: 'self-peer',
            authorizationId: 'invite-absent',
          );
      expect(absentRollbackReplay.rolledBack, isTrue);
      expect(
        absentRollbackReplay.binding!.encryptedKeyReference,
        'secure:accepted-absent-key',
      );
    },
  );

  test(
    'accepted re-entry refuses self joined_at that is not strictly newer than removal authority',
    () async {
      for (final candidate in <String>[_joinedAt, _removedAt]) {
        final groupId = candidate == _joinedAt
            ? 'group-stale-self-generation'
            : 'group-equal-self-generation';
        await _insertGroup(db, groupId);
        await _insertMember(db, groupId: groupId, peerId: 'self-peer');
        final active = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
          db,
          groupId: groupId,
          selfPeerId: 'self-peer',
        );
        final removal = await dbCommitSelfRemovalAuthority(
          db,
          expected: active,
          removalAt: DateTime.parse(_removedAt),
          removalEventId: 'remove-$groupId',
        );
        expect(removal.committed, isTrue);

        final refused = await _commitAcceptedReentry(
          db,
          groupRow: _acceptedGroupRow(groupId),
          rosterRows: _acceptedRoster(groupId, selfJoinedAt: candidate),
          stagedKeyRow: _acceptedKeyRow(groupId),
          selfPeerId: 'self-peer',
          authorizationId: 'invite-$groupId',
          signedMembershipWatermark: '2026-07-07T00:00:00.000Z',
          signedIssuedAt: '2026-07-06T00:00:00.000Z',
          bindingNonce: 'nonce-$groupId',
        );

        expect(
          refused.disposition,
          SelfRemovedGroupAcceptedReentryDisposition.refusedStaleAuthority,
        );
        final preserved = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
          db,
          groupId: groupId,
          selfPeerId: 'self-peer',
        );
        expect(
          preserved.shape,
          SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
        );
        expect(await _countForGroup(db, 'group_keys', groupId), 0);
        expect(await _countForGroup(db, 'group_event_log', groupId), 0);
      }
    },
  );

  test(
    'accepted SQL staging crash is enumerable and a later phase replays origin then replaces the orphan address',
    () async {
      const groupId = 'group-staging-restart';
      await _insertGroup(db, groupId);
      await _insertMember(db, groupId: groupId, peerId: 'self-peer');
      final active = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: groupId,
        selfPeerId: 'self-peer',
      );
      final removal = await dbCommitSelfRemovalAuthority(
        db,
        expected: active,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-staging-restart',
      );
      expect(removal.committed, isTrue);

      Map<String, Object?> stagedRow(String nonce) => _acceptedKeyRow(
        groupId,
        generation: 4,
        reference: secureStoreReferenceForKey(
          groupAcceptedKeyMaterialStoreName(groupId, 4, nonce),
        ),
      );

      Future<SelfRemovedGroupAcceptedReentryPreparationResult> prepare(
        String nonce,
      ) {
        return dbPrepareSelfRemovedGroupAcceptedReentry(
          db,
          groupRow: _acceptedGroupRow(groupId),
          rosterRows: _acceptedRoster(groupId),
          stagedKeyRow: stagedRow(nonce),
          selfPeerId: 'self-peer',
          authorizationId: 'invite-staging-restart',
          signedMembershipWatermark: '2026-07-07T00:00:00.000Z',
          signedIssuedAt: '2026-07-06T00:00:00.000Z',
          bindingNonce: nonce,
        );
      }

      final first = await prepare('phase-1');
      expect(first.prepared, isTrue);
      final firstPreparation = first.preparation!;
      expect(firstPreparation.prior.keyReferences, isEmpty);
      expect(
        (await db.query(
          'group_event_log',
          where: 'group_id = ?',
          whereArgs: <Object?>[groupId],
          orderBy: 'sequence ASC',
        )).map((row) => row['event_type']),
        <Object?>[
          kLocalSelfRemovedFreshnessFloorEventType,
          kLocalSelfRemovedAcceptOriginEventType,
        ],
      );
      final firstStage = await dbStageSelfRemovedGroupAcceptedReentryKey(
        db,
        preparation: firstPreparation,
        stagedKeyRow: stagedRow('phase-1'),
      );
      expect(firstStage.staged, isTrue);
      expect(
        (await db.query('group_keys')).single['encrypted_key'],
        stagedRow('phase-1')['encrypted_key'],
      );

      // Simulate process death before primary secure-store write. A new phase
      // must treat the retained accepted address as cleanup enumeration, not
      // as original marked-membership key authority.
      final second = await prepare('phase-2');
      expect(second.prepared, isTrue);
      final secondPreparation = second.preparation!;
      expect(secondPreparation.originEntryId, firstPreparation.originEntryId);
      expect(secondPreparation.prior.keyReferences, isEmpty);
      expect(secondPreparation.retiringKeyReferences, hasLength(1));
      final secondStage = await dbStageSelfRemovedGroupAcceptedReentryKey(
        db,
        preparation: secondPreparation,
        stagedKeyRow: stagedRow('phase-2'),
      );
      expect(secondStage.staged, isTrue);
      expect(
        (await db.query('group_keys')).single['encrypted_key'],
        stagedRow('phase-2')['encrypted_key'],
      );
      expect(
        await _countForGroup(db, 'group_event_log', groupId),
        2,
        reason: 'the deterministic shape origin replays without collision',
      );

      final finalized = await dbFinalizeSelfRemovedGroupAcceptedReentryStaging(
        db,
        preparation: secondPreparation,
        stagedKeyRow: stagedRow('phase-2'),
      );
      expect(finalized.staged, isTrue);
      expect(await _countForGroup(db, 'group_keys', groupId), 0);
    },
  );

  test(
    'accepted re-entry collision rolls back and rollback selects newest full state binding before authorization',
    () async {
      final missing = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-1',
      );
      expect(
        missing.disposition,
        SelfRemovedGroupAcceptedRollbackDisposition.refusedBindingMissing,
      );

      await _insertGroup(db, 'group-1');
      await _insertMember(db, groupId: 'group-1', peerId: 'self-peer');
      await db.insert('group_keys', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 4,
        'encrypted_key': 'secure:prior-key-4',
        'created_at': _createdAt,
      });
      await db.insert('group_key_rotation_drafts', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 5,
        'encrypted_key': 'secure:prior-draft-5',
        'created_at': _joinedAt,
      });
      final active = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      final removal = await dbCommitSelfRemovalAuthority(
        db,
        expected: active,
        removalAt: DateTime.parse(_removedAt),
        removalEventId: 'event-removed',
      );
      expect(removal.committed, isTrue);

      Future<SelfRemovedGroupAcceptedReentryResult> commit({
        required String authorizationId,
        required String nonce,
      }) {
        return _commitAcceptedReentry(
          db,
          groupRow: _acceptedGroupRow('group-1'),
          rosterRows: _acceptedRoster('group-1'),
          stagedKeyRow: _acceptedKeyRow('group-1'),
          selfPeerId: 'self-peer',
          authorizationId: authorizationId,
          signedMembershipWatermark: '2026-07-07T00:00:00.000Z',
          signedIssuedAt: '2026-07-06T00:00:00.000Z',
          bindingNonce: nonce,
        );
      }

      final first = await commit(authorizationId: 'invite-1', nonce: 'nonce-1');
      expect(first.committed, isTrue);
      expect(first.prior!.keyReferences, hasLength(2));
      final firstRollback = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-1',
      );
      expect(firstRollback.rolledBack, isTrue);
      expect(await _countForGroup(db, 'group_keys', 'group-1'), 1);
      expect(
        await _countForGroup(db, 'group_key_rotation_drafts', 'group-1'),
        0,
      );
      expect(
        (await db.query('group_keys')).single['encrypted_key'],
        'secure:accepted-key-9',
      );

      // Reusing the same phase nonce reaches an exact old binding replay.
      // The helper must classify it as a collision and roll back every SQL
      // mutation, including terminalization and the replayed origin.
      await _seedMembershipInstanceWork(db, 'group-1');
      final collision = await commit(
        authorizationId: 'invite-1',
        nonce: 'nonce-1',
      );
      expect(
        collision.disposition,
        SelfRemovedGroupAcceptedReentryDisposition.refusedBindingCollision,
      );
      final afterCollision = await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
      );
      expect(
        afterCollision.shape,
        SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
      );
      expect(await _countForGroup(db, 'group_rejoin_state', 'group-1'), 1);
      expect(
        (await db.query('group_keys')).single['encrypted_key'],
        'secure:accepted-key-9',
      );

      final second = await commit(
        authorizationId: 'invite-2',
        nonce: 'nonce-2',
      );
      expect(second.committed, isTrue);
      expect(
        second.binding!.acceptedStateFingerprint,
        first.binding!.acceptedStateFingerprint,
      );
      expect(second.binding!.sequence, greaterThan(first.binding!.sequence));

      // Every group/roster/key/draft cell participates in the fingerprint.
      await db.update(
        'groups',
        <String, Object?>{'name': 'newer metadata'},
        where: 'id = ?',
        whereArgs: <Object?>['group-1'],
      );
      final metadataMismatch = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-2',
      );
      expect(
        metadataMismatch.disposition,
        SelfRemovedGroupAcceptedRollbackDisposition.refusedBindingMissing,
      );
      await db.update(
        'groups',
        <String, Object?>{'name': 'Accepted group'},
        where: 'id = ?',
        whereArgs: <Object?>['group-1'],
      );

      // Both B1 and B2 match the same current state. Newest B2 is selected
      // before authorization is compared, so invite-1 cannot claim B1.
      final olderAuthorization =
          await dbRollbackSelfRemovedGroupAcceptedReentry(
            db,
            groupId: 'group-1',
            selfPeerId: 'self-peer',
            authorizationId: 'invite-1',
          );
      expect(
        olderAuthorization.disposition,
        SelfRemovedGroupAcceptedRollbackDisposition
            .refusedAuthorizationMismatch,
      );
      expect(olderAuthorization.binding!.authorizationId, 'invite-2');
      expect(
        (await dbLoadSelfRemovedGroupShellAuthoritySnapshot(
          db,
          groupId: 'group-1',
          selfPeerId: 'self-peer',
        )).shape,
        SelfRemovedGroupShellAuthorityShape.unmarkedSelfPresent,
      );

      final newestRollback = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-2',
      );
      expect(newestRollback.rolledBack, isTrue);
      expect(newestRollback.binding!.entryId, second.binding!.entryId);
      expect(
        newestRollback.authority.shape,
        SelfRemovedGroupShellAuthorityShape.markedSelfAbsent,
      );
      expect(
        (await db.query('group_keys')).single['encrypted_key'],
        'secure:accepted-key-9',
      );

      final idempotentRetry = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-2',
      );
      expect(idempotentRetry.rolledBack, isTrue);
      expect(idempotentRetry.binding!.entryId, second.binding!.entryId);

      await db.update(
        'group_event_log',
        <String, Object?>{'entry_hash': 'tampered-chain'},
        where: 'id = ?',
        whereArgs: <Object?>[second.binding!.entryId],
      );
      final malformedChain = await dbRollbackSelfRemovedGroupAcceptedReentry(
        db,
        groupId: 'group-1',
        selfPeerId: 'self-peer',
        authorizationId: 'invite-2',
      );
      expect(
        malformedChain.disposition,
        SelfRemovedGroupAcceptedRollbackDisposition.refusedEvidenceInvalid,
      );
    },
  );
}
