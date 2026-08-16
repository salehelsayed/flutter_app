import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_projection_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/direct_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/direct_conversation_notification_snapshot.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_display_retry_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_projection_owner.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reaction_terminal_event.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_read_acknowledgement.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reaction_terminal_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_read_acknowledgement_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reconciliation_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class ProductionCanonicalDirectProjectionComposition {
  const ProductionCanonicalDirectProjectionComposition({
    required this.owner,
    required this.readProjector,
  });

  final DirectNotificationProjectionOwner owner;
  final DirectNotificationReadProjector readProjector;
}

typedef _DirectCanonicalMetadataKey = ({
  String peerId,
  ConversationNotificationContentKind kind,
  String eventIdentity,
  String? generation,
});

final class _DurableDirectMessageMaterialization {
  const _DurableDirectMessageMaterialization({
    required this.correlationMatches,
    required this.message,
    required this.snapshot,
  });

  final bool correlationMatches;
  final ConversationMessage message;
  final ConversationNotificationSnapshot? snapshot;
}

final class _DirectCanonicalMessageState {
  const _DirectCanonicalMessageState({
    required this.newestMessage,
    required this.snapshot,
  });

  final ConversationMessage? newestMessage;
  final ConversationNotificationSnapshot? snapshot;
}

final class _DirectReactionMaterialization {
  const _DirectReactionMaterialization({
    required this.terminal,
    required this.target,
    required this.reaction,
  });

  final DirectNotificationReactionTerminalEvent terminal;
  final ConversationMessage? target;
  final MessageReaction? reaction;
}

final class ProductionCanonicalDirectProjectionDependencies {
  const ProductionCanonicalDirectProjectionDependencies({
    required this.database,
    required this.notificationService,
    required this.appVisibility,
    required this.contactRepository,
    required this.messageRepository,
    required this.reactionRepository,
    required this.mediaAttachmentRepository,
    required this.displayOutbox,
    required this.reconciliationOutbox,
    required this.reactionTerminal,
    required this.readAcknowledgement,
    required this.durableRegistry,
    required this.readCurrentOpaqueBinding,
    required this.resolvePhysicalPeerId,
    required this.presentationOwner,
    required this.completedOutcomeProducerEnabled,
    required this.notificationToneTracker,
    required this.durableNotificationCoordinatorResolver,
    this.pendingNotificationOverlay,
    this.kickCompletedOutcomeDrain,
  });

  final Database database;
  final NotificationService notificationService;
  final AppVisibilitySuppressionReader appVisibility;
  final ContactRepository contactRepository;
  final MessageRepository messageRepository;
  final ReactionRepository reactionRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final DirectNotificationDisplayOutboxRepository displayOutbox;
  final DirectNotificationReconciliationOutboxRepository reconciliationOutbox;
  final DirectNotificationReactionTerminalRepository reactionTerminal;
  final DirectNotificationReadAcknowledgementRepository readAcknowledgement;
  final DurableLocalNotificationEffectRegistry? durableRegistry;
  final Future<String?> Function() readCurrentOpaqueBinding;
  final Future<String?> Function() resolvePhysicalPeerId;
  final LocalNotificationPresentationOwner presentationOwner;
  final bool completedOutcomeProducerEnabled;
  final NotificationToneTracker notificationToneTracker;
  final ResolveDurableNotificationCoordinator
  durableNotificationCoordinatorResolver;
  final PendingConversationNotificationOverlayStore? pendingNotificationOverlay;
  final void Function()? kickCompletedOutcomeDrain;
}

/// Builds the exact direct canonical owner used by both foreground and
/// headless recovery. Keeping all final-disposition, replacement and
/// effect-terminal recovery logic here prevents isolate-specific drift.
ProductionCanonicalDirectProjectionComposition
buildProductionCanonicalDirectProjectionComposition(
  ProductionCanonicalDirectProjectionDependencies dependencies,
) {
  final coordinator = DirectNotificationPresentationCoordinator();
  final generationCancellation =
      dependencies.notificationService
          as ConversationNotificationGenerationCancellation;
  final generationReplacement =
      dependencies.notificationService
          as ConversationNotificationGenerationReplacement;
  final readProjector = DirectNotificationReadProjector(
    coordinator: coordinator,
    cancellation: generationCancellation,
    commitRead: (peerId, metadata) =>
        dbMarkDirectConversationReadAndAcknowledge(
          dependencies.database,
          peerId: peerId,
          metadata: metadata,
        ),
  );
  final durableMessageMaterializations =
      <
        _DirectCanonicalMetadataKey,
        Future<_DurableDirectMessageMaterialization?>
      >{};
  final reactionMaterializations =
      <_DirectCanonicalMetadataKey, Future<_DirectReactionMaterialization?>>{};

  _DirectCanonicalMetadataKey metadataKey(
    String peerId,
    ConversationNotificationContentMetadata metadata,
    String eventIdentity,
  ) => (
    peerId: peerId,
    kind: metadata.kind,
    eventIdentity: eventIdentity,
    generation: metadata.generation?.trim(),
  );

  Future<bool> directPeerAllowsNotification(String peerId) async {
    final contact = await dependencies.contactRepository.getContact(peerId);
    return contact != null && !contact.isBlocked && !contact.isArchived;
  }

  Future<DurableLocalNotificationCanonicalDisposition>
  readFinalDirectNotificationDisposition(
    DirectNotificationDisplayOutboxEntry entry, {
    required void Function(DirectNotificationDisplayOutboxEntry current)
    onExactReady,
    String? durableEventCorrelation,
  }) async {
    Future<DurableLocalNotificationCanonicalDisposition>
    readCanonicalFacts() async {
      final contact = await dependencies.contactRepository.getContact(
        entry.peerId,
      );
      if (contact == null) {
        return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
      if (contact.isBlocked || contact.isArchived) {
        return DurableLocalNotificationCanonicalDisposition.suppressedPolicy;
      }
      switch (entry.eventKind) {
        case DirectNotificationDisplayOutboxKind.message:
          final message = await dependencies.messageRepository.getMessage(
            entry.messageId,
          );
          if (message == null ||
              message.contactPeerId != entry.peerId ||
              message.senderPeerId != entry.actorPeerId ||
              message.timestamp != entry.eventTimestamp ||
              !message.isIncoming) {
            return DurableLocalNotificationCanonicalDisposition
                .retryableUnknown;
          }
          if (message.isDeleted ||
              message.hiddenAt != null ||
              message.privateMediaState.isTerminal) {
            return DurableLocalNotificationCanonicalDisposition.cancelled;
          }
          return message.readAt != null
              ? DurableLocalNotificationCanonicalDisposition.read
              : DurableLocalNotificationCanonicalDisposition.eligible;
        case DirectNotificationDisplayOutboxKind.reaction:
          final target = await dependencies.messageRepository.getMessage(
            entry.messageId,
          );
          final reaction = await dependencies.reactionRepository
              .getReactionForSenderIncludingRemoved(
                messageId: entry.messageId,
                senderPeerId: entry.actorPeerId,
              );
          if (target == null ||
              reaction == null ||
              target.contactPeerId != entry.peerId ||
              target.isIncoming) {
            return DurableLocalNotificationCanonicalDisposition
                .retryableUnknown;
          }
          if (target.isDeleted ||
              target.isHidden ||
              target.privateMediaState.isTerminal ||
              reaction.isRemoved ||
              reaction.id != entry.reactionId ||
              reaction.timestamp != entry.eventTimestamp) {
            return DurableLocalNotificationCanonicalDisposition.cancelled;
          }
          if (durableEventCorrelation != null) {
            final acknowledgement = await dependencies.readAcknowledgement
                .loadExact(
                  peerId: entry.peerId,
                  contentKind:
                      DirectNotificationReadAcknowledgementKind.reaction,
                  eventIdentity: durableEventCorrelation,
                  generation: durableLocalNotificationContentGeneration(
                    durableEventCorrelation,
                  ),
                );
            if (acknowledgement != null &&
                acknowledgement.messageId == entry.messageId &&
                acknowledgement.actorPeerId == entry.actorPeerId) {
              return DurableLocalNotificationCanonicalDisposition.read;
            }
          }
          return DurableLocalNotificationCanonicalDisposition.eligible;
        default:
          return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      }
    }

    final canonicalDisposition = await readCanonicalFacts();
    final current = await dependencies.displayOutbox.loadExact(
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    );
    if (current == null ||
        !current.isReady ||
        current.eventKind != entry.eventKind ||
        current.peerId != entry.peerId ||
        current.messageId != entry.messageId ||
        current.actorPeerId != entry.actorPeerId ||
        current.eventTimestamp != entry.eventTimestamp ||
        current.reactionId != entry.reactionId ||
        current.reactionAction != entry.reactionAction ||
        current.reactionTombstone != entry.reactionTombstone) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    if (current.hasCanonicalRetirementProof) {
      onExactReady(current);
      return DurableLocalNotificationCanonicalDisposition.cancelled;
    }
    if (current.revision != entry.revision) {
      return DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    }
    onExactReady(current);
    return canonicalDisposition;
  }

  DirectNotificationDisplayProjection finishDirectNotificationProjection({
    required NotificationPresentationResult presentation,
    required DirectNotificationDurableEffectAttempt? durableAttempt,
    required int sqlReadyRevision,
  }) {
    final authority = durableAttempt?.completedAuthority?.withSqlReadyRevision(
      sqlReadyRevision,
    );
    if (durableAttempt != null &&
        presentation.isTerminal &&
        authority == null) {
      return const DirectNotificationDisplayProjection(
        presentation: NotificationPresentationResult.contendedRetryable,
      );
    }
    return DirectNotificationDisplayProjection(
      presentation: presentation,
      durableEffectAuthority: authority,
    );
  }

  Future<void> notifyDirectDurablePostHandoff(
    DurableLocalNotificationEffectReceipt receipt,
  ) async {
    final Object service = dependencies.notificationService;
    if (service is MessageNotificationDurablePostHandoffReconciliation) {
      try {
        await service.notifyDurableEffectHandoffComplete(receipt);
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_NOTIFICATION_POST_HANDOFF_REFRESH_FAILED',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }
  }

  Future<void> recoverCommittedDirectNotificationDurableEffects(
    String peerId,
  ) async {
    final registry = dependencies.durableRegistry;
    if (registry == null) return;
    final binding = await dependencies.readCurrentOpaqueBinding();
    final physicalPeerId = await dependencies.resolvePhysicalPeerId();
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: peerId,
    );
    if (binding == null || physicalPeerId == null || identity == null) {
      throw const DirectNotificationDisplayStateUnavailableException();
    }
    final listed = await registry.listSqlReadyEffectTerminals(
      currentOpaqueBinding: binding,
    );
    final pending = listed
        .where(
          (record) =>
              record.sourceCustody == LocalNotificationSourceCustody.sqlReady &&
              (record.effectPhase ==
                      LocalNotificationEffectPhase.effectTerminal ||
                  record.effectPhase == LocalNotificationEffectPhase.settled) &&
              record.conversationDigest == identity.digest &&
              (record.producerKind ==
                      LocalNotificationProducerKind.directMessage ||
                  record.producerKind ==
                      LocalNotificationProducerKind.directReaction),
        )
        .toList(growable: false);
    if (pending.isEmpty) return;
    final readyEntries =
        (await dbLoadAllReadyDirectNotificationDisplayOutboxEntriesForPeer(
              dependencies.database,
              peerId: peerId,
            ))
            .map(DirectNotificationDisplayOutboxEntry.fromMap)
            .toList(growable: false);
    final terminals =
        await dbLoadDirectNotificationCommittedSqlTerminalsForPeer(
          dependencies.database,
          peerId: peerId,
        );
    for (final record in pending) {
      DirectNotificationDisplayOutboxEntry? exactReady;
      DirectNotificationCommittedSqlTerminal? exactTerminal;
      NotificationCompletedOutcomeProducerKind? outcomeProducerKind;
      String? eventKey;
      for (final ready in readyEntries) {
        late final NotificationCompletedOutcomeProducerKind candidateKind;
        late final String candidateKey;
        if (record.producerKind ==
                LocalNotificationProducerKind.directMessage &&
            ready.eventKind == DirectNotificationDisplayOutboxKind.message) {
          candidateKind =
              NotificationCompletedOutcomeProducerKind.directMessage;
          candidateKey = ready.messageId;
        } else if (record.producerKind ==
                LocalNotificationProducerKind.directReaction &&
            ready.eventKind == DirectNotificationDisplayOutboxKind.reaction &&
            ready.reactionId != null) {
          candidateKind =
              NotificationCompletedOutcomeProducerKind.directReaction;
          candidateKey = ready.reactionId!;
        } else {
          continue;
        }
        if (tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: physicalPeerId,
              producerKind: candidateKind,
              eventKey: candidateKey,
            ) !=
            record.eventCorrelation) {
          continue;
        }
        if (exactReady != null) {
          throw const DirectNotificationDisplayStateUnavailableException();
        }
        exactReady = ready;
        outcomeProducerKind = candidateKind;
        eventKey = candidateKey;
      }
      for (final terminal
          in exactReady == null &&
                  record.effectPhase ==
                      LocalNotificationEffectPhase.effectTerminal
              ? terminals
              : const <DirectNotificationCommittedSqlTerminal>[]) {
        late final NotificationCompletedOutcomeProducerKind candidateKind;
        late final String candidateKey;
        if (record.producerKind ==
                LocalNotificationProducerKind.directMessage &&
            terminal.eventKind == DirectNotificationDisplayOutboxKind.message) {
          candidateKind =
              NotificationCompletedOutcomeProducerKind.directMessage;
          candidateKey = terminal.messageId;
        } else if (record.producerKind ==
                LocalNotificationProducerKind.directReaction &&
            terminal.eventKind ==
                DirectNotificationDisplayOutboxKind.reaction &&
            terminal.reactionId != null) {
          candidateKind =
              NotificationCompletedOutcomeProducerKind.directReaction;
          candidateKey = terminal.reactionId!;
        } else {
          continue;
        }
        if (tryComputeNotificationCompletedOutcomeCorrelation(
              physicalPeerId: physicalPeerId,
              producerKind: candidateKind,
              eventKey: candidateKey,
            ) ==
            record.eventCorrelation) {
          exactTerminal = terminal;
          outcomeProducerKind = candidateKind;
          eventKey = candidateKey;
          break;
        }
      }
      if (record.effectPhase == LocalNotificationEffectPhase.settled &&
          exactReady == null) {
        continue;
      }
      if ((exactReady == null && exactTerminal == null) ||
          outcomeProducerKind == null ||
          eventKey == null) {
        throw const DirectNotificationDisplayStateUnavailableException();
      }
      final eventId = exactReady?.eventId ?? exactTerminal!.eventId;
      final eventKind = exactReady?.eventKind ?? exactTerminal!.eventKind;
      final expectedRevision = exactReady?.revision;
      final expectedPeerId = exactReady?.peerId ?? exactTerminal!.peerId;
      final expectedMessageId =
          exactReady?.messageId ?? exactTerminal!.messageId;
      final expectedActorPeerId =
          exactReady?.actorPeerId ?? exactTerminal!.actorPeerId;
      final expectedEventTimestamp =
          exactReady?.eventTimestamp ?? exactTerminal!.eventTimestamp;
      final expectedReactionId =
          exactReady?.reactionId ?? exactTerminal!.reactionId;
      final expectedReactionAction =
          exactReady?.reactionAction ?? exactTerminal!.reactionAction;
      final expectedReactionTombstone =
          exactReady?.reactionTombstone ?? exactTerminal!.reactionTombstone;
      if (record.effectPhase == LocalNotificationEffectPhase.effectTerminal) {
        final outcomeCategory = switch (record.presentationState) {
          LocalNotificationPresentationState.osPosted =>
            NotificationCompletedOutcomeCategory.osPosted,
          LocalNotificationPresentationState.inChat =>
            NotificationCompletedOutcomeCategory.inChat,
          LocalNotificationPresentationState.notEvaluated ||
          LocalNotificationPresentationState.suppressedPolicy ||
          LocalNotificationPresentationState.cancelled => null,
        };
        final outcome =
            !dependencies.completedOutcomeProducerEnabled ||
                outcomeCategory == null
            ? null
            : NotificationCompletedOutcomeCandidate(
                physicalPeerId: physicalPeerId,
                producerKind: outcomeProducerKind,
                eventKey: eventKey,
                outcome: outcomeCategory,
                completedAt: DateTime.parse(record.terminalAtUtc!).toUtc(),
              );
        final handoff =
            await dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
              dependencies.database,
              eventId: eventId,
              expectedRevision: expectedRevision,
              expectedEventKind: eventKind,
              expectedPeerId: expectedPeerId,
              expectedMessageId: expectedMessageId,
              expectedActorPeerId: expectedActorPeerId,
              expectedEventTimestamp: expectedEventTimestamp,
              expectedReactionId: expectedReactionId,
              expectedReactionAction: expectedReactionAction,
              expectedReactionTombstone: expectedReactionTombstone,
              completedAt: record.terminalAtUtc!,
              outcome: outcome,
            );
        if (handoff ==
            DurableLocalNotificationSqlHandoffResult.retryableMismatch) {
          throw const DirectNotificationDisplayRetryableException();
        }
        final settled = await registry.settleSqlReadyEffect(
          currentOpaqueBinding: binding,
          eventCorrelation: record.eventCorrelation,
          expectedRevision: record.revision,
        );
        if (settled == null) {
          throw const DirectNotificationDisplayRetryableException();
        }
      }
      if (!await dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
        dependencies.database,
        eventId: eventId,
        expectedRevision: expectedRevision,
        expectedEventKind: eventKind,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId,
        expectedActorPeerId: expectedActorPeerId,
        expectedEventTimestamp: expectedEventTimestamp,
        expectedReactionId: expectedReactionId,
        expectedReactionAction: expectedReactionAction,
        expectedReactionTombstone: expectedReactionTombstone,
      )) {
        throw const DirectNotificationDisplayRetryableException();
      }
      await notifyDirectDurablePostHandoff(
        DurableLocalNotificationEffectReceipt(
          eventCorrelation: record.eventCorrelation,
          recordRevision: record.revision,
          presentationState: record.presentationState,
        ),
      );
    }
  }

  Future<_DirectCanonicalMessageState?> loadDirectCanonicalMessageState(
    String peerId,
  ) async {
    final messages = await dependencies.messageRepository.getMessagesForContact(
      peerId,
    );
    final canonicalSnapshot = await buildDirectConversationNotificationSnapshot(
      messages: messages,
      contactPeerId: peerId,
      loadAttachments: (messageId) => dependencies.mediaAttachmentRepository
          .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct),
    );
    ConversationMessage? newestMessage;
    if (canonicalSnapshot != null) {
      if (canonicalSnapshot.orderedHistory.isEmpty) return null;
      final canonicalEventId = canonicalSnapshot.orderedHistory.last.eventId;
      final exact = messages
          .where(
            (message) =>
                message.contactPeerId == peerId &&
                message.id == canonicalEventId,
          )
          .toList(growable: false);
      if (exact.length != 1) return null;
      newestMessage = exact.single;
    }
    final overlay = dependencies.pendingNotificationOverlay;
    final snapshot = overlay == null
        ? canonicalSnapshot
        : await overlay.project(
            conversationKey: peerId,
            canonicalSnapshot: canonicalSnapshot,
          );
    return _DirectCanonicalMessageState(
      newestMessage: newestMessage,
      snapshot: snapshot,
    );
  }

  Future<_DurableDirectMessageMaterialization?> materializeDurableDirectMessage(
    String peerId,
    String durableCorrelation,
  ) async {
    final physicalPeerId = await dependencies.resolvePhysicalPeerId();
    if (physicalPeerId == null || physicalPeerId.isEmpty) return null;
    final canonical = await loadDirectCanonicalMessageState(peerId);
    final message = canonical?.newestMessage;
    if (canonical == null || message == null) return null;
    final eventKey = trySelectNotificationCompletedOutcomeEventKey(
      producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
      authenticatedEnvelope: <String, Object?>{'messageId': message.id},
    );
    if (eventKey == null) return null;
    final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
      physicalPeerId: physicalPeerId,
      producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
      eventKey: eventKey,
    );
    if (correlation == null) return null;
    return _DurableDirectMessageMaterialization(
      correlationMatches: correlation == durableCorrelation,
      message: message,
      snapshot: canonical.snapshot,
    );
  }

  Future<_DirectReactionMaterialization?> materializeDirectReaction(
    String peerId, {
    required String eventIdentity,
    required String? durableCorrelation,
  }) async {
    DirectNotificationCommittedSqlTerminal? matched;
    if (durableCorrelation != null) {
      final physicalPeerId = await dependencies.resolvePhysicalPeerId();
      if (physicalPeerId == null || physicalPeerId.isEmpty) return null;
      matched =
          await dbLoadUniqueDirectNotificationCommittedReactionTerminalByCorrelation(
            dependencies.database,
            peerId: peerId,
            physicalPeerId: physicalPeerId,
            eventCorrelation: durableCorrelation,
          );
      if (matched == null) return null;
    }
    final terminal = await dependencies.reactionTerminal.loadByTerminalEvent(
      peerId: peerId,
      terminalEventId: matched?.eventId ?? eventIdentity,
    );
    if (terminal == null) return null;
    if (matched != null &&
        (terminal.peerId != matched.peerId ||
            terminal.messageId != matched.messageId ||
            terminal.actorPeerId != matched.actorPeerId ||
            terminal.reactionId != matched.reactionId ||
            terminal.terminalEventId != matched.eventId ||
            terminal.updatedAt != matched.eventTimestamp)) {
      return null;
    }
    final target = await dependencies.messageRepository.getMessage(
      terminal.messageId,
    );
    final reaction = await dependencies.reactionRepository
        .getReactionForSenderIncludingRemoved(
          messageId: terminal.messageId,
          senderPeerId: terminal.actorPeerId,
        );
    return _DirectReactionMaterialization(
      terminal: terminal,
      target: target,
      reaction: reaction,
    );
  }

  Future<DirectNotificationCanonicalContentDecision>
  resolveDirectCanonicalContent(
    String peerId,
    ConversationNotificationContentMetadata metadata,
  ) async {
    final eventIdentity = metadata.eventIdentity?.trim();
    if (eventIdentity == null || eventIdentity.isEmpty) {
      return DirectNotificationCanonicalContentDecision.unknown;
    }
    if (!await directPeerAllowsNotification(peerId)) {
      return DirectNotificationCanonicalContentDecision.retire;
    }
    final durableCorrelation =
        durableLocalNotificationContentGeneration(eventIdentity) ==
            metadata.generation?.trim()
        ? eventIdentity
        : null;
    switch (metadata.kind) {
      case ConversationNotificationContentKind.message:
        _DurableDirectMessageMaterialization? durableMaterialization;
        if (durableCorrelation != null) {
          final key = metadataKey(peerId, metadata, eventIdentity);
          final pending = durableMessageMaterializations.putIfAbsent(
            key,
            () => materializeDurableDirectMessage(peerId, durableCorrelation),
          );
          try {
            durableMaterialization = await pending;
          } catch (_) {
            if (identical(durableMessageMaterializations[key], pending)) {
              durableMessageMaterializations.remove(key);
            }
            rethrow;
          }
          if (durableMaterialization == null) {
            durableMessageMaterializations.remove(key);
          }
        }
        if (durableCorrelation != null && durableMaterialization == null) {
          return DirectNotificationCanonicalContentDecision.unknown;
        }
        if (durableMaterialization?.correlationMatches == false) {
          // A different newest canonical event owns the one direct card.
          return DirectNotificationCanonicalContentDecision.retire;
        }
        final message =
            durableMaterialization?.message ??
            await dependencies.messageRepository.getMessage(eventIdentity);
        if (message == null) {
          final acknowledgement = await dependencies.readAcknowledgement
              .loadExact(
                peerId: peerId,
                contentKind: 'message',
                eventIdentity: eventIdentity,
                generation: metadata.generation,
              );
          return acknowledgement == null
              ? DirectNotificationCanonicalContentDecision.unknown
              : DirectNotificationCanonicalContentDecision.retire;
        }
        return message.contactPeerId == peerId &&
                message.isIncoming &&
                message.readAt == null &&
                !message.isDeleted &&
                message.hiddenAt == null &&
                !message.privateMediaState.isTerminal
            ? DirectNotificationCanonicalContentDecision.keep
            : DirectNotificationCanonicalContentDecision.retire;
      case ConversationNotificationContentKind.reaction:
        final key = metadataKey(peerId, metadata, eventIdentity);
        final pending = reactionMaterializations.putIfAbsent(
          key,
          () => materializeDirectReaction(
            peerId,
            eventIdentity: eventIdentity,
            durableCorrelation: durableCorrelation,
          ),
        );
        late final _DirectReactionMaterialization? materialization;
        try {
          materialization = await pending;
        } catch (_) {
          if (identical(reactionMaterializations[key], pending)) {
            reactionMaterializations.remove(key);
          }
          rethrow;
        }
        if (materialization == null) {
          if (durableCorrelation != null) {
            reactionMaterializations.remove(key);
            return DirectNotificationCanonicalContentDecision.unknown;
          }
          final acknowledgement = await dependencies.readAcknowledgement
              .loadExact(
                peerId: peerId,
                contentKind: 'reaction',
                eventIdentity: eventIdentity,
                generation: metadata.generation,
              );
          if (acknowledgement == null) {
            reactionMaterializations.remove(key);
            return DirectNotificationCanonicalContentDecision.unknown;
          }
          return DirectNotificationCanonicalContentDecision.retire;
        }
        final terminal = materialization.terminal;
        if (terminal.notificationAcknowledgedAt != null) {
          return DirectNotificationCanonicalContentDecision.retire;
        }
        final target = materialization.target;
        final reaction = materialization.reaction;
        return target != null &&
                directReactionTargetAllowsNotificationDisplay(
                  target: target,
                  expectedContactPeerId: peerId,
                ) &&
                reaction != null &&
                !reaction.isRemoved &&
                reaction.id == terminal.reactionId
            ? DirectNotificationCanonicalContentDecision.keep
            : DirectNotificationCanonicalContentDecision.retire;
    }
  }

  Future<CanonicalConversationNotificationReplacement?>
  loadDirectCanonicalReplacement(
    String peerId,
    ConversationNotificationContentMetadata currentMetadata,
  ) async {
    final currentEventIdentity = currentMetadata.eventIdentity?.trim();
    final key = currentEventIdentity == null || currentEventIdentity.isEmpty
        ? null
        : metadataKey(peerId, currentMetadata, currentEventIdentity);
    final cachedDurableMessage =
        currentMetadata.kind == ConversationNotificationContentKind.message &&
            key != null
        ? durableMessageMaterializations.remove(key)
        : null;
    final cachedReaction =
        currentMetadata.kind == ConversationNotificationContentKind.reaction &&
            key != null
        ? reactionMaterializations.remove(key)
        : null;
    final contact = await dependencies.contactRepository.getContact(peerId);
    if (contact == null || contact.isBlocked || contact.isArchived) return null;
    final currentDurableCorrelation =
        currentEventIdentity != null &&
            currentEventIdentity.isNotEmpty &&
            durableLocalNotificationContentGeneration(currentEventIdentity) ==
                currentMetadata.generation?.trim()
        ? currentEventIdentity
        : null;
    if (currentMetadata.kind == ConversationNotificationContentKind.message &&
        currentDurableCorrelation != null) {
      final materialized =
          await (cachedDurableMessage ??
              materializeDurableDirectMessage(
                peerId,
                currentDurableCorrelation,
              ));
      if (materialized == null) return null;
      final message = materialized.message;
      return CanonicalConversationNotificationReplacement(
        senderUsername: contact.username,
        messageText: notificationBodyForMessage(
          message.text,
          message.media,
          privateMediaPolicy: message.privateMediaPolicy,
        ),
        routePayload: NotificationRouteTarget.conversation(
          peerId,
          messageId: message.id,
        ).toPayload(),
        contentKind: ConversationNotificationContentKind.message,
        eventIdentity: message.id,
        snapshot: materialized.snapshot,
      );
    }
    final canonicalMessages = await loadDirectCanonicalMessageState(peerId);
    if (canonicalMessages == null) return null;
    final newestMessage = canonicalMessages.newestMessage;
    if (newestMessage != null) {
      return CanonicalConversationNotificationReplacement(
        senderUsername: contact.username,
        messageText: notificationBodyForMessage(
          newestMessage.text,
          newestMessage.media,
          privateMediaPolicy: newestMessage.privateMediaPolicy,
        ),
        routePayload: NotificationRouteTarget.conversation(
          peerId,
          messageId: newestMessage.id,
        ).toPayload(),
        contentKind: ConversationNotificationContentKind.message,
        eventIdentity: newestMessage.id,
        snapshot: canonicalMessages.snapshot,
      );
    }
    if (currentMetadata.kind != ConversationNotificationContentKind.reaction) {
      return null;
    }
    final eventIdentity = currentEventIdentity;
    if (eventIdentity == null || eventIdentity.isEmpty) return null;
    final durableCorrelation =
        durableLocalNotificationContentGeneration(eventIdentity) ==
            currentMetadata.generation?.trim()
        ? eventIdentity
        : null;
    final materialization =
        await (cachedReaction ??
            materializeDirectReaction(
              peerId,
              eventIdentity: eventIdentity,
              durableCorrelation: durableCorrelation,
            ));
    final terminal = materialization?.terminal;
    if (materialization == null ||
        terminal == null ||
        terminal.notificationAcknowledgedAt != null) {
      return null;
    }
    final target = materialization.target;
    final reaction = materialization.reaction;
    if (target == null ||
        !directReactionTargetAllowsNotificationDisplay(
          target: target,
          expectedContactPeerId: peerId,
        ) ||
        reaction == null ||
        reaction.isRemoved ||
        reaction.id != terminal.reactionId) {
      return null;
    }
    return CanonicalConversationNotificationReplacement(
      senderUsername: contact.username,
      messageText: 'Reacted ${reaction.emoji} to your message',
      routePayload: NotificationRouteTarget.conversation(
        peerId,
        messageId: terminal.messageId,
      ).toPayload(),
      contentKind: ConversationNotificationContentKind.reaction,
      eventIdentity: terminal.terminalEventId,
      snapshot: canonicalMessages.snapshot,
    );
  }

  final canonicalReconciler = DirectNotificationCanonicalReconciler(
    coordinator: coordinator,
    generationCancellation: generationCancellation,
    generationReplacement: generationReplacement,
    isCurrentContentCanonical: resolveDirectCanonicalContent,
    loadReplacement: loadDirectCanonicalReplacement,
  );

  late final DirectNotificationProjectionOwner owner;
  owner = DirectNotificationProjectionOwner(
    displayOutbox: dependencies.displayOutbox,
    reconciliationOutbox: dependencies.reconciliationOutbox,
    reactionTerminal: dependencies.reactionTerminal,
    coordinator: coordinator,
    canonicalReconciler: canonicalReconciler,
    resolveCompletedOutcomePhysicalPeerId: dependencies.resolvePhysicalPeerId,
    completedOutcomeProducerEnabled:
        dependencies.completedOutcomeProducerEnabled,
    durableLocalNotificationEffectRegistry: dependencies.durableRegistry,
    completeDurableSqlHandoff: (entry, outcome, _) async {
      final handoff =
          await dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
            dependencies.database,
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
            completedAt: DateTime.now().toUtc().toIso8601String(),
            outcome: outcome,
          );
      if (handoff !=
              DurableLocalNotificationSqlHandoffResult.retryableMismatch &&
          outcome != null) {
        dependencies.kickCompletedOutcomeDrain?.call();
      }
      return handoff;
    },
    afterDurableSettlement: (_, authority) =>
        notifyDirectDurablePostHandoff(authority.receipt),
    enqueueReconciliation: (peerId) =>
        dbEnqueueDirectNotificationReconciliationOutbox(
          dependencies.database,
          peerId: peerId,
        ),
    recoverCommittedDurableEffects:
        recoverCommittedDirectNotificationDurableEffects,
    projectDisplay: (entry) async {
      var terminalEntry = entry;
      DirectNotificationDurableEffectAttempt? durableAttempt;
      if (dependencies.durableRegistry != null) {
        late final DirectNotificationDurableEffectAttempt? attempt;
        attempt = DirectNotificationDurableEffectAttempt.tryCreate(
          entry: entry,
          currentOpaqueBinding: await dependencies.readCurrentOpaqueBinding(),
          physicalPeerId: await dependencies.resolvePhysicalPeerId(),
          presentationOwner: dependencies.presentationOwner,
          readFinalCanonicalDisposition: () =>
              readFinalDirectNotificationDisposition(
                entry,
                onExactReady: (current) => terminalEntry = current,
                durableEventCorrelation: attempt?.context.eventCorrelation,
              ),
        );
        durableAttempt = attempt;
      }
      if (dependencies.durableRegistry != null && durableAttempt == null) {
        throw const DirectNotificationDisplayStateUnavailableException();
      }
      if (entry.hasCanonicalRetirementProof) {
        if (durableAttempt == null) return null;
        final presentation = await maybeShowNotification(
          notificationService: dependencies.notificationService,
          appVisibility: dependencies.appVisibility,
          contactPeerId: entry.peerId,
          routePayload: NotificationRouteTarget.conversation(
            entry.peerId,
            messageId: entry.messageId,
          ).toPayload(),
          senderUsername: '',
          messageText: '',
          messageId: entry.messageId,
          notificationEventIdentity: entry.eventId,
          notificationEventType:
              entry.eventKind == DirectNotificationDisplayOutboxKind.reaction
              ? 'message_reaction'
              : 'new_message',
          backgroundDuplicateGuardDelay: Duration.zero,
          durableEffectContext: durableAttempt.context,
        );
        return finishDirectNotificationProjection(
          presentation: presentation,
          durableAttempt: durableAttempt,
          sqlReadyRevision: terminalEntry.revision,
        );
      }
      final contact = await dependencies.contactRepository.getContact(
        entry.peerId,
      );
      if (contact == null) {
        throw const DirectNotificationDisplayStateUnavailableException();
      }
      if (durableAttempt == null && (contact.isBlocked || contact.isArchived)) {
        return null;
      }
      switch (entry.eventKind) {
        case DirectNotificationDisplayOutboxKind.message:
          final message = await dependencies.messageRepository.getMessage(
            entry.messageId,
          );
          if (message == null) {
            throw const DirectNotificationDisplayStateUnavailableException();
          }
          final ineligible =
              message.contactPeerId != entry.peerId ||
              message.senderPeerId != entry.actorPeerId ||
              message.timestamp != entry.eventTimestamp ||
              !message.isIncoming ||
              message.readAt != null ||
              message.isDeleted ||
              message.hiddenAt != null ||
              message.privateMediaState.isTerminal;
          if (ineligible && durableAttempt == null) return null;
          final presentation = await maybeShowNotification(
            notificationService: dependencies.notificationService,
            appVisibility: dependencies.appVisibility,
            contactPeerId: entry.peerId,
            routePayload: NotificationRouteTarget.conversation(
              entry.peerId,
              messageId: entry.messageId,
            ).toPayload(),
            senderUsername: contact.username,
            messageText: notificationBodyForMessage(
              message.text,
              message.media,
              privateMediaPolicy: message.privateMediaPolicy,
            ),
            messageId: entry.messageId,
            notificationEventIdentity: entry.eventId,
            notificationEventType: 'new_message',
            toneTracker: dependencies.notificationToneTracker,
            durableNotificationCoordinatorResolver:
                dependencies.durableNotificationCoordinatorResolver,
            loadConversationNotificationSnapshot: () =>
                loadDirectConversationNotificationSnapshot(
                  messageRepository: dependencies.messageRepository,
                  contactPeerId: entry.peerId,
                  mediaAttachmentRepository:
                      dependencies.mediaAttachmentRepository,
                  pendingNotificationOverlay:
                      dependencies.pendingNotificationOverlay,
                ),
            consumeRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) =>
                    recentRemoteNotificationGate.consumeIfRecentAnnouncement(
                      payload: payload,
                      messageId: messageId,
                    ),
            markRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) =>
                    recentRemoteNotificationGate.markAnnouncement(
                      payload: payload,
                      messageId: messageId,
                    ),
            durableEffectContext: durableAttempt?.context,
          );
          return finishDirectNotificationProjection(
            presentation: presentation,
            durableAttempt: durableAttempt,
            sqlReadyRevision: terminalEntry.revision,
          );
        case DirectNotificationDisplayOutboxKind.reaction:
          final target = await dependencies.messageRepository.getMessage(
            entry.messageId,
          );
          final reaction = await dependencies.reactionRepository
              .getReactionForSenderIncludingRemoved(
                messageId: entry.messageId,
                senderPeerId: entry.actorPeerId,
              );
          if (target == null || reaction == null) {
            throw const DirectNotificationDisplayStateUnavailableException();
          }
          final ineligible =
              !directReactionTargetAllowsNotificationDisplay(
                target: target,
                expectedContactPeerId: entry.peerId,
              ) ||
              reaction.isRemoved ||
              reaction.id != entry.reactionId ||
              reaction.timestamp != entry.eventTimestamp;
          if (ineligible && durableAttempt == null) return null;
          final presentation = await maybeShowNotification(
            notificationService: dependencies.notificationService,
            appVisibility: dependencies.appVisibility,
            contactPeerId: entry.peerId,
            routePayload: NotificationRouteTarget.conversation(
              entry.peerId,
              messageId: entry.messageId,
            ).toPayload(),
            senderUsername: contact.username,
            messageText: 'Reacted ${reaction.emoji} to your message',
            messageId: entry.reactionId,
            notificationEventIdentity: entry.eventId,
            notificationEventType: 'message_reaction',
            toneTracker: dependencies.notificationToneTracker,
            durableNotificationCoordinatorResolver:
                dependencies.durableNotificationCoordinatorResolver,
            loadConversationNotificationSnapshot: () =>
                loadDirectConversationNotificationSnapshot(
                  messageRepository: dependencies.messageRepository,
                  contactPeerId: entry.peerId,
                  mediaAttachmentRepository:
                      dependencies.mediaAttachmentRepository,
                  pendingNotificationOverlay:
                      dependencies.pendingNotificationOverlay,
                ),
            consumeRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) =>
                    recentRemoteNotificationGate.consumeIfRecentAnnouncement(
                      payload: payload,
                      messageId: messageId,
                    ),
            markRecentRemoteNotificationAnnouncement:
                ({required payload, String? messageId}) =>
                    recentRemoteNotificationGate.markAnnouncement(
                      payload: payload,
                      messageId: messageId,
                    ),
            durableEffectContext: durableAttempt?.context,
          );
          return finishDirectNotificationProjection(
            presentation: presentation,
            durableAttempt: durableAttempt,
            sqlReadyRevision: terminalEntry.revision,
          );
        default:
          return null;
      }
    },
  );
  return ProductionCanonicalDirectProjectionComposition(
    owner: owner,
    readProjector: readProjector,
  );
}
