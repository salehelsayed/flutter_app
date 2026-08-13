import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/106_group_notification_display_outbox.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, 102);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeGroupRow({
    String id = 'group-1',
    String name = 'Test Group',
    String type = 'chat',
    String topicName = '/mknoon/groups/group-1',
    String? description = 'A test group',
    String createdAt = '2026-01-15T12:00:00.000Z',
    String createdBy = 'peer-creator',
    String myRole = 'admin',
    int isArchived = 0,
    String? archivedAt,
  }) {
    return {
      'id': id,
      'name': name,
      'type': type,
      'topic_name': topicName,
      'description': description,
      'created_at': createdAt,
      'created_by': createdBy,
      'my_role': myRole,
      'is_archived': isArchived,
      'archived_at': archivedAt,
    };
  }

  group('dbInsertGroup', () {
    test('inserts a new group', () async {
      await dbInsertGroup(db, makeGroupRow());

      final rows = await db.query('groups');
      expect(rows.length, 1);
      expect(rows[0]['id'], 'group-1');
      expect(rows[0]['name'], 'Test Group');
    });
  });

  group('dbLoadAllGroups', () {
    test('returns all groups ordered by created_at DESC', () async {
      await dbInsertGroup(
        db,
        makeGroupRow(
          id: 'g1',
          topicName: '/t/1',
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );
      await dbInsertGroup(
        db,
        makeGroupRow(
          id: 'g2',
          topicName: '/t/2',
          createdAt: '2026-01-02T00:00:00.000Z',
        ),
      );

      final results = await dbLoadAllGroups(db);
      expect(results.length, 2);
      expect(results[0]['id'], 'g2');
      expect(results[1]['id'], 'g1');
    });
  });

  group('dbLoadGroup', () {
    test('returns null for non-existent group', () async {
      final result = await dbLoadGroup(db, 'non-existent');
      expect(result, isNull);
    });

    test('returns group when it exists', () async {
      await dbInsertGroup(db, makeGroupRow());

      final result = await dbLoadGroup(db, 'group-1');
      expect(result, isNotNull);
      expect(result!['name'], 'Test Group');
    });
  });

  group('dbUpdateGroup', () {
    test('updates group fields', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbUpdateGroup(db, makeGroupRow(name: 'Updated Name'));

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['name'], 'Updated Name');
    });
  });

  group('dbCommitProtectedGroupMetadataAuthority', () {
    const eventAt = '2026-08-13T19:00:00.000Z';
    const preparedId = 'pga1:p:metadata-event';
    final memberRow = <String, Object?>{
      'group_id': 'group-1',
      'peer_id': 'peer-creator',
      'username': 'Creator',
      'role': 'admin',
      'permissions_json': '{}',
      'public_key': 'pk-creator',
      'ml_kem_public_key': 'mlkem-creator',
      'devices_json': '[]',
      'joined_at': '2026-01-15T12:00:00.000Z',
    };
    final pendingRow = <String, Object?>{
      'id': 'protected-authority:metadata-event:peer-linked',
      'group_id': 'group-1',
      'kind': 'group_authority_v1',
      'sys_text': 'immutable-protected-metadata-envelope',
      'recipient_peer_ids': jsonEncode(<String>['peer-linked']),
      'event_at': eventAt,
      'source_message_id': 'metadata-event:peer-linked',
      'created_at': eventAt,
      'updated_at': eventAt,
    };
    final authorityPayload = <String, Object?>{
      'proof': <String, Object?>{'eventId': 'metadata-event'},
    };

    setUp(() async {
      await dbInsertGroup(db, makeGroupRow());
      await db.insert('group_members', memberRow);
      await db.insert('group_keys', <String, Object?>{
        'group_id': 'group-1',
        'key_generation': 1,
        'encrypted_key': 'group-key-v1',
        'created_at': '2026-01-15T12:00:00.000Z',
      });
    });

    Future<void> commit({Map<String, Object?>? expectedGroup}) {
      return dbCommitProtectedGroupMetadataAuthority(
        db,
        expectedGroupRow: expectedGroup ?? makeGroupRow(),
        expectedMemberRows: <Map<String, Object?>>[memberRow],
        expectedLatestKeyGeneration: 1,
        groupRow: makeGroupRow(name: 'Protected Rename')
          ..['last_metadata_event_at'] = eventAt,
        pendingBroadcastRows: <Map<String, Object?>>[pendingRow],
        authorityPreparedSourcePeerId: 'peer-creator',
        authorityPreparedSourceEventId: preparedId,
        authorityPreparedSourceTimestamp: eventAt,
        authorityPreparedPayload: authorityPayload,
      );
    }

    test(
      'deferred prepare performs no SQL persistence before atomic commit',
      () async {
        final repository = GroupPendingBroadcastRepositoryImpl(
          dbInsert: (row) => dbInsertPendingGroupBroadcast(db, row),
          dbInsertProtectedBatch:
              ({
                required groupId,
                required rows,
                required authorityPreparedSourcePeerId,
                required authorityPreparedSourceEventId,
                required authorityPreparedSourceTimestamp,
                required authorityPreparedPayload,
              }) =>
                  dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
                    db,
                    groupId: groupId,
                    rows: rows,
                    authorityPreparedSourcePeerId:
                        authorityPreparedSourcePeerId,
                    authorityPreparedSourceEventId:
                        authorityPreparedSourceEventId,
                    authorityPreparedSourceTimestamp:
                        authorityPreparedSourceTimestamp,
                    authorityPreparedPayload: authorityPreparedPayload,
                  ),
          dbLoadForGroup: (groupId) =>
              dbLoadPendingGroupBroadcastsForGroup(db, groupId),
          dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(db),
          dbCountForGroup: (groupId) =>
              dbCountPendingGroupBroadcastsForGroup(db, groupId),
          dbDelete: (id) => dbDeletePendingGroupBroadcast(db, id),
        );
        const sender = GroupMemberDeviceIdentity(
          deviceId: 'device-creator',
          transportPeerId: 'transport-creator',
          deviceSigningPublicKey: 'pk-device-creator',
        );
        final replayData = <String, dynamic>{
          'groupId': 'group-1',
          'senderId': 'peer-creator',
          'messageId': 'metadata-event',
          'timestamp': eventAt,
          'text': '{"__sys":"group_metadata_updated"}',
        };
        final proof = AuthenticatedGroupAuthorityProof(
          eventId: 'metadata-event',
          groupId: 'group-1',
          eventAt: DateTime.parse(eventAt),
          keyEpoch: 1,
          control: ProtectedGroupAuthorityControl.memberConfig.wireValue,
          actorAccountPeerId: 'peer-creator',
          actorAccountPublicKey: 'pk-creator',
          senderTransportPeerId: sender.transportPeerId,
          senderTransportPublicKey: sender.deviceSigningPublicKey,
          authorityData: const <String, Object?>{'test': 'metadata'},
          signature: 'signed-metadata-authority',
        );
        final preparation = ProtectedGroupAuthorityPreparation(
          groupId: 'group-1',
          rows: <GroupPendingBroadcast>[
            GroupPendingBroadcast.fromMap(pendingRow),
          ],
          authorityProof: proof,
          control: ProtectedGroupAuthorityControl.memberConfig,
          replayData: replayData,
        );

        final disposition =
            await persistPreparedProtectedGroupAuthorityForRequest(
              repository: repository,
              request: ProtectedGroupAuthorityPrepareRequest(
                groupId: 'group-1',
                transitionId: 'metadata-event',
                control: ProtectedGroupAuthorityControl.memberConfig,
                replayData: replayData,
                actorAccountPeerId: 'peer-creator',
                actorAccountPublicKey: 'pk-creator',
                actorAccountPrivateKey: 'sk-creator',
                senderDevice: sender,
                frozenRecipients: const <GroupMemberDeviceIdentity>[],
                deferPersistenceUntilAtomicProjection: true,
              ),
              preparation: preparation,
            );

        expect(
          disposition,
          ProtectedGroupAuthorityPreparationPersistence.deferred,
        );
        expect(await db.query('pending_group_broadcasts'), isEmpty);
        expect(await db.query('group_event_log'), isEmpty);
      },
    );

    test(
      'commits metadata, immutable rows, and PREPARED without COMPLETE',
      () async {
        await commit();

        expect((await dbLoadGroup(db, 'group-1'))?['name'], 'Protected Rename');
        expect(await db.query('pending_group_broadcasts'), hasLength(1));
        expect(
          (await db.query(
            'group_event_log',
            orderBy: 'sequence ASC',
          )).map((row) => row['event_type']),
          <String>['protected_authority_prepared'],
        );
      },
    );

    test(
      'mid-commit failure rolls projection, rows, and PREPARED back',
      () async {
        await db.execute('''
          CREATE TRIGGER fail_metadata_prepared
          BEFORE INSERT ON group_event_log
          WHEN NEW.event_type = 'protected_authority_prepared'
          BEGIN
            SELECT RAISE(ABORT, 'forced metadata authority crash');
          END
        ''');

        await expectLater(commit(), throwsA(isA<DatabaseException>()));

        expect((await dbLoadGroup(db, 'group-1'))?['name'], 'Test Group');
        expect(await db.query('pending_group_broadcasts'), isEmpty);
        expect(await db.query('group_event_log'), isEmpty);
      },
    );

    test('CAS drift refuses without exposing PREPARED', () async {
      await dbUpdateGroup(db, makeGroupRow(name: 'Newer Remote Name'));

      await expectLater(commit(), throwsA(isA<StateError>()));

      expect((await dbLoadGroup(db, 'group-1'))?['name'], 'Newer Remote Name');
      expect(await db.query('pending_group_broadcasts'), isEmpty);
      expect(await db.query('group_event_log'), isEmpty);
    });
  });

  group('dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox', () {
    Future<void> stageMarker(String eventId, String groupId) async {
      const timestamp = '2026-08-03T08:00:00.000Z';
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        GroupNotificationDisplayOutboxEntry.message(
          eventId: eventId,
          groupId: groupId,
          messageId: 'message-$eventId',
          actorPeerId: 'peer-sender',
          eventTimestamp: timestamp,
          createdAt: timestamp,
          updatedAt: timestamp,
        ).toMap(),
      );
    }

    setUp(() async {
      await runGroupNotificationDisplayOutboxMigration(db);
      await dbInsertGroup(db, makeGroupRow());
      await dbInsertGroup(
        db,
        makeGroupRow(
          id: 'group-sibling',
          topicName: '/mknoon/groups/group-sibling',
        ),
      );
      await stageMarker('target-a', 'group-1');
      await stageMarker('target-b', 'group-1');
      await stageMarker('sibling', 'group-sibling');
    });

    test(
      'commits terminal state and deletes only exact-group custody',
      () async {
        await dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(db, {
          ...makeGroupRow(),
          'is_dissolved': 1,
          'dissolved_at': '2026-08-03T08:01:00.000Z',
          'dissolved_by': 'peer-admin',
        });

        final group = await dbLoadGroup(db, 'group-1');
        expect(group, containsPair('is_dissolved', 1));
        expect(group, containsPair('dissolved_by', 'peer-admin'));
        expect(
          (await db.query(
            'group_notification_display_outbox',
          )).map((row) => row['event_id']).toList(),
          <String>['sibling'],
        );
      },
    );

    test('cleanup failure rolls the dissolved row update back', () async {
      await db.execute('''
        CREATE TRIGGER fail_group_display_cleanup
        BEFORE DELETE ON group_notification_display_outbox
        WHEN OLD.group_id = 'group-1'
        BEGIN
          SELECT RAISE(ABORT, 'forced display cleanup failure');
        END
      ''');

      await expectLater(
        dbCommitDissolvedGroupAndDeleteNotificationDisplayOutbox(db, {
          ...makeGroupRow(),
          'is_dissolved': 1,
          'dissolved_at': '2026-08-03T08:01:00.000Z',
          'dissolved_by': 'peer-admin',
        }),
        throwsA(isA<DatabaseException>()),
      );

      final group = await dbLoadGroup(db, 'group-1');
      expect(group, containsPair('is_dissolved', 0));
      expect(
        (await db.query(
          'group_notification_display_outbox',
          orderBy: 'event_id',
        )).map((row) => row['event_id']),
        <String>['sibling', 'target-a', 'target-b'],
      );
    });
  });

  group('dbDeleteGroup', () {
    test('deletes a group', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbDeleteGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result, isNull);
    });
  });

  group('dbCountGroups', () {
    test('returns correct count', () async {
      expect(await dbCountGroups(db), 0);

      await dbInsertGroup(db, makeGroupRow(id: 'g1', topicName: '/t/1'));
      await dbInsertGroup(db, makeGroupRow(id: 'g2', topicName: '/t/2'));

      expect(await dbCountGroups(db), 2);
    });
  });

  group('dbArchiveGroup', () {
    test('sets is_archived to 1 and sets archived_at', () async {
      await dbInsertGroup(db, makeGroupRow());

      await dbArchiveGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['is_archived'], 1);
      expect(result['archived_at'], isNotNull);
    });
  });

  group('dbUnarchiveGroup', () {
    test('sets is_archived to 0 and clears archived_at', () async {
      await dbInsertGroup(
        db,
        makeGroupRow(isArchived: 1, archivedAt: '2026-01-15T12:00:00.000Z'),
      );

      await dbUnarchiveGroup(db, 'group-1');

      final result = await dbLoadGroup(db, 'group-1');
      expect(result!['is_archived'], 0);
      expect(result['archived_at'], isNull);
    });
  });

  group('dbLoadActiveGroups', () {
    test('returns only non-archived groups', () async {
      await dbInsertGroup(
        db,
        makeGroupRow(id: 'active', topicName: '/t/active', isArchived: 0),
      );
      await dbInsertGroup(
        db,
        makeGroupRow(
          id: 'archived',
          topicName: '/t/archived',
          isArchived: 1,
          archivedAt: '2026-01-15T12:00:00.000Z',
        ),
      );

      final results = await dbLoadActiveGroups(db);
      expect(results.length, 1);
      expect(results[0]['id'], 'active');
    });
  });

  test(
    'ordinary full-row update preserves removal authority and membership watermark while accepted replacement clears and advances',
    () async {
      const marker = '2026-07-20T12:00:00.000Z';
      const watermark = '2026-07-20T12:00:00.000Z';
      await dbInsertGroup(db, {
        ...makeGroupRow(id: 'protected', topicName: '/t/protected'),
        'self_removed_at': marker,
        'last_membership_event_at': watermark,
        'last_membership_event_id': 'removal-event',
      });

      await dbUpdateGroup(db, {
        ...makeGroupRow(
          id: 'protected',
          topicName: '/t/protected',
          name: 'ordinary metadata update',
        ),
        'self_removed_at': null,
        'last_membership_event_at': '2026-07-19T12:00:00.000Z',
        'last_membership_event_id': 'stale-event',
      });

      var stored = await dbLoadGroup(db, 'protected');
      expect(stored!['name'], 'ordinary metadata update');
      expect(stored['self_removed_at'], marker);
      expect(stored['last_membership_event_at'], watermark);
      expect(stored['last_membership_event_id'], 'removal-event');

      final accepted = await dbReplaceAcceptedGroupAuthority(
        db,
        row: {
          ...makeGroupRow(
            id: 'protected',
            topicName: '/t/protected',
            name: 'accepted membership',
          ),
        },
        expectedSelfRemovedAt: marker,
        acceptedMembershipEventAt: '2026-07-21T12:00:00.000Z',
        acceptedMembershipEventId: null,
      );

      expect(accepted, isTrue);
      stored = await dbLoadGroup(db, 'protected');
      expect(stored!['name'], 'accepted membership');
      expect(stored['self_removed_at'], isNull);
      expect(stored['last_membership_event_at'], '2026-07-21T12:00:00.000Z');
      expect(stored['last_membership_event_id'], isNull);

      await dbUpdateGroup(db, {
        ...makeGroupRow(
          id: 'protected',
          topicName: '/t/protected',
          name: 'ordinary post-accept metadata',
        ),
        'is_muted': 1,
        'last_membership_event_at': '2026-07-18T12:00:00.000Z',
        'last_membership_event_id': 'stale-after-accept',
      });
      stored = await dbLoadGroup(db, 'protected');
      expect(stored!['name'], 'ordinary post-accept metadata');
      expect(stored['is_muted'], 1);
      expect(stored['self_removed_at'], isNull);
      expect(stored['last_membership_event_at'], '2026-07-21T12:00:00.000Z');
      expect(stored['last_membership_event_id'], isNull);
    },
  );
}
