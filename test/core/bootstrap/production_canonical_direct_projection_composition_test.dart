import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_direct_projection_composition.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reaction_terminal_event.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_read_acknowledgement.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reaction_terminal_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_read_acknowledgement_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/conversation/domain/repositories/fake_reaction_repository.dart';
import '../../shared/fakes/fake_app_visibility.dart';
import '../../shared/fakes/fake_notification_service.dart';

const _peerId = 'peer-direct-correlation';
const _physicalPeerId = 'physical-direct-correlation';

void main() {
  sqfliteFfiInit();

  test('TC-393-02 production wires exact generation cancellation', () async {
    final service = _GenerationNotificationService(
      const ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: 'event-active-generation',
        generation: 'active-generation',
      ),
    );
    final cleanup = buildProductionExactConversationActivationCleanup(service);
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: _peerId,
    )!;

    await cleanup(identity);

    expect(service.cancelledGenerations, <String>['active-generation']);
    expect(service.metadata, isNull);
  });

  test(
    'durable direct message correlation materializes and rewrites raw identity',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directMessage,
        'message-raw',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      harness.messages.seed(<ConversationMessage>[
        _message(
          id: 'message-raw',
          timestamp: '2026-08-16T10:00:00.000Z',
          incoming: true,
        ),
      ]);

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, hasLength(1));
      expect(harness.service.replacements.single.eventIdentity, 'message-raw');
      expect(
        harness.service.replacements.single.contentKind,
        ConversationNotificationContentKind.message,
      );
      expect(harness.messages.getMessagesForContactCalls, 1);
      expect(harness.reconciliation.entry, isNull);
    },
  );

  test(
    'durable direct reaction correlation uses unique SQL terminal and rewrites raw identity',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directReaction,
        'reaction-raw',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      harness.messages.seed(<ConversationMessage>[
        _message(
          id: 'target-raw',
          timestamp: '2026-08-16T10:00:00.000Z',
          incoming: false,
        ),
      ]);
      await harness.reactions.saveReaction(
        const MessageReaction(
          id: 'reaction-raw',
          messageId: 'target-raw',
          emoji: '❤️',
          senderPeerId: _peerId,
          timestamp: '2026-08-16T10:01:00.000Z',
          createdAt: '2026-08-16T10:01:00.000Z',
        ),
      );
      await harness.insertReactionTerminal(
        const DirectNotificationReactionTerminalEvent(
          peerId: _peerId,
          messageId: 'target-raw',
          actorPeerId: _peerId,
          reactionId: 'reaction-raw',
          terminalEventId: 'reaction-terminal-raw',
          notificationAcknowledgedAt: null,
          updatedAt: '2026-08-16T10:01:00.000Z',
        ),
      );

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, hasLength(1));
      expect(
        harness.service.replacements.single.eventIdentity,
        'reaction-terminal-raw',
      );
      expect(
        harness.service.replacements.single.contentKind,
        ConversationNotificationContentKind.reaction,
      );
      expect(harness.terminals.loadByTerminalEventCalls, 1);
      expect(harness.messages.getMessagesForContactCalls, 1);
      expect(harness.reconciliation.entry, isNull);
    },
  );

  test(
    'older durable message correlation advances to newer canonical raw sibling',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directMessage,
        'message-old',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      harness.messages.seed(<ConversationMessage>[
        _message(
          id: 'message-old',
          timestamp: '2026-08-16T10:00:00.000Z',
          incoming: true,
        ),
        _message(
          id: 'message-new',
          timestamp: '2026-08-16T10:02:00.000Z',
          incoming: true,
        ),
      ]);

      await harness.composition.owner.retryNow();

      expect(harness.service.cancelledGenerations, isEmpty);
      expect(harness.service.replacements, hasLength(1));
      expect(harness.service.replacements.single.eventIdentity, 'message-new');
      expect(harness.messages.getMessagesForContactCalls, 1);
      expect(harness.reconciliation.entry, isNull);
    },
  );

  test(
    'durable message uses parsed instant then id tie-break for canonical newest',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directMessage,
        'message-z',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      harness.messages.seed(<ConversationMessage>[
        _message(
          id: 'message-z',
          timestamp: '2026-08-16T09:30:00.000Z',
          incoming: true,
        ),
        _message(
          id: 'message-a',
          timestamp: '2026-08-16T11:30:00.000+02:00',
          incoming: true,
        ),
      ]);

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, hasLength(1));
      expect(harness.service.replacements.single.eventIdentity, 'message-z');
      expect(harness.messages.getMessagesForContactCalls, 1);
      expect(harness.reconciliation.entry, isNull);
    },
  );

  test(
    'newer terminal private message cannot displace canonical eligible message',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directMessage,
        'message-eligible',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.message,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      harness.messages.seed(<ConversationMessage>[
        _message(
          id: 'message-eligible',
          timestamp: '2026-08-16T10:00:00.000Z',
          incoming: true,
        ),
        _message(
          id: 'message-private-terminal',
          timestamp: '2026-08-16T10:05:00.000Z',
          incoming: true,
          privateMediaPolicy: const PrivateMediaPolicy.protected(),
          privateMediaState: PrivateMediaLifecycleState.consumed,
        ),
      ]);

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, hasLength(1));
      expect(
        harness.service.replacements.single.eventIdentity,
        'message-eligible',
      );
      expect(harness.messages.getMessagesForContactCalls, 1);
      expect(harness.reconciliation.entry, isNull);
    },
  );

  test('missing durable reaction materialization remains retryable', () async {
    final correlation = _correlation(
      NotificationCompletedOutcomeProducerKind.directReaction,
      'reaction-missing',
    );
    final harness = await _Harness.create(
      ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.reaction,
        eventIdentity: correlation,
        generation: durableLocalNotificationContentGeneration(correlation),
      ),
    );
    addTearDown(harness.dispose);

    await harness.composition.owner.retryNow();

    expect(harness.service.replacements, isEmpty);
    expect(harness.service.cancelledGenerations, isEmpty);
    expect(harness.reconciliation.entry, isNotNull);
    expect(harness.reconciliation.failures, 1);
  });

  test(
    'ambiguous durable reaction materialization remains retryable',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directReaction,
        'reaction-shared',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      await harness.insertReactionTerminal(
        const DirectNotificationReactionTerminalEvent(
          peerId: _peerId,
          messageId: 'target-a',
          actorPeerId: 'actor-a',
          reactionId: 'reaction-shared',
          terminalEventId: 'terminal-a',
          notificationAcknowledgedAt: null,
          updatedAt: '2026-08-16T10:01:00.000Z',
        ),
      );
      await harness.insertReactionTerminal(
        const DirectNotificationReactionTerminalEvent(
          peerId: _peerId,
          messageId: 'target-b',
          actorPeerId: 'actor-b',
          reactionId: 'reaction-shared',
          terminalEventId: 'terminal-b',
          notificationAcknowledgedAt: null,
          updatedAt: '2026-08-16T10:02:00.000Z',
        ),
      );

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, isEmpty);
      expect(harness.service.cancelledGenerations, isEmpty);
      expect(harness.reconciliation.entry, isNotNull);
      expect(harness.reconciliation.failures, 1);
    },
  );

  test(
    'reaction duplicate beyond 512-row recovery window remains retryable',
    () async {
      final correlation = _correlation(
        NotificationCompletedOutcomeProducerKind.directReaction,
        'reaction-global-duplicate',
      );
      final harness = await _Harness.create(
        ConversationNotificationContentMetadata(
          kind: ConversationNotificationContentKind.reaction,
          eventIdentity: correlation,
          generation: durableLocalNotificationContentGeneration(correlation),
        ),
      );
      addTearDown(harness.dispose);
      await harness
          .insertReactionTerminals(<DirectNotificationReactionTerminalEvent>[
            const DirectNotificationReactionTerminalEvent(
              peerId: _peerId,
              messageId: 'target-match-new',
              actorPeerId: 'actor-match-new',
              reactionId: 'reaction-global-duplicate',
              terminalEventId: 'terminal-match-new',
              notificationAcknowledgedAt: null,
              updatedAt: '2026-08-16T12:00:00.000Z',
            ),
            for (var index = 0; index < 511; index++)
              DirectNotificationReactionTerminalEvent(
                peerId: _peerId,
                messageId: 'target-filler-$index',
                actorPeerId: 'actor-filler-$index',
                reactionId: 'reaction-filler-$index',
                terminalEventId: 'terminal-filler-$index',
                notificationAcknowledgedAt: null,
                updatedAt: '2025-08-16T12:00:00.000Z',
              ),
            const DirectNotificationReactionTerminalEvent(
              peerId: _peerId,
              messageId: 'target-match-old',
              actorPeerId: 'actor-match-old',
              reactionId: 'reaction-global-duplicate',
              terminalEventId: 'terminal-match-old',
              notificationAcknowledgedAt: null,
              updatedAt: '2024-08-16T12:00:00.000Z',
            ),
          ]);

      await harness.composition.owner.retryNow();

      expect(harness.service.replacements, isEmpty);
      expect(harness.service.cancelledGenerations, isEmpty);
      expect(harness.terminals.loadByTerminalEventCalls, 0);
      expect(harness.reconciliation.entry, isNotNull);
      expect(harness.reconciliation.failures, 1);
    },
  );

  test(
    'production durable direct message probes current remote proof without consuming it',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final constructionGate = _TrackingRecentRemoteNotificationGate(
        hasProof: false,
      );
      final invocationGate = _TrackingRecentRemoteNotificationGate(
        hasProof: true,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(constructionGate);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
      });

      const timestamp = '2026-08-16T12:30:00.000Z';
      const messageId = 'message-remote-direct';
      final entry = DirectNotificationDisplayOutboxEntry.message(
        eventId: messageId,
        peerId: _peerId,
        messageId: messageId,
        actorPeerId: _peerId,
        eventTimestamp: timestamp,
        readiness: DirectNotificationDisplayOutboxReadiness.ready,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      final messages = _CountingMessageRepository()
        ..seed(<ConversationMessage>[
          _message(id: messageId, timestamp: timestamp, incoming: true),
        ]);
      final contacts = FakeContactRepository()
        ..seed(const <ContactModel>[
          ContactModel(
            peerId: _peerId,
            publicKey: 'public-key',
            rendezvous: '/memory/direct',
            username: 'Direct Peer',
            signature: 'signature',
            scannedAt: timestamp,
          ),
        ]);
      final displayOutbox = _SingleDisplayOutbox(entry);
      final service = _RemoteAdoptionNotificationService();
      final composition = buildProductionCanonicalDirectProjectionComposition(
        ProductionCanonicalDirectProjectionDependencies(
          database: database,
          notificationService: service,
          appVisibility: FixedAppVisibility(),
          contactRepository: contacts,
          messageRepository: messages,
          reactionRepository: FakeReactionRepository(),
          mediaAttachmentRepository: FakeMediaAttachmentRepository(),
          displayOutbox: displayOutbox,
          reconciliationOutbox: _ReconciliationOutbox(null),
          reactionTerminal: _ReactionTerminalRepository(),
          readAcknowledgement: _EmptyReadAcknowledgement(),
          durableRegistry: _NoopDurableEffectRegistry(),
          readCurrentOpaqueBinding: () async =>
              'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          resolvePhysicalPeerId: () async => _physicalPeerId,
          presentationOwner: LocalNotificationPresentationOwner.inboxReconciler,
          completedOutcomeProducerEnabled: false,
          notificationToneTracker: NotificationToneTracker(),
          durableNotificationCoordinatorResolver: () async => null,
        ),
      );
      addTearDown(() async {
        composition.owner.dispose();
        await database.close();
      });

      debugSetRecentRemoteNotificationGate(invocationGate);
      await composition.owner.retryNow();

      expect(constructionGate.probes, 0);
      expect(constructionGate.consumes, 0);
      expect(invocationGate.exactProbes, 1);
      expect(invocationGate.probes, 0);
      expect(invocationGate.exactConsumes, 0);
      expect(invocationGate.consumes, 0);
      expect(invocationGate.marks, 0);
      expect(invocationGate.hasProof, isTrue);
      expect(service.durableContexts, hasLength(1));
      expect(
        service.durableContexts.single.remotePresentationEstablished,
        isTrue,
      );
      expect(service.shown, isEmpty);
      expect(displayOutbox.entry, isNotNull);
      expect(displayOutbox.entry!.retryCount, 1);
      expect(
        displayOutbox.entry!.lastErrorCode,
        DirectNotificationDisplayOutboxErrorCode.claimPending,
      );
    },
  );

  test(
    'adopted direct proof is consumed once only after SQL settlement and retirement',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final gate = _TrackingRecentRemoteNotificationGate(hasProof: true);
      final settlementReplacementGate = _TrackingRecentRemoteNotificationGate(
        hasProof: true,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
      });

      final harness = await _DurableDirectProjectionHarness.create(
        messageId: 'message-remote-direct-settled',
      );
      addTearDown(harness.dispose);
      harness.registry.onSettle = () {
        debugSetRecentRemoteNotificationGate(settlementReplacementGate);
      };
      var sqlCustodyRetiredWhenProofConsumed = false;
      var ledgerSettledWhenProofConsumed = false;
      gate.beforeExactConsume = () async {
        sqlCustodyRetiredWhenProofConsumed = (await harness.database.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>['message-remote-direct-settled'],
        )).isEmpty;
        ledgerSettledWhenProofConsumed = harness.registry.settlements == 1;
      };

      await harness.composition.owner.retryNow();
      await harness.composition.owner.retryNow();

      expect(gate.exactProbes, 1);
      expect(gate.exactConsumes, 1);
      expect(gate.consumes, 0);
      expect(gate.marks, 0);
      expect(gate.hasProof, isFalse);
      expect(settlementReplacementGate.exactConsumes, 0);
      expect(settlementReplacementGate.hasProof, isTrue);
      expect(sqlCustodyRetiredWhenProofConsumed, isTrue);
      expect(ledgerSettledWhenProofConsumed, isTrue);
      expect(harness.service.durableContexts, hasLength(1));
      expect(
        harness.service.durableContexts.single.remotePresentationEstablished,
        isTrue,
      );
      expect(harness.service.shown, isEmpty);
      expect(harness.registry.settlements, 1);
      expect(harness.displayOutbox.retireAfterSettlementCalls, 1);
      expect(harness.displayOutbox.entry, isNull);
      expect(
        await harness.database.query(
          'direct_notification_display_outbox',
          where: 'event_id = ?',
          whereArgs: const <Object?>['message-remote-direct-settled'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'ordinary direct local post keeps its marker for a late remote delivery',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final gate = _TrackingRecentRemoteNotificationGate(hasProof: false);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
      });

      final harness = await _DurableDirectProjectionHarness.create(
        messageId: 'message-local-direct-settled',
      );
      addTearDown(harness.dispose);

      await harness.composition.owner.retryNow();

      expect(gate.exactProbes, 1);
      expect(gate.exactConsumes, 0);
      expect(gate.marks, 1);
      expect(gate.hasProof, isTrue);
      expect(harness.service.shown, hasLength(1));
      expect(harness.registry.settlements, 1);
      expect(harness.displayOutbox.retireAfterSettlementCalls, 1);
      expect(harness.displayOutbox.entry, isNull);
    },
  );

  test(
    'production direct reaction adopts exact proof through interrupted settlement',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final gate = _TrackingRecentRemoteNotificationGate(hasProof: true);
      final replacementGate = _TrackingRecentRemoteNotificationGate(
        hasProof: true,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
      });
      final harness = await _DurableDirectProjectionHarness.create(
        messageId: 'authored-reaction-target',
        reactionId: 'reaction-remote-settlement',
      );
      addTearDown(harness.dispose);
      harness.registry.onSettle = () {
        if (harness.registry.settlements == 1) {
          throw StateError('settlement interrupted');
        }
        debugSetRecentRemoteNotificationGate(replacementGate);
      };
      gate.beforeExactConsume = () async {
        expect(harness.registry.settlements, 2);
        expect(harness.displayOutbox.entry, isNull);
        expect(
          await harness.database.query('direct_notification_display_outbox'),
          isEmpty,
        );
      };

      await harness.composition.owner.retryNow();
      expect(harness.service.shown, isEmpty);
      expect(harness.service.durableContexts, hasLength(1));
      expect(
        harness.service.durableContexts.single.remotePresentationEstablished,
        isTrue,
      );
      expect(gate.exactProbes, 1);
      expect(gate.exactProbeIdentities, <(String, String)>[
        (_peerId, 'reaction-remote-settlement'),
      ]);
      expect(gate.consumes, 0);
      expect(gate.exactConsumes, 0);
      expect(gate.hasProof, isTrue);
      expect(harness.displayOutbox.entry, isNotNull);

      await harness.composition.owner.retryNow();
      expect(harness.service.shown, isEmpty);
      expect(harness.service.durableContexts, hasLength(1));
      expect(gate.exactProbes, 1);
      expect(gate.exactConsumes, 1);
      expect(gate.marks, 0);
      expect(gate.hasProof, isFalse);
      expect(replacementGate.exactConsumes, 0);
      expect(replacementGate.hasProof, isTrue);
      expect(harness.displayOutbox.entry, isNull);
    },
  );

  for (final (name, sourcePayload, sourceEvent, matches)
      in <(String, String, String, bool)>[
        ('matching event', _peerId, 'incoming-reaction', true),
        ('other reaction', _peerId, 'other-reaction', false),
        ('other conversation', 'other-peer', 'incoming-reaction', false),
      ]) {
    test('direct reaction exact NSE sidecar adoption: $name', () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final directory = await Directory.systemTemp.createTemp(
        'reaction-proof-',
      );
      final gate = RecentRemoteNotificationGate(
        filePath: '${directory.path}/dart-gate.json',
        appGroupSidecarDirProvider: () async => directory,
      );
      final marker = File(
        '${directory.path}/RecentRemoteShown/'
        '${gate.sidecarMarkerName(sourcePayload, sourceEvent)}',
      );
      await marker.parent.create(recursive: true);
      await marker.writeAsString('');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
        await directory.delete(recursive: true);
      });
      final harness = await _DurableDirectProjectionHarness.create(
        messageId: 'authored-target',
        reactionId: 'incoming-reaction',
      );
      addTearDown(harness.dispose);

      await harness.composition.owner.retryNow();

      expect(harness.service.shown, hasLength(matches ? 0 : 1));
      expect(
        harness.service.durableContexts.single.remotePresentationEstablished,
        matches,
      );
      expect(await marker.exists(), !matches);
      expect(harness.displayOutbox.entry, isNull);
    });
  }

  for (final (kind, reactionId) in <(String, String?)>[
    ('message', null),
    ('reaction', 'reaction-delayed'),
  ]) {
    test(
      'canonical direct $kind retirement cleans exact proof only after settlement',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        final originalGate = recentRemoteNotificationGate;
        final gate = _TrackingRecentRemoteNotificationGate(hasProof: true);
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        debugSetRecentRemoteNotificationGate(gate);
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previousPlatform;
          debugSetRecentRemoteNotificationGate(originalGate);
        });
        final harness = await _DurableDirectProjectionHarness.create(
          messageId: 'retired-message',
          reactionId: reactionId,
        );
        addTearDown(harness.dispose);
        final retired = harness.displayOutbox.entry!.copyWith(
          lastErrorCode:
              DirectNotificationDisplayOutboxErrorCode.stateUnavailable,
          lastAttemptAt: DirectNotificationDisplayOutboxErrorCode
              .canonicalRetirementAttemptMarker,
        );
        harness.displayOutbox.entry = retired;
        await harness.database.update(
          'direct_notification_display_outbox',
          retired.toMap(),
          where: 'event_id = ?',
          whereArgs: <Object?>[retired.eventId],
        );
        harness.registry.onSettle = () {
          if (harness.registry.settlements == 1) {
            throw StateError('retirement settlement interrupted');
          }
        };
        gate.beforeExactConsume = () async {
          expect(harness.displayOutbox.entry, isNull);
          expect(harness.registry.settlements, 2);
        };
        await harness.composition.owner.retryNow();
        expect(gate.exactProbes, 0);
        expect(gate.exactConsumes, 0);
        expect(gate.hasProof, isTrue);
        await harness.composition.owner.retryNow();
        expect(gate.exactConsumes, 1);
        expect(gate.exactConsumeIdentities, <(String, String)>[
          (_peerId, reactionId ?? 'retired-message'),
        ]);
        expect(gate.hasProof, isFalse);
        expect(harness.displayOutbox.entry, isNull);
      },
    );

    test('pending direct $kind adopts NSE proof after 13 hours', () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      final originalGate = recentRemoteNotificationGate;
      final directory = await Directory.systemTemp.createTemp(
        'delayed-direct-proof-',
      );
      final gate = RecentRemoteNotificationGate(
        filePath: '${directory.path}/dart-gate.json',
        appGroupSidecarDirProvider: () async => directory,
      );
      final eventId = reactionId ?? 'delayed-message';
      final marker = File(
        '${directory.path}/RecentRemoteShown/'
        '${gate.sidecarMarkerName(_peerId, eventId)}',
      );
      await marker.parent.create(recursive: true);
      await marker.writeAsString('');
      await marker.setLastModified(
        DateTime.now().subtract(const Duration(hours: 13)),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugSetRecentRemoteNotificationGate(gate);
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = previousPlatform;
        debugSetRecentRemoteNotificationGate(originalGate);
        await directory.delete(recursive: true);
      });
      final harness = await _DurableDirectProjectionHarness.create(
        messageId: 'delayed-message',
        reactionId: reactionId,
      );
      addTearDown(harness.dispose);
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'unrelated-peer',
          messageId: 'unrelated-event',
        ),
        isFalse,
      );
      expect(
        await gate.hasRecentExactAnnouncement(
          payload: _peerId,
          messageId: eventId,
        ),
        isFalse,
      );

      await harness.composition.owner.retryNow();
      await harness.composition.owner.retryNow();

      expect(harness.service.shown, isEmpty);
      expect(harness.service.durableContexts, hasLength(1));
      expect(
        harness.service.durableContexts.single.remotePresentationEstablished,
        isTrue,
      );
      expect(harness.registry.settlements, 1);
      expect(harness.displayOutbox.entry, isNull);
      expect(await marker.exists(), isFalse);
    });
  }

  for (final (mediaType, body) in <(String, String)>[
    ('image', 'Photo'),
    ('video', 'Video'),
    ('audio', 'Voice message'),
    ('file', 'File'),
  ]) {
    test(
      'durable direct $mediaType body loads persisted attachment metadata',
      () async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        final originalGate = recentRemoteNotificationGate;
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        debugSetRecentRemoteNotificationGate(
          _TrackingRecentRemoteNotificationGate(hasProof: false),
        );
        addTearDown(() {
          debugDefaultTargetPlatformOverride = previousPlatform;
          debugSetRecentRemoteNotificationGate(originalGate);
        });
        final harness = await _DurableDirectProjectionHarness.create(
          messageId: 'message-media-$mediaType',
          messageText: '',
          attachments: <MediaAttachment>[
            _attachment('message-media-$mediaType', mediaType),
            // A same-parent group row must not influence the direct preview.
            _attachment(
              'message-media-$mediaType',
              'file',
              owner: MediaOwnerLane.group,
            ),
          ],
        );
        addTearDown(harness.dispose);

        await harness.composition.owner.retryNow();
        await harness.composition.owner.retryNow();

        expect(harness.service.shown, hasLength(1));
        expect(harness.service.shown.single.messageText, body);
        expect(harness.service.shown.single.snapshot!.historyLines, <String>[
          body,
        ]);
        expect(harness.displayOutbox.entry, isNull);
      },
    );
  }

  for (final durableMetadata in <bool>[false, true]) {
    test(
      'direct media reconciliation restores native body (durable=$durableMetadata)',
      () async {
        const messageId = 'message-media-reconciliation';
        final correlation = _correlation(
          NotificationCompletedOutcomeProducerKind.directMessage,
          messageId,
        );
        final harness = await _Harness.create(
          ConversationNotificationContentMetadata(
            kind: ConversationNotificationContentKind.message,
            eventIdentity: durableMetadata ? correlation : messageId,
            generation: durableMetadata
                ? durableLocalNotificationContentGeneration(correlation)
                : 'old-generation',
          ),
          attachments: <MediaAttachment>[_attachment(messageId, 'audio')],
        );
        addTearDown(harness.dispose);
        harness.messages.seed(<ConversationMessage>[
          _message(
            id: messageId,
            timestamp: '2026-08-16T10:00:00.000Z',
            incoming: true,
          ).copyWith(text: ''),
        ]);

        await harness.composition.owner.retryNow();

        expect(harness.service.replacements, hasLength(1));
        expect(
          harness.service.replacements.single.messageText,
          'Voice message',
        );
        expect(harness.reconciliation.entry, isNull);
      },
    );
  }
}

MediaAttachment _attachment(
  String messageId,
  String mediaType, {
  MediaOwnerLane owner = MediaOwnerLane.direct,
}) => MediaAttachment(
  id: 'attachment-$mediaType-${owner.name}',
  messageId: messageId,
  mime: '$mediaType/test',
  size: 12,
  mediaType: mediaType,
  downloadStatus: 'pending',
  createdAt: '2026-08-16T10:00:00.000Z',
  ownerLane: owner,
);

String _correlation(
  NotificationCompletedOutcomeProducerKind producerKind,
  String eventKey,
) => tryComputeNotificationCompletedOutcomeCorrelation(
  physicalPeerId: _physicalPeerId,
  producerKind: producerKind,
  eventKey: eventKey,
)!;

ConversationMessage _message({
  required String id,
  required String timestamp,
  required bool incoming,
  PrivateMediaPolicy privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
  PrivateMediaLifecycleState privateMediaState =
      PrivateMediaLifecycleState.none,
}) => ConversationMessage(
  id: id,
  contactPeerId: _peerId,
  senderPeerId: incoming ? _peerId : 'self-peer',
  text: 'message $id',
  timestamp: timestamp,
  status: 'delivered',
  isIncoming: incoming,
  createdAt: timestamp,
  privateMediaPolicy: privateMediaPolicy,
  privateMediaState: privateMediaState,
);

final class _CountingMessageRepository extends FakeMessageRepository {
  int getMessagesForContactCalls = 0;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) {
    getMessagesForContactCalls++;
    return super.getMessagesForContact(contactPeerId);
  }
}

final class _Harness {
  _Harness._({
    required this.database,
    required this.messages,
    required this.reactions,
    required this.terminals,
    required this.reconciliation,
    required this.service,
    required this.composition,
  });

  final Database database;
  final _CountingMessageRepository messages;
  final FakeReactionRepository reactions;
  final _ReactionTerminalRepository terminals;
  final _ReconciliationOutbox reconciliation;
  final _GenerationNotificationService service;
  final ProductionCanonicalDirectProjectionComposition composition;

  static Future<_Harness> create(
    ConversationNotificationContentMetadata metadata, {
    List<MediaAttachment> attachments = const <MediaAttachment>[],
  }) async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        contact_peer_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        notification_display_terminal_event_id TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE direct_notification_reaction_terminal_events (
        peer_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        actor_peer_id TEXT NOT NULL,
        reaction_id TEXT NOT NULL,
        terminal_event_id TEXT NOT NULL,
        notification_acknowledged_at TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (peer_id, message_id, actor_peer_id)
      )
    ''');
    final contacts = FakeContactRepository()
      ..seed(const <ContactModel>[
        ContactModel(
          peerId: _peerId,
          publicKey: 'public-key',
          rendezvous: '/memory/direct',
          username: 'Direct Peer',
          signature: 'signature',
          scannedAt: '2026-08-16T09:00:00.000Z',
        ),
      ]);
    final messages = _CountingMessageRepository();
    final reactions = FakeReactionRepository();
    final terminals = _ReactionTerminalRepository();
    final reconciliation = _ReconciliationOutbox(_reconciliationEntry());
    final service = _GenerationNotificationService(metadata);
    final composition = buildProductionCanonicalDirectProjectionComposition(
      ProductionCanonicalDirectProjectionDependencies(
        database: database,
        notificationService: service,
        appVisibility: FixedAppVisibility(),
        contactRepository: contacts,
        messageRepository: messages,
        reactionRepository: reactions,
        mediaAttachmentRepository: FakeMediaAttachmentRepository()
          ..seed(attachments),
        displayOutbox: _EmptyDisplayOutbox(),
        reconciliationOutbox: reconciliation,
        reactionTerminal: terminals,
        readAcknowledgement: _EmptyReadAcknowledgement(),
        durableRegistry: null,
        readCurrentOpaqueBinding: () async => null,
        resolvePhysicalPeerId: () async => _physicalPeerId,
        presentationOwner: LocalNotificationPresentationOwner.inboxReconciler,
        completedOutcomeProducerEnabled: false,
        notificationToneTracker: NotificationToneTracker(),
        durableNotificationCoordinatorResolver: () async => null,
      ),
    );
    return _Harness._(
      database: database,
      messages: messages,
      reactions: reactions,
      terminals: terminals,
      reconciliation: reconciliation,
      service: service,
      composition: composition,
    );
  }

  Future<void> insertReactionTerminal(
    DirectNotificationReactionTerminalEvent terminal,
  ) => insertReactionTerminals(<DirectNotificationReactionTerminalEvent>[
    terminal,
  ]);

  Future<void> insertReactionTerminals(
    Iterable<DirectNotificationReactionTerminalEvent> values,
  ) async {
    final batch = database.batch();
    for (final terminal in values) {
      terminals.seed(terminal);
      batch.insert(
        'direct_notification_reaction_terminal_events',
        terminal.toMap(),
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> dispose() async {
    composition.owner.dispose();
    await database.close();
  }
}

DirectNotificationReconciliationOutboxEntry _reconciliationEntry() =>
    const DirectNotificationReconciliationOutboxEntry(
      peerId: _peerId,
      incarnationId: 'incarnation-1',
      revision: 1,
      retryCount: 0,
      lastAttemptAt: null,
      nextAttemptAt: null,
      createdAt: '2026-08-16T11:00:00.000Z',
      updatedAt: '2026-08-16T11:00:00.000Z',
    );

final class _GenerationNotificationService extends FakeNotificationService
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement {
  _GenerationNotificationService(this.metadata);

  ConversationNotificationContentMetadata? metadata;
  final List<String> cancelledGenerations = <String>[];
  final List<CanonicalConversationNotificationReplacement> replacements =
      <CanonicalConversationNotificationReplacement>[];

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
  ) async {
    if (metadata?.generation != expectedGeneration) return false;
    replacements.add(replacement);
    metadata = ConversationNotificationContentMetadata(
      kind: replacement.contentKind,
      eventIdentity: replacement.eventIdentity,
      generation: 'replacement-${replacements.length}',
    );
    return true;
  }
}

final class _ReconciliationOutbox
    implements DirectNotificationReconciliationOutboxRepository {
  _ReconciliationOutbox(this.entry);

  DirectNotificationReconciliationOutboxEntry? entry;
  int failures = 0;

  @override
  Future<List<DirectNotificationReconciliationOutboxEntry>> loadEligible({
    int limit = 20,
  }) async => entry == null
      ? const <DirectNotificationReconciliationOutboxEntry>[]
      : <DirectNotificationReconciliationOutboxEntry>[entry!];

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async =>
      DateTime.tryParse(entry?.nextAttemptAt ?? '');

  @override
  Future<bool> completeIfExact(
    DirectNotificationReconciliationOutboxEntry expected,
  ) async {
    if (entry != expected) return false;
    entry = null;
    return true;
  }

  @override
  Future<bool> recordFailureIfExact({
    required DirectNotificationReconciliationOutboxEntry expected,
    required DateTime nextAttemptAt,
  }) async {
    if (entry != expected) return false;
    failures++;
    entry = DirectNotificationReconciliationOutboxEntry(
      peerId: expected.peerId,
      incarnationId: expected.incarnationId,
      revision: expected.revision + 1,
      retryCount: expected.retryCount + 1,
      lastAttemptAt: '2026-08-16T11:01:00.000Z',
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      createdAt: expected.createdAt,
      updatedAt: '2026-08-16T11:01:00.000Z',
    );
    return true;
  }
}

class _EmptyDisplayOutbox implements DirectNotificationDisplayOutboxRepository {
  @override
  Future<void> stage(DirectNotificationDisplayOutboxEntry entry) async {}

  @override
  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async => null;

  @override
  Future<bool> promoteReadyIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
  }) async => false;

  @override
  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async => const <DirectNotificationDisplayOutboxEntry>[];

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async => null;

  @override
  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) async => false;

  @override
  Future<bool> completeIfExact(
    DirectNotificationDisplayOutboxEntry expected, {
    NotificationCompletedOutcomeCandidate? outcome,
  }) async => false;

  @override
  Future<bool> retireAfterDurableSettlementIfExact(
    DirectNotificationDisplayOutboxEntry expected,
  ) async => false;

  @override
  Future<bool> retireIfExact(
    DirectNotificationDisplayOutboxEntry expected,
  ) async => false;

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

final class _SingleDisplayOutbox extends _EmptyDisplayOutbox {
  _SingleDisplayOutbox(this.entry, {this.settlementDatabase});

  DirectNotificationDisplayOutboxEntry? entry;
  final Database? settlementDatabase;
  int retireAfterSettlementCalls = 0;

  bool _matches({
    required String peerId,
    required String eventKind,
    required String eventId,
    int? expectedRevision,
  }) {
    final current = entry;
    return current != null &&
        current.peerId == peerId &&
        current.eventKind == eventKind &&
        current.eventId == eventId &&
        (expectedRevision == null || current.revision == expectedRevision);
  }

  @override
  Future<DirectNotificationDisplayOutboxEntry?> loadExact({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async => _matches(peerId: peerId, eventKind: eventKind, eventId: eventId)
      ? entry
      : null;

  @override
  Future<List<DirectNotificationDisplayOutboxEntry>> loadReady({
    int limit = 20,
  }) async {
    final current = entry;
    if (current == null || !current.isReady || limit <= 0) {
      return const <DirectNotificationDisplayOutboxEntry>[];
    }
    final nextAttemptAt = DateTime.tryParse(current.nextAttemptAt ?? '');
    if (nextAttemptAt != null && nextAttemptAt.isAfter(DateTime.now())) {
      return const <DirectNotificationDisplayOutboxEntry>[];
    }
    return <DirectNotificationDisplayOutboxEntry>[current];
  }

  @override
  Future<DateTime?> loadEarliestNextAttemptAt() async =>
      DateTime.tryParse(entry?.nextAttemptAt ?? '');

  @override
  Future<bool> recordRetryIfExact({
    required String peerId,
    required String eventKind,
    required String eventId,
    required int expectedRevision,
    required String lastErrorCode,
    required DateTime nextAttemptAt,
  }) async {
    if (!_matches(
      peerId: peerId,
      eventKind: eventKind,
      eventId: eventId,
      expectedRevision: expectedRevision,
    )) {
      return false;
    }
    final current = entry!;
    entry = current.copyWith(
      revision: current.revision + 1,
      retryCount: current.retryCount + 1,
      lastErrorCode: lastErrorCode,
      lastAttemptAt: DateTime.now().toUtc().toIso8601String(),
      nextAttemptAt: nextAttemptAt.toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return true;
  }

  @override
  Future<bool> retireAfterDurableSettlementIfExact(
    DirectNotificationDisplayOutboxEntry expected,
  ) async {
    retireAfterSettlementCalls += 1;
    if (!_matches(
      peerId: expected.peerId,
      eventKind: expected.eventKind,
      eventId: expected.eventId,
      expectedRevision: expected.revision,
    )) {
      return false;
    }
    final database = settlementDatabase;
    final retired = database == null
        ? false
        : await dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
            database,
            eventId: expected.eventId,
            expectedRevision: expected.revision,
            expectedEventKind: expected.eventKind,
            expectedPeerId: expected.peerId,
            expectedMessageId: expected.messageId,
            expectedActorPeerId: expected.actorPeerId,
            expectedEventTimestamp: expected.eventTimestamp,
            expectedReactionId: expected.reactionId,
            expectedReactionAction: expected.reactionAction,
            expectedReactionTombstone: expected.reactionTombstone,
          );
    if (retired) entry = null;
    return retired;
  }
}

final class _TrackingRecentRemoteNotificationGate
    extends RecentRemoteNotificationGate {
  _TrackingRecentRemoteNotificationGate({required this.hasProof})
    : super(filePath: '/unused/direct-remote-proof.json');

  bool hasProof;
  int probes = 0;
  int exactProbes = 0;
  final exactProbeIdentities = <(String, String)>[];
  int consumes = 0;
  int exactConsumes = 0;
  final exactConsumeIdentities = <(String, String)>[];
  int marks = 0;
  Future<void> Function()? beforeExactConsume;

  @override
  Future<bool> hasRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    probes += 1;
    return hasProof;
  }

  @override
  Future<bool> hasExactPendingAnnouncement({
    required String payload,
    required String messageId,
  }) async {
    exactProbes += 1;
    exactProbeIdentities.add((payload, messageId));
    return hasProof;
  }

  @override
  Future<bool> consumeIfRecentAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    consumes += 1;
    final result = hasProof;
    hasProof = false;
    return result;
  }

  @override
  Future<bool> consumeExactPendingAnnouncement({
    required String payload,
    required String messageId,
  }) async {
    await beforeExactConsume?.call();
    exactConsumes += 1;
    exactConsumeIdentities.add((payload, messageId));
    final result = hasProof;
    hasProof = false;
    return result;
  }

  @override
  Future<void> markAnnouncement({
    required String payload,
    String? messageId,
  }) async {
    marks += 1;
    hasProof = true;
  }
}

final class _RemoteAdoptionNotificationService extends FakeNotificationService
    implements
        ConversationNotificationGenerationCancellation,
        ConversationNotificationGenerationReplacement,
        MessageNotificationDurableFinalEffectBoundary {
  _RemoteAdoptionNotificationService({this.terminal = false});

  final bool terminal;
  final List<DurableLocalNotificationEffectContext> durableContexts =
      <DurableLocalNotificationEffectContext>[];

  @override
  Future<ConversationNotificationContentMetadata?>
  lookupConversationNotificationContentMetadata(String conversationKey) async =>
      null;

  @override
  Future<bool> cancelConversationNotificationGeneration(
    String conversationKey,
    String generation,
  ) async => false;

  @override
  Future<bool> replaceConversationNotificationGeneration(
    String conversationKey,
    String expectedGeneration,
    CanonicalConversationNotificationReplacement replacement,
  ) async => false;

  @override
  Future<DurableLocalNotificationEffectResult>
  showMessageNotificationWithDurableFinalEffect({
    required String contactPeerId,
    required String senderUsername,
    required String messageText,
    String? payload,
    bool silent = false,
    required ConversationNotificationContentKind contentKind,
    required String contentEventIdentity,
    ConversationNotificationSnapshot? snapshot,
    required DurableLocalNotificationEffectContext durableEffectContext,
    required AppVisibilitySuppressionReader finalVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required PublishNativeMessageNotificationAtDurableBarrier publishNative,
  }) async {
    durableContexts.add(durableEffectContext);
    if (!terminal) {
      return const DurableLocalNotificationEffectResult.retryable();
    }
    var enteredNative = false;
    if (!durableEffectContext.remotePresentationEstablished) {
      enteredNative = await publishNative(
        ({required bool silent}) => super.showMessageNotification(
          contactPeerId: contactPeerId,
          senderUsername: senderUsername,
          messageText: messageText,
          payload: payload,
          silent: silent,
          contentKind: contentKind,
          contentEventIdentity: contentEventIdentity,
          snapshot: snapshot,
        ),
        () async => true,
      );
    }
    return DurableLocalNotificationEffectResult(
      disposition: DurableLocalNotificationEffectDisposition.osPosted,
      receipt: DurableLocalNotificationEffectReceipt(
        eventCorrelation: durableEffectContext.eventCorrelation,
        recordRevision: 7,
        presentationState: LocalNotificationPresentationState.osPosted,
      ),
      currentNativeEntryAttempted: enteredNative,
    );
  }
}

class _NoopDurableEffectRegistry
    implements DurableLocalNotificationEffectRegistry {
  @override
  Future<DurableLocalNotificationEffectResult> runFinalEffect({
    required DurableLocalNotificationEffectContext context,
    required AppVisibilitySuppressionReader appVisibility,
    required AppVisibilityConversationIdentity conversationIdentity,
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() retireCurrent,
    required Future<void> Function() publishNative,
    Future<void> Function()? publishNativeSilently,
    PublishDurableLocalNotificationAtFinalBarrier? publishNativeAtFinalBarrier,
    ResolveDurableLocalNotificationActiveIds? activeNotificationIds,
  }) => throw UnsupportedError('notification service owns the test boundary');

  @override
  Future<LocalNotificationRecordV1?> settleSqlReadyEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async => null;

  @override
  Future<LocalNotificationRecordV1?> lookupExactEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required String conversationDigest,
    required int notificationId,
    required String contentGeneration,
  }) async => null;

  @override
  Future<List<LocalNotificationRecordV1>> listSqlReadyEffectTerminals({
    required String currentOpaqueBinding,
  }) async => const <LocalNotificationRecordV1>[];

  @override
  Future<LocalNotificationRecordV1?> upgradeRelayCustodyToSqlReady({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async => null;
}

final class _SettlingDurableEffectRegistry extends _NoopDurableEffectRegistry {
  _SettlingDurableEffectRegistry({
    this.producerKind = LocalNotificationProducerKind.directMessage,
  });

  final LocalNotificationProducerKind producerKind;
  int settlements = 0;
  void Function()? onSettle;

  @override
  Future<LocalNotificationRecordV1?> settleSqlReadyEffect({
    required String currentOpaqueBinding,
    required String eventCorrelation,
    required int expectedRevision,
  }) async {
    settlements += 1;
    onSettle?.call();
    const createdAt = '2026-08-16T12:29:00.000Z';
    const terminalAt = '2026-08-16T12:30:00.000Z';
    const settledAt = '2026-08-16T12:31:00.000Z';
    return LocalNotificationRecordV1(
      eventCorrelation: eventCorrelation,
      conversationDigest:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      producerKind: producerKind,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      readState: LocalNotificationReadState.unread,
      presentationState: LocalNotificationPresentationState.osPosted,
      presentationOwner: LocalNotificationPresentationOwner.iosNse,
      notificationId: 7,
      contentGeneration: 'ledger:$eventCorrelation',
      lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.background,
      visibilityRevision: 1,
      lifecycleGeneration: 1,
      effectPhase: LocalNotificationEffectPhase.settled,
      attemptKind: null,
      effectToken: null,
      revision: expectedRevision + 1,
      createdAtUtc: createdAt,
      updatedAtUtc: settledAt,
      terminalAtUtc: terminalAt,
      settledAtUtc: settledAt,
    );
  }
}

final class _DurableDirectProjectionHarness {
  _DurableDirectProjectionHarness._({
    required this.database,
    required this.displayOutbox,
    required this.registry,
    required this.service,
    required this.composition,
  });

  final Database database;
  final _SingleDisplayOutbox displayOutbox;
  final _SettlingDurableEffectRegistry registry;
  final _RemoteAdoptionNotificationService service;
  final ProductionCanonicalDirectProjectionComposition composition;

  static Future<_DurableDirectProjectionHarness> create({
    required String messageId,
    String? reactionId,
    String? messageText,
    List<MediaAttachment> attachments = const <MediaAttachment>[],
  }) async {
    const timestamp = '2026-08-16T12:30:00.000Z';
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await database.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        contact_peer_id TEXT NOT NULL,
        sender_peer_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_incoming INTEGER NOT NULL,
        read_at TEXT,
        deleted_at TEXT,
        hidden_at TEXT,
        private_media_state TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE contacts (
        peer_id TEXT PRIMARY KEY,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    if (reactionId != null) {
      await database.execute('''
        CREATE TABLE message_reactions (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          sender_peer_id TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          removed_at TEXT
        )
      ''');
      await database.insert('message_reactions', <String, Object?>{
        'id': reactionId,
        'message_id': messageId,
        'sender_peer_id': _peerId,
        'timestamp': timestamp,
      });
    }
    await runDirectNotificationDurabilityMigration(database);
    await database.insert('messages', <String, Object?>{
      'id': messageId,
      'contact_peer_id': _peerId,
      'sender_peer_id': reactionId == null ? _peerId : 'self-peer',
      'timestamp': timestamp,
      'is_incoming': reactionId == null ? 1 : 0,
    });
    final entry = reactionId == null
        ? DirectNotificationDisplayOutboxEntry.message(
            eventId: messageId,
            peerId: _peerId,
            messageId: messageId,
            actorPeerId: _peerId,
            eventTimestamp: timestamp,
            readiness: DirectNotificationDisplayOutboxReadiness.ready,
            createdAt: timestamp,
            updatedAt: timestamp,
          )
        : DirectNotificationDisplayOutboxEntry.reaction(
            eventId: 'terminal:$reactionId',
            peerId: _peerId,
            messageId: messageId,
            actorPeerId: _peerId,
            eventTimestamp: timestamp,
            reactionId: reactionId,
            reactionAction: 'add',
            reactionTombstone: false,
            readiness: DirectNotificationDisplayOutboxReadiness.ready,
            createdAt: timestamp,
            updatedAt: timestamp,
          );
    await database.insert('direct_notification_display_outbox', entry.toMap());
    final messages = _CountingMessageRepository()
      ..seed(<ConversationMessage>[
        _message(
          id: messageId,
          timestamp: timestamp,
          incoming: reactionId == null,
        ).copyWith(text: messageText),
      ]);
    final contacts = FakeContactRepository()
      ..seed(const <ContactModel>[
        ContactModel(
          peerId: _peerId,
          publicKey: 'public-key',
          rendezvous: '/memory/direct',
          username: 'Direct Peer',
          signature: 'signature',
          scannedAt: timestamp,
        ),
      ]);
    final displayOutbox = _SingleDisplayOutbox(
      entry,
      settlementDatabase: database,
    );
    final registry = _SettlingDurableEffectRegistry(
      producerKind: reactionId == null
          ? LocalNotificationProducerKind.directMessage
          : LocalNotificationProducerKind.directReaction,
    );
    final reactions = FakeReactionRepository();
    if (reactionId != null) {
      await reactions.saveReaction(
        MessageReaction(
          id: reactionId,
          messageId: messageId,
          emoji: '❤️',
          senderPeerId: _peerId,
          timestamp: timestamp,
          createdAt: timestamp,
        ),
      );
    }
    final service = _RemoteAdoptionNotificationService(terminal: true);
    final composition = buildProductionCanonicalDirectProjectionComposition(
      ProductionCanonicalDirectProjectionDependencies(
        database: database,
        notificationService: service,
        appVisibility: FixedAppVisibility(),
        contactRepository: contacts,
        messageRepository: messages,
        reactionRepository: reactions,
        mediaAttachmentRepository: FakeMediaAttachmentRepository()
          ..seed(attachments),
        displayOutbox: displayOutbox,
        reconciliationOutbox: _ReconciliationOutbox(null),
        reactionTerminal: _ReactionTerminalRepository(),
        readAcknowledgement: _EmptyReadAcknowledgement(),
        durableRegistry: registry,
        readCurrentOpaqueBinding: () async =>
            'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        resolvePhysicalPeerId: () async => _physicalPeerId,
        presentationOwner: LocalNotificationPresentationOwner.inboxReconciler,
        completedOutcomeProducerEnabled: false,
        notificationToneTracker: NotificationToneTracker(),
        durableNotificationCoordinatorResolver: () async => null,
      ),
    );
    return _DurableDirectProjectionHarness._(
      database: database,
      displayOutbox: displayOutbox,
      registry: registry,
      service: service,
      composition: composition,
    );
  }

  Future<void> dispose() async {
    composition.owner.dispose();
    await database.close();
  }
}

final class _ReactionTerminalRepository
    implements DirectNotificationReactionTerminalRepository {
  final Map<String, DirectNotificationReactionTerminalEvent> _byEvent =
      <String, DirectNotificationReactionTerminalEvent>{};
  int loadByTerminalEventCalls = 0;

  void seed(DirectNotificationReactionTerminalEvent terminal) {
    _byEvent[terminal.terminalEventId] = terminal;
  }

  @override
  Future<bool> upsert({
    required String peerId,
    required String messageId,
    required String actorPeerId,
    required String reactionId,
    required String terminalEventId,
  }) async => false;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadExact({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async => _byEvent.values
      .where(
        (terminal) =>
            terminal.peerId == peerId &&
            terminal.messageId == messageId &&
            terminal.actorPeerId == actorPeerId,
      )
      .firstOrNull;

  @override
  Future<DirectNotificationReactionTerminalEvent?> loadByTerminalEvent({
    required String peerId,
    required String terminalEventId,
  }) async {
    loadByTerminalEventCalls++;
    final terminal = _byEvent[terminalEventId];
    return terminal?.peerId == peerId ? terminal : null;
  }

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

final class _EmptyReadAcknowledgement
    implements DirectNotificationReadAcknowledgementRepository {
  @override
  Future<bool> record(
    DirectNotificationReadAcknowledgement acknowledgement,
  ) async => false;

  @override
  Future<DirectNotificationReadAcknowledgement?> loadExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
    String? generation,
  }) async => null;

  @override
  Future<int> consumeExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
  }) async => 0;

  @override
  Future<int> deleteForPeer(String peerId) async => 0;
}
