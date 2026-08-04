import 'dart:async';

import 'package:flutter_app/core/notifications/direct_notification_canonical_reconciler.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
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
    Future<NotificationPresentationResult?> Function(
      DirectNotificationDisplayOutboxEntry entry,
    );
typedef EnqueueDirectNotificationReconciliation =
    Future<void> Function(String peerId);

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
    DateTime Function()? nowUtc,
    this.retryDelay = const Duration(seconds: 65),
  }) : _displayOutbox = displayOutbox,
       _reconciliationOutbox = reconciliationOutbox,
       _reactionTerminal = reactionTerminal,
       _coordinator = coordinator,
       _projectDisplay = projectDisplay,
       _canonicalReconciler = canonicalReconciler,
       _enqueueReconciliation = enqueueReconciliation,
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
          complete: (entry) async {
            if (!await _displayOutbox.completeIfExact(entry)) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          retire: (entry) async {
            if (!await _displayOutbox.retireIfExact(entry)) {
              throw const DirectNotificationDisplayRetryableException();
            }
          },
          recordFailure: _recordDisplayFailure,
          scheduleRetry: _scheduleRetry,
          nowUtc: _nowUtc,
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
            await _canonicalReconciler.reconcile(entry.peerId);
            return DirectNotificationDisplayRetryDisposition.completed;
          },
          complete: (entry) async {
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
  final DateTime Function() _nowUtc;
  final Duration retryDelay;
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
        targetMessage.isIncoming ||
        targetMessage.contactPeerId != payload.senderPeerId) {
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

  Future<DirectNotificationDisplayRetryDisposition> _projectInsidePeerLane(
    DirectNotificationDisplayOutboxEntry entry,
  ) => _coordinator.runForPeer(entry.peerId, () async {
    final result = await _projectDisplay(entry);
    return switch (result) {
      null => DirectNotificationDisplayRetryDisposition.retired,
      NotificationPresentationResult.contendedRetryable =>
        DirectNotificationDisplayRetryDisposition.retryLater,
      NotificationPresentationResult.shown ||
      NotificationPresentationResult.terminalSuppressed =>
        DirectNotificationDisplayRetryDisposition.completed,
    };
  });

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
