import 'dart:async';

import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/direct_notification_display_retry_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_reconciliation_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_display_outbox_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reaction_terminal_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/direct_notification_reconciliation_outbox_repository.dart';

typedef ProjectDirectNotificationDisplayEntry =
    Future<DirectNotificationDisplayProjection?> Function(
      DirectNotificationDisplayOutboxEntry entry,
    );
typedef EnqueueDirectNotificationReconciliation =
    Future<void> Function(String peerId);
typedef RecoverCommittedDirectNotificationDurableEffects =
    Future<void> Function(String peerId);

/// Whether an outgoing message may still anchor an incoming reaction card.
///
/// This predicate is shared by initial custody and live retry projection so a
/// hide/private-media terminalization race cannot leave a reaction eligible
/// for native presentation or a durable completed outcome.
bool directReactionTargetAllowsNotificationDisplay({
  required ConversationMessage target,
  required String expectedContactPeerId,
}) =>
    target.contactPeerId == expectedContactPeerId &&
    !target.isIncoming &&
    !target.isDeleted &&
    !target.isHidden &&
    !target.privateMediaState.isTerminal;

/// Mutable only for the one synchronous projection attempt. The receipt is
/// captured by [DurableLocalNotificationEffectContext.onEffectTerminal] after
/// the registry lock is released, then frozen into the projection result.
final class DirectNotificationDurableEffectAttempt {
  DirectNotificationDurableEffectAttempt._({
    required this.context,
    required String currentOpaqueBinding,
    required String physicalPeerId,
    required NotificationCompletedOutcomeProducerKind outcomeProducerKind,
    required String eventKey,
    required String eventCorrelation,
    required _DirectNotificationEffectReceiptCapture capture,
  }) : _currentOpaqueBinding = currentOpaqueBinding,
       _physicalPeerId = physicalPeerId,
       _outcomeProducerKind = outcomeProducerKind,
       _eventKey = eventKey,
       _eventCorrelation = eventCorrelation,
       _capture = capture;

  static DirectNotificationDurableEffectAttempt? tryCreate({
    required DirectNotificationDisplayOutboxEntry entry,
    required String? currentOpaqueBinding,
    required String? physicalPeerId,
    required LocalNotificationPresentationOwner presentationOwner,
    required ReadDurableLocalNotificationCanonicalDisposition
    readFinalCanonicalDisposition,
  }) {
    // These are authority bytes, not display strings. Never normalize a
    // secure binding or physical recipient into a value it did not attest.
    final binding = currentOpaqueBinding;
    final physicalPeer = physicalPeerId;
    if (binding == null ||
        physicalPeer == null ||
        binding.isEmpty ||
        physicalPeer.isEmpty) {
      return null;
    }
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.direct,
      value: entry.peerId,
    );
    final outcomeProducerKind = switch (entry.eventKind) {
      DirectNotificationDisplayOutboxKind.message =>
        NotificationCompletedOutcomeProducerKind.directMessage,
      DirectNotificationDisplayOutboxKind.reaction =>
        NotificationCompletedOutcomeProducerKind.directReaction,
      _ => null,
    };
    if (identity == null || outcomeProducerKind == null) return null;
    final eventKey = trySelectNotificationCompletedOutcomeEventKey(
      producerKind: outcomeProducerKind,
      authenticatedEnvelope: <String, Object?>{
        if (outcomeProducerKind ==
            NotificationCompletedOutcomeProducerKind.directMessage)
          'messageId': entry.messageId,
        if (outcomeProducerKind ==
            NotificationCompletedOutcomeProducerKind.directReaction)
          // Never use entry.eventId here: reaction display custody deliberately
          // stores a bounded alias, not the authenticated raw reaction key.
          'reactionId': entry.reactionId,
      },
    );
    if (eventKey == null) return null;
    final eventCorrelation = tryComputeNotificationCompletedOutcomeCorrelation(
      physicalPeerId: physicalPeer,
      producerKind: outcomeProducerKind,
      eventKey: eventKey,
    );
    if (eventCorrelation == null) return null;
    final ledgerProducerKind = switch (outcomeProducerKind) {
      NotificationCompletedOutcomeProducerKind.directMessage =>
        LocalNotificationProducerKind.directMessage,
      NotificationCompletedOutcomeProducerKind.directReaction =>
        LocalNotificationProducerKind.directReaction,
      NotificationCompletedOutcomeProducerKind.groupMessage ||
      NotificationCompletedOutcomeProducerKind.groupReaction => null,
    };
    if (ledgerProducerKind == null) return null;

    final capture = _DirectNotificationEffectReceiptCapture(
      eventCorrelation: eventCorrelation,
    );
    final context = DurableLocalNotificationEffectContext(
      currentOpaqueBinding: binding,
      eventCorrelation: eventCorrelation,
      conversationDigest: identity.digest,
      producerKind: ledgerProducerKind,
      sourceCustody: LocalNotificationSourceCustody.sqlReady,
      presentationOwner: presentationOwner,
      readFinalCanonicalDisposition: readFinalCanonicalDisposition,
      onEffectTerminal: capture.call,
      terminalObserverCompletesSqlHandoff: false,
    );
    if (!context.isValid) return null;
    return DirectNotificationDurableEffectAttempt._(
      context: context,
      currentOpaqueBinding: binding,
      physicalPeerId: physicalPeer,
      outcomeProducerKind: outcomeProducerKind,
      eventKey: eventKey,
      eventCorrelation: eventCorrelation,
      capture: capture,
    );
  }

  final DurableLocalNotificationEffectContext context;
  final String _currentOpaqueBinding;
  final String _physicalPeerId;
  final NotificationCompletedOutcomeProducerKind _outcomeProducerKind;
  final String _eventKey;
  final String _eventCorrelation;
  final _DirectNotificationEffectReceiptCapture _capture;

  DirectNotificationDurableEffectAuthority? get completedAuthority {
    final receipt = _capture.receipt;
    if (receipt == null || receipt.eventCorrelation != _eventCorrelation) {
      return null;
    }
    return DirectNotificationDurableEffectAuthority(
      currentOpaqueBinding: _currentOpaqueBinding,
      physicalPeerId: _physicalPeerId,
      outcomeProducerKind: _outcomeProducerKind,
      eventKey: _eventKey,
      receipt: receipt,
    );
  }
}

final class _DirectNotificationEffectReceiptCapture {
  _DirectNotificationEffectReceiptCapture({required this.eventCorrelation});

  final String eventCorrelation;
  DurableLocalNotificationEffectReceipt? receipt;

  Future<void> call(DurableLocalNotificationEffectReceipt value) async {
    if (value.eventCorrelation != eventCorrelation) {
      throw StateError('direct durable effect correlation mismatch');
    }
    final existing = receipt;
    if (existing != null &&
        (existing.recordRevision != value.recordRevision ||
            existing.presentationState != value.presentationState)) {
      throw StateError('direct durable effect receipt changed in one attempt');
    }
    receipt = value;
  }
}

/// One direct projection result, including the exact durable effect terminal
/// that must be settled only after SQL custody completion succeeds.
final class DirectNotificationDisplayProjection {
  const DirectNotificationDisplayProjection({
    required this.presentation,
    this.durableEffectAuthority,
  });

  final NotificationPresentationResult presentation;
  final DirectNotificationDurableEffectAuthority? durableEffectAuthority;
}

/// Shared production owner for every direct show/read/reconciliation mutation.
///
/// A null display projection means canonical state proved the staged event is
/// stale or ineligible. It is retired without writing terminal authority.
final class DirectNotificationProjectionOwner {
  DirectNotificationProjectionOwner({
    required DirectNotificationDisplayOutboxRepository displayOutbox,
    required DirectNotificationReconciliationOutboxRepository
    reconciliationOutbox,
    required DirectNotificationReactionTerminalRepository reactionTerminal,
    required DirectNotificationPresentationCoordinator coordinator,
    required ProjectDirectNotificationDisplayEntry projectDisplay,
    required DirectNotificationCanonicalReconciler canonicalReconciler,
    required EnqueueDirectNotificationReconciliation enqueueReconciliation,
    RecoverCommittedDirectNotificationDurableEffects?
    recoverCommittedDurableEffects,
    DurableLocalNotificationEffectRegistry?
    durableLocalNotificationEffectRegistry,
    CompleteDirectNotificationDurableSqlHandoff<
      DirectNotificationDisplayOutboxEntry
    >?
    completeDurableSqlHandoff,
    NotifyDirectNotificationDurablePostSettlement<
      DirectNotificationDisplayOutboxEntry
    >?
    afterDurableSettlement,
    Future<String?> Function()? resolveCompletedOutcomePhysicalPeerId,
    this.completedOutcomeProducerEnabled = false,
    DateTime Function()? nowUtc,
    this.retryDelay = const Duration(seconds: 65),
  }) : _displayOutbox = displayOutbox,
       _reconciliationOutbox = reconciliationOutbox,
       _reactionTerminal = reactionTerminal,
       _coordinator = coordinator,
       _projectDisplay = projectDisplay,
       _canonicalReconciler = canonicalReconciler,
       _enqueueReconciliation = enqueueReconciliation,
       _recoverCommittedDurableEffects = recoverCommittedDurableEffects,
       _durableLocalNotificationEffectRegistry =
           durableLocalNotificationEffectRegistry,
       _completeDurableSqlHandoff = completeDurableSqlHandoff,
       _afterDurableSettlement = afterDurableSettlement,
       _resolveCompletedOutcomePhysicalPeerId =
           resolveCompletedOutcomePhysicalPeerId,
       _nowUtc = nowUtc ?? DateTime.now {
    _displayRetry =
        DirectNotificationDisplayRetryCoordinator<
          DirectNotificationDisplayOutboxEntry
        >(
          loadReady: ({required limit}) =>
              _displayOutbox.loadReady(limit: limit),
          entryIdentity: (entry) =>
              (entry.peerId, entry.eventKind, entry.eventId),
          loadEarliestNextAttemptAt: _displayOutbox.loadEarliestNextAttemptAt,
          project: _projectInsidePeerLane,
          completeWithOutcome: (entry, outcome) async {
            if (!await _displayOutbox.completeIfExact(
              entry,
              outcome: outcome,
            )) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          completeDurableSqlHandoff: _completeDurableSqlHandoff == null
              ? null
              : _completeDurableSqlHandoffAtFinalRevision,
          settleDurableEffect: _settleDurableEffect,
          afterDurableSettlement: _retireDurableSqlCustodyAfterSettlement,
          retire: (entry) async {
            if (!await _displayOutbox.retireIfExact(entry)) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          recordFailure: _recordDisplayFailure,
          scheduleRetry: _scheduleRetry,
          nowUtc: _nowUtc,
          durableSettlementRetryDelay: retryDelay,
        );
    _reconciliationRetry =
        DirectNotificationDisplayRetryCoordinator<
          DirectNotificationReconciliationOutboxEntry
        >(
          loadReady: ({required limit}) =>
              _reconciliationOutbox.loadEligible(limit: limit),
          entryIdentity: (entry) => entry.peerId,
          loadEarliestNextAttemptAt:
              _reconciliationOutbox.loadEarliestNextAttemptAt,
          project: (entry) async {
            await _recoverCommittedDurableEffects?.call(entry.peerId);
            await _canonicalReconciler.reconcile(entry.peerId);
            return const DirectNotificationDisplayProjectionResult.completed(
              outcomeCandidate: null,
            );
          },
          completeWithOutcome: (entry, outcome) async {
            if (outcome != null) {
              throw StateError(
                'direct reconciliation cannot emit a completed outcome',
              );
            }
            if (!await _reconciliationOutbox.completeIfExact(entry)) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          retire: (entry) async {
            if (!await _reconciliationOutbox.completeIfExact(entry)) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          recordFailure: (entry, _) async {
            await _reconciliationOutbox.recordFailureIfExact(
              expected: entry,
              nextAttemptAt: _nowUtc().toUtc().add(retryDelay),
            );
          },
          scheduleRetry: _scheduleRetry,
          nowUtc: _nowUtc,
        );
  }

  final DirectNotificationDisplayOutboxRepository _displayOutbox;
  final DirectNotificationReconciliationOutboxRepository _reconciliationOutbox;
  final DirectNotificationReactionTerminalRepository _reactionTerminal;
  final DirectNotificationPresentationCoordinator _coordinator;
  final ProjectDirectNotificationDisplayEntry _projectDisplay;
  final DirectNotificationCanonicalReconciler _canonicalReconciler;
  final EnqueueDirectNotificationReconciliation _enqueueReconciliation;
  final RecoverCommittedDirectNotificationDurableEffects?
  _recoverCommittedDurableEffects;
  final DurableLocalNotificationEffectRegistry?
  _durableLocalNotificationEffectRegistry;
  final CompleteDirectNotificationDurableSqlHandoff<
    DirectNotificationDisplayOutboxEntry
  >?
  _completeDurableSqlHandoff;
  final NotifyDirectNotificationDurablePostSettlement<
    DirectNotificationDisplayOutboxEntry
  >?
  _afterDurableSettlement;
  final Future<String?> Function()? _resolveCompletedOutcomePhysicalPeerId;
  final DateTime Function() _nowUtc;
  final Duration retryDelay;
  final bool completedOutcomeProducerEnabled;
  late final DirectNotificationDisplayRetryCoordinator<
    DirectNotificationDisplayOutboxEntry
  >
  _displayRetry;
  late final DirectNotificationDisplayRetryCoordinator<
    DirectNotificationReconciliationOutboxEntry
  >
  _reconciliationRetry;
  Timer? _retryTimer;
  DateTime? _retryDueAt;
  bool _disposed = false;

  Future<void> stageMessage(ConversationMessage message) async {
    if (_disposed || !message.isIncoming) return;
    final now = _nowUtc().toUtc().toIso8601String();
    await _displayOutbox.stage(
      DirectNotificationDisplayOutboxEntry.message(
        eventId: message.id,
        peerId: message.contactPeerId,
        messageId: message.id,
        actorPeerId: message.senderPeerId,
        eventTimestamp: message.timestamp,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> stageReaction({
    required ReactionPayload payload,
    required ConversationMessage targetMessage,
  }) async {
    if (_disposed ||
        payload.action != ReactionPayload.addAction ||
        !directReactionTargetAllowsNotificationDisplay(
          target: targetMessage,
          expectedContactPeerId: payload.senderPeerId,
        )) {
      return;
    }
    final now = _nowUtc().toUtc().toIso8601String();
    await _displayOutbox.stage(
      DirectNotificationDisplayOutboxEntry.reaction(
        eventId: boundedReactionEventIdentity(payload.id),
        peerId: payload.senderPeerId,
        messageId: payload.messageId,
        actorPeerId: payload.senderPeerId,
        eventTimestamp: payload.timestamp,
        reactionId: payload.id,
        reactionAction: payload.action,
        reactionTombstone: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _promoteReady({
    required String peerId,
    required String eventKind,
    required String eventId,
  }) async {
    if (_disposed) return;
    var entry = await _displayOutbox.loadExact(
      peerId: peerId,
      eventKind: eventKind,
      eventId: eventId,
    );
    if (entry == null || entry.isReady) return;
    if (await _displayOutbox.promoteReadyIfExact(
      peerId: peerId,
      eventKind: eventKind,
      eventId: eventId,
      expectedRevision: entry.revision,
    )) {
      return;
    }
    entry = await _displayOutbox.loadExact(
      peerId: peerId,
      eventKind: eventKind,
      eventId: eventId,
    );
    if (entry?.isReady == true) return;
    throw StateError('direct notification display custody ready CAS failed');
  }

  Future<void> promoteMessageReadyIfExact(ConversationMessage message) async {
    if (_disposed) return;
    final entry = await _displayOutbox.loadExact(
      peerId: message.contactPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.message,
      eventId: message.id,
    );
    if (entry == null) return;
    if (entry.eventKind != DirectNotificationDisplayOutboxKind.message ||
        entry.peerId != message.contactPeerId ||
        entry.messageId != message.id ||
        entry.actorPeerId != message.senderPeerId ||
        entry.eventTimestamp != message.timestamp ||
        !message.isIncoming) {
      throw StateError('direct message display custody authority mismatch');
    }
    await _promoteReady(
      peerId: message.contactPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.message,
      eventId: message.id,
    );
  }

  Future<void> promoteReactionReadyIfExact({
    required ReactionPayload payload,
    required ConversationMessage targetMessage,
  }) async {
    if (_disposed) return;
    final eventId = boundedReactionEventIdentity(payload.id);
    final entry = await _displayOutbox.loadExact(
      peerId: payload.senderPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.reaction,
      eventId: eventId,
    );
    if (entry == null) return;
    if (entry.eventKind != DirectNotificationDisplayOutboxKind.reaction ||
        entry.peerId != payload.senderPeerId ||
        entry.messageId != payload.messageId ||
        entry.messageId != targetMessage.id ||
        entry.actorPeerId != payload.senderPeerId ||
        entry.eventTimestamp != payload.timestamp ||
        entry.reactionId != payload.id ||
        entry.reactionAction != payload.action ||
        entry.reactionTombstone != false ||
        targetMessage.contactPeerId != payload.senderPeerId ||
        targetMessage.isIncoming) {
      throw StateError('direct reaction display custody authority mismatch');
    }
    await _promoteReady(
      peerId: payload.senderPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.reaction,
      eventId: eventId,
    );
  }

  Future<void> onReactionRemoveCommitted({
    required String peerId,
    required String messageId,
    required String actorPeerId,
  }) async {
    if (_disposed) return;
    await _reactionTerminal.deleteForActor(
      peerId: peerId,
      messageId: messageId,
      actorPeerId: actorPeerId,
    );
    await _enqueueReconciliation(peerId);
    await retryNow();
  }

  /// Startup, resumed lifecycle, and post-canonical-commit signal.
  Future<void> retryNow() async {
    if (_disposed) return;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _displayRetry.retryNow();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await _reconciliationRetry.retryNow();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<DirectNotificationDisplayProjectionResult> _projectInsidePeerLane(
    DirectNotificationDisplayOutboxEntry entry,
  ) => _coordinator.runForPeer(entry.peerId, () async {
    final projection = await _projectDisplay(entry);
    if (projection == null) {
      return const DirectNotificationDisplayProjectionResult.retired();
    }
    if (projection.presentation ==
        NotificationPresentationResult.contendedRetryable) {
      return const DirectNotificationDisplayProjectionResult.retryLater();
    }
    final outcome = await _buildCompletedOutcomeCandidate(
      entry,
      presentation: projection.presentation,
      durableAuthority: projection.durableEffectAuthority,
    );
    return DirectNotificationDisplayProjectionResult.completed(
      outcomeCandidate: outcome,
      durableEffectAuthority: projection.durableEffectAuthority,
    );
  });

  Future<NotificationCompletedOutcomeCandidate?>
  _buildCompletedOutcomeCandidate(
    DirectNotificationDisplayOutboxEntry entry, {
    required NotificationPresentationResult presentation,
    required DirectNotificationDurableEffectAuthority? durableAuthority,
  }) async {
    final expectedReceiptPresentation = switch (presentation) {
      NotificationPresentationResult.osPosted =>
        LocalNotificationPresentationState.osPosted,
      NotificationPresentationResult.inChat =>
        LocalNotificationPresentationState.inChat,
      NotificationPresentationResult.suppressedPolicy =>
        LocalNotificationPresentationState.suppressedPolicy,
      NotificationPresentationResult.terminalWithoutOutcome =>
        LocalNotificationPresentationState.cancelled,
      NotificationPresentationResult.contendedRetryable => null,
    };
    final receiptPresentation = durableAuthority?.receipt.presentationState;
    if (receiptPresentation != null &&
        receiptPresentation != expectedReceiptPresentation) {
      throw const DirectNotificationDisplayRetryableException();
    }
    if (!completedOutcomeProducerEnabled) return null;
    final outcome = switch (presentation) {
      NotificationPresentationResult.osPosted =>
        NotificationCompletedOutcomeCategory.osPosted,
      NotificationPresentationResult.inChat =>
        NotificationCompletedOutcomeCategory.inChat,
      // The policy outcome remains reserved until the downstream policy
      // admission plan; cancelled/legacy terminal paths never mint v116.
      NotificationPresentationResult.suppressedPolicy ||
      NotificationPresentationResult.terminalWithoutOutcome ||
      NotificationPresentationResult.contendedRetryable => null,
    };
    if (outcome == null) return null;
    final physicalPeerId =
        durableAuthority?.physicalPeerId ??
        await _resolveCompletedOutcomePhysicalPeerId?.call();
    if (physicalPeerId == null || physicalPeerId.isEmpty) return null;
    final producerKind =
        durableAuthority?.outcomeProducerKind ??
        switch (entry.eventKind) {
          DirectNotificationDisplayOutboxKind.message =>
            NotificationCompletedOutcomeProducerKind.directMessage,
          DirectNotificationDisplayOutboxKind.reaction =>
            NotificationCompletedOutcomeProducerKind.directReaction,
          _ => null,
        };
    if (producerKind == null) {
      return null;
    }
    final eventKey =
        durableAuthority?.eventKey ??
        trySelectNotificationCompletedOutcomeEventKey(
          producerKind: producerKind,
          authenticatedEnvelope: <String, Object?>{
            if (entry.eventKind == DirectNotificationDisplayOutboxKind.message)
              'messageId': entry.messageId,
            if (entry.eventKind == DirectNotificationDisplayOutboxKind.reaction)
              'reactionId': entry.reactionId,
          },
        );
    if (eventKey == null) return null;
    return NotificationCompletedOutcomeCandidate(
      physicalPeerId: physicalPeerId,
      producerKind: producerKind,
      eventKey: eventKey,
      outcome: outcome,
      completedAt: _nowUtc().toUtc(),
    );
  }

  Future<void> _settleDurableEffect(
    DirectNotificationDisplayOutboxEntry _,
    DirectNotificationDurableEffectAuthority authority,
  ) async {
    final registry = _durableLocalNotificationEffectRegistry;
    if (registry == null) {
      throw const DirectNotificationDisplayRetryableException();
    }
    final settled = await registry.settleSqlReadyEffect(
      currentOpaqueBinding: authority.currentOpaqueBinding,
      eventCorrelation: authority.receipt.eventCorrelation,
      expectedRevision: authority.receipt.recordRevision,
    );
    if (settled == null) {
      throw const DirectNotificationDisplayRetryableException();
    }
  }

  DirectNotificationDisplayOutboxEntry _entryAtFinalSqlReadyRevision(
    DirectNotificationDisplayOutboxEntry entry,
    DirectNotificationDurableEffectAuthority authority,
  ) {
    final revision = authority.sqlReadyRevision;
    if (revision == null || revision <= 0) {
      throw const DirectNotificationDisplayRetryableException();
    }
    return revision == entry.revision
        ? entry
        : entry.copyWith(revision: revision);
  }

  Future<DurableLocalNotificationSqlHandoffResult>
  _completeDurableSqlHandoffAtFinalRevision(
    DirectNotificationDisplayOutboxEntry entry,
    NotificationCompletedOutcomeCandidate? outcome,
    DirectNotificationDurableEffectAuthority authority,
  ) => _completeDurableSqlHandoff!(
    _entryAtFinalSqlReadyRevision(entry, authority),
    outcome,
    authority,
  );

  Future<void> _retireDurableSqlCustodyAfterSettlement(
    DirectNotificationDisplayOutboxEntry entry,
    DirectNotificationDurableEffectAuthority authority,
  ) async {
    final terminalEntry = _entryAtFinalSqlReadyRevision(entry, authority);
    if (!await _displayOutbox.retireAfterDurableSettlementIfExact(
      terminalEntry,
    )) {
      throw const DirectNotificationDisplayRetryableException();
    }
    await _afterDurableSettlement?.call(terminalEntry, authority);
  }

  Future<void> _recordDisplayFailure(
    DirectNotificationDisplayOutboxEntry entry,
    Object error,
  ) async {
    await _displayOutbox.recordRetryIfExact(
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
      expectedRevision: entry.revision,
      lastErrorCode: error is DirectNotificationDisplayStateUnavailableException
          ? DirectNotificationDisplayOutboxErrorCode.stateUnavailable
          : error is DirectNotificationDisplayRetryableException
          ? DirectNotificationDisplayOutboxErrorCode.claimPending
          : DirectNotificationDisplayOutboxErrorCode.displayFailed,
      nextAttemptAt: _nowUtc().toUtc().add(retryDelay),
    );
  }

  void _scheduleRetry(Duration requestedDelay) {
    if (_disposed) return;
    final delay = requestedDelay.isNegative ? Duration.zero : requestedDelay;
    final dueAt = _nowUtc().toUtc().add(delay);
    if (_retryTimer?.isActive == true &&
        _retryDueAt != null &&
        !dueAt.isBefore(_retryDueAt!)) {
      return;
    }
    _retryTimer?.cancel();
    _retryDueAt = dueAt;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _retryDueAt = null;
      unawaited(
        retryNow().catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'DIRECT_NOTIFICATION_BACKGROUND_RETRY_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
        }),
      );
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _displayRetry.dispose();
    _reconciliationRetry.dispose();
  }
}
