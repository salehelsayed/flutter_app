import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Service that automatically retries failed outgoing messages
/// when the P2P node reconnects.
///
/// Subscribes to [P2PService.stateStream] and detects transitions
/// to online state (isStarted && circuitAddresses.isNotEmpty).
/// Debounces by 5 seconds to avoid retrying during rapid state changes.
class PendingMessageRetrier {
  static const Duration defaultRetryDebounce = Duration(seconds: 5);
  static const Duration defaultPeriodicRetryInterval = Duration(minutes: 5);
  static const Duration defaultGroupContinuitySweepInterval = Duration(
    seconds: 30,
  );

  final P2PService p2pService;
  final MessageRepository messageRepo;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final MediaAttachmentRepository? mediaAttachmentRepo;

  // Injectable recovery callbacks for correct ordering
  final Future<void> Function()? rejoinGroupTopicsFn;
  final Future<bool> Function()? rejoinGroupTopicsWithRecoveryAckEligibilityFn;
  final Future<void> Function()? acknowledgeGroupRecoveryFn;
  final Future<void> Function()? drainGroupOfflineInboxFn;
  final Future<int> Function()? recoverStuckSendingMessagesFn; // Part A
  final Future<int> Function()? retryIncompleteUploadsFn; // Part G -- NEW
  final Future<int> Function()? recoverStuckSendingGroupMessagesFn;
  final Future<int> Function()? retryIncompleteGroupUploadsFn;
  final Future<int> Function()? retryFailedGroupMessagesFn;
  final Future<int> Function()? retryPendingIntroductionDeliveriesFn;
  final Future<int> Function()? retryFailedGroupInboxStoresFn;
  final Future<int> Function()? retryFailedMessagesOverride;
  final Future<int> Function()? retryUnackedMessagesOverride;
  final Duration retryDebounce;
  final Duration periodicRetryInterval;
  final Duration groupContinuitySweepInterval;

  bool Function()? _isExternalRecoveryInProgressFn;

  StreamSubscription? _stateSubscription;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _groupContinuityTimer;
  bool _wasOnline = false;
  bool _needsGroupRecovery = false;
  bool _isRetrying = false;
  bool _isGroupContinuitySweeping = false;

  PendingMessageRetrier({
    required this.p2pService,
    required this.messageRepo,
    required this.identityRepo,
    required this.contactRepo,
    required this.bridge,
    this.mediaAttachmentRepo,
    this.rejoinGroupTopicsFn,
    this.rejoinGroupTopicsWithRecoveryAckEligibilityFn,
    this.acknowledgeGroupRecoveryFn,
    this.drainGroupOfflineInboxFn,
    this.recoverStuckSendingMessagesFn, // Part A
    this.retryIncompleteUploadsFn, // Part G -- NEW
    this.recoverStuckSendingGroupMessagesFn,
    this.retryIncompleteGroupUploadsFn,
    this.retryFailedGroupMessagesFn,
    this.retryPendingIntroductionDeliveriesFn,
    this.retryFailedGroupInboxStoresFn,
    this.retryFailedMessagesOverride,
    this.retryUnackedMessagesOverride,
    this.retryDebounce = defaultRetryDebounce,
    this.periodicRetryInterval = defaultPeriodicRetryInterval,
    this.groupContinuitySweepInterval = defaultGroupContinuitySweepInterval,
    bool Function()? isExternalRecoveryInProgressFn,
  }) : _isExternalRecoveryInProgressFn = isExternalRecoveryInProgressFn;

  void setExternalRecoveryInProgressProvider(bool Function() provider) {
    _isExternalRecoveryInProgressFn = provider;
  }

  /// Starts listening for state transitions.
  void start() {
    emitFlowEvent(layer: 'FL', event: 'PENDING_RETRIER_START', details: {});

    _wasOnline = _isOnline(p2pService.currentState);
    _needsGroupRecovery = p2pService.currentState.needsGroupRecovery ?? false;

    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);
      final nowNeedsGroupRecovery = state.needsGroupRecovery ?? false;

      if (nowOnline && !_wasOnline) {
        // Transition to online — schedule retry with debounce and
        // keep group continuity catch-up on a shorter cadence.
        _startOnlineTimers();
      } else if (nowOnline &&
          _wasOnline &&
          nowNeedsGroupRecovery &&
          !_needsGroupRecovery) {
        unawaited(_runGroupContinuitySweepIfNeeded());
      } else if (!nowOnline && _wasOnline) {
        // Went offline — stop background sweeps.
        _stopRecurringOnlineTimers();
      }

      _wasOnline = nowOnline;
      _needsGroupRecovery = nowNeedsGroupRecovery;
    });

    // If already online when start() is called, schedule an initial sweep.
    // Handles cold-start where the Go node reports already-running.
    if (_wasOnline) {
      _startOnlineTimers();
    }
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  bool _isGroupRecoveryEnabled() {
    return p2pService.currentState.featureFlags?['enableResumeGroupRecovery'] ??
        true;
  }

  Future<int> _retryFailedMessagesNow() {
    if (retryFailedMessagesOverride != null) {
      return retryFailedMessagesOverride!();
    }
    return retryFailedMessages(
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );
  }

  Future<int> _retryUnackedMessagesNow() {
    if (retryUnackedMessagesOverride != null) {
      return retryUnackedMessagesOverride!();
    }
    return retryUnackedMessages(
      messageRepo: messageRepo,
      p2pService: p2pService,
    );
  }

  void _startOnlineTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(retryDebounce, _retryIfNeeded);

    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      periodicRetryInterval,
      (_) => _retryIfNeeded(),
    );

    _groupContinuityTimer?.cancel();
    _groupContinuityTimer = Timer.periodic(
      groupContinuitySweepInterval,
      (_) => _runGroupContinuitySweepIfNeeded(),
    );
  }

  void _stopRecurringOnlineTimers() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _groupContinuityTimer?.cancel();
    _groupContinuityTimer = null;
  }

  void _stopAllTimers() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _stopRecurringOnlineTimers();
  }

  Future<void> _runGroupRejoinIfNeeded() async {
    var shouldAcknowledgeRecovery = false;

    if (rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
      shouldAcknowledgeRecovery =
          await rejoinGroupTopicsWithRecoveryAckEligibilityFn!();
    } else if (rejoinGroupTopicsFn != null) {
      await rejoinGroupTopicsFn!();
    }

    if (!shouldAcknowledgeRecovery || acknowledgeGroupRecoveryFn == null) {
      return;
    }

    try {
      await acknowledgeGroupRecoveryFn!();
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_GROUP_ACK_RECOVERY_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _runGroupContinuitySweepIfNeeded() async {
    if (_isGroupContinuitySweeping || _isRetrying) return;
    if (!_isGroupRecoveryEnabled()) return;
    if (rejoinGroupTopicsFn == null &&
        rejoinGroupTopicsWithRecoveryAckEligibilityFn == null &&
        drainGroupOfflineInboxFn == null) {
      return;
    }
    if (_isExternalRecoveryInProgressFn?.call() == true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_GROUP_SWEEP_SKIPPED_EXTERNAL_RECOVERY',
        details: {},
      );
      return;
    }

    _isGroupContinuitySweeping = true;
    try {
      await runWithGroupRecoveryGate(() async {
        if (rejoinGroupTopicsFn != null ||
            rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
          try {
            await _runGroupRejoinIfNeeded();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_REJOIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (drainGroupOfflineInboxFn != null) {
          try {
            await drainGroupOfflineInboxFn!();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        }
      });
    } finally {
      _isGroupContinuitySweeping = false;
    }
  }

  Future<void> _retryIfNeeded() async {
    if (_isRetrying) return;
    if (_isExternalRecoveryInProgressFn?.call() == true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY',
        details: {},
      );
      return;
    }
    _isRetrying = true;

    try {
      final groupRecoveryEnabled = _isGroupRecoveryEnabled();

      // ORDERING CONTRACT:
      //   1. group rejoin topics
      //   2. group drain offline inbox
      //   3. group recover stuck
      //   4. group retry incomplete uploads
      //   5. group retry failed messages
      //   6. 1:1 recover stuck
      //   7. 1:1 retry incomplete uploads
      //   8. 1:1 retry failed messages
      //   9. 1:1 retry unacked messages
      //  10. intro retry pending deliveries
      //  11. group retry failed inbox stores

      if (groupRecoveryEnabled) {
        if (rejoinGroupTopicsFn != null ||
            rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
          try {
            await _runGroupRejoinIfNeeded();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_REJOIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (drainGroupOfflineInboxFn != null) {
          try {
            await drainGroupOfflineInboxFn!();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (recoverStuckSendingGroupMessagesFn != null) {
          try {
            await recoverStuckSendingGroupMessagesFn!();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_RECOVER_STUCK_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (retryIncompleteGroupUploadsFn != null) {
          try {
            await retryIncompleteGroupUploadsFn!();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_INCOMPLETE_UPLOAD_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (retryFailedGroupMessagesFn != null) {
          try {
            await retryFailedGroupMessagesFn!();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_FAILED_MESSAGES_ERROR',
              details: {'error': e.toString()},
            );
          }
        }
      }

      // Step 6: Recover stuck sending messages
      if (recoverStuckSendingMessagesFn != null) {
        try {
          final count = await recoverStuckSendingMessagesFn!();
          if (count > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_RECOVERED_STUCK',
              details: {'count': count},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_RECOVER_STUCK_ERROR',
            details: {'error': e.toString()},
          );
        }
      }

      // Step 7: Re-upload incomplete attachments (Part G)
      if (retryIncompleteUploadsFn != null) {
        try {
          final count = await retryIncompleteUploadsFn!();
          if (count > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_INCOMPLETE_UPLOADS_RETRIED',
              details: {'count': count},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_INCOMPLETE_UPLOAD_ERROR',
            details: {'error': e.toString()},
          );
          // Non-fatal: continue to retryFailedMessages
        }
      }

      // Step 8: Retry failed messages
      final count = await _retryFailedMessagesNow();

      if (count > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_RETRIED',
          details: {'count': count},
        );
      }

      // Step 9: Retry unacked messages
      final unackedCount = await _retryUnackedMessagesNow();

      if (unackedCount > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_UNACKED_RETRIED',
          details: {'count': unackedCount},
        );
      }

      if (retryPendingIntroductionDeliveriesFn != null) {
        try {
          final count = await retryPendingIntroductionDeliveriesFn!();
          if (count > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_INTRO_OUTBOX_RETRIED',
              details: {'count': count},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_INTRO_OUTBOX_ERROR',
            details: {'error': e.toString()},
          );
        }
      }

      if (groupRecoveryEnabled && retryFailedGroupInboxStoresFn != null) {
        try {
          await retryFailedGroupInboxStoresFn!();
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_GROUP_INBOX_RETRY_ERROR',
            details: {'error': e.toString()},
          );
        }
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _isRetrying = false;
    }
  }

  /// Stops listening and cleans up resources.
  void dispose() {
    emitFlowEvent(layer: 'FL', event: 'PENDING_RETRIER_DISPOSE', details: {});

    _stopAllTimers();
    _stateSubscription?.cancel();
    _stateSubscription = null;
  }
}
