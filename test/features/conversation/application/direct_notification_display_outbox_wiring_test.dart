import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
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

void main() {
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
}

DirectNotificationProjectionOwner _owner({
  required _DisplayOutbox display,
  required _GenerationService service,
  required DateTime Function() now,
  required ProjectDirectNotificationDisplayEntry project,
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
    projectDisplay: project,
    canonicalReconciler: reconciler,
    enqueueReconciliation: (_) async {},
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
    DirectNotificationDisplayOutboxEntry expected,
  ) async {
    final key = _key(expected.peerId, expected.eventKind, expected.eventId);
    final current = rows[key];
    if (current?.revision != expected.revision) return false;
    rows.remove(key);
    completed.add(expected.eventId);
    return true;
  }

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
