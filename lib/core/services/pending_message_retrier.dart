import 'dart:async';
import 'dart:math';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Finding 05 Phase 4 (P1.6): a ±20% jittered copy of [interval], used to
/// stagger the periodic retry + continuity timers across reconnecting clients
/// so they do not stampede the relay in lockstep.
Duration jitteredRetryInterval(Duration interval, Random random) {
  final factor = 0.8 + random.nextDouble() * 0.4;
  return Duration(microseconds: (interval.inMicroseconds * factor).round());
}

/// Service that automatically retries failed outgoing messages
/// when the P2P node reconnects.
///
/// Subscribes to [P2PService.stateStream] and detects transitions
/// to online state (isStarted && circuitAddresses.isNotEmpty), or explicit
/// send/readiness recovery state when available.
/// Debounces by 5 seconds to avoid retrying during rapid state changes.
class PendingMessageRetrier {
  static const Duration defaultRetryDebounce = Duration(seconds: 5);
  static const Duration defaultPeriodicRetryInterval = Duration(minutes: 5);
  static const Duration defaultGroupContinuitySweepInterval = Duration(
    seconds: 30,
  );

  /// 195: the OS-restored trigger fires the retry pass on a SHORTER debounce
  /// than the node-edge one — the point is to beat node recovery, not wait it
  /// out. 1s lets the just-restored route settle; the signal already emits
  /// only on restored edges, and the node online edge remains the backstop
  /// for anything this early pass could not deliver.
  static const Duration defaultNetworkRestoredDebounce = Duration(seconds: 1);

  final P2PService p2pService;
  final MessageRepository messageRepo;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final MediaAttachmentRepository? mediaAttachmentRepo;
  final MediaFileManager? mediaFileManager;

  // Injectable recovery callbacks for correct ordering
  final Future<void> Function()? rejoinGroupTopicsFn;
  final Future<bool> Function()? rejoinGroupTopicsWithRecoveryAckEligibilityFn;
  final Future<void> Function()? acknowledgeGroupRecoveryFn;
  final Future<dynamic> Function()? drainGroupOfflineInboxFn;
  final Future<int> Function()? recoverStuckSendingMessagesFn; // Part A
  final Future<int> Function()? retryIncompleteUploadsFn; // Part G -- NEW
  final Future<int> Function()? drainDirectMediaBlobCustodyFn;
  final Future<int> Function()? retryIncompleteUploadsNetworkRestoredFn;
  final Future<int> Function()? retryIncompleteUploadsPeriodicFn;
  final Future<int> Function()? recoverStuckSendingGroupMessagesFn;
  final Future<int> Function()? retryIncompleteGroupUploadsFn;
  final Future<int> Function()? retryIncompleteGroupUploadsNetworkRestoredFn;
  final Future<int> Function()? retryIncompleteGroupUploadsPeriodicFn;
  final Future<int> Function()? retryIncompleteGroupDownloadsFn;
  final Future<int> Function()? retryIncompleteGroupDownloadsPeriodicFn;
  final Future<int> Function()? retryFailedGroupMessagesFn;
  final Future<int> Function()? retryPendingIntroductionDeliveriesFn;
  final Future<int> Function()? retryFailedGroupInboxStoresFn;

  /// Finding 05 Phase 4: clears the per-row retry-backoff window for failed
  /// group rows on reconnect, so a fresh offline→online transition grants every
  /// backed-off row one immediate attempt.
  final Future<int> Function()? clearGroupRetryBackoffFn;
  final Future<int> Function()? retryFailedMessagesOverride;
  final Future<int> Function()? retryUnackedMessagesOverride;
  final Future<int> Function()? drainDirectInboxCustodyOutboxFn;
  final Future<int> Function()? verifyInboxCustodyFn;
  final Future<void> Function()? drainNotificationCompletedOutcomesFn;

  /// 195: OS connectivity-restored edges (the 182 `connectivityRestoredSignal`
  /// adapter). Each event schedules a [networkRestoredDebounce]-debounced
  /// retry pass with the unacked age gate dropped (same pass as the node
  /// online edge) WITHOUT waiting for the node's relay session: storing to
  /// the relay durable inbox only needs an outbound dial
  /// (go-mknoon/node/inbox.go — plain h.Connect + h.NewStream, no
  /// reservation), so queued offline sends can leave as soon as any route to
  /// the relay exists (~2s) instead of after node recovery + the 5s node-edge
  /// debounce (~8s, report 192 S3). Null (default) keeps node-edge-only
  /// behavior.
  final Stream<void>? networkRestoredSignal;
  final Duration retryDebounce;
  final Duration networkRestoredDebounce;
  final Duration periodicRetryInterval;
  final Duration groupContinuitySweepInterval;

  /// Finding 05 Phase 4 (P1.6): when non-null, the periodic retry + continuity
  /// timers fire at a ±20% jittered, self-rescheduling interval to avoid a
  /// thundering herd of reconnecting clients. Null (default, used by tests)
  /// keeps deterministic fixed-interval `Timer.periodic` behavior.
  final Random? jitterRandom;

  bool Function()? _isExternalRecoveryInProgressFn;

  StreamSubscription? _stateSubscription;
  StreamSubscription? _networkRestoredSubscription;
  Timer? _debounceTimer;
  Timer? _networkRestoredDebounceTimer;
  Timer? _periodicTimer;
  Timer? _groupContinuityTimer;
  bool _wasOnline = false;
  bool _wasGroupRecoveryReady = false;
  bool _needsGroupRecovery = false;
  bool _isRetrying = false;
  bool _isGroupContinuitySweeping = false;
  bool _isNetworkRestoredFlushing = false;

  PendingMessageRetrier({
    required this.p2pService,
    required this.messageRepo,
    required this.identityRepo,
    required this.contactRepo,
    required this.bridge,
    this.mediaAttachmentRepo,
    this.mediaFileManager,
    this.rejoinGroupTopicsFn,
    this.rejoinGroupTopicsWithRecoveryAckEligibilityFn,
    this.acknowledgeGroupRecoveryFn,
    this.drainGroupOfflineInboxFn,
    this.recoverStuckSendingMessagesFn, // Part A
    this.retryIncompleteUploadsFn, // Part G -- NEW
    this.drainDirectMediaBlobCustodyFn,
    this.retryIncompleteUploadsNetworkRestoredFn,
    this.retryIncompleteUploadsPeriodicFn,
    this.recoverStuckSendingGroupMessagesFn,
    this.retryIncompleteGroupUploadsFn,
    this.retryIncompleteGroupUploadsNetworkRestoredFn,
    this.retryIncompleteGroupUploadsPeriodicFn,
    this.retryIncompleteGroupDownloadsFn,
    this.retryIncompleteGroupDownloadsPeriodicFn,
    this.retryFailedGroupMessagesFn,
    this.retryPendingIntroductionDeliveriesFn,
    this.retryFailedGroupInboxStoresFn,
    this.clearGroupRetryBackoffFn,
    this.retryFailedMessagesOverride,
    this.retryUnackedMessagesOverride,
    this.drainDirectInboxCustodyOutboxFn,
    this.verifyInboxCustodyFn,
    this.drainNotificationCompletedOutcomesFn,
    this.networkRestoredSignal,
    this.retryDebounce = defaultRetryDebounce,
    this.networkRestoredDebounce = defaultNetworkRestoredDebounce,
    this.periodicRetryInterval = defaultPeriodicRetryInterval,
    this.groupContinuitySweepInterval = defaultGroupContinuitySweepInterval,
    this.jitterRandom,
    bool Function()? isExternalRecoveryInProgressFn,
  }) : _isExternalRecoveryInProgressFn = isExternalRecoveryInProgressFn;

  void setExternalRecoveryInProgressProvider(bool Function() provider) {
    _isExternalRecoveryInProgressFn = provider;
  }

  /// Starts listening for state transitions.
  void start() {
    emitFlowEvent(layer: 'FL', event: 'PENDING_RETRIER_START', details: {});

    // Plan 370: reopen/cold-start shares the same durable outcome drain owner
    // as reconnect, restored-network, periodic, and resume triggers.
    unawaited(_drainNotificationCompletedOutcomes());

    _wasOnline = _isOnline(p2pService.currentState);
    _wasGroupRecoveryReady = _isGroupRecoveryReady(p2pService.currentState);
    _needsGroupRecovery = p2pService.currentState.needsGroupRecovery ?? false;

    _stateSubscription = p2pService.stateStream.listen((state) {
      final nowOnline = _isOnline(state);
      final nowGroupRecoveryReady = _isGroupRecoveryReady(state);
      final nowNeedsGroupRecovery = state.needsGroupRecovery ?? false;

      if (nowOnline && !_wasOnline) {
        // Finding 05 Phase 4: a reconnect grants every backed-off failed group
        // row one immediate attempt — clear the backoff window before the
        // debounced retry runs.
        final clearBackoff = clearGroupRetryBackoffFn;
        if (clearBackoff != null) {
          unawaited(clearBackoff());
        }
        // Transition to online — schedule the debounced retry (186: it drops
        // the 60s unacked age gate so queued offline messages converge on
        // reconnect) and keep group continuity catch-up on a shorter cadence.
        _startOnlineTimers();
      } else if (nowOnline &&
          _wasOnline &&
          nowNeedsGroupRecovery &&
          !_needsGroupRecovery) {
        unawaited(_runGroupContinuitySweepIfNeeded());
      } else if (!nowOnline && _wasOnline) {
        // Went offline — stop background sweeps.
        if (!nowGroupRecoveryReady) {
          _stopRecurringOnlineTimers();
        }
      }

      if (nowGroupRecoveryReady && !_wasGroupRecoveryReady) {
        _startOnlineTimers();
      } else if (!nowGroupRecoveryReady && _wasGroupRecoveryReady) {
        if (!nowOnline) {
          _stopRecurringOnlineTimers();
        }
      }

      _wasOnline = nowOnline;
      _wasGroupRecoveryReady = nowGroupRecoveryReady;
      _needsGroupRecovery = nowNeedsGroupRecovery;
    });

    // If already online when start() is called, schedule an initial sweep.
    // Handles cold-start where the Go node reports already-running.
    if (_wasOnline || _wasGroupRecoveryReady) {
      _startOnlineTimers();
    }

    // 195: OS restored edge → short-debounced LIGHT flush (1:1 unacked only),
    // deliberately NOT gated on the node's online state — the whole point is
    // to flush queued sends before node recovery finishes (inbox store dials
    // the relay directly). It is NOT the full _retryIfNeeded pass: device
    // evidence (2026-07-02, Pixel) showed the full pass is guard-skipped
    // (external recovery / group gate held) in exactly the post-restore
    // window this trigger exists for, silently deferring the flush to the
    // node-edge pass. The unacked re-store is recovery-independent — no group
    // state, no failed-row re-dials, duplicate stores deduped by the receiver
    // — so it runs under its OWN in-flight guard, ignoring the external-
    // recovery guard and never blocking (or being blocked by) a full pass.
    // A spurious restored edge (signal seeds disconnected, so subscription on
    // an already-online device emits once) is harmless: the flush is cheap
    // when nothing is queued, and at process start nothing can be in flight.
    final restoredSignal = networkRestoredSignal;
    if (restoredSignal != null) {
      _networkRestoredSubscription = restoredSignal.listen((_) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_NETWORK_RESTORED_TRIGGER',
          details: {},
        );
        _networkRestoredDebounceTimer?.cancel();
        _networkRestoredDebounceTimer = Timer(
          networkRestoredDebounce,
          () => _flushUnackedOnNetworkRestored(),
        );
      });
    }
  }

  Future<void> _flushUnackedOnNetworkRestored() async {
    if (_isNetworkRestoredFlushing) return;
    _isNetworkRestoredFlushing = true;
    try {
      unawaited(_drainNotificationCompletedOutcomes());
      await _drainDirectMediaBlobCustody();
      // TC-343-05: the shared text+reaction exact-envelope custody composite is
      // the first retry family on the OS-restored light pass. Its internal
      // family boundaries and this callback boundary keep zero-age unacked and
      // media recovery running after any custody error.
      await _drainDirectInboxCustodyOutbox();

      try {
        final count = await _retryUnackedMessagesNow(olderThan: Duration.zero);
        if (count > 0) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_NETWORK_RESTORED_FLUSHED',
            details: {'count': count},
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_NETWORK_RESTORED_FLUSH_ERROR',
          details: {'error': e.toString()},
        );
      }

      final retryDirect = retryIncompleteUploadsNetworkRestoredFn;
      if (retryDirect != null) {
        try {
          await retryDirect();
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_NETWORK_RESTORED_INCOMPLETE_UPLOAD_ERROR',
            details: {'error': e.toString()},
          );
        }
      }

      final retryGroup = retryIncompleteGroupUploadsNetworkRestoredFn;
      if (retryGroup != null) {
        try {
          await retryGroup();
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event:
                'PENDING_RETRIER_NETWORK_RESTORED_GROUP_INCOMPLETE_UPLOAD_ERROR',
            details: {'error': e.toString()},
          );
        }
      }
    } finally {
      _isNetworkRestoredFlushing = false;
    }
  }

  bool _isOnline(dynamic state) {
    return state.isStarted && (state.circuitAddresses as List).isNotEmpty;
  }

  bool _hasExplicitGroupRecoveryReadiness(dynamic state) {
    return state.relayState != null ||
        state.sendCapabilityReady == true ||
        state.inboxCapabilityReady == true;
  }

  bool _isGroupRecoveryReady(dynamic state) {
    if (!state.isStarted) return false;
    if (!_hasExplicitGroupRecoveryReadiness(state)) {
      return _isOnline(state);
    }
    final relayReady = state.relayState == null ? true : state.relayReady;
    return relayReady && state.usabilityReady;
  }

  bool _isGroupRecoveryEnabled() {
    return p2pService.currentState.featureFlags?['enableResumeGroupRecovery'] ??
        true;
  }

  /// A restored edge owns incomplete-media retry priority until its dedicated
  /// pass finishes. The node can report online early enough that an older
  /// full-pass timer fires inside the shorter restored debounce window; letting
  /// that pass claim media would erase the restored source's causal ownership.
  bool get _networkRestoredMediaPassHasPriority =>
      _networkRestoredDebounceTimer?.isActive == true ||
      _isNetworkRestoredFlushing;

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
      mediaFileManager: mediaFileManager,
      // The full pass has just run the fair global custody drain. Retained
      // rows still suppress rebuild, but must not be deposited twice in one
      // automatic trigger. Lightweight/legacy compositions without that
      // callback retain the standalone bulk retry default.
      retryDirectInboxCustody: drainDirectInboxCustodyOutboxFn == null,
    );
  }

  Future<int> _retryUnackedMessagesNow({Duration? olderThan}) {
    if (retryUnackedMessagesOverride != null) {
      return retryUnackedMessagesOverride!();
    }
    return retryUnackedMessages(
      messageRepo: messageRepo,
      p2pService: p2pService,
      mediaAttachmentRepo: mediaAttachmentRepo,
      // 186: reconnect passes Duration.zero (no age gate); periodic/cold-start
      // pass null → the use case default (60s anti-race window).
      olderThan: olderThan ?? const Duration(seconds: 60),
    );
  }

  Future<void> _drainDirectInboxCustodyOutbox() async {
    final drain = drainDirectInboxCustodyOutboxFn;
    if (drain == null) return;
    try {
      final count = await drain();
      if (count > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_DIRECT_INBOX_CUSTODY_DRAINED',
          details: {'count': count},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_DIRECT_INBOX_CUSTODY_DRAIN_ERROR',
        details: {'errorType': e.runtimeType.toString()},
      );
    }
  }

  Future<void> _drainDirectMediaBlobCustody() async {
    final drain = drainDirectMediaBlobCustodyFn;
    if (drain == null) return;
    try {
      final count = await drain();
      if (count > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_DIRECT_MEDIA_BLOB_CUSTODY_DRAINED',
          details: {'count': count},
        );
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_DIRECT_MEDIA_BLOB_CUSTODY_DRAIN_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _drainNotificationCompletedOutcomes() async {
    final drain = drainNotificationCompletedOutcomesFn;
    if (drain == null) return;
    try {
      await drain();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_NOTIFICATION_OUTCOME_DRAIN_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  void _startOnlineTimers() {
    _debounceTimer?.cancel();
    // 186 (FU-185-A): the first post-online (reconnect / cold-start / group-
    // recovery) retry drops the 60s unacked age gate (olderThan: 0) so a
    // freshly-queued offline message converges on reconnect instead of waiting
    // out the 5-min periodic. It stays DEBOUNCED (not immediate) so flappy
    // online/offline transitions still coalesce into a single retry — the debounce
    // cancel/reset is the relay-stampede guard. The periodic pass below keeps the
    // 60s anti-race window (a genuinely in-flight recent send may still get its
    // ack).
    _debounceTimer = Timer(
      retryDebounce,
      () => _retryIfNeeded(unackedOlderThan: Duration.zero),
    );

    _periodicTimer?.cancel();
    _groupContinuityTimer?.cancel();

    final random = jitterRandom;
    if (random == null) {
      // Deterministic fixed cadence (default + tests).
      _periodicTimer = Timer.periodic(
        periodicRetryInterval,
        (_) => _retryIfNeeded(periodic: true),
      );
      _groupContinuityTimer = Timer.periodic(
        groupContinuitySweepInterval,
        (_) => _runGroupContinuitySweepIfNeeded(),
      );
      return;
    }

    // Self-rescheduling jittered cadence (production): each tick recomputes a
    // ±20% delay so reconnecting clients do not retry in lockstep.
    void schedulePeriodic() {
      _periodicTimer = Timer(
        jitteredRetryInterval(periodicRetryInterval, random),
        () {
          _retryIfNeeded(periodic: true);
          schedulePeriodic();
        },
      );
    }

    void scheduleContinuity() {
      _groupContinuityTimer = Timer(
        jitteredRetryInterval(groupContinuitySweepInterval, random),
        () {
          _runGroupContinuitySweepIfNeeded();
          scheduleContinuity();
        },
      );
    }

    schedulePeriodic();
    scheduleContinuity();
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
    // 195: only dispose cancels this — going node-offline must NOT, because
    // the OS restored edge is expected to fire while the node still reports
    // offline (that is the trigger's purpose).
    _networkRestoredDebounceTimer?.cancel();
    _networkRestoredDebounceTimer = null;
    _stopRecurringOnlineTimers();
  }

  Future<bool> _runGroupRejoinIfNeeded() async {
    var shouldAcknowledgeRecovery = false;

    if (rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
      shouldAcknowledgeRecovery =
          await rejoinGroupTopicsWithRecoveryAckEligibilityFn!();
    } else if (rejoinGroupTopicsFn != null) {
      await rejoinGroupTopicsFn!();
    }

    return shouldAcknowledgeRecovery;
  }

  Future<bool> _runGroupDrainIfNeeded() async {
    if (drainGroupOfflineInboxFn == null) {
      return true;
    }

    final result = await drainGroupOfflineInboxFn!();
    if (result is GroupOfflineInboxDrainResult) {
      return result.isSuccessful;
    }
    return true;
  }

  Future<void> _acknowledgeGroupRecoveryIfEligible(
    bool shouldAcknowledgeRecovery,
  ) async {
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
    if (!_isGroupRecoveryReady(p2pService.currentState)) return;
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
      // P1.1: this best-effort continuity sweep skips (does not queue) when a
      // recovery pass already holds the serialized gate, so 30s ticks never
      // pile up behind an in-flight startup/resume/retry pass.
      final sweep = runWithGroupRecoveryGateOrSkip(() async {
        var shouldAcknowledgeRecovery = false;
        if (rejoinGroupTopicsFn != null ||
            rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
          try {
            shouldAcknowledgeRecovery = await _runGroupRejoinIfNeeded();
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_REJOIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        var drainSucceeded = true;
        try {
          drainSucceeded = await _runGroupDrainIfNeeded();
        } catch (e) {
          drainSucceeded = false;
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_GROUP_DRAIN_ERROR',
            details: {'error': e.toString()},
          );
        }

        await _acknowledgeGroupRecoveryIfEligible(
          shouldAcknowledgeRecovery && drainSucceeded,
        );
      });
      if (sweep == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_GROUP_SWEEP_SKIPPED_GATE_ACTIVE',
          details: {},
        );
      } else {
        await sweep;
      }
    } finally {
      _isGroupContinuitySweeping = false;
    }
  }

  Future<void> _retryIfNeeded({
    Duration? unackedOlderThan,
    bool periodic = false,
  }) async {
    if (_isRetrying) {
      unawaited(_drainNotificationCompletedOutcomes());
      return;
    }
    if (_isExternalRecoveryInProgressFn?.call() == true) {
      unawaited(_drainNotificationCompletedOutcomes());
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_SKIPPED_EXTERNAL_RECOVERY',
        details: {},
      );
      return;
    }
    _isRetrying = true;

    try {
      unawaited(_drainNotificationCompletedOutcomes());
      final groupRecoveryEnabled = _isGroupRecoveryEnabled();
      final groupRecoveryReady = _isGroupRecoveryReady(p2pService.currentState);

      // ORDERING CONTRACT:
      //   1. group rejoin topics
      //   2. group drain offline inbox
      //   3. group acknowledge recovery when rejoin and drain both succeeded
      //   4. group retry incomplete downloads
      //   5. group recover stuck outgoing messages
      //   6. group retry incomplete uploads
      //   7. group retry failed inbox stores (publish-free custody confirm)
      //   8. group retry failed messages (re-publish)
      //   9. 1:1 recover stuck
      //  10. 1:1 retry incomplete uploads
      //  11. 1:1 drain direct-text sender custody
      //  12. 1:1 retry failed messages
      //  13. 1:1 retry unacked messages
      //  14. intro retry pending deliveries
      // Confirm (7) runs before re-publish (8): both touch 'pending' rows, and
      // confirm-first prevents re-publishing a pending row custody resolved.

      if (groupRecoveryEnabled && groupRecoveryReady) {
        // P1.3: hold the serialized group recovery gate for the whole group
        // recovery + outbound-repair pass so isGroupRecoveryInProgress() reports
        // true to the group-mutation guards and the "catching up" UI shell
        // (matching the 30s continuity sweep), and so the serialized gate keeps
        // this pass from overlapping the startup/resume recovery passes. Step
        // order is preserved byte-for-byte (finding-125 GAP 3a: inbox-store
        // custody-confirm before the re-publish retrier).
        await runWithGroupRecoveryGate(() async {
          var shouldAcknowledgeRecovery = false;
          if (rejoinGroupTopicsFn != null ||
              rejoinGroupTopicsWithRecoveryAckEligibilityFn != null) {
            try {
              shouldAcknowledgeRecovery = await _runGroupRejoinIfNeeded();
            } catch (e) {
              emitFlowEvent(
                layer: 'FL',
                event: 'PENDING_RETRIER_GROUP_REJOIN_ERROR',
                details: {'error': e.toString()},
              );
            }
          }

          var drainSucceeded = true;
          try {
            drainSucceeded = await _runGroupDrainIfNeeded();
          } catch (e) {
            drainSucceeded = false;
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_GROUP_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }

          await _acknowledgeGroupRecoveryIfEligible(
            shouldAcknowledgeRecovery && drainSucceeded,
          );

          // Ordinary incoming group media recovery intentionally belongs only
          // to the node/relay-ready group pass. The early OS-restored flush
          // above never invokes it. Production supplies callbacks wrapped by
          // the account-migration network gate, which remains the final
          // authority before the shared coordinator does any work.
          final retryIncompleteGroupDownloadsForPass = periodic
              ? retryIncompleteGroupDownloadsPeriodicFn ??
                    retryIncompleteGroupDownloadsFn
              : retryIncompleteGroupDownloadsFn;
          if (retryIncompleteGroupDownloadsForPass != null) {
            try {
              final count = await retryIncompleteGroupDownloadsForPass();
              if (count > 0) {
                emitFlowEvent(
                  layer: 'FL',
                  event: 'PENDING_RETRIER_GROUP_INCOMPLETE_DOWNLOADS_RETRIED',
                  details: {'count': count},
                );
              }
            } catch (e) {
              emitFlowEvent(
                layer: 'FL',
                event: 'PENDING_RETRIER_GROUP_INCOMPLETE_DOWNLOAD_ERROR',
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

          final retryIncompleteGroupUploadsForPass = periodic
              ? retryIncompleteGroupUploadsPeriodicFn ??
                    retryIncompleteGroupUploadsFn
              : retryIncompleteGroupUploadsFn;
          if (retryIncompleteGroupUploadsForPass != null &&
              !_networkRestoredMediaPassHasPriority) {
            try {
              await retryIncompleteGroupUploadsForPass();
            } catch (e) {
              emitFlowEvent(
                layer: 'FL',
                event: 'PENDING_RETRIER_GROUP_INCOMPLETE_UPLOAD_ERROR',
                details: {'error': e.toString()},
              );
            }
          }

          // Publish-free custody confirm BEFORE the re-publish retrier:
          // promote a reconcilable pending row to sent without re-sending.
          // Both this and the re-publish step touch 'pending' rows;
          // confirm-first prevents the re-publish below from re-transmitting
          // — and risking a duplicate delivery of — a pending row that relay
          // custody already resolved (GAP 3a).
          if (retryFailedGroupInboxStoresFn != null) {
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
        });
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

      // Immutable strict blob recovery precedes mutable attachment retry.
      await _drainDirectMediaBlobCustody();

      // Step 7: Re-upload incomplete attachments (Part G)
      final retryIncompleteUploadsForPass = periodic
          ? retryIncompleteUploadsPeriodicFn ?? retryIncompleteUploadsFn
          : retryIncompleteUploadsFn;
      if (retryIncompleteUploadsForPass != null &&
          !_networkRestoredMediaPassHasPriority) {
        try {
          final count = await retryIncompleteUploadsForPass();
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

      // TC-343-05: retry the shared immutable direct text+reaction custody
      // composite after stuck/upload recovery and before either message rebuild
      // family. The composite isolates its siblings; this helper also isolates
      // the callback so a poison/drain failure cannot starve later retries.
      await _drainDirectInboxCustodyOutbox();

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
      final unackedCount = await _retryUnackedMessagesNow(
        olderThan: unackedOlderThan,
      );

      if (unackedCount > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_UNACKED_RETRIED',
          details: {'count': unackedCount},
        );
      }

      if (verifyInboxCustodyFn != null) {
        try {
          final custodyCount = await verifyInboxCustodyFn!();
          if (custodyCount > 0) {
            emitFlowEvent(
              layer: 'FL',
              event: 'PENDING_RETRIER_INBOX_CUSTODY_VERIFIED',
              details: {'count': custodyCount},
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_INBOX_CUSTODY_ERROR',
            details: {'error': e.toString()},
          );
        }
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
    _networkRestoredSubscription?.cancel();
    _networkRestoredSubscription = null;
  }
}
