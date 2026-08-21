import 'package:flutter_app/app/bootstrap/production_canonical_direct_projection_composition.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reaction_terminal_event.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_read_acknowledgement.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
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
}

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
    ConversationNotificationContentMetadata metadata,
  ) async {
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
        mediaAttachmentRepository: FakeMediaAttachmentRepository(),
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

final class _EmptyDisplayOutbox
    implements DirectNotificationDisplayOutboxRepository {
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
