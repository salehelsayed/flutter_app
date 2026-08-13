import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/060_group_event_log.dart';
import 'package:flutter_app/core/database/migrations/086_pending_group_broadcasts.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runGroupEventLogMigration(db);
    await runPendingGroupBroadcastsMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('canonical payload ordering is deterministic', () {
    final first = canonicalizeGroupEventLogPayload({
      'z': 1,
      'a': {'b': 2, 'a': 1},
    });
    final second = canonicalizeGroupEventLogPayload({
      'a': {'a': 1, 'b': 2},
      'z': 1,
    });

    expect(first, second);
    expect(jsonDecode(first), {
      'a': {'a': 1, 'b': 2},
      'z': 1,
    });
  });

  test('appends entries with per-group hash chain', () async {
    final first = await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'message',
      sourcePeerId: 'peer-a',
      sourceEventId: 'msg-1',
      sourceTimestamp: '2026-04-30T12:00:00.000Z',
      payload: {'messageId': 'msg-1', 'text': 'hello'},
      createdAt: DateTime.utc(2026, 4, 30, 12, 0, 1),
    );
    final second = await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'member_removed',
      sourcePeerId: 'peer-admin',
      sourceEventId: 'sys-1',
      sourceTimestamp: '2026-04-30T12:01:00.000Z',
      payload: {'removedPeerId': 'peer-b'},
      createdAt: DateTime.utc(2026, 4, 30, 12, 1, 1),
    );

    expect(first['sequence'], 1);
    expect(first['previous_entry_hash'], isNull);
    expect(second['sequence'], 2);
    expect(second['previous_entry_hash'], first['entry_hash']);
    expect(await dbVerifyGroupEventLogChain(db), isEmpty);
  });

  test(
    'exact duplicate replay is idempotent but changed replay fails',
    () async {
      final first = await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'message',
        sourcePeerId: 'peer-a',
        sourceEventId: 'msg-1',
        sourceTimestamp: '2026-04-30T12:00:00.000Z',
        payload: {'messageId': 'msg-1', 'text': 'hello'},
        createdAt: DateTime.utc(2026, 4, 30, 12),
      );
      final duplicate = await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'message',
        sourcePeerId: 'peer-a',
        sourceEventId: 'msg-1',
        sourceTimestamp: '2026-04-30T12:00:00.000Z',
        payload: {'text': 'hello', 'messageId': 'msg-1'},
        createdAt: DateTime.utc(2026, 4, 30, 13),
      );

      expect(duplicate['id'], first['id']);
      expect(await dbLoadGroupEventLogEntries(db, 'group-1'), hasLength(1));

      expect(
        () => dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-1',
          eventType: 'message',
          sourcePeerId: 'peer-a',
          sourceEventId: 'msg-1',
          sourceTimestamp: '2026-04-30T12:00:00.000Z',
          payload: {'messageId': 'msg-1', 'text': 'tampered'},
        ),
        throwsA(isA<GroupEventLogTamperException>()),
      );
    },
  );

  test('chain verification detects row tampering', () async {
    await dbAppendGroupEventLogEntry(
      db,
      groupId: 'group-1',
      eventType: 'message',
      sourcePeerId: 'peer-a',
      sourceEventId: 'msg-1',
      sourceTimestamp: '2026-04-30T12:00:00.000Z',
      payload: {'messageId': 'msg-1', 'text': 'hello'},
      createdAt: DateTime.utc(2026, 4, 30, 12),
    );

    await db.update(
      'group_event_log',
      {'canonical_payload': '{"messageId":"msg-1","text":"changed"}'},
      where: 'source_event_id = ?',
      whereArgs: ['msg-1'],
    );

    final violations = await dbVerifyGroupEventLogChain(db);
    expect(violations, hasLength(1));
    expect(violations.single.reason, 'entry_hash_mismatch');
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT detects conflicting signed transition forks without leaking secrets',
    () async {
      final signedPayload = canonicalizeGroupEventLogPayload({
        'schemaVersion': 1,
        'transitionType': 'member_role_updated',
        'groupId': 'group-1',
        'sourceEventId': 'role-transition-1',
        'eventAt': '2026-05-01T12:00:00.000Z',
        'actor': {'peerId': 'peer-admin', 'signingPublicKey': 'pk-admin'},
        'transitionSubject': {
          'member': {'peerId': 'peer-bob', 'role': 'admin'},
        },
        'preTransitionStateHash': 'pre-state-hash',
        'transitionOutputHash': 'post-state-hash',
      });
      final audit = {
        'schemaVersion': 1,
        'transitionType': 'member_role_updated',
        'groupId': 'group-1',
        'sourceEventId': 'role-transition-1',
        'eventAt': '2026-05-01T12:00:00.000Z',
        'signatureAlgorithm': 'ed25519',
        'signedPayload': signedPayload,
        'signature': 'raw-signature-secret',
      };

      await dbAppendGroupEventLogEntry(
        db,
        groupId: 'group-1',
        eventType: 'member_role_updated',
        sourcePeerId: 'peer-admin',
        sourceEventId: 'role-transition-1',
        sourceTimestamp: '2026-05-01T12:00:00.000Z',
        payload: {'groupId': 'group-1', 'signedTransitionAudit': audit},
      );

      await expectLater(
        () => dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-1',
          eventType: 'member_role_updated',
          sourcePeerId: 'peer-admin',
          sourceEventId: 'role-transition-1',
          sourceTimestamp: '2026-05-01T12:00:00.000Z',
          payload: {
            'groupId': 'group-1',
            'signedTransitionAudit': {
              ...audit,
              'signedPayload': signedPayload.replaceAll(
                'peer-bob',
                'peer-carol',
              ),
            },
          },
        ),
        throwsA(
          isA<GroupEventLogTamperException>()
              .having(
                (error) => error.message,
                'message',
                contains('conflicting_replay'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('raw-signature-secret')),
              ),
        ),
      );
    },
  );

  test(
    'Plan 363 audit exact and bounded authority loaders preserve microsecond order',
    () async {
      for (final (id, timestamp) in <(String, String)>[
        ('pga1:c:a', '2026-08-13T12:00:00.000000Z'),
        ('pga1:c:b', '2026-08-13T12:00:00.000001Z'),
        ('pga1:c:c', '2026-08-13T12:00:00.001000Z'),
      ]) {
        await dbAppendGroupEventLogEntry(
          db,
          groupId: 'group-authority-history',
          eventType: 'protected_authority_complete',
          sourcePeerId: 'peer-admin',
          sourceEventId: id,
          sourceTimestamp: timestamp,
          payload: <String, Object?>{'proof': id},
        );
      }

      expect(
        (await dbLoadGroupEventLogEntryExact(
          db,
          groupId: 'group-authority-history',
          sourceEventId: 'pga1:c:b',
        ))?['source_timestamp'],
        '2026-08-13T12:00:00.000001Z',
      );
      final firstPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        limit: 2,
      );
      expect(firstPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:a',
        'pga1:c:b',
      ]);
      final secondPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        afterSourceTimestamp: firstPage.last['source_timestamp'] as String,
        afterSourceEventId: firstPage.last['source_event_id'] as String,
        limit: 2,
      );
      expect(secondPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:c',
      ]);
      final newestPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        newestFirst: true,
        limit: 2,
      );
      expect(newestPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:c',
        'pga1:c:b',
      ]);
      final olderPage = await dbLoadGroupEventLogTypePage(
        db,
        groupId: 'group-authority-history',
        eventType: 'protected_authority_complete',
        afterSourceTimestamp: newestPage.last['source_timestamp'] as String,
        afterSourceEventId: newestPage.last['source_event_id'] as String,
        newestFirst: true,
        limit: 2,
      );
      expect(olderPage.map((row) => row['source_event_id']), <Object?>[
        'pga1:c:a',
      ]);

      final requestedAt = DateTime.utc(2026, 8, 13, 12, 0, 0, 1);
      AuthenticatedGroupAuthorityProof proof({
        required DateTime eventAt,
        required int keyEpoch,
        required String signature,
      }) => AuthenticatedGroupAuthorityProof(
        eventId: 'shared-event-id',
        groupId: 'group-authority-history',
        eventAt: eventAt,
        keyEpoch: keyEpoch,
        control: 'member_role_updated',
        actorAccountPeerId: 'peer-admin',
        actorAccountPublicKey: 'pk-admin',
        senderTransportPeerId: 'transport-admin',
        senderTransportPublicKey: 'pk-device-admin',
        authorityData: const <String, Object?>{
          'groupId': 'group-authority-history',
        },
        signature: signature,
      );
      final matchingComplete = proof(
        eventAt: requestedAt,
        keyEpoch: 7,
        signature: 'valid-complete',
      );
      for (final collidingGenesis in <AuthenticatedGroupAuthorityProof>[
        proof(
          eventAt: requestedAt.subtract(const Duration(microseconds: 1)),
          keyEpoch: 6,
          signature: 'valid-other-version',
        ),
        proof(eventAt: requestedAt, keyEpoch: 7, signature: 'invalid-genesis'),
      ]) {
        final resolved = await loadAuthenticatedAuthorityVersion(
          load: ({required groupId, required phase, required eventId}) async =>
              phase == AuthenticatedGroupAuthorityPhase.genesis
              ? collidingGenesis
              : matchingComplete,
          verify:
              ({required publicKey, required data, required signature}) async =>
                  signature.startsWith('valid-'),
          groupId: 'group-authority-history',
          eventAt: requestedAt,
          eventId: 'shared-event-id',
          keyEpoch: 7,
        );
        expect(
          resolved,
          same(matchingComplete),
          reason:
              'a colliding genesis must not mask the exact COMPLETE version',
        );
      }
    },
  );

  test(
    'unfinished local protected authority paging cannot starve behind completed or remote history',
    () async {
      const groupId = 'group-unfinished-authority';
      const oldEventId = 'old-interrupted-event';
      const oldTimestamp = '2026-08-13T10:00:00.000000Z';
      await dbAppendGroupEventLogEntry(
        db,
        groupId: groupId,
        eventType: protectedGroupAuthorityPreparedEventType,
        sourcePeerId: 'peer-admin',
        sourceEventId: 'pga1:p:$oldEventId',
        sourceTimestamp: oldTimestamp,
        payload: const <String, Object?>{'proof': oldEventId},
      );

      // More than the old four-page scan budget. Both terminal pairs and
      // receiver-authored PREPARED facts must be excluded before LIMIT rather
      // than hiding the interrupted older local fact.
      for (var index = 0; index < 805; index++) {
        final eventId = 'completed-$index';
        final timestamp = DateTime.utc(
          2026,
          8,
          13,
          11,
        ).add(Duration(microseconds: index)).toIso8601String();
        final payload = <String, Object?>{'proof': eventId};
        await dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: protectedGroupAuthorityPreparedEventType,
          sourcePeerId: 'peer-admin',
          sourceEventId: 'pga1:p:$eventId',
          sourceTimestamp: timestamp,
          payload: payload,
        );
        await dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: protectedGroupAuthorityCompleteEventType,
          sourcePeerId: 'peer-admin',
          sourceEventId: 'pga1:c:$eventId',
          sourceTimestamp: timestamp,
          payload: payload,
        );
        await dbAppendGroupEventLogEntry(
          db,
          groupId: groupId,
          eventType: protectedGroupAuthorityPreparedEventType,
          sourcePeerId: 'peer-remote',
          sourceEventId: 'pga1:p:remote-$index',
          sourceTimestamp: timestamp,
          payload: <String, Object?>{'proof': 'remote-$index'},
        );
      }

      final unfinished = await dbLoadUnfinishedProtectedAuthorityPage(
        db,
        groupId: groupId,
        sourcePeerId: 'peer-admin',
        limit: 1,
      );
      expect(unfinished, hasLength(1));
      expect(unfinished.single['source_event_id'], 'pga1:p:$oldEventId');
      expect(unfinished.single['source_timestamp'], oldTimestamp);
      expect(await dbVerifyGroupEventLogChain(db), isEmpty);
    },
  );

  group('durable protected authority ABORTED transaction', () {
    const groupId = 'group-abort-authority';
    const transitionId = 'member-role-event-1';
    const sourcePeerId = 'peer-admin';
    const sourceTimestamp = '2026-08-13T15:00:00.000000Z';
    final proof = AuthenticatedGroupAuthorityProof(
      eventId: transitionId,
      groupId: groupId,
      eventAt: DateTime.utc(2026, 8, 13, 15),
      keyEpoch: 4,
      control: 'member_role_updated',
      actorAccountPeerId: sourcePeerId,
      actorAccountPublicKey: 'pk-admin',
      senderTransportPeerId: 'transport-admin',
      senderTransportPublicKey: 'pk-device-admin',
      authorityData: const <String, Object?>{
        'groupId': groupId,
        'senderId': sourcePeerId,
        'messageId': transitionId,
        'recipientTransportPeerIds': <String>[
          'transport-target-1',
          'transport-target-2',
        ],
      },
      signature: 'signed-authority',
    );
    late final preparedSourceEventId = authenticatedGroupAuthoritySourceEventId(
      AuthenticatedGroupAuthorityPhase.prepared,
      transitionId,
    );
    late final abortedSourceEventId = authenticatedGroupAuthoritySourceEventId(
      AuthenticatedGroupAuthorityPhase.aborted,
      transitionId,
    );
    late final completeSourceEventId = authenticatedGroupAuthoritySourceEventId(
      AuthenticatedGroupAuthorityPhase.complete,
      transitionId,
    );
    late final authorityPayload = authenticatedGroupAuthorityFactPayload(proof);

    Map<String, Object?> ownerRow(
      int index, {
      String eventId = transitionId,
      String control = 'member_role_updated',
    }) {
      final recipient = 'transport-target-$index';
      final deliveryId = protectedGroupAuthorityDeliveryId(
        control,
        eventId,
        recipient,
      );
      return <String, Object?>{
        'id': 'protected-authority:$deliveryId',
        'group_id': groupId,
        'kind': 'group_authority_v1',
        'sys_text': 'immutable-envelope-$index',
        'recipient_peer_ids': jsonEncode(<String>[recipient]),
        'event_at': sourceTimestamp,
        'source_message_id': deliveryId,
        'created_at': sourceTimestamp,
        'updated_at': sourceTimestamp,
      };
    }

    Future<void> seedPrepared(List<Map<String, Object?>> owners) async {
      await dbAppendGroupEventLogEntry(
        db,
        groupId: groupId,
        eventType: protectedGroupAuthorityPreparedEventType,
        sourcePeerId: sourcePeerId,
        sourceEventId: preparedSourceEventId,
        sourceTimestamp: sourceTimestamp,
        payload: authorityPayload,
      );
      for (final owner in owners) {
        await db.insert('pending_group_broadcasts', owner);
      }
    }

    Future<DbProtectedGroupAuthorityAbortResult> abort(
      List<Map<String, Object?>> expectedOwners,
    ) => dbAbortPendingGroupBroadcastsWithAuthorityAtomically(
      db,
      groupId: groupId,
      expectedRows: expectedOwners,
      authorityPreparedSourcePeerId: sourcePeerId,
      authorityPreparedSourceEventId: preparedSourceEventId,
      authorityPreparedSourceTimestamp: sourceTimestamp,
      authorityPreparedPayload: authorityPayload,
      authorityAbortedSourcePeerId: sourcePeerId,
      authorityAbortedSourceEventId: abortedSourceEventId,
      authorityAbortedSourceTimestamp: sourceTimestamp,
      authorityAbortedPayload: authorityPayload,
      authorityCompleteSourceEventId: completeSourceEventId,
    );

    test(
      'atomically appends ABORTED and deletes every exact owner row',
      () async {
        final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
        await seedPrepared(owners);

        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.aborted,
        );

        expect(await db.query('pending_group_broadcasts'), isEmpty);
        final history = await dbLoadGroupEventLogEntries(db, groupId);
        expect(history.map((row) => row['event_type']), <Object?>[
          protectedGroupAuthorityPreparedEventType,
          protectedGroupAuthorityAbortedEventType,
        ]);
        expect(history.last['source_event_id'], abortedSourceEventId);
        expect(
          history.last['canonical_payload'],
          canonicalizeGroupEventLogPayload(authorityPayload),
        );
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test(
      'atomically retires the exact ordinary role PREPARED owner too',
      () async {
        final protectedOwners = <Map<String, Object?>>[
          ownerRow(1),
          ownerRow(2),
        ];
        final ordinaryOwner = <String, Object?>{
          'id': 'pending_group_broadcast:$groupId:$transitionId',
          'group_id': groupId,
          'kind': 'member_role_updated_prepared',
          'sys_text': 'signed-role-transition',
          'recipient_peer_ids': jsonEncode(<String>['peer-member']),
          'event_at': sourceTimestamp,
          'source_message_id': transitionId,
          'created_at': sourceTimestamp,
          'updated_at': sourceTimestamp,
        };
        final owners = <Map<String, Object?>>[
          ...protectedOwners,
          ordinaryOwner,
        ];
        await seedPrepared(owners);

        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.aborted,
        );

        expect(await db.query('pending_group_broadcasts'), isEmpty);
        final history = await dbLoadGroupEventLogEntries(db, groupId);
        expect(history.map((row) => row['event_type']), <Object?>[
          protectedGroupAuthorityPreparedEventType,
          protectedGroupAuthorityAbortedEventType,
        ]);
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test('refuses ABORTED after COMPLETE and preserves exact owners', () async {
      final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
      await seedPrepared(owners);
      await dbAppendGroupEventLogEntry(
        db,
        groupId: groupId,
        eventType: protectedGroupAuthorityCompleteEventType,
        sourcePeerId: sourcePeerId,
        sourceEventId: completeSourceEventId,
        sourceTimestamp: sourceTimestamp,
        payload: authorityPayload,
      );

      expect(
        await abort(owners),
        DbProtectedGroupAuthorityAbortResult.refusedComplete,
      );

      expect(await db.query('pending_group_broadcasts'), hasLength(2));
      final history = await dbLoadGroupEventLogEntries(db, groupId);
      expect(history.map((row) => row['event_type']), <Object?>[
        protectedGroupAuthorityPreparedEventType,
        protectedGroupAuthorityCompleteEventType,
      ]);
      expect(await dbVerifyGroupEventLogChain(db), isEmpty);
    });

    test(
      'owner mismatch rolls back without ABORTED or partial deletion',
      () async {
        final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
        await seedPrepared(owners);
        final mismatchedOwners = <Map<String, Object?>>[
          owners.first,
          <String, Object?>{...owners.last, 'sys_text': 'different-envelope'},
        ];

        expect(
          await abort(mismatchedOwners),
          DbProtectedGroupAuthorityAbortResult.conflict,
        );

        final storedOwners = await db.query(
          'pending_group_broadcasts',
          orderBy: 'id ASC',
        );
        expect(storedOwners, hasLength(2));
        expect(storedOwners.map((row) => row['sys_text']), <Object?>[
          'immutable-envelope-1',
          'immutable-envelope-2',
        ]);
        final history = await dbLoadGroupEventLogEntries(db, groupId);
        expect(history, hasLength(1));
        expect(
          history.single['event_type'],
          protectedGroupAuthorityPreparedEventType,
        );
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test(
      'omitted matching owner refuses ABORTED without partial deletion',
      () async {
        final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
        await seedPrepared(owners);

        expect(
          await abort(<Map<String, Object?>>[owners.first]),
          DbProtectedGroupAuthorityAbortResult.conflict,
        );

        expect(await db.query('pending_group_broadcasts'), hasLength(2));
        final history = await dbLoadGroupEventLogEntries(db, groupId);
        expect(history, hasLength(1));
        expect(
          history.single['event_type'],
          protectedGroupAuthorityPreparedEventType,
        );
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test('unrelated supplied owner is preserved and refuses ABORTED', () async {
      final owner = ownerRow(1);
      final unrelated = ownerRow(2, eventId: 'unrelated-event');
      await seedPrepared(<Map<String, Object?>>[owner, unrelated]);

      expect(
        await abort(<Map<String, Object?>>[owner, unrelated]),
        DbProtectedGroupAuthorityAbortResult.conflict,
      );

      final stored = await db.query(
        'pending_group_broadcasts',
        orderBy: 'id ASC',
      );
      expect(stored, hasLength(2));
      expect(stored.map((row) => row['source_message_id']).toSet(), <Object?>{
        owner['source_message_id'],
        unrelated['source_message_id'],
      });
      expect(await dbLoadGroupEventLogEntries(db, groupId), hasLength(1));
      expect(await dbVerifyGroupEventLogChain(db), isEmpty);
    });

    test(
      'recipient outside the signed ACL cannot be deleted as an owner',
      () async {
        final owner = ownerRow(1);
        final outsideAcl = ownerRow(3);
        await seedPrepared(<Map<String, Object?>>[owner, outsideAcl]);

        expect(
          await abort(<Map<String, Object?>>[owner, outsideAcl]),
          DbProtectedGroupAuthorityAbortResult.conflict,
        );

        expect(await db.query('pending_group_broadcasts'), hasLength(2));
        expect(await dbLoadGroupEventLogEntries(db, groupId), hasLength(1));
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test('exact retry is idempotent after durable ABORTED', () async {
      final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
      await seedPrepared(owners);
      expect(await abort(owners), DbProtectedGroupAuthorityAbortResult.aborted);

      expect(
        await abort(owners),
        DbProtectedGroupAuthorityAbortResult.alreadyAborted,
      );

      expect(await db.query('pending_group_broadcasts'), isEmpty);
      final history = await dbLoadGroupEventLogEntries(db, groupId);
      expect(history, hasLength(2));
      expect(
        history
            .where(
              (row) =>
                  row['event_type'] == protectedGroupAuthorityAbortedEventType,
            )
            .length,
        1,
      );
      expect(await dbVerifyGroupEventLogChain(db), isEmpty);
    });

    test(
      'idempotent retry refuses a matching owner recreated below ABORTED',
      () async {
        final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
        await seedPrepared(owners);
        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.aborted,
        );
        await db.insert('pending_group_broadcasts', owners.last);

        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.conflict,
        );

        final survivors = await db.query('pending_group_broadcasts');
        expect(survivors, hasLength(1));
        expect(survivors.single['id'], owners.last['id']);
        final history = await dbLoadGroupEventLogEntries(db, groupId);
        expect(
          history
              .where(
                (row) =>
                    row['event_type'] ==
                    protectedGroupAuthorityAbortedEventType,
              )
              .length,
          1,
        );
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );

    test(
      'idempotent retry refuses an unrelated collision at an expected id',
      () async {
        final owners = <Map<String, Object?>>[ownerRow(1), ownerRow(2)];
        await seedPrepared(owners);
        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.aborted,
        );
        final collision = <String, Object?>{
          ...ownerRow(1, eventId: 'unrelated-after-abort'),
          'id': owners.first['id'],
        };
        await db.insert('pending_group_broadcasts', collision);

        expect(
          await abort(owners),
          DbProtectedGroupAuthorityAbortResult.conflict,
        );

        final survivors = await db.query('pending_group_broadcasts');
        expect(survivors, hasLength(1));
        expect(
          survivors.single['source_message_id'],
          collision['source_message_id'],
        );
        expect(await dbVerifyGroupEventLogChain(db), isEmpty);
      },
    );
  });
}
