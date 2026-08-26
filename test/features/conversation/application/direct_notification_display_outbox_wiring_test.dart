import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reaction_terminal_event.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reaction_terminal_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'TC-372-05 direct durable attempt uses raw reaction correlation and exact authority',
    () async {
      const rawReactionId =
          'authenticated-reaction-id-that-must-not-be-replaced-by-display-alias';
      final boundedAlias = boundedReactionEventIdentity(rawReactionId);
      final entry = DirectNotificationDisplayOutboxEntry.reaction(
        eventId: boundedAlias,
        peerId: 'peer-direct-authority',
        messageId: 'target-message',
        actorPeerId: 'peer-direct-authority',
        eventTimestamp: '2026-08-16T10:00:00.000Z',
        reactionId: rawReactionId,
        reactionAction: ReactionPayload.addAction,
        reactionTombstone: false,
        createdAt: '2026-08-16T10:00:00.000Z',
        updatedAt: '2026-08-16T10:00:00.000Z',
      );
      final attempt = DirectNotificationDurableEffectAttempt.tryCreate(
        entry: entry,
        currentOpaqueBinding:
            'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        physicalPeerId: '12D3KooWphysical-direct-authority',
        presentationOwner: LocalNotificationPresentationOwner.inboxReconciler,
        readFinalCanonicalDisposition: () async =>
            DurableLocalNotificationCanonicalDisposition.eligible,
      );

      expect(attempt, isNotNull);
      final expectedCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWphysical-direct-authority',
            producerKind:
                NotificationCompletedOutcomeProducerKind.directReaction,
            eventKey: rawReactionId,
          );
      expect(attempt!.context.eventCorrelation, expectedCorrelation);
      expect(
        attempt.context.eventCorrelation,
        isNot(
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWphysical-direct-authority',
            producerKind:
                NotificationCompletedOutcomeProducerKind.directReaction,
            eventKey: boundedAlias,
          ),
        ),
      );
      expect(
        attempt.context.conversationDigest,
        AppVisibilityConversationIdentity.tryParse(
          lane: AppVisibilityConversationLane.direct,
          value: entry.peerId,
        )!.digest,
      );
      expect(
        attempt.context.sourceCustody,
        LocalNotificationSourceCustody.sqlReady,
      );
      expect(
        attempt.context.presentationOwner,
        LocalNotificationPresentationOwner.inboxReconciler,
      );
      expect(attempt.context.terminalObserverCompletesSqlHandoff, isFalse);

      await attempt.context.onEffectTerminal!(
        DurableLocalNotificationEffectReceipt(
          eventCorrelation: expectedCorrelation!,
          recordRevision: 9,
          presentationState: LocalNotificationPresentationState.inChat,
        ),
      );
      final completed = attempt.completedAuthority;
      expect(completed, isNotNull);
      expect(completed!.eventKey, rawReactionId);
      expect(completed.receipt.recordRevision, 9);
      expect(
        DirectNotificationDurableEffectAttempt.tryCreate(
          entry: entry,
          currentOpaqueBinding:
              ' v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          physicalPeerId: '12D3KooWphysical-direct-authority',
          presentationOwner: LocalNotificationPresentationOwner.inboxReconciler,
          readFinalCanonicalDisposition: () async =>
              DurableLocalNotificationCanonicalDisposition.eligible,
        ),
        isNull,
        reason: 'the canonical secure binding must match byte-for-byte',
      );
    },
  );

  test(
    'TC-369-02 exact display completion and outcome are one transaction',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'direct_outcome_atomic_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/identity.db',
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      const completedAt = '2026-08-15T10:00:00.000Z';
      const peerId = 'peer-direct-atomic';
      await db.insert('contacts', <String, Object?>{
        'peer_id': peerId,
        'public_key': 'public-direct-atomic',
        'rendezvous': 'relay-direct-atomic',
        'username': 'Direct Atomic',
        'signature': 'signature-direct-atomic',
        'scanned_at': completedAt,
      });

      Future<void> insertMessage(String messageId) =>
          db.insert('messages', <String, Object?>{
            'id': messageId,
            'contact_peer_id': peerId,
            'sender_peer_id': peerId,
            'text': 'canonical content',
            'timestamp': completedAt,
            'status': 'delivered',
            'is_incoming': 1,
            'created_at': completedAt,
          });
      DirectNotificationDisplayOutboxEntry readyEntry(String messageId) =>
          DirectNotificationDisplayOutboxEntry.message(
            eventId: messageId,
            peerId: peerId,
            messageId: messageId,
            actorPeerId: peerId,
            eventTimestamp: completedAt,
            readiness: DirectNotificationDisplayOutboxReadiness.ready,
            createdAt: completedAt,
            updatedAt: completedAt,
          );
      NotificationCompletedOutcomeCandidate candidate(
        String messageId,
        NotificationCompletedOutcomeCategory outcome,
      ) => NotificationCompletedOutcomeCandidate(
        physicalPeerId: '12D3KooWdirect-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: messageId,
        outcome: outcome,
        completedAt: DateTime.parse(completedAt),
      );
      Future<bool> complete(
        DirectNotificationDisplayOutboxEntry entry,
        NotificationCompletedOutcomeCandidate outcome,
      ) => dbCompleteDirectNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: entry.eventId,
        expectedRevision: entry.revision,
        expectedEventKind: entry.eventKind,
        expectedPeerId: entry.peerId,
        expectedMessageId: entry.messageId,
        expectedActorPeerId: entry.actorPeerId,
        expectedEventTimestamp: entry.eventTimestamp,
        expectedReactionId: entry.reactionId,
        expectedReactionAction: entry.reactionAction,
        expectedReactionTombstone: entry.reactionTombstone,
        completedAt: completedAt,
        outcome: outcome,
      );

      const exactId = 'direct-exact-message';
      await insertMessage(exactId);
      final exact = readyEntry(exactId);
      await db.insert('direct_notification_display_outbox', exact.toMap());
      expect(
        await complete(
          exact,
          candidate(exactId, NotificationCompletedOutcomeCategory.osPosted),
        ),
        isTrue,
      );
      expect(
        await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[exactId],
        ),
        isEmpty,
      );
      expect(
        (await db.query(
          'messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[exactId],
        )).single['notification_display_terminal_event_id'],
        exactId,
      );
      final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
        physicalPeerId: '12D3KooWdirect-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: exactId,
      );
      expect(correlation, isNotNull);
      expect(
        (await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[correlation],
        )).single['outcome'],
        'os_posted',
      );

      // A valid category replay completes custody without rewriting the first
      // immutable completed-effect category.
      await db.insert('direct_notification_display_outbox', exact.toMap());
      expect(
        await complete(
          exact,
          candidate(exactId, NotificationCompletedOutcomeCategory.inChat),
        ),
        isTrue,
      );
      expect(
        (await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[correlation],
        )).single['outcome'],
        'os_posted',
      );

      // A delete fault occurs after terminal/outcome writes in source order;
      // the exclusive transaction must roll all three facts back together.
      const faultId = 'direct-fault-message';
      await insertMessage(faultId);
      final fault = readyEntry(faultId);
      await db.insert('direct_notification_display_outbox', fault.toMap());
      await db.execute('''
        CREATE TRIGGER tc369_direct_delete_fault
        BEFORE DELETE ON direct_notification_display_outbox
        WHEN OLD.event_id = '$faultId'
        BEGIN
          SELECT RAISE(ABORT, 'tc369 injected delete fault');
        END
      ''');
      await expectLater(
        complete(
          fault,
          candidate(faultId, NotificationCompletedOutcomeCategory.osPosted),
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await db.query(
          'messages',
          columns: const <String>['notification_display_terminal_event_id'],
          where: 'id = ?',
          whereArgs: const <Object?>[faultId],
        )).single['notification_display_terminal_event_id'],
        isNull,
      );
      expect(
        await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[faultId],
        ),
        hasLength(1),
      );
      final faultCorrelation =
          tryComputeNotificationCompletedOutcomeCorrelation(
            physicalPeerId: '12D3KooWdirect-physical',
            producerKind:
                NotificationCompletedOutcomeProducerKind.directMessage,
            eventKey: faultId,
          );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[faultCorrelation],
        ),
        isEmpty,
      );
    },
  );

  test(
    'TC-372-06 direct SQL handoff verifies an already committed exact terminal',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'direct_durable_handoff_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final db = await databaseFactoryFfi.openDatabase(
        '${tempDir.path}/identity.db',
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
          onDowngrade: onDatabaseVersionChangeError,
        ),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
      });
      const timestamp = '2026-08-16T11:00:00.000Z';
      const peerId = 'peer-direct-durable';
      const messageId = 'message-direct-durable';
      await db.insert('contacts', <String, Object?>{
        'peer_id': peerId,
        'public_key': 'public-direct-durable',
        'rendezvous': 'relay-direct-durable',
        'username': 'Direct Durable',
        'signature': 'signature-direct-durable',
        'scanned_at': timestamp,
      });
      await db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': peerId,
        'sender_peer_id': peerId,
        'text': 'durable direct content',
        'timestamp': timestamp,
        'status': 'delivered',
        'is_incoming': 1,
        'created_at': timestamp,
      });
      final entry = DirectNotificationDisplayOutboxEntry.message(
        eventId: messageId,
        peerId: peerId,
        messageId: messageId,
        actorPeerId: peerId,
        eventTimestamp: timestamp,
        readiness: DirectNotificationDisplayOutboxReadiness.ready,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await db.insert('direct_notification_display_outbox', entry.toMap());
      await db.delete(
        'direct_notification_reconciliation_outbox',
        where: 'peer_id = ?',
        whereArgs: const <Object?>[peerId],
      );
      final outcome = NotificationCompletedOutcomeCandidate(
        physicalPeerId: '12D3KooWdirect-durable-physical',
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: messageId,
        outcome: NotificationCompletedOutcomeCategory.inChat,
        completedAt: DateTime.parse(timestamp),
      );

      Future<DurableLocalNotificationSqlHandoffResult> handoff({
        String actorPeerId = peerId,
      }) => dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
        db,
        eventId: entry.eventId,
        expectedRevision: entry.revision,
        expectedEventKind: entry.eventKind,
        expectedPeerId: entry.peerId,
        expectedMessageId: entry.messageId,
        expectedActorPeerId: actorPeerId,
        expectedEventTimestamp: entry.eventTimestamp,
        expectedReactionId: entry.reactionId,
        expectedReactionAction: entry.reactionAction,
        expectedReactionTombstone: entry.reactionTombstone,
        completedAt: timestamp,
        outcome: outcome,
      );

      expect(
        await handoff(),
        DurableLocalNotificationSqlHandoffResult.committed,
      );
      expect(
        await handoff(),
        DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
      );
      expect(
        await handoff(actorPeerId: 'stale-actor'),
        DurableLocalNotificationSqlHandoffResult.retryableMismatch,
      );
      expect(
        await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[messageId],
        ),
        hasLength(1),
        reason:
            'transaction A retains the exact raw READY tuple through ledger settlement',
      );
      final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
        physicalPeerId: outcome.physicalPeerId,
        producerKind: outcome.producerKind,
        eventKey: outcome.eventKey,
      );
      expect(
        await db.query(
          'notification_completed_outcome_outbox',
          where: 'wake_correlation = ?',
          whereArgs: <Object?>[correlation],
        ),
        hasLength(1),
      );
      expect(
        await dbLoadDirectNotificationReconciliationOutboxEntry(db, peerId),
        isNull,
        reason:
            'the reconciliation trigger belongs to post-settlement transaction B',
      );
      final terminals =
          await dbLoadDirectNotificationCommittedSqlTerminalsForPeer(
            db,
            peerId: peerId,
          );
      expect(terminals, hasLength(1));
      expect(terminals.single.eventId, messageId);
      expect(terminals.single.messageId, messageId);

      expect(
        await dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
          db,
          eventId: entry.eventId,
          expectedRevision: entry.revision,
          expectedEventKind: entry.eventKind,
          expectedPeerId: entry.peerId,
          expectedMessageId: entry.messageId,
          expectedActorPeerId: entry.actorPeerId,
          expectedEventTimestamp: entry.eventTimestamp,
          expectedReactionId: entry.reactionId,
          expectedReactionAction: entry.reactionAction,
          expectedReactionTombstone: entry.reactionTombstone,
        ),
        isTrue,
      );
      expect(
        await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[messageId],
        ),
        isEmpty,
      );
      expect(
        await dbLoadDirectNotificationReconciliationOutboxEntry(db, peerId),
        isNull,
        reason:
            'a successfully settled display must retire exact custody without '
            'immediately republishing the same peer card',
      );

      final newerRevision = entry.copyWith(revision: entry.revision + 1);
      await db.insert(
        'direct_notification_display_outbox',
        newerRevision.toMap(),
      );
      expect(
        await dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
          db,
          eventId: entry.eventId,
          expectedRevision: entry.revision,
          expectedEventKind: entry.eventKind,
          expectedPeerId: entry.peerId,
          expectedMessageId: entry.messageId,
          expectedActorPeerId: entry.actorPeerId,
          expectedEventTimestamp: entry.eventTimestamp,
          expectedReactionId: entry.reactionId,
          expectedReactionAction: entry.reactionAction,
          expectedReactionTombstone: entry.reactionTombstone,
        ),
        isFalse,
        reason: 'transaction B must not consume a same-event newer revision',
      );
      expect(
        (await db.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>[messageId],
        )).single['revision'],
        newerRevision.revision,
      );
    },
  );

  test(
    'TC-331-08 message marker first survives display throw and restart',
    () async {
      var now = DateTime.utc(2026, 8, 3, 10);
      final display = _DisplayOutbox(() => now);
      final service = _GenerationService();
      var attempts = 0;
      final first = _owner(
        display: display,
        service: service,
        now: () => now,
        project: (_) async {
          attempts++;
          throw StateError('native show failed');
        },
      );
      const message = ConversationMessage(
        id: 'message-a',
        contactPeerId: 'peer-a',
        senderPeerId: 'peer-a',
        text: 'hello',
        timestamp: '2026-08-03T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-03T10:00:00.000Z',
      );

      await first.stageMessage(message);
      expect(display.entry('peer-a', 'message', 'message-a')?.isReady, isFalse);
      await first.promoteMessageReadyIfExact(message);
      expect(display.entry('peer-a', 'message', 'message-a')?.isReady, isTrue);
      await first.retryNow();

      expect(attempts, 1);
      expect(display.entry('peer-a', 'message', 'message-a')?.isReady, isTrue);
      expect(display.completed, isEmpty);
      first.dispose();

      now = now.add(const Duration(hours: 2));
      final restarted = _owner(
        display: display,
        service: service,
        now: () => now,
        project: (_) async => NotificationPresentationResult.shown,
      );
      await restarted.retryNow();

      expect(display.rows, isEmpty);
      expect(display.completed, const ['message-a']);
      restarted.dispose();
    },
  );

  test(
    'stale policy retires ready custody without terminal authority',
    () async {
      final now = DateTime.utc(2026, 8, 3, 10);
      final display = _DisplayOutbox(() => now);
      final owner = _owner(
        display: display,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => null,
      );
      const message = ConversationMessage(
        id: 'archived-message',
        contactPeerId: 'peer-archived',
        senderPeerId: 'peer-archived',
        text: 'hidden by policy',
        timestamp: '2026-08-03T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-03T10:00:00.000Z',
      );
      await owner.stageMessage(message);
      await owner.promoteMessageReadyIfExact(message);
      await owner.retryNow();

      expect(display.rows, isEmpty);
      expect(display.retired, const ['archived-message']);
      expect(display.completed, isEmpty);
      owner.dispose();
    },
  );

  test(
    'reaction replay promotion requires the full direct authority tuple',
    () async {
      final now = DateTime.utc(2026, 8, 3, 10);
      final display = _DisplayOutbox(() => now);
      final owner = _owner(
        display: display,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.shown,
      );
      const target = ConversationMessage(
        id: 'target-a',
        contactPeerId: 'peer-a',
        senderPeerId: 'self',
        text: 'mine',
        timestamp: '2026-08-03T09:00:00.000Z',
        status: 'sent',
        isIncoming: false,
        createdAt: '2026-08-03T09:00:00.000Z',
      );
      const payload = ReactionPayload(
        id: 'reaction-a',
        messageId: 'target-a',
        emoji: '👍',
        action: ReactionPayload.addAction,
        senderPeerId: 'peer-a',
        timestamp: '2026-08-03T10:00:00.000Z',
      );
      await owner.stageReaction(payload: payload, targetMessage: target);

      await expectLater(
        owner.promoteReactionReadyIfExact(
          payload: const ReactionPayload(
            id: 'reaction-a',
            messageId: 'target-a',
            emoji: '👍',
            action: ReactionPayload.addAction,
            senderPeerId: 'peer-a',
            timestamp: '2026-08-03T10:00:01.000Z',
          ),
          targetMessage: target,
        ),
        throwsStateError,
      );
      expect(display.rows.values.single.isReady, isFalse);

      await owner.promoteReactionReadyIfExact(
        payload: payload,
        targetMessage: target,
      );
      expect(display.rows.values.single.isReady, isTrue);
      owner.dispose();
    },
  );

  test(
    'same event id on another peer is not starved by a persistent failure',
    () async {
      final now = DateTime.utc(2026, 8, 3, 10);
      final display = _DisplayOutbox(() => now);
      final projectedPeers = <String>[];
      final owner = _owner(
        display: display,
        service: _GenerationService(),
        now: () => now,
        project: (entry) async {
          projectedPeers.add(entry.peerId);
          if (entry.peerId == 'peer-failing') {
            throw StateError('persistent native failure');
          }
          return NotificationPresentationResult.shown;
        },
      );

      Future<void> stageReady(String peerId, String messageId) async {
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: peerId,
          senderPeerId: peerId,
          text: 'collision proof',
          timestamp: '2026-08-03T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-08-03T10:00:00.000Z',
        );
        await owner.stageMessage(message);
        await owner.promoteMessageReadyIfExact(message);
      }

      await stageReady('peer-failing', 'shared-event');
      for (var index = 0; index < 19; index++) {
        await stageReady('peer-filler-$index', 'filler-event-$index');
      }
      await stageReady('peer-independent', 'shared-event');

      await owner.retryNow();

      expect(projectedPeers, contains('peer-failing'));
      expect(projectedPeers, contains('peer-independent'));
      expect(
        display.entry('peer-independent', 'message', 'shared-event'),
        isNull,
        reason:
            'failed-row exclusion must use peer/kind/event, not the colliding event id alone',
      );
      expect(
        display.entry('peer-failing', 'message', 'shared-event'),
        isNotNull,
      );
      owner.dispose();
    },
  );

  test(
    'TC-369-05 canonical display custody is the sole direct outcome producer',
    () async {
      final now = DateTime.utc(2026, 8, 15, 10);
      const message = ConversationMessage(
        id: 'authenticated-message-key',
        contactPeerId: 'peer-a',
        senderPeerId: 'peer-a',
        text: 'hello',
        timestamp: '2026-08-15T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-15T10:00:00.000Z',
      );

      final defaultOff = _DisplayOutbox(() => now);
      final defaultOffOwner = _owner(
        display: defaultOff,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.osPosted,
      );
      await defaultOffOwner.stageMessage(message);
      await defaultOffOwner.promoteMessageReadyIfExact(message);
      await defaultOffOwner.retryNow();
      expect(defaultOff.completedOutcomes, const [null]);
      defaultOffOwner.dispose();

      final enabled = _DisplayOutbox(() => now);
      final enabledOwner = _owner(
        display: enabled,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.osPosted,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWphysical-installation',
      );
      await enabledOwner.stageMessage(message);
      await enabledOwner.promoteMessageReadyIfExact(message);
      await enabledOwner.retryNow();

      final candidate = enabled.completedOutcomes.single;
      expect(candidate, isNotNull);
      expect(candidate!.physicalPeerId, '12D3KooWphysical-installation');
      expect(
        candidate.producerKind,
        NotificationCompletedOutcomeProducerKind.directMessage,
      );
      expect(candidate.eventKey, 'authenticated-message-key');
      expect(candidate.outcome, NotificationCompletedOutcomeCategory.osPosted);
      expect(candidate.completedAt, now);
      enabledOwner.dispose();

      const target = ConversationMessage(
        id: 'direct-reaction-target',
        contactPeerId: 'peer-a',
        senderPeerId: 'peer-self',
        text: 'mine',
        timestamp: '2026-08-15T09:59:00.000Z',
        status: 'sent',
        isIncoming: false,
        createdAt: '2026-08-15T09:59:00.000Z',
      );
      const reaction = ReactionPayload(
        id: 'authenticated-direct-reaction-key',
        messageId: 'direct-reaction-target',
        emoji: '👍',
        action: ReactionPayload.addAction,
        senderPeerId: 'peer-a',
        timestamp: '2026-08-15T10:01:00.000Z',
      );
      final reactionDisplay = _DisplayOutbox(() => now);
      final reactionOwner = _owner(
        display: reactionDisplay,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.osPosted,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWphysical-installation',
      );
      await reactionOwner.stageReaction(
        payload: reaction,
        targetMessage: target,
      );
      await reactionOwner.promoteReactionReadyIfExact(
        payload: reaction,
        targetMessage: target,
      );
      await reactionOwner.retryNow();
      expect(
        reactionDisplay.completedOutcomes.single?.producerKind,
        NotificationCompletedOutcomeProducerKind.directReaction,
      );
      expect(
        reactionDisplay.completedOutcomes.single?.eventKey,
        reaction.id,
        reason: 'the authenticated raw reaction id, not its bounded card id',
      );
      reactionOwner.dispose();

      for (final ineligibleTarget in <ConversationMessage>[
        target.copyWith(hiddenAt: '2026-08-15T10:00:30.000Z'),
        target.copyWith(privateMediaState: PrivateMediaLifecycleState.consumed),
      ]) {
        final residueDisplay = _DisplayOutbox(() => now);
        var projected = false;
        final residueOwner = _owner(
          display: residueDisplay,
          service: _GenerationService(),
          now: () => now,
          project: (_) async {
            projected = true;
            return NotificationPresentationResult.osPosted;
          },
          completedOutcomeProducerEnabled: true,
          resolveCompletedOutcomePhysicalPeerId: () async =>
              '12D3KooWphysical-installation',
        );
        expect(
          directReactionTargetAllowsNotificationDisplay(
            target: ineligibleTarget,
            expectedContactPeerId: reaction.senderPeerId,
          ),
          isFalse,
        );
        await residueOwner.stageReaction(
          payload: reaction,
          targetMessage: ineligibleTarget,
        );
        await residueOwner.promoteReactionReadyIfExact(
          payload: reaction,
          targetMessage: ineligibleTarget,
        );
        await residueOwner.retryNow();
        expect(residueDisplay.rows, isEmpty);
        expect(residueDisplay.completedOutcomes, isEmpty);
        expect(projected, isFalse);
        residueOwner.dispose();
      }

      final siblingDisplay = _DisplayOutbox(() => now);
      final siblingOwner = _owner(
        display: siblingDisplay,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.osPosted,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async => null,
      );
      await siblingOwner.stageMessage(message);
      await siblingOwner.promoteMessageReadyIfExact(message);
      expect(siblingDisplay.completedOutcomes, isEmpty);
      await siblingOwner.retryNow();
      expect(
        siblingDisplay.completedOutcomes,
        const [null],
        reason:
            'a sibling without this installation physical identity cannot inherit its outcome',
      );
      expect(
        candidate.physicalPeerId,
        '12D3KooWphysical-installation',
        reason: 'the first installation candidate remains installation-bound',
      );
      siblingOwner.dispose();

      var policyResolverCalled = false;
      final policyDisplay = _DisplayOutbox(() => now);
      final policyOwner = _owner(
        display: policyDisplay,
        service: _GenerationService(),
        now: () => now,
        project: (_) async =>
            NotificationPresentationResult.terminalWithoutOutcome,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async {
          policyResolverCalled = true;
          return '12D3KooWphysical-installation';
        },
      );
      await policyOwner.stageMessage(message);
      await policyOwner.promoteMessageReadyIfExact(message);
      await policyOwner.retryNow();
      expect(policyDisplay.completedOutcomes, const [null]);
      expect(policyResolverCalled, isFalse);
      policyOwner.dispose();

      final bypassDisplay = _DisplayOutbox(() => now);
      final bypassOwner = _owner(
        display: bypassDisplay,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => null,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWphysical-installation',
      );
      await bypassOwner.stageMessage(message);
      await bypassOwner.promoteMessageReadyIfExact(message);
      await bypassOwner.retryNow();
      expect(bypassDisplay.completedOutcomes, isEmpty);
      expect(bypassDisplay.retired, const ['authenticated-message-key']);
      bypassOwner.dispose();

      const unanchoredCompatibilityMessage = ConversationMessage(
        id: ' legacy-unanchored-message ',
        contactPeerId: 'peer-a',
        senderPeerId: 'peer-a',
        text: 'legacy',
        timestamp: '2026-08-15T10:02:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-08-15T10:02:00.000Z',
      );
      final compatibilityDisplay = _DisplayOutbox(() => now);
      final compatibilityOwner = _owner(
        display: compatibilityDisplay,
        service: _GenerationService(),
        now: () => now,
        project: (_) async => NotificationPresentationResult.osPosted,
        completedOutcomeProducerEnabled: true,
        resolveCompletedOutcomePhysicalPeerId: () async =>
            '12D3KooWphysical-installation',
      );
      await compatibilityOwner.stageMessage(unanchoredCompatibilityMessage);
      await compatibilityOwner.promoteMessageReadyIfExact(
        unanchoredCompatibilityMessage,
      );
      await compatibilityOwner.retryNow();
      expect(
        compatibilityDisplay.completedOutcomes,
        const [null],
        reason:
            'an unanchored non-canonical compatibility id may complete locally but cannot mint an outcome',
      );
      compatibilityOwner.dispose();
    },
  );
}

DirectNotificationProjectionOwner _owner({
  required _DisplayOutbox display,
  required _GenerationService service,
  required DateTime Function() now,
  required Future<NotificationPresentationResult?> Function(
    DirectNotificationDisplayOutboxEntry entry,
  )
  project,
  Future<String?> Function()? resolveCompletedOutcomePhysicalPeerId,
  bool completedOutcomeProducerEnabled = false,
}) {
  final coordinator = DirectNotificationPresentationCoordinator();
  final reconciler = DirectNotificationCanonicalReconciler(
    coordinator: coordinator,
    generationCancellation: service,
    generationReplacement: service,
    isCurrentContentCanonical: (_, _) async =>
        DirectNotificationCanonicalContentDecision.retire,
    loadReplacement: (_, _) async => null,
  );
  return DirectNotificationProjectionOwner(
    displayOutbox: display,
    reconciliationOutbox: _EmptyReconciliationOutbox(),
    reactionTerminal: _EmptyReactionTerminal(),
    coordinator: coordinator,
    projectDisplay: (entry) async {
      final presentation = await project(entry);
      return presentation == null
          ? null
          : DirectNotificationDisplayProjection(presentation: presentation);
    },
    canonicalReconciler: reconciler,
    enqueueReconciliation: (_) async {},
    resolveCompletedOutcomePhysicalPeerId:
        resolveCompletedOutcomePhysicalPeerId,
    completedOutcomeProducerEnabled: completedOutcomeProducerEnabled,
    nowUtc: now,
    retryDelay: const Duration(hours: 1),
  );
}

final class _DisplayOutbox
    implements DirectNotificationDisplayOutboxRepository {
  _DisplayOutbox(this.now);

  final DateTime Function() now;
  final Map<String, DirectNotificationDisplayOutboxEntry> rows = {};
  final List<String> completed = [];
  final List<NotificationCompletedOutcomeCandidate?> completedOutcomes = [];
  final List<String> retired = [];

  String _key(String peerId, String eventKind, String eventId) =>
      '$peerId\u0000$eventKind\u0000$eventId';

  DirectNotificationDisplayOutboxEntry? entry(
    String peerId,
    String eventKind,
    String eventId,
  ) => rows[_key(peerId, eventKind, eventId)];

  @override
  Future<void> stage(DirectNotificationDisplayOutboxEntry entry) async {
    final key = _key(entry.peerId, entry.eventKind, entry.eventId);
    final existing = rows[key];
    if (existing == null) {
      rows[key] = entry;
      return;
    }
    if (existing.peerId != entry.peerId ||
        existing.messageId != entry.messageId ||
        existing.actorPeerId != entry.actorPeerId ||
        existing.eventTimestamp != entry.eventTimestamp) {
      throw StateError('authority conflict');
    }
  }

  @override
  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async {
    return rows[_key(peerId, eventKind, eventId)];
  }

  @override
  Future<bool> promoteReadyIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
  }) async {
    final key = _key(peerId, eventKind, eventId);
    final current = rows[key];
    if (current == null ||
        current.peerId != peerId ||
        current.eventKind != eventKind ||
        current.revision != expectedRevision ||
        current.isReady) {
      return false;
    }
    rows[key] = current.copyWith(
      readiness: DirectNotificationDisplayOutboxReadiness.ready,
      revision: current.revision + 1,
    );
    return true;
  }

  @override
  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async => rows.values
      .where(
        (entry) =>
            entry.isReady &&
            (entry.nextAttemptAt == null ||
                !DateTime.parse(entry.nextAttemptAt!).isAfter(now())),
      )
      .take(limit)
      .toList(growable: false);

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async => rows.values
      .where((entry) => entry.isReady && entry.nextAttemptAt != null)
      .map((entry) => DateTime.parse(entry.nextAttemptAt!))
      .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);

  @override
  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) async {
    final key = _key(peerId, eventKind, eventId);
    final current = rows[key];
    if (current == null ||
        current.peerId != peerId ||
        current.eventKind != eventKind ||
        current.revision != expectedRevision) {
      return false;
    }
    rows[key] = current.copyWith(
      revision: current.revision + 1,
      retryCount: current.retryCount + 1,
      lastErrorCode: lastErrorCode,
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<bool> completeIfExact(
    DirectNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  }) async {
    final key = _key(expected.peerId, expected.eventKind, expected.eventId);
    final current = rows[key];
    if (current?.revision != expected.revision) return false;
    rows.remove(key);
    completed.add(expected.eventId);
    completedOutcomes.add(outcome);
    return true;
  }

  @override
  Future<bool> retireAfterDurableSettlementIfExact(
    DirectNotificationDisplayOutboxEntry expected,
  ) => retireIfExact(expected);

  @override
  Future<bool> retireIfExact(
    DirectNotificationDisplayOutboxEntry expected,
  ) async {
    final key = _key(expected.peerId, expected.eventKind, expected.eventId);
    final current = rows[key];
    if (current?.revision != expected.revision) return false;
    rows.remove(key);
    retired.add(expected.eventId);
    return true;
  }

  @override
  Future<int> deleteForPeer(String peerId) async => 0;

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) async => 0;

  @override
  Future<int> deleteForReactionActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => 0;
}

final class _EmptyReconciliationOutbox
    implements DirectNotificationReconciliationOutboxRepository {
  @override
  Future<List<DirectNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  }) async => const [];

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async => null;

  @override
  Future<bool> recordFailureIfExact({
    required DirectNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  }) async => false;

  @override
  Future<bool> completeIfExact(
    DirectNotificationReconciliationOutboxEntry expected,
  ) async => false;
}

final class _EmptyReactionTerminal
    implements DirectNotificationReactionTerminalRepository {
  @override
  Future<bool> upsert({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
  }) async => true;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => null;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadByTerminalEvent({
    required String peerId,
    required String terminalEventId,
  }) async => null;

  @override
  Future<bool> markAcknowledgedIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
  }) async => false;

  @override
  Future<bool> consumeAcknowledgementIfExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String terminalEventId,
    required String generation,
  }) async => false;

  @override
  Future<int> deleteForActor({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => 0;

  @override
  Future<int> deleteForMessage({
    required String peerId,
    required String messageId,
  }) async => 0;

  @override
  Future<int> deleteForPeer(String peerId) async => 0;
}

final class _GenerationService
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      null;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async => true;

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async => true;
}
