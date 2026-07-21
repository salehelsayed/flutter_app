import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _createdAt = '2026-07-21T08:00:00.000Z';
const _joinedAt = '2026-07-21T08:01:00.000Z';
const _watermark = '2026-07-21T08:02:00.000Z';
const _eventAt = '2026-07-21T08:03:00.000Z';

Map<String, Object?> _intent(
  String groupId, {
  String? intentId,
  String? pendingBroadcastId,
  String state = 'queued',
  int revision = 0,
  String? sourceEventId,
  String? eventAt,
  String selfJoinedAt = _joinedAt,
}) => <String, Object?>{
  'group_id': groupId,
  'intent_id': intentId ?? 'intent-$groupId',
  'self_peer_id': 'peer-self',
  'self_joined_at': selfJoinedAt,
  'state': state,
  'pending_broadcast_id': pendingBroadcastId ?? 'leave-outbox-$groupId',
  'source_event_id': sourceEventId,
  'event_at': eventAt,
  'revision': revision,
  'last_error_code': null,
  'created_at': _createdAt,
  'updated_at': _createdAt,
};

Map<String, Object?> _pending(
  String groupId, {
  String id = '',
  String kind = 'member_removed_exit_intent',
  String source = '',
  String eventAt = _eventAt,
}) => <String, Object?>{
  'id': id.isEmpty ? 'leave-outbox-$groupId' : id,
  'group_id': groupId,
  'kind': kind,
  'sys_text': '{"signed":true}',
  'recipient_peer_ids': '["peer-other"]',
  'event_at': eventAt,
  'source_message_id': source.isEmpty ? 'source-$groupId' : source,
  'created_at': _createdAt,
  'updated_at': _createdAt,
};

Map<String, Object?> _timeline(String groupId) => <String, Object?>{
  'id': 'timeline-$groupId',
  'group_id': groupId,
  'sender_peer_id': 'peer-self',
  'text': '{"__sys":"member_removed"}',
  'timestamp': _eventAt,
  'key_generation': 1,
  'status': 'sent',
  'is_incoming': 0,
  'created_at': _createdAt,
};

Future<void> _seedIdentity(Database db) =>
    db.insert('identity', <String, Object?>{
      'id': 1,
      'peer_id': 'peer-self',
      'public_key': '',
      'private_key': null,
      'mnemonic12': null,
      'username': 'Self',
      'created_at': _createdAt,
      'updated_at': _createdAt,
    });

Future<void> _seedGroup(
  Database db,
  String groupId, {
  String joinedAt = _joinedAt,
  bool withSelf = true,
  bool dissolved = false,
  String? selfRemovedAt,
}) async {
  await db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': groupId,
    'type': 'chat',
    'topic_name': 'topic-$groupId',
    'created_at': _createdAt,
    'created_by': 'peer-admin',
    'my_role': 'member',
    'is_dissolved': dissolved ? 1 : 0,
    'self_removed_at': selfRemovedAt,
    'last_membership_event_at': _watermark,
  });
  if (withSelf) {
    await db.insert('group_members', <String, Object?>{
      'group_id': groupId,
      'peer_id': 'peer-self',
      'role': 'writer',
      'joined_at': joinedAt,
    });
  }
}

Future<void> _insertRole(Database db, String groupId, {bool prepared = false}) {
  return db.insert(
    'pending_group_broadcasts',
    _pending(
      groupId,
      id: 'role-$groupId',
      kind: prepared ? 'member_role_updated_prepared' : 'member_role_updated',
      source: 'role-source-$groupId',
    ),
  );
}

Future<void> _seedExecutableMembershipWork(Database db, String groupId) async {
  await db.insert('group_pending_key_repairs', <String, Object?>{
    'id': 'repair-$groupId',
    'group_id': groupId,
    'message_id': 'repair-message-$groupId',
    'payload_type': 'group_message',
    'key_epoch': 1,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_key_distributions', <String, Object?>{
    'id': 'distribution-$groupId',
    'group_id': groupId,
    'peer_id': 'peer-other',
    'key_epoch': 1,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_membership_messages', <String, Object?>{
    'id': 'membership-$groupId',
    'group_id': groupId,
    'sender_peer_id': 'peer-other',
    'message_id': 'membership-message-$groupId',
    'payload_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_history_gap_repairs', <String, Object?>{
    'group_id': groupId,
    'gap_id': 'gap-$groupId',
    'missing_after_message_id': 'before-gap',
    'missing_before_message_id': 'after-gap',
    'expected_range_hash': 'range-hash',
    'expected_head_message_id': 'head-message',
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('group_pending_reactions', <String, Object?>{
    'id': 'reaction-$groupId',
    'group_id': groupId,
    'message_id': 'reaction-message-$groupId',
    'sender_peer_id': 'peer-other',
    'reaction_json': '{}',
    'received_at': _createdAt,
    'created_at': _createdAt,
    'updated_at': _createdAt,
  });
  await db.insert('pending_sibling_devices', <String, Object?>{
    'group_id': groupId,
    'member_peer_id': 'peer-self',
    'device_id': 'device-$groupId',
    'transport_peer_id': 'transport-$groupId',
    'device_signing_public_key': 'device-key',
    'verified_account_signing_public_key': 'account-key',
    'announced_at': _createdAt,
  });
  for (final status in const <String>['pending', 'failed']) {
    await db.insert('group_reaction_replay_outbox', <String, Object?>{
      'reaction_id': 'outbox-$status-$groupId',
      'group_id': groupId,
      'message_id': 'outbox-message-$status-$groupId',
      'sender_peer_id': 'peer-self',
      'emoji': '✅',
      'action': 'add',
      'inbox_retry_payload': '{}',
      'delivery_status': status,
      'created_at': _createdAt,
      'updated_at': _createdAt,
    });
  }
}

Future<({Directory directory, Database first, Database second})>
_openSharedDatabasePair(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(prefix);
  final path = '${directory.path}/identity.db';
  final first = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await runProductionOnCreate(first, 103);
  await _seedIdentity(first);
  final second = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await first.execute('PRAGMA busy_timeout = 5000');
  await second.execute('PRAGMA busy_timeout = 5000');
  return (directory: directory, first: first, second: second);
}

Future<void> _closeSharedDatabasePair(
  ({Directory directory, Database first, Database second}) pair,
) async {
  if (pair.second.isOpen) await pair.second.close();
  if (pair.first.isOpen) await pair.first.close();
  if (await pair.directory.exists()) {
    await pair.directory.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _prepareExitOnIsolatedFfiWorker({
  required String path,
  required Map<String, Object?> expected,
  required Map<String, Object?> timelineRow,
  required Map<String, Object?> pendingBroadcastRow,
  required String updatedAt,
  required SendPort ready,
}) async {
  ready.send('worker-entered');
  sqfliteFfiInit();
  final isolatedDb = await databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await isolatedDb.execute('PRAGMA busy_timeout = 5000');
    final start = ReceivePort();
    ready.send(start.sendPort);
    await start.first;
    start.close();
    final result = await dbPrepareGroupExitLeaveNotice(
      isolatedDb,
      expected: expected,
      timelineRow: timelineRow,
      pendingBroadcastRow: pendingBroadcastRow,
      updatedAt: updatedAt,
    );
    return <String, Object?>{
      'disposition': result.disposition.name,
      'current': result.current,
    };
  } finally {
    await isolatedDb.close();
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
    await _seedIdentity(db);
  });

  tearDown(() => db.close());

  test('PB264-04 enqueue rejects raw or prediagnosed error text', () async {
    await _seedGroup(db, 'group-raw-error');
    final raw = _intent('group-raw-error')
      ..['last_error_code'] = 'SocketException: signed payload leaked';

    final result = await dbEnqueueGroupExitIntent(db, raw);

    expect(
      result.disposition,
      DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
    );
    expect(await dbLoadGroupExitIntentForGroup(db, 'group-raw-error'), isNull);
  });

  test(
    'PB264-06 exact membership enqueue and cancel-versus-start CAS have one winner',
    () async {
      await _seedGroup(db, 'group-1');
      await _insertRole(db, 'group-1');
      await db.insert('group_messages', _timeline('group-1'));
      final queued = _intent('group-1');

      final inserted = await dbEnqueueGroupExitIntent(db, queued);
      expect(
        inserted.disposition,
        DbGroupExitIntentMutationDisposition.committed,
      );
      expect(
        (await dbEnqueueGroupExitIntent(db, queued)).disposition,
        DbGroupExitIntentMutationDisposition.alreadyCurrent,
      );

      final cancelled = await dbCancelQueuedGroupExitIntent(
        db,
        expected: queued,
        updatedAt: _eventAt,
      );
      expect(
        cancelled.disposition,
        DbGroupExitIntentMutationDisposition.committed,
      );
      expect(await dbLoadGroupExitIntentForGroup(db, 'group-1'), isNull);
      expect(await db.query('pending_group_broadcasts'), hasLength(1));
      expect(await db.query('groups'), hasLength(1));
      expect(await db.query('group_members'), hasLength(1));
      expect(await db.query('group_messages'), hasLength(1));
      expect(
        (await dbCancelQueuedGroupExitIntent(
          db,
          expected: queued,
          updatedAt: _eventAt,
        )).disposition,
        DbGroupExitIntentMutationDisposition.absent,
      );

      await dbEnqueueGroupExitIntent(db, queued);
      await db.delete(
        'group_members',
        where: 'group_id = ? AND peer_id = ?',
        whereArgs: ['group-1', 'peer-self'],
      );
      await db.insert('group_members', <String, Object?>{
        'group_id': 'group-1',
        'peer_id': 'peer-self',
        'role': 'writer',
        'joined_at': '2026-07-21T09:00:00.000Z',
      });
      final stale = await dbCancelQueuedGroupExitIntent(
        db,
        expected: queued,
        updatedAt: _eventAt,
      );
      expect(
        stale.disposition,
        DbGroupExitIntentMutationDisposition.retiredStaleMembership,
      );
      expect(await dbLoadGroupExitIntentForGroup(db, 'group-1'), isNull);
      expect(await db.query('pending_group_broadcasts'), hasLength(1));
      expect(await db.query('group_messages'), hasLength(1));

      for (final phase in const <(String, int)>[
        ('leave_notice_pending', 1),
        ('leave_notice_attempted', 2),
        ('rotation_claimed', 3),
        ('native_leave_pending', 4),
        ('cleanup_pending', 5),
      ]) {
        final groupId = 'later-${phase.$1}';
        await _seedGroup(db, groupId);
        final queuedToken = _intent(groupId);
        await db.insert(
          'group_exit_intents',
          _intent(
            groupId,
            state: phase.$1,
            revision: phase.$2,
            sourceEventId: 'source-$groupId',
            eventAt: _eventAt,
          ),
        );
        final tooLate = await dbCancelQueuedGroupExitIntent(
          db,
          expected: queuedToken,
          updatedAt: '2026-07-21T08:03:30.000Z',
        );
        expect(
          tooLate.disposition,
          DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
          reason: phase.$1,
        );
        expect(
          (await dbLoadGroupExitIntentForGroup(db, groupId))!['state'],
          phase.$1,
        );
      }

      final pair = await _openSharedDatabasePair('pb264_cancel_start_');
      addTearDown(() => _closeSharedDatabasePair(pair));
      Future<void> proveCancelStartOrder({required bool cancelFirst}) async {
        final groupId = cancelFirst ? 'race-cancel-wins' : 'race-start-wins';
        await _seedGroup(pair.first, groupId);
        final raceQueued = _intent(groupId);
        expect(
          (await dbEnqueueGroupExitIntent(pair.first, raceQueued)).committed,
          isTrue,
        );
        final cancelReady = Completer<void>();
        final prepareReady = Completer<void>();
        final releaseCancel = Completer<void>();
        final releasePrepare = Completer<void>();
        final cancelFuture = (() async {
          cancelReady.complete();
          await releaseCancel.future;
          return dbCancelQueuedGroupExitIntent(
            pair.first,
            expected: raceQueued,
            updatedAt: '2026-07-21T08:03:40.000Z',
          );
        })();
        final prepareFuture = (() async {
          prepareReady.complete();
          await releasePrepare.future;
          return dbPrepareGroupExitLeaveNotice(
            pair.second,
            expected: raceQueued,
            timelineRow: _timeline(groupId),
            pendingBroadcastRow: _pending(groupId),
            updatedAt: '2026-07-21T08:03:41.000Z',
          );
        })();
        await Future.wait([cancelReady.future, prepareReady.future]);

        late final DbGroupExitIntentMutationResult cancelRace;
        late final DbGroupExitIntentMutationResult prepareRace;
        if (cancelFirst) {
          releaseCancel.complete();
          cancelRace = await cancelFuture;
          releasePrepare.complete();
          prepareRace = await prepareFuture;
        } else {
          releasePrepare.complete();
          prepareRace = await prepareFuture;
          releaseCancel.complete();
          cancelRace = await cancelFuture;
        }

        expect(
          <DbGroupExitIntentMutationResult>[
            cancelRace,
            prepareRace,
          ].where((result) => result.committed),
          hasLength(1),
        );
        final raceCurrent = await dbLoadGroupExitIntentForGroup(
          pair.first,
          groupId,
        );
        final messages = await pair.first.query(
          'group_messages',
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
        final broadcasts = await pair.first.query(
          'pending_group_broadcasts',
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
        if (cancelFirst) {
          expect(cancelRace.committed, isTrue);
          expect(
            prepareRace.disposition,
            DbGroupExitIntentMutationDisposition.absent,
          );
          expect(raceCurrent, isNull);
          expect(messages, isEmpty);
          expect(broadcasts, isEmpty);
        } else {
          expect(prepareRace.committed, isTrue);
          expect(
            cancelRace.disposition,
            DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
          );
          expect(raceCurrent!['state'], 'leave_notice_pending');
          expect(raceCurrent['revision'], 1);
          expect(messages, hasLength(1));
          expect(broadcasts, hasLength(1));
        }
      }

      await proveCancelStartOrder(cancelFirst: true);
      await proveCancelStartOrder(cancelFirst: false);
    },
  );

  test('enqueue fails closed for every non-exact parent shape', () async {
    await _seedGroup(db, 'different', joinedAt: _eventAt);
    await _seedGroup(db, 'missing', withSelf: false);
    await _seedGroup(db, 'dissolved', dissolved: true);
    await _seedGroup(db, 'removed', selfRemovedAt: _eventAt);

    expect(
      (await dbEnqueueGroupExitIntent(db, _intent('absent'))).disposition,
      DbGroupExitIntentMutationDisposition.refusedParentAbsent,
    );
    expect(
      (await dbEnqueueGroupExitIntent(db, _intent('different'))).disposition,
      DbGroupExitIntentMutationDisposition.refusedMembershipChanged,
    );
    expect(
      (await dbEnqueueGroupExitIntent(db, _intent('missing'))).disposition,
      DbGroupExitIntentMutationDisposition.refusedSelfMissing,
    );
    expect(
      (await dbEnqueueGroupExitIntent(db, _intent('dissolved'))).disposition,
      DbGroupExitIntentMutationDisposition.refusedDissolved,
    );
    expect(
      (await dbEnqueueGroupExitIntent(db, _intent('removed'))).disposition,
      DbGroupExitIntentMutationDisposition.refusedSelfRemoved,
    );
  });

  test(
    'same-state diagnostic write is revision-CASed and remains cancelable',
    () async {
      await _seedGroup(db, 'group-1');
      final queued = _intent('group-1');
      await dbEnqueueGroupExitIntent(db, queued);

      final diagnosed = await dbAdvanceGroupExitIntent(
        db,
        expected: queued,
        nextState: 'queued',
        updatedAt: _eventAt,
        lastErrorCode: 'last_admin',
      );
      expect(diagnosed.committed, isTrue);
      expect(diagnosed.current!['state'], 'queued');
      expect(diagnosed.current!['revision'], 1);
      expect(diagnosed.current!['last_error_code'], 'last_admin');
      expect(
        (await dbCancelQueuedGroupExitIntent(
          db,
          expected: queued,
          updatedAt: _eventAt,
        )).disposition,
        DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
      );
      expect(
        (await dbCancelQueuedGroupExitIntent(
          db,
          expected: diagnosed.current!,
          updatedAt: _eventAt,
        )).committed,
        isTrue,
      );
    },
  );

  test(
    'enqueue atomically replaces only an old membership-generation intent',
    () async {
      await _seedGroup(db, 'group-1', joinedAt: _eventAt);
      final stale = _intent('group-1');
      await db.insert('group_exit_intents', stale);
      final fresh = _intent(
        'group-1',
        intentId: 'intent-fresh',
        pendingBroadcastId: 'pending-fresh',
        selfJoinedAt: _eventAt,
      );

      final result = await dbEnqueueGroupExitIntent(db, fresh);
      expect(result.committed, isTrue);
      expect(result.current!['intent_id'], 'intent-fresh');
      expect(result.current!['self_joined_at'], _eventAt);
      expect(await db.query('groups'), hasLength(1));
      expect(await db.query('group_members'), hasLength(1));
    },
  );

  test(
    'PB264-07 role absence claim and signed notice handoff are atomic with role preparation',
    () async {
      await _seedGroup(db, 'group-1');
      final queued = _intent('group-1');
      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'role-group-1',
          kind: 'member_role_updated',
          source: 'role-source-group-1',
        ),
      );
      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'second-role-group-1',
          kind: 'member_role_updated_prepared',
          source: 'second-role-source-group-1',
        ),
      );
      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'metadata-control',
          kind: 'group_metadata_updated',
          source: 'metadata-control-source',
        ),
      );
      expect((await dbEnqueueGroupExitIntent(db, queued)).committed, isTrue);
      expect(
        await db.query('pending_group_broadcasts'),
        hasLength(3),
        reason: 'total count is deliberately not a role-absence proof',
      );

      final refused = await dbPrepareGroupExitLeaveNotice(
        db,
        expected: queued,
        timelineRow: _timeline('group-1'),
        pendingBroadcastRow: _pending('group-1'),
        updatedAt: _eventAt,
      );
      expect(
        refused.disposition,
        DbGroupExitIntentMutationDisposition.refusedRoleBroadcastPresent,
      );
      expect(await db.query('group_messages'), isEmpty);
      expect(
        (await dbLoadGroupExitIntentForGroup(db, 'group-1'))!['state'],
        'queued',
      );

      await db.delete(
        'pending_group_broadcasts',
        where: 'kind IN (?, ?)',
        whereArgs: ['member_role_updated', 'member_role_updated_prepared'],
      );
      expect(
        (await db.query('pending_group_broadcasts')).single['id'],
        'metadata-control',
      );
      final ordinaryRemoval = await dbPrepareGroupExitLeaveNotice(
        db,
        expected: queued,
        timelineRow: _timeline('group-1'),
        pendingBroadcastRow: _pending('group-1', kind: 'member_removed'),
        updatedAt: _eventAt,
      );
      expect(
        ordinaryRemoval.disposition,
        DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
        reason: 'an ordinary member removal is not an exit-intent notice',
      );
      expect(await db.query('group_messages'), isEmpty);
      expect(
        (await dbLoadGroupExitIntentForGroup(db, 'group-1'))!['state'],
        'queued',
      );

      final prepared = await dbPrepareGroupExitLeaveNotice(
        db,
        expected: queued,
        timelineRow: _timeline('group-1'),
        pendingBroadcastRow: _pending('group-1'),
        updatedAt: _eventAt,
      );
      expect(
        prepared.disposition,
        DbGroupExitIntentMutationDisposition.committed,
      );
      expect(prepared.current!['state'], 'leave_notice_pending');
      expect(prepared.current!['revision'], 1);
      expect(prepared.current!['source_event_id'], 'source-group-1');
      expect(await db.query('group_messages'), hasLength(1));
      expect(await db.query('pending_group_broadcasts'), hasLength(2));

      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'new-role',
          kind: 'member_role_updated_prepared',
          source: 'new-role-source',
        ),
      );
      expect(
        await db.query(
          'pending_group_broadcasts',
          where: 'id = ?',
          whereArgs: ['new-role'],
        ),
        isEmpty,
      );
      expect(await db.query('pending_group_broadcasts'), hasLength(2));

      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'generic',
          kind: 'group_metadata_updated',
          source: 'generic-source',
        ),
      );
      expect(await db.query('pending_group_broadcasts'), hasLength(3));

      final pending = _pending('group-1');
      final ordinaryCompletion = Map<String, Object?>.from(pending)
        ..['kind'] = 'member_removed';
      expect(
        (await dbCompleteGroupExitLeaveNotice(
          db,
          expected: prepared.current!,
          pendingBroadcastRow: ordinaryCompletion,
          completionCode: 'delivered',
          updatedAt: '2026-07-21T08:04:00.000Z',
        )).disposition,
        DbGroupExitIntentMutationDisposition.refusedInvalidTransition,
        reason: 'an ordinary member removal cannot complete an exit intent',
      );
      expect(await db.query('pending_group_broadcasts'), hasLength(3));

      final mismatched = Map<String, Object?>.from(pending)
        ..['sys_text'] = '{"different":true}';
      expect(
        (await dbCompleteGroupExitLeaveNotice(
          db,
          expected: prepared.current!,
          pendingBroadcastRow: mismatched,
          completionCode: 'delivered',
          updatedAt: '2026-07-21T08:04:00.000Z',
        )).disposition,
        DbGroupExitIntentMutationDisposition.refusedNoticeMissing,
      );

      final completed = await dbCompleteGroupExitLeaveNotice(
        db,
        expected: prepared.current!,
        pendingBroadcastRow: pending,
        completionCode: 'delivered',
        updatedAt: '2026-07-21T08:04:00.000Z',
      );
      expect(
        completed.disposition,
        DbGroupExitIntentMutationDisposition.committed,
      );
      expect(completed.current!['state'], 'leave_notice_attempted');
      expect(
        (await db.query(
          'pending_group_broadcasts',
        )).map((row) => row['id']).toSet(),
        {'metadata-control', 'generic'},
      );

      final rotation = await dbAdvanceGroupExitIntent(
        db,
        expected: completed.current!,
        nextState: 'rotation_claimed',
        updatedAt: '2026-07-21T08:05:00.000Z',
      );
      expect(rotation.committed, isTrue);
      expect(
        (await dbAdvanceGroupExitIntent(
          db,
          expected: completed.current!,
          nextState: 'rotation_claimed',
          updatedAt: '2026-07-21T08:05:00.000Z',
        )).disposition,
        DbGroupExitIntentMutationDisposition.alreadyCurrent,
      );

      await _seedGroup(db, 'activation-control');
      await _insertRole(db, 'activation-control', prepared: true);
      final activationQueued = _intent('activation-control');
      expect(
        (await dbEnqueueGroupExitIntent(db, activationQueued)).committed,
        isTrue,
      );
      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'activation-control',
          id: 'active-role-activation-control',
          kind: 'member_role_updated',
          source: 'role-source-activation-control',
        ),
      );
      final activated = (await db.query(
        'pending_group_broadcasts',
        where: 'group_id = ?',
        whereArgs: ['activation-control'],
      )).single;
      expect(activated['id'], 'active-role-activation-control');
      expect(activated['kind'], 'member_role_updated');
      expect(
        (await dbLoadGroupExitIntentForGroup(
          db,
          'activation-control',
        ))!['state'],
        'queued',
      );

      final pair = await _openSharedDatabasePair('pb264_role_exit_race_');
      addTearDown(() => _closeSharedDatabasePair(pair));
      Future<void> proveRoleExitOrder({required bool roleFirst}) async {
        final groupId = roleFirst ? 'race-role-wins' : 'race-exit-wins';
        await _seedGroup(pair.first, groupId);
        await dbInsertPendingGroupBroadcast(
          pair.first,
          _pending(
            groupId,
            id: 'metadata-control-$groupId',
            kind: 'group_metadata_updated',
            source: 'metadata-control-source-$groupId',
          ),
        );
        final raceQueued = _intent(groupId);
        if (!roleFirst) {
          expect(
            (await dbEnqueueGroupExitIntent(pair.first, raceQueued)).committed,
            isTrue,
          );
        }
        final roleReady = Completer<void>();
        final exitReady = Completer<void>();
        final releaseRole = Completer<void>();
        final releaseExit = Completer<void>();
        final roleFuture = (() async {
          roleReady.complete();
          await releaseRole.future;
          await dbInsertPendingGroupBroadcast(
            pair.first,
            _pending(
              groupId,
              id: 'racing-role-$groupId',
              kind: 'member_role_updated_prepared',
              source: 'racing-role-source-$groupId',
            ),
          );
        })();
        final exitFuture = (() async {
          exitReady.complete();
          await releaseExit.future;
          return dbPrepareGroupExitLeaveNotice(
            pair.second,
            expected: raceQueued,
            timelineRow: _timeline(groupId),
            pendingBroadcastRow: _pending(groupId),
            updatedAt: '2026-07-21T08:03:50.000Z',
          );
        })();
        await Future.wait([roleReady.future, exitReady.future]);

        late final DbGroupExitIntentMutationResult exitRace;
        if (roleFirst) {
          releaseRole.complete();
          await roleFuture;
          expect(
            (await dbEnqueueGroupExitIntent(pair.first, raceQueued)).committed,
            isTrue,
          );
          releaseExit.complete();
          exitRace = await exitFuture;
        } else {
          releaseExit.complete();
          exitRace = await exitFuture;
          releaseRole.complete();
          await roleFuture;
        }

        final roleRows = await pair.first.query(
          'pending_group_broadcasts',
          where: 'group_id = ? AND kind IN (?, ?)',
          whereArgs: [
            groupId,
            'member_role_updated_prepared',
            'member_role_updated',
          ],
        );
        final raceIntent = await dbLoadGroupExitIntentForGroup(
          pair.first,
          groupId,
        );
        final messages = await pair.first.query(
          'group_messages',
          where: 'group_id = ?',
          whereArgs: [groupId],
        );
        if (roleFirst) {
          expect(
            exitRace.disposition,
            DbGroupExitIntentMutationDisposition.refusedRoleBroadcastPresent,
          );
          expect(roleRows, hasLength(1));
          expect(raceIntent!['state'], 'queued');
          expect(messages, isEmpty);
        } else {
          expect(exitRace.committed, isTrue);
          expect(roleRows, isEmpty);
          expect(raceIntent!['state'], 'leave_notice_pending');
          expect(messages, hasLength(1));
        }
        expect(
          await pair.first.query(
            'pending_group_broadcasts',
            where: 'group_id = ?',
            whereArgs: [groupId],
          ),
          hasLength(2),
          reason:
              'metadata plus the winning role/leave row keeps total count misleading',
        );
      }

      await proveRoleExitOrder(roleFirst: true);
      await proveRoleExitOrder(roleFirst: false);
    },
  );

  test(
    'prepared activation is allowed only while the exit remains queued',
    () async {
      await _seedGroup(db, 'group-1');
      await _insertRole(db, 'group-1', prepared: true);
      final queued = _intent('group-1');
      await dbEnqueueGroupExitIntent(db, queued);

      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'active-role',
          kind: 'member_role_updated',
          source: 'role-source-group-1',
        ),
      );
      expect(
        (await db.query('pending_group_broadcasts')).single['kind'],
        'member_role_updated',
      );

      await db.delete('pending_group_broadcasts');
      final prepared = await dbPrepareGroupExitLeaveNotice(
        db,
        expected: queued,
        timelineRow: _timeline('group-1'),
        pendingBroadcastRow: _pending('group-1'),
        updatedAt: _eventAt,
      );
      expect(prepared.committed, isTrue);
      await db.insert(
        'pending_group_broadcasts',
        _pending(
          'group-1',
          id: 'late-prepared',
          kind: 'member_role_updated_prepared',
          source: 'late-role-source',
        ),
      );
      await dbInsertPendingGroupBroadcast(
        db,
        _pending(
          'group-1',
          id: 'late-active',
          kind: 'member_role_updated',
          source: 'late-role-source',
        ),
      );
      final late = await db.query(
        'pending_group_broadcasts',
        where: 'source_message_id = ?',
        whereArgs: ['late-role-source'],
      );
      expect(late.single['kind'], 'member_role_updated_prepared');
      expect(late.single['id'], 'late-prepared');
    },
  );

  test(
    'PB264-07 real SQLite overlap cannot prepare an exit behind a role insert',
    () async {
      final pair = await _openSharedDatabasePair('pb264_role_claim_overlap_');
      addTearDown(() => _closeSharedDatabasePair(pair));
      const groupId = 'overlapping-role-wins';
      await _seedGroup(pair.first, groupId);
      await dbInsertPendingGroupBroadcast(
        pair.first,
        _pending(
          groupId,
          id: 'metadata-control-$groupId',
          kind: 'group_metadata_updated',
          source: 'metadata-control-source-$groupId',
        ),
      );
      final queued = _intent(groupId);
      expect(
        (await dbEnqueueGroupExitIntent(pair.first, queued)).committed,
        isTrue,
      );

      final exitWorkerReady = ReceivePort();
      addTearDown(exitWorkerReady.close);
      final exitWorkerEvents = StreamIterator<Object?>(exitWorkerReady);
      final workerPath = '${pair.directory.path}/identity.db';
      final workerExpected = Map<String, Object?>.from(queued);
      final workerTimeline = _timeline(groupId);
      final workerPending = _pending(groupId);
      final workerReadyPort = exitWorkerReady.sendPort;
      var exitSettled = false;
      final exitClaim =
          Isolate.run(
                () => _prepareExitOnIsolatedFfiWorker(
                  path: workerPath,
                  expected: workerExpected,
                  timelineRow: workerTimeline,
                  pendingBroadcastRow: workerPending,
                  updatedAt: '2026-07-21T08:03:50.000Z',
                  ready: workerReadyPort,
                ),
              )
              .catchError((Object error, StackTrace stackTrace) {
                workerReadyPort.send('worker-error: $error');
                Error.throwWithStackTrace(error, stackTrace);
              })
              .whenComplete(() => exitSettled = true);
      expect(
        await exitWorkerEvents.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(exitWorkerEvents.current, 'worker-entered');
      expect(
        await exitWorkerEvents.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final startExitClaim = exitWorkerEvents.current as SendPort;

      final roleWriterHasLock = Completer<void>();
      final allowRoleInsert = Completer<void>();
      final roleInsert = dbWriteTransaction(pair.first, (transaction) async {
        roleWriterHasLock.complete();
        await allowRoleInsert.future;
        await transaction.insert(
          'pending_group_broadcasts',
          _pending(
            groupId,
            id: 'overlapping-role-$groupId',
            kind: 'member_role_updated_prepared',
            source: 'overlapping-role-source-$groupId',
          ),
        );
      });
      await roleWriterHasLock.future;
      startExitClaim.send(null);

      // The production claim has been invoked on a second handle while the
      // role transaction owns SQLite's write lock. It cannot inspect role
      // absence or settle until that competing transaction commits.
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(exitSettled, isFalse);
      allowRoleInsert.complete();

      await roleInsert;
      final result = await exitClaim;
      final roleRows = await pair.first.query(
        'pending_group_broadcasts',
        where: 'group_id = ? AND kind IN (?, ?)',
        whereArgs: [
          groupId,
          'member_role_updated_prepared',
          'member_role_updated',
        ],
      );
      final stored = await dbLoadGroupExitIntentForGroup(pair.first, groupId);
      final timeline = await pair.first.query(
        'group_messages',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      final rowsForGroup = await pair.first.query(
        'pending_group_broadcasts',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );

      expect(
        result['disposition'],
        DbGroupExitIntentMutationDisposition.refusedRoleBroadcastPresent.name,
      );
      expect(roleRows, hasLength(1));
      expect(roleRows.single['id'], 'overlapping-role-$groupId');
      expect(stored!['state'], 'queued');
      expect(stored['revision'], 0);
      expect(timeline, isEmpty);
      expect(rowsForGroup.map((row) => row['id']).toSet(), {
        'metadata-control-$groupId',
        'overlapping-role-$groupId',
      });
      expect(
        stored['state'] == 'leave_notice_pending' && roleRows.isNotEmpty,
        isFalse,
        reason:
            'moving the role-absence read before the write transaction admits '
            'a prepared exit and a disqualifying role row together',
      );
    },
  );

  test(
    'PB264-12 cleanup is atomic and preserves a later membership generation',
    () async {
      await _seedGroup(db, 'group-1');
      final cleanup = _intent(
        'group-1',
        state: 'cleanup_pending',
        revision: 4,
        sourceEventId: 'source-group-1',
        eventAt: _eventAt,
      );
      await db.insert('group_exit_intents', cleanup);
      await db.insert('group_messages', _timeline('group-1'));
      await db.insert('group_keys', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 1,
        'encrypted_key': 'key',
        'created_at': _createdAt,
      });
      await db.insert('group_rejoin_state', <String, Object?>{
        'group_id': 'group-1',
        'rejoin_attempt_count': 1,
        'next_eligible_at': 0,
      });
      await db.insert('pending_group_broadcasts', _pending('group-1'));
      await _seedExecutableMembershipWork(db, 'group-1');

      final result = await dbCleanupOrRetireGroupExitIntent(
        db,
        expected: cleanup,
        updatedAt: '2026-07-21T08:10:00.000Z',
      );
      expect(
        result.disposition,
        DbGroupExitIntentMutationDisposition.committed,
      );
      expect(await db.query('groups'), isEmpty);
      expect(await db.query('group_members'), isEmpty);
      expect(await db.query('group_messages'), isEmpty);
      expect(await db.query('group_keys'), isEmpty);
      expect(await db.query('group_rejoin_state'), isEmpty);
      expect(await db.query('pending_group_broadcasts'), isEmpty);
      for (final table in const <String>[
        'group_pending_key_repairs',
        'group_pending_key_distributions',
        'group_pending_membership_messages',
        'group_history_gap_repairs',
        'group_pending_reactions',
        'pending_sibling_devices',
        'group_reaction_replay_outbox',
      ]) {
        expect(
          await db.query(table),
          isEmpty,
          reason: '$table cannot leak into a later same-id membership',
        );
      }
      expect(await db.query('group_exit_intents'), isEmpty);

      await _seedGroup(db, 'group-2', joinedAt: '2026-07-21T10:00:00.000Z');
      final stale = _intent(
        'group-2',
        state: 'cleanup_pending',
        revision: 4,
        sourceEventId: 'source-group-2',
        eventAt: _eventAt,
      );
      await db.insert('group_exit_intents', stale);
      await db.insert('group_messages', _timeline('group-2'));
      await db.insert('pending_group_broadcasts', _pending('group-2'));

      final retired = await dbCleanupOrRetireGroupExitIntent(
        db,
        expected: stale,
        updatedAt: '2026-07-21T08:10:00.000Z',
      );
      expect(
        retired.disposition,
        DbGroupExitIntentMutationDisposition.retiredStaleMembership,
      );
      expect(await db.query('group_exit_intents'), isEmpty);
      expect(await db.query('pending_group_broadcasts'), isEmpty);
      expect(await db.query('groups'), hasLength(1));
      expect(await db.query('group_members'), hasLength(1));
      expect(await db.query('group_messages'), hasLength(1));
    },
  );

  test(
    'cleanup rolls back every SQL deletion and pauses absent self',
    () async {
      await _seedGroup(db, 'group-fail');
      final cleanup = _intent(
        'group-fail',
        state: 'cleanup_pending',
        revision: 4,
        sourceEventId: 'source-group-fail',
        eventAt: _eventAt,
      );
      await db.insert('group_exit_intents', cleanup);
      await db.insert('group_messages', _timeline('group-fail'));
      await db.execute('''
      CREATE TRIGGER abort_exit_cleanup
      BEFORE DELETE ON groups
      WHEN OLD.id = 'group-fail'
      BEGIN
        SELECT RAISE(ABORT, 'injected cleanup failure');
      END
    ''');
      await expectLater(
        dbCleanupOrRetireGroupExitIntent(
          db,
          expected: cleanup,
          updatedAt: '2026-07-21T08:10:00.000Z',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('groups'), hasLength(1));
      expect(await db.query('group_members'), hasLength(1));
      expect(await db.query('group_messages'), hasLength(1));
      expect(await db.query('group_exit_intents'), hasLength(1));

      await db.execute('DROP TRIGGER abort_exit_cleanup');
      await db.delete(
        'group_members',
        where: 'group_id = ?',
        whereArgs: ['group-fail'],
      );
      final paused = await dbCleanupOrRetireGroupExitIntent(
        db,
        expected: cleanup,
        updatedAt: '2026-07-21T08:11:00.000Z',
      );
      expect(
        paused.disposition,
        DbGroupExitIntentMutationDisposition.refusedSelfMissing,
      );
      expect(await db.query('groups'), hasLength(1));
      expect(await db.query('group_messages'), hasLength(1));
      expect(await db.query('group_exit_intents'), hasLength(1));
    },
  );

  test('absent parent is already-clean and terminalization is exact', () async {
    final absent = _intent(
      'absent',
      state: 'cleanup_pending',
      revision: 4,
      sourceEventId: 'source-absent',
      eventAt: _eventAt,
    );
    await db.insert('group_exit_intents', absent);
    await db.insert('pending_group_broadcasts', _pending('absent'));
    final completed = await dbCleanupOrRetireGroupExitIntent(
      db,
      expected: absent,
      updatedAt: '2026-07-21T08:11:00.000Z',
    );
    expect(
      completed.disposition,
      DbGroupExitIntentMutationDisposition.cleanupAlreadyComplete,
    );
    expect(await db.query('group_exit_intents'), isEmpty);
    expect(await db.query('pending_group_broadcasts'), isEmpty);

    await db.insert('group_exit_intents', _intent('terminal'));
    await db.insert(
      'pending_group_broadcasts',
      _pending(
        'terminal',
        id: 'generic-terminal',
        kind: 'group_metadata_updated',
        source: 'generic-terminal',
      ),
    );
    expect(await dbTerminalizeGroupExitIntentForGroup(db, 'terminal'), 1);
    expect(await db.query('group_exit_intents'), isEmpty);
    // A queued intent has no leave-notice identity, so unrelated work remains.
    expect(await db.query('pending_group_broadcasts'), hasLength(1));
  });
}
