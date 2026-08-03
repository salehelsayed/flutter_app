import 'dart:async';

import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef GroupUnreadCountResolver = Future<int> Function(String groupId);
typedef GroupMessageEventReadResolver =
    Future<bool> Function(String groupId, String eventIdentity);
typedef GroupNotificationContentEventAcknowledgedResolver =
    Future<bool> Function(
      String groupId,
      ConversationNotificationContentMetadata metadata,
    );
typedef ExistingGroupIdsResolver = Future<Iterable<String>> Function();

/// Projects canonical group read commits onto the exact delivered OS card.
///
/// [cancellation] is optional because not every [NotificationService] owns an
/// OS surface. No event allocates a notification id and no blanket cancel is
/// available at this boundary.
final class GroupNotificationReadProjector {
  GroupNotificationReadProjector({
    required GroupNotificationPresentationCoordinator coordinator,
    required Stream<String> readEvents,
    required GroupUnreadCountResolver unreadCountForGroup,
    GroupMessageEventReadResolver? messageEventIsRead,
    GroupNotificationContentEventAcknowledgedResolver?
    contentEventIsAcknowledged,
    required ConversationNotificationCancellation? cancellation,
    ExistingGroupIdsResolver? existingGroupIds,
    Duration retryDelay = const Duration(seconds: 5),
  }) : _coordinator = coordinator,
       _readEvents = readEvents,
       _unreadCountForGroup = unreadCountForGroup,
       _messageEventIsRead = messageEventIsRead,
       _contentEventIsAcknowledged = contentEventIsAcknowledged,
       _cancellation = cancellation,
       _generationCancellation =
           cancellation is ConversationNotificationGenerationCancellation
           ? cancellation as ConversationNotificationGenerationCancellation
           : null,
       _existingGroupIds = existingGroupIds,
       _retryDelay = retryDelay {
    if (retryDelay.inMicroseconds <= 0) {
      throw ArgumentError.value(
        retryDelay,
        'retryDelay',
        'must be greater than zero to prevent a retry busy-loop',
      );
    }
  }

  final GroupNotificationPresentationCoordinator _coordinator;
  final Stream<String> _readEvents;
  final GroupUnreadCountResolver _unreadCountForGroup;
  final GroupMessageEventReadResolver? _messageEventIsRead;
  final GroupNotificationContentEventAcknowledgedResolver?
  _contentEventIsAcknowledged;
  final ConversationNotificationCancellation? _cancellation;
  final ConversationNotificationGenerationCancellation? _generationCancellation;
  final ExistingGroupIdsResolver? _existingGroupIds;
  final Duration _retryDelay;
  final Set<Future<void>> _pending = <Future<void>>{};
  final Map<String, Timer> _retryTimers = <String, Timer>{};
  final Map<String, bool> _retryAcknowledgesConversations = <String, bool>{};
  final Map<String, _ConversationAcknowledgementSnapshot>
  _retryAcknowledgementSnapshots =
      <String, _ConversationAcknowledgementSnapshot>{};

  StreamSubscription<String>? _subscription;
  Timer? _reconciliationRetryTimer;
  bool _reconciliationInFlight = false;
  bool _reconciliationComplete = false;
  bool _startupReconciliationDeferred = false;
  bool _disposed = false;

  void start({bool deferStartupReconciliation = false}) {
    if (_disposed) {
      throw StateError('GroupNotificationReadProjector is disposed');
    }
    if (_subscription != null) return;
    _subscription = _readEvents.listen(_onReadCommit);
    _startupReconciliationDeferred = deferStartupReconciliation;
    if (!_startupReconciliationDeferred) {
      _startReconciliation();
    }
  }

  /// Releases the one-shot startup scan only after canonical group recovery
  /// has exhausted its inbox. Live read commits remain subscribed while this
  /// scan is deferred.
  void completeStartupCanonicalRecovery({
    required bool canonicalStateComplete,
  }) {
    if (_disposed || !_startupReconciliationDeferred) return;
    if (!canonicalStateComplete) return;
    _startupReconciliationDeferred = false;
    _startReconciliation();
  }

  void _onReadCommit(String rawGroupId) {
    final groupId = rawGroupId.trim();
    final generationCancellation = _generationCancellation;
    _queueProjection(
      groupId,
      cancelScheduledRetry: true,
      acknowledgeConversation: true,
      acknowledgementSnapshot: groupId.isEmpty || generationCancellation == null
          ? null
          : _ConversationAcknowledgementSnapshot(
              cancellation: generationCancellation,
              conversationKey: 'group:$groupId',
            ),
    );
  }

  void _startReconciliation() {
    final existingGroupIds = _existingGroupIds;
    if (_disposed ||
        existingGroupIds == null ||
        _cancellation == null ||
        _startupReconciliationDeferred ||
        _reconciliationComplete ||
        _reconciliationInFlight ||
        _reconciliationRetryTimer?.isActive == true) {
      return;
    }

    _reconciliationInFlight = true;
    late final Future<void> work;
    work = _reconcileExistingGroups(existingGroupIds)
        .then((_) {
          if (_disposed) return;
          _reconciliationComplete = true;
          _reconciliationRetryTimer?.cancel();
          _reconciliationRetryTimer = null;
        })
        .catchError((Object error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_NOTIFICATION_READ_RECONCILIATION_ERROR',
            details: {'errorType': error.runtimeType.toString()},
          );
          _scheduleReconciliationRetry();
        })
        .whenComplete(() {
          _reconciliationInFlight = false;
          _pending.remove(work);
        });
    _pending.add(work);
  }

  void _scheduleReconciliationRetry() {
    if (_disposed ||
        _reconciliationComplete ||
        _reconciliationRetryTimer?.isActive == true) {
      return;
    }
    _reconciliationRetryTimer = Timer(_retryDelay, () {
      _reconciliationRetryTimer = null;
      _startReconciliation();
    });
  }

  Future<void> _reconcileExistingGroups(
    ExistingGroupIdsResolver existingGroupIds,
  ) async {
    final rawGroupIds = await existingGroupIds();
    if (_disposed) return;
    final groupIds = rawGroupIds
        .map((groupId) => groupId.trim())
        .where((groupId) => groupId.isNotEmpty)
        .toSet();
    for (final groupId in groupIds) {
      _queueProjection(
        groupId,
        cancelScheduledRetry: true,
        acknowledgeConversation: false,
        acknowledgementSnapshot: null,
      );
    }
  }

  void _queueProjection(
    String rawGroupId, {
    required bool cancelScheduledRetry,
    required bool acknowledgeConversation,
    required _ConversationAcknowledgementSnapshot? acknowledgementSnapshot,
  }) {
    if (_disposed || _cancellation == null) return;
    final groupId = rawGroupId.trim();
    if (groupId.isEmpty) return;
    if (cancelScheduledRetry) {
      _retryTimers.remove(groupId)?.cancel();
      _retryAcknowledgesConversations.remove(groupId);
      _retryAcknowledgementSnapshots.remove(groupId);
    }
    late final Future<void> work;
    work =
        _project(
              groupId,
              acknowledgeConversation: acknowledgeConversation,
              acknowledgementSnapshot: acknowledgementSnapshot,
            )
            .then((_) {
              _retryTimers.remove(groupId)?.cancel();
              _retryAcknowledgesConversations.remove(groupId);
              _retryAcknowledgementSnapshots.remove(groupId);
            })
            .catchError((Object error) {
              emitFlowEvent(
                layer: 'FL',
                event: 'GROUP_NOTIFICATION_READ_PROJECTION_ERROR',
                details: {'errorType': error.runtimeType.toString()},
              );
              _scheduleRetry(
                groupId,
                acknowledgeConversation: acknowledgeConversation,
                acknowledgementSnapshot: acknowledgementSnapshot,
              );
            })
            .whenComplete(() => _pending.remove(work));
    _pending.add(work);
  }

  void _scheduleRetry(
    String groupId, {
    required bool acknowledgeConversation,
    required _ConversationAcknowledgementSnapshot? acknowledgementSnapshot,
  }) {
    if (_disposed) return;
    if (_retryTimers.containsKey(groupId)) {
      if (acknowledgeConversation) {
        _retryAcknowledgesConversations[groupId] = true;
      }
      if (acknowledgementSnapshot != null) {
        _retryAcknowledgementSnapshots[groupId] = acknowledgementSnapshot;
      }
      return;
    }
    _retryAcknowledgesConversations[groupId] = acknowledgeConversation;
    if (acknowledgementSnapshot != null) {
      _retryAcknowledgementSnapshots[groupId] = acknowledgementSnapshot;
    }
    _retryTimers[groupId] = Timer(_retryDelay, () {
      _retryTimers.remove(groupId);
      final retryAcknowledgesConversation =
          _retryAcknowledgesConversations.remove(groupId) ?? false;
      final retryAcknowledgementSnapshot = _retryAcknowledgementSnapshots
          .remove(groupId);
      _queueProjection(
        groupId,
        cancelScheduledRetry: false,
        acknowledgeConversation: retryAcknowledgesConversation,
        acknowledgementSnapshot: retryAcknowledgementSnapshot,
      );
    });
  }

  Future<void> _project(
    String groupId, {
    required bool acknowledgeConversation,
    required _ConversationAcknowledgementSnapshot? acknowledgementSnapshot,
  }) async {
    final cancellation = _cancellation;
    if (cancellation == null) return;
    await _coordinator.runForGroup(groupId, () async {
      // Capture before querying SQL. A cross-isolate replacement during the
      // query is then protected by the registry's generation compare-and-cancel.
      final acknowledgedMetadata = acknowledgeConversation
          ? await acknowledgementSnapshot?.capture()
          : null;
      // Recheck inside the same key that owns final show calls. A count observed
      // before entering this operation would reintroduce query/show/cancel.
      final unreadCount = await _unreadCountForGroup(groupId);
      if (unreadCount != 0) return;
      final acknowledgedGeneration = acknowledgedMetadata?.generation?.trim();
      final contentEventIsAcknowledged = _contentEventIsAcknowledged;
      if (acknowledgeConversation && contentEventIsAcknowledged != null) {
        if (acknowledgedMetadata != null &&
            acknowledgedGeneration != null &&
            acknowledgedGeneration.isNotEmpty &&
            await contentEventIsAcknowledged(groupId, acknowledgedMetadata)) {
          await acknowledgementSnapshot?.cancel(acknowledgedGeneration);
        }
        // With a durable resolver, absence or mismatch means this card was not
        // the exact event covered by the read commit. Never fall through to a
        // kind-wide cancellation that could erase a later replacement.
        return;
      }
      if (acknowledgeConversation &&
          acknowledgementSnapshot != null &&
          acknowledgedGeneration != null &&
          acknowledgedGeneration.isNotEmpty) {
        await acknowledgementSnapshot.cancel(acknowledgedGeneration);
        return;
      }
      final messageEventIsRead = _messageEventIsRead;
      await cancellation.cancelConversationNotification(
        'group:$groupId',
        onlyIfContentKind: ConversationNotificationContentKind.message,
        shouldCancelContent:
            acknowledgeConversation || messageEventIsRead == null
            ? null
            : (metadata) async {
                final eventIdentity = metadata.eventIdentity?.trim();
                if (eventIdentity == null || eventIdentity.isEmpty) {
                  return false;
                }
                return messageEventIsRead(groupId, eventIdentity);
              },
      );
      if (acknowledgeConversation) {
        // Startup unread reconciliation cannot prove that the user has seen a
        // reaction. A live repository acknowledgement can: it is emitted by a
        // successful conversation-level mark-as-read call even when there were
        // no unread message rows. The message branch above also deliberately
        // skips canonical-identity proof for this live acknowledgement, which
        // retires an unanchored foreground fallback. Durable generation CAS in
        // both branches preserves a later replacement.
        await cancellation.cancelConversationNotification(
          'group:$groupId',
          onlyIfContentKind: ConversationNotificationContentKind.reaction,
        );
      }
    });
  }

  Future<void> waitForIdle() async {
    // Allow an asynchronous stream controller to deliver already-added events.
    await Future<void>.delayed(Duration.zero);
    while (_pending.isNotEmpty) {
      await Future.wait<void>(_pending.toList(growable: false));
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryAcknowledgesConversations.clear();
    _retryAcknowledgementSnapshots.clear();
    _reconciliationRetryTimer?.cancel();
    _reconciliationRetryTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await waitForIdle();
  }
}

final class _ConversationAcknowledgementSnapshot {
  _ConversationAcknowledgementSnapshot({
    required this.cancellation,
    required this.conversationKey,
  });

  final ConversationNotificationGenerationCancellation cancellation;
  final String conversationKey;
  Future<ConversationNotificationContentMetadata?>? _captured;

  Future<ConversationNotificationContentMetadata?> capture() async {
    final inFlight = _captured;
    if (inFlight != null) return inFlight;
    final capture = cancellation.lookupConversationNotificationContentMetadata(
      conversationKey,
    );
    _captured = capture;
    try {
      return await capture;
    } catch (_) {
      if (identical(_captured, capture)) _captured = null;
      rethrow;
    }
  }

  Future<bool> cancel(String generation) => cancellation
      .cancelConversationNotificationGeneration(conversationKey, generation);
}
