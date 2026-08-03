import 'package:flutter_app/core/database/helpers/group_notification_canonical_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/group_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runProductionOnCreate(db, 106);
    await db.insert('groups', <String, Object?>{
      'id': 'group-a',
      'name': 'Family',
      'type': 'chat',
      'topic_name': '/group-a',
      'created_at': '2026-08-03T00:00:00.000Z',
      'created_by': 'self',
      'my_role': 'admin',
    });
  });

  tearDown(() => db.close());

  Future<void> insertMessage({
    required String id,
    required String sender,
    required bool incoming,
    required String timestamp,
    String? readAt,
    String? terminalEventId,
  }) {
    return db.insert('group_messages', <String, Object?>{
      'id': id,
      'group_id': 'group-a',
      'sender_peer_id': sender,
      'text': 'body',
      'timestamp': timestamp,
      'status': 'delivered',
      'is_incoming': incoming ? 1 : 0,
      'read_at': readAt,
      'created_at': timestamp,
      'notification_display_terminal_event_id': terminalEventId,
    });
  }

  test(
    'message validity is exact, unread, incoming, and group-scoped',
    () async {
      await insertMessage(
        id: 'unread',
        sender: 'alice',
        incoming: true,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await insertMessage(
        id: 'read',
        sender: 'alice',
        incoming: true,
        readAt: '2026-08-03T02:00:00.000Z',
        timestamp: '2026-08-03T01:30:00.000Z',
      );

      expect(
        await dbIsUnreadGroupNotificationMessage(
          db,
          groupId: 'group-a',
          eventIdentity: 'unread',
        ),
        isTrue,
      );
      expect(
        await dbIsUnreadGroupNotificationMessage(
          db,
          groupId: 'group-a',
          eventIdentity: 'read',
        ),
        isFalse,
      );
    },
  );

  test('latest fallback excludes unqualified and read rows', () async {
    await insertMessage(
      id: 'qualified-old',
      sender: 'alice',
      incoming: true,
      timestamp: '2026-08-03T01:00:00.000Z',
      terminalEventId: 'qualified-old',
    );
    await insertMessage(
      id: 'unqualified-new',
      sender: 'bob',
      incoming: true,
      timestamp: '2026-08-03T03:00:00.000Z',
    );
    await insertMessage(
      id: 'qualified-read-newer',
      sender: 'bob',
      incoming: true,
      timestamp: '2026-08-03T02:00:00.000Z',
      readAt: '2026-08-03T04:00:00.000Z',
      terminalEventId: 'qualified-read-newer',
    );

    expect(
      (await dbLoadLatestUnreadGroupNotificationMessage(db, 'group-a'))?['id'],
      'qualified-old',
    );
  });

  test(
    'reaction validity follows active terminal ADD and target existence',
    () async {
      await insertMessage(
        id: 'target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-state',
        'message_id': 'target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': '2026-08-03T02:00:00.000Z',
        'created_at': '2026-08-03T02:00:00.000Z',
        'notification_display_terminal_event_id': 'reaction-add-event',
      });

      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'reaction-add-event',
        ),
        GroupNotificationCanonicalContentDecision.keep,
      );
      await db.update(
        'message_reactions',
        <String, Object?>{'removed_at': '2026-08-03T03:00:00.000Z'},
        where: 'id = ?',
        whereArgs: <Object?>['reaction-state'],
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'reaction-add-event',
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
    },
  );

  test(
    'conversation read durably acknowledges existing reactions but preserves later and not-ready work',
    () async {
      const oldAt = '2026-08-03T02:00:00.000Z';
      const futureAt = '2026-08-03T03:00:00.000Z';
      await insertMessage(
        id: 'read-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-before-read',
        'message_id': 'read-target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': oldAt,
        'created_at': oldAt,
        'notification_display_terminal_event_id': 'event-before-read',
      });
      final readyCustody = GroupNotificationDisplayOutboxEntry.reaction(
        eventId: 'ready-before-read',
        groupId: 'group-a',
        messageId: 'read-target',
        actorPeerId: 'alice',
        eventTimestamp: oldAt,
        reactionId: 'reaction-before-read',
        reactionAction: 'add',
        reactionTombstone: false,
        createdAt: oldAt,
        updatedAt: oldAt,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        readyCustody.toMap(),
      );
      expect(
        await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
          db,
          eventId: readyCustody.eventId,
          expectedRevision: 1,
          updatedAt: oldAt,
        ),
        isTrue,
      );
      const notReadyCustody = GroupNotificationDisplayOutboxEntry.reaction(
        eventId: 'not-ready-after-read-race',
        groupId: 'group-a',
        messageId: 'read-target',
        actorPeerId: 'bob',
        eventTimestamp: futureAt,
        reactionId: 'reaction-after-read-race',
        reactionAction: 'add',
        reactionTombstone: false,
        createdAt: futureAt,
        updatedAt: futureAt,
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        notReadyCustody.toMap(),
      );

      expect(await dbMarkGroupMessagesAsRead(db, 'group-a'), 0);

      final acknowledged = (await db.query(
        'message_reactions',
        where: 'id = ?',
        whereArgs: const <Object?>['reaction-before-read'],
      )).single;
      expect(acknowledged['notification_acknowledged_at'], isNotNull);
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(
          db,
          readyCustody.eventId,
        ),
        isNotNull,
        reason:
            'a loaded ready retry must retain custody until its exact '
            'acknowledgement fence observes the read',
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(
          db,
          notReadyCustody.eventId,
        ),
        isNotNull,
        reason:
            'a pre-mutation marker racing the read is not yet proven viewed',
      );
      expect(
        await dbLoadGroupNotificationReconciliationOutboxEntry(db, 'group-a'),
        isNotNull,
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'event-before-read',
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
      expect(
        await dbLoadLatestActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
        ),
        isNull,
      );

      await db.insert('message_reactions', <String, Object?>{
        'id': 'reaction-after-read',
        'message_id': 'read-target',
        'emoji': '🎉',
        'sender_peer_id': 'carol',
        'timestamp': futureAt,
        'created_at': futureAt,
        'notification_display_terminal_event_id': 'event-after-read',
      });
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'event-after-read',
        ),
        GroupNotificationCanonicalContentDecision.keep,
      );
      expect(
        (await dbLoadLatestActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
        ))?['notification_display_terminal_event_id'],
        'event-after-read',
      );
    },
  );

  test(
    'push-before-inbox reaction acknowledgement transfers to its exact later ADD',
    () async {
      const rawEventId = 'reaction-before-inbox-event';
      final eventIdentity = boundedReactionEventIdentity(rawEventId);
      await insertMessage(
        id: 'late-reaction-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T04:00:00.000Z',
      );

      expect(
        await dbMarkGroupMessagesAsRead(
          db,
          'group-a',
          acknowledgedContentKind: 'reaction',
          acknowledgedEventIdentity: eventIdentity,
          acknowledgedGeneration: 'generation-before-inbox',
        ),
        0,
      );
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'reaction',
          eventIdentity: eventIdentity,
        ),
        allOf(
          containsPair('generation', 'generation-before-inbox'),
          containsPair('event_identity', eventIdentity),
        ),
      );

      final result = await dbApplyIncomingReactionMutation(
        db,
        const <String, Object?>{
          'id': 'late-reaction-state',
          'message_id': 'late-reaction-target',
          'emoji': '👍',
          'sender_peer_id': 'alice',
          'timestamp': '2026-08-03T04:01:00.000Z',
          'created_at': '2026-08-03T04:01:00.000Z',
        },
        mutation: DbIncomingReactionMutation.add,
        groupIdForNotificationCleanup: 'group-a',
        notificationEventIdForStaleAddCleanup: rawEventId,
      );

      expect(result, DbIncomingReactionApplyResult.inserted);
      final transferred = (await db.query(
        'message_reactions',
        where: 'id = ?',
        whereArgs: const <Object?>['late-reaction-state'],
      )).single;
      expect(transferred['notification_acknowledged_at'], isNotNull);
      expect(
        transferred['notification_display_terminal_event_id'],
        eventIdentity,
      );
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'reaction',
          eventIdentity: eventIdentity,
        ),
        isNull,
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: eventIdentity,
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );

      const laterRawEventId = 'reaction-after-read-event';
      final later = await dbApplyIncomingReactionMutation(
        db,
        const <String, Object?>{
          'id': 'late-reaction-state-2',
          'message_id': 'late-reaction-target',
          'emoji': '🎉',
          'sender_peer_id': 'alice',
          'timestamp': '2026-08-03T04:02:00.000Z',
          'created_at': '2026-08-03T04:02:00.000Z',
        },
        mutation: DbIncomingReactionMutation.add,
        groupIdForNotificationCleanup: 'group-a',
        notificationEventIdForStaleAddCleanup: laterRawEventId,
      );
      expect(later, DbIncomingReactionApplyResult.updated);
      final laterRow = (await db.query(
        'message_reactions',
        where: 'id = ?',
        whereArgs: const <Object?>['late-reaction-state-2'],
      )).single;
      expect(laterRow['notification_acknowledged_at'], isNull);
    },
  );

  test(
    'read binds exact staged reaction custody before a loaded retry can show',
    () async {
      const rawEventId = 'staged-before-read-event';
      final eventIdentity = boundedReactionEventIdentity(rawEventId);
      await insertMessage(
        id: 'staged-before-read-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T04:02:30.000Z',
      );
      await db.insert('message_reactions', const <String, Object?>{
        'id': 'staged-before-read-reaction',
        'message_id': 'staged-before-read-target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': '2026-08-03T04:02:31.000Z',
        'created_at': '2026-08-03T04:02:31.000Z',
      });
      const custody = GroupNotificationDisplayOutboxEntry.reaction(
        eventId: rawEventId,
        groupId: 'group-a',
        messageId: 'staged-before-read-target',
        actorPeerId: 'alice',
        eventTimestamp: '2026-08-03T04:02:31.000Z',
        reactionId: 'staged-before-read-reaction',
        reactionAction: 'add',
        reactionTombstone: false,
        readiness: GroupNotificationDisplayOutboxReadiness.ready,
        revision: 2,
        createdAt: '2026-08-03T04:02:31.000Z',
        updatedAt: '2026-08-03T04:02:31.000Z',
      );
      await db.insert('group_notification_display_outbox', custody.toMap());

      expect(
        await dbMarkGroupMessagesAsRead(
          db,
          'group-a',
          acknowledgedContentKind: 'reaction',
          acknowledgedEventIdentity: eventIdentity,
          acknowledgedGeneration: 'staged-before-read-generation',
        ),
        0,
      );

      final reaction = (await db.query(
        'message_reactions',
        where: 'id = ?',
        whereArgs: const <Object?>['staged-before-read-reaction'],
      )).single;
      expect(reaction['notification_acknowledged_at'], isNotNull);
      expect(reaction['notification_display_terminal_event_id'], eventIdentity);
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'reaction',
          eventIdentity: eventIdentity,
        ),
        isNull,
        reason: 'the canonical reaction row has absorbed exact custody',
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: eventIdentity,
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, rawEventId),
        isNotNull,
        reason: 'the keyed projector still owns exact completion',
      );
    },
  );

  test(
    'push-before-inbox message acknowledgement transfers to its exact later row',
    () async {
      expect(
        await dbMarkGroupMessagesAsRead(
          db,
          'group-a',
          acknowledgedContentKind: 'message',
          acknowledgedEventIdentity: 'late-message',
          acknowledgedGeneration: 'late-message-generation',
        ),
        0,
      );
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'message',
          eventIdentity: 'late-message',
        ),
        isNotNull,
      );

      expect(
        await dbInsertGroupMessage(db, <String, Object?>{
          'id': 'late-message',
          'group_id': 'group-a',
          'sender_peer_id': 'alice',
          'text': 'arrived after the read boundary',
          'timestamp': '2026-08-03T04:03:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-08-03T04:03:00.000Z',
        }),
        isTrue,
      );
      final transferred = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: const <Object?>['late-message'],
      )).single;
      expect(transferred['read_at'], isNotNull);
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'message',
          eventIdentity: 'late-message',
        ),
        isNull,
      );
      expect(
        await dbIsGroupNotificationEventAcknowledged(
          db,
          groupId: 'group-a',
          contentKind: ConversationNotificationContentKind.message,
          eventIdentity: 'late-message',
        ),
        isTrue,
      );

      await insertMessage(
        id: 'later-distinct-message',
        sender: 'bob',
        incoming: true,
        timestamp: '2026-08-03T04:04:00.000Z',
      );
      expect(
        await dbIsUnreadGroupNotificationMessage(
          db,
          groupId: 'group-a',
          eventIdentity: 'later-distinct-message',
        ),
        isTrue,
      );
    },
  );

  test(
    'long accepted message identity cannot roll back the conversation read',
    () async {
      final longMessageId = List<String>.filled(2048, 'm').join();
      expect(
        await dbMarkGroupMessagesAsRead(
          db,
          'group-a',
          acknowledgedContentKind: 'message',
          acknowledgedEventIdentity: longMessageId,
          acknowledgedGeneration: 'long-message-generation',
        ),
        0,
      );
      expect(
        await dbLoadExactGroupNotificationReadAcknowledgement(
          db,
          groupId: 'group-a',
          contentKind: 'message',
          eventIdentity: longMessageId,
        ),
        isNotNull,
      );

      expect(
        await dbInsertGroupMessage(db, <String, Object?>{
          'id': longMessageId,
          'group_id': 'group-a',
          'sender_peer_id': 'alice',
          'text': 'long-but-accepted identity',
          'timestamp': '2026-08-03T04:04:00.000Z',
          'status': 'delivered',
          'is_incoming': 1,
          'created_at': '2026-08-03T04:04:00.000Z',
        }),
        isTrue,
      );
      final transferred = (await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[longMessageId],
      )).single;
      expect(transferred['read_at'], isNotNull);
    },
  );

  test(
    'reaction target accepts only legacy or canonical ordinary media policy',
    () async {
      await insertMessage(
        id: 'policy-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await db.insert('message_reactions', <String, Object?>{
        'id': 'policy-reaction',
        'message_id': 'policy-target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': '2026-08-03T02:00:00.000Z',
        'created_at': '2026-08-03T02:00:00.000Z',
        'notification_display_terminal_event_id': 'policy-reaction-event',
      });

      Future<GroupNotificationCanonicalContentDecision> decision() =>
          dbIsActiveGroupNotificationReaction(
            db,
            groupId: 'group-a',
            selfPeerId: 'self',
            eventIdentity: 'policy-reaction-event',
          );

      expect(await decision(), GroupNotificationCanonicalContentDecision.keep);
      await db.update(
        'group_messages',
        <String, Object?>{
          'media_policy_version': 0,
          'media_lifecycle': 'standard',
          'media_duration_seconds': null,
          'media_protected': 0,
        },
        where: 'id = ?',
        whereArgs: <Object?>['policy-target'],
      );
      expect(await decision(), GroupNotificationCanonicalContentDecision.keep);

      await db.update(
        'group_messages',
        <String, Object?>{
          'media_policy_version': 1,
          'media_lifecycle': 'standard',
          'media_duration_seconds': null,
          'media_protected': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>['policy-target'],
      );
      expect(
        await decision(),
        GroupNotificationCanonicalContentDecision.retire,
      );

      await db.update(
        'group_messages',
        <String, Object?>{
          'media_policy_version': 0,
          'media_lifecycle': 'standard',
          'media_duration_seconds': null,
          'media_protected': 1,
        },
        where: 'id = ?',
        whereArgs: <Object?>['policy-target'],
      );
      expect(
        await decision(),
        GroupNotificationCanonicalContentDecision.retire,
      );
    },
  );

  test(
    'reaction absence is unknown while an exact REMOVE is terminal',
    () async {
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'push-before-inbox-reaction',
        ),
        GroupNotificationCanonicalContentDecision.unknown,
      );

      await insertMessage(
        id: 'remove-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await db.insert('message_reactions', <String, Object?>{
        'id': 'removed-state',
        'message_id': 'remove-target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': '2026-08-03T02:00:00.000Z',
        'created_at': '2026-08-03T02:00:00.000Z',
        'removed_at': '2026-08-03T03:00:00.000Z',
        'notification_display_terminal_event_id': 'removed-add-event',
      });

      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'removed-add-event',
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
    },
  );

  test(
    'markerless background ADD custody transfers to a later REMOVE tombstone',
    () async {
      const addAt = '2026-08-03T02:00:00.000Z';
      const removeAt = '2026-08-03T03:00:00.000Z';
      const addEventId = 'background-add-transition';
      const reactionId = 'background-add-state';
      await insertMessage(
        id: 'background-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await dbStageGroupNotificationDisplayOutboxEntry(
        db,
        GroupNotificationDisplayOutboxEntry.reaction(
          eventId: addEventId,
          groupId: 'group-a',
          messageId: 'background-target',
          actorPeerId: 'alice',
          eventTimestamp: addAt,
          reactionId: reactionId,
          reactionAction: 'add',
          reactionTombstone: false,
          createdAt: addAt,
          updatedAt: addAt,
        ).toMap(),
      );
      await dbApplyIncomingReactionMutation(
        db,
        <String, Object?>{
          'id': reactionId,
          'message_id': 'background-target',
          'emoji': '👍',
          'sender_peer_id': 'alice',
          'timestamp': addAt,
          'created_at': addAt,
        },
        mutation: DbIncomingReactionMutation.add,
        groupIdForNotificationCleanup: 'group-a',
        notificationEventIdForStaleAddCleanup: addEventId,
      );
      expect(
        (await db.query(
          'message_reactions',
        )).single['notification_display_terminal_event_id'],
        isNull,
      );

      await dbApplyIncomingReactionMutation(
        db,
        <String, Object?>{
          'id': reactionId,
          'message_id': 'background-target',
          'emoji': '👍',
          'sender_peer_id': 'alice',
          'timestamp': removeAt,
          'created_at': removeAt,
        },
        mutation: DbIncomingReactionMutation.remove,
        groupIdForNotificationCleanup: 'group-a',
      );

      final boundedEventId = boundedReactionEventIdentity(addEventId);
      expect(
        (await db.query(
          'message_reactions',
        )).single['notification_display_terminal_event_id'],
        boundedEventId,
      );
      expect(
        await dbLoadGroupNotificationDisplayOutboxEntry(db, addEventId),
        isNull,
      );
      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: boundedEventId,
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );
    },
  );

  test(
    'hard target deletion retires exact bound reaction without local tombstone',
    () async {
      await insertMessage(
        id: 'deleted-target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      await db.insert('message_reactions', <String, Object?>{
        'id': 'target-reaction',
        'message_id': 'deleted-target',
        'emoji': '👍',
        'sender_peer_id': 'alice',
        'timestamp': '2026-08-03T02:00:00.000Z',
        'created_at': '2026-08-03T02:00:00.000Z',
        'notification_display_terminal_event_id': 'target-reaction-event',
      });
      await dbDeleteGroupMessageForMembershipRepair(db, 'deleted-target');
      expect(
        await db.query(
          'group_message_local_deletions',
          where: 'message_id = ?',
          whereArgs: <Object?>['deleted-target'],
        ),
        isEmpty,
      );

      expect(
        await dbIsActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
          eventIdentity: 'target-reaction-event',
        ),
        GroupNotificationCanonicalContentDecision.retire,
      );

      final generation = _TestGenerationMutation(
        const ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: 'target-reaction-event',
          generation: 'displayed-generation',
        ),
      );
      final reconciler = GroupNotificationCanonicalReconciler(
        coordinator: GroupNotificationPresentationCoordinator(),
        generationCancellation: generation,
        generationReplacement: generation,
        isCurrentContentCanonical: (_, metadata) {
          final eventIdentity = metadata.eventIdentity;
          return eventIdentity == null
              ? Future<GroupNotificationCanonicalContentDecision>.value(
                  GroupNotificationCanonicalContentDecision.unknown,
                )
              : dbIsActiveGroupNotificationReaction(
                  db,
                  groupId: 'group-a',
                  selfPeerId: 'self',
                  eventIdentity: eventIdentity,
                );
        },
        loadReplacement: (_, _) async => null,
      );
      await reconciler.reconcile('group-a');
      expect(generation.cancelledGenerations, <String>['displayed-generation']);
    },
  );

  test(
    'latest active reaction replacement chooses the newest eligible ADD',
    () async {
      await insertMessage(
        id: 'target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      for (final reaction in <({String id, String timestamp, String event})>[
        (
          id: 'reaction-older',
          timestamp: '2026-08-03T02:00:00.000Z',
          event: 'event-older',
        ),
        (
          id: 'reaction-newer',
          timestamp: '2026-08-03T03:00:00.000Z',
          event: 'event-newer',
        ),
      ]) {
        await db.insert('message_reactions', <String, Object?>{
          'id': reaction.id,
          'message_id': 'target',
          'emoji': '👍',
          'sender_peer_id': reaction.id,
          'timestamp': reaction.timestamp,
          'created_at': reaction.timestamp,
          'notification_display_terminal_event_id': reaction.event,
        });
      }

      expect(
        (await dbLoadLatestActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
        ))?['notification_display_terminal_event_id'],
        'event-newer',
      );
    },
  );

  test(
    'latest replacements use UTC instants instead of ISO text order',
    () async {
      await insertMessage(
        id: 'target',
        sender: 'self',
        incoming: false,
        timestamp: '2026-08-03T01:00:00.000Z',
      );
      for (final reaction in <({String id, String timestamp, String event})>[
        (
          id: 'lexically-newer-but-earlier',
          timestamp: '2026-08-03T10:00:00.000+02:00',
          event: 'event-earlier',
        ),
        (
          id: 'standard-newer',
          timestamp: '2026-08-03T09:00:00.000Z',
          event: 'event-standard-newer',
        ),
        (
          id: 'compact-newer',
          timestamp: '20260803T094500Z',
          event: 'event-compact-newer',
        ),
        (
          id: 'chronologically-newest',
          timestamp: '2026-08-03T11:00:00.000+0100',
          event: 'event-newest',
        ),
      ]) {
        await db.insert('message_reactions', <String, Object?>{
          'id': reaction.id,
          'message_id': 'target',
          'emoji': '👍',
          'sender_peer_id': reaction.id,
          'timestamp': reaction.timestamp,
          'created_at': reaction.timestamp,
          'notification_display_terminal_event_id': reaction.event,
        });
      }
      await insertMessage(
        id: 'lexically-newer-message',
        sender: 'alice',
        incoming: true,
        timestamp: '2026-08-03T10:30:00.000+02:00',
        terminalEventId: 'lexically-newer-message',
      );
      await insertMessage(
        id: 'standard-newer-message',
        sender: 'bob',
        incoming: true,
        timestamp: '2026-08-03T09:30:00.000Z',
        terminalEventId: 'standard-newer-message',
      );
      await insertMessage(
        id: 'chronologically-newest-message',
        sender: 'carol',
        incoming: true,
        timestamp: '20260803T103000Z',
        terminalEventId: 'chronologically-newest-message',
      );

      expect(
        (await dbLoadLatestActiveGroupNotificationReaction(
          db,
          groupId: 'group-a',
          selfPeerId: 'self',
        ))?['notification_display_terminal_event_id'],
        'event-newest',
      );
      expect(
        (await dbLoadLatestUnreadGroupNotificationMessage(
          db,
          'group-a',
        ))?['id'],
        'chronologically-newest-message',
      );
    },
  );
}

final class _TestGenerationMutation
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  _TestGenerationMutation(this.metadata);

  ConversationNotificationContentMetadata? metadata;
  final List<String> cancelledGenerations = <String>[];

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      metadata;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async {
    if (metadata?.generation != generation) return false;
    cancelledGenerations.add(generation);
    metadata = null;
    return true;
  }

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async => false;
}
