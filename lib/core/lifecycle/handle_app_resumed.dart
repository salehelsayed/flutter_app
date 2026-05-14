import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';

bool _resumeGroupRecoveryEnabled(P2PService p2pService) {
  return p2pService.currentState.featureFlags?['enableResumeGroupRecovery'] ??
      true;
}

/// Handles app resume lifecycle recovery.
///
/// Checks bridge health (reinitializes if dead), triggers P2P health check,
/// drains the offline inbox, and retries incomplete key exchanges.
/// Returns whether the bridge was healthy.
/// Catches all errors so callers never see exceptions.
Future<bool?> handleAppResumed({
  required Bridge bridge,
  required P2PService p2pService,
  ContactRepository? contactRepo,
  IdentityRepository? identityRepo,
  GroupRepository? groupRepo,
  GroupMessageRepository? groupMsgRepo,
  GroupMessageListener? groupMessageListener,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
  GroupHistoryGapRepairRepository? historyGapRepairRepo,
  RequestGroupKeyRepair? requestGroupKeyRepair,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  NearbyLocationService? nearbyLocationService,
  Future<int> Function()? retryPendingPostMediaUploads,
  Future<int> Function()? retryPendingPostDeliveries,
  Future<int> Function()? retryIncompleteKeyExchangesFn,
  Future<int> Function()? recoverStuckSendingMessagesFn, // Part A
  Future<int> Function()? recoverStuckSendingGroupMessagesFn, // Section 1
  Future<int> Function()? retryIncompleteGroupUploadsFn, // Section 5
  Future<int> Function()? retryFailedGroupMessagesFn, // Section 1
  Future<int> Function()? retryIncompleteUploadsFn, // Part G -- NEW
  Future<int> Function()? retryFailedMessagesFn, // Parts B/C
  Future<int> Function()? retryUnackedMessagesFn, // existing
  Future<int> Function()? retryPendingIntroductionDeliveriesFn,
  Future<int> Function()? retryFailedGroupInboxStoresFn, // Section 4
  Future<void> Function()? retryPushRegistrationFn,
}) async {
  final resumeStart = DateTime.now();
  final readinessProofRecorder = p2pService is ReadinessProofRecorder
      ? p2pService as ReadinessProofRecorder
      : null;
  final hadPendingResumeStarted =
      readinessProofRecorder?.hasPendingResumeStarted ?? false;
  debugPrint(
    '[RESUME] ====== APP RESUME BEGIN ====== ${resumeStart.toIso8601String()}',
  );
  debugPrint(
    '[RESUME] currentState before resume: '
    'isStarted=${p2pService.currentState.isStarted}, '
    'circuitAddresses=${p2pService.currentState.circuitAddresses.length}, '
    'connections=${p2pService.currentState.connections.length}',
  );

  emitFlowEvent(layer: 'FL', event: 'APP_LIFECYCLE_RESUME_BEGIN', details: {});
  readinessProofRecorder?.markResumeStarted();

  try {
    int? groupReregisterMs;

    // 1. Check bridge health — reinitialize if dead
    final healthStart = DateTime.now();
    debugPrint('[RESUME] Step 1: bridge.checkHealth() starting...');
    final bridgeOk = await bridge.checkHealth();
    final healthMs = DateTime.now().difference(healthStart).inMilliseconds;
    debugPrint(
      '[RESUME] Step 1: bridge.checkHealth() = $bridgeOk (took ${healthMs}ms)',
    );

    if (!bridgeOk) {
      final reinitStart = DateTime.now();
      debugPrint('[RESUME] Step 1b: bridge.reinitialize() starting...');
      await bridge.reinitialize();
      final reinitMs = DateTime.now().difference(reinitStart).inMilliseconds;
      debugPrint(
        '[RESUME] Step 1b: bridge.reinitialize() done (took ${reinitMs}ms)',
      );
      readinessProofRecorder?.noteTransportSessionReset(
        trigger: 'bridge_reinitialize',
      );
    }

    // 2. Immediate health check (re-dials relay, re-registers FCM)
    final hcStart = DateTime.now();
    debugPrint('[RESUME] Step 2: performImmediateHealthCheck() starting...');
    debugPrint(
      '[RESUME] Step 2: state BEFORE health check: '
      'isStarted=${p2pService.currentState.isStarted}, '
      'circuitAddresses=${p2pService.currentState.circuitAddresses.length}',
    );
    await p2pService.performImmediateHealthCheck();
    final hcMs = DateTime.now().difference(hcStart).inMilliseconds;
    debugPrint(
      '[RESUME] Step 2: performImmediateHealthCheck() done (took ${hcMs}ms)',
    );
    debugPrint(
      '[RESUME] Step 2: state AFTER health check: '
      'isStarted=${p2pService.currentState.isStarted}, '
      'circuitAddresses=${p2pService.currentState.circuitAddresses.length}',
    );

    if (retryPushRegistrationFn != null) {
      try {
        await retryPushRegistrationFn();
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_RESUME_PUSH_REGISTRATION_RETRY_ERROR',
          details: {'error': e.toString()},
        );
      }
    }

    // 3. Drain offline inbox (messages queued while backgrounded)
    final drainStart = DateTime.now();
    debugPrint('[RESUME] Step 3: drainOfflineInbox() starting...');
    await p2pService.drainOfflineInbox();
    final drainMs = DateTime.now().difference(drainStart).inMilliseconds;
    debugPrint('[RESUME] Step 3: drainOfflineInbox() done (took ${drainMs}ms)');

    final resumeGroupRecoveryEnabled = _resumeGroupRecoveryEnabled(p2pService);

    if (resumeGroupRecoveryEnabled &&
        groupRepo != null &&
        groupMsgRepo != null) {
      await runWithGroupRecoveryGate(() async {
        final needsGroupRecovery =
            p2pService.currentState.needsGroupRecovery ?? false;
        final recoveryMethod = p2pService.lastRecoveryMethod;
        final reason = needsGroupRecovery
            ? RejoinReason.nodeRequestedRecovery
            : recoveryMethod == 'watchdog_restart'
            ? RejoinReason.watchdogRestart
            : RejoinReason.inPlaceRecovery;

        debugPrint(
          '[RESUME] Step 3b: rejoinGroupTopics(reason=$reason, '
          'needsGroupRecovery=$needsGroupRecovery) starting...',
        );
        final rejoinStart = DateTime.now();
        final rejoinResult = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          reason: reason,
        );
        final rejoinMs = DateTime.now().difference(rejoinStart).inMilliseconds;
        groupReregisterMs = rejoinMs;
        debugPrint(
          '[RESUME] Step 3b: rejoinGroupTopics done '
          '(joined=${rejoinResult.joinedGroupCount}, '
          'skippedNoKey=${rejoinResult.skippedNoKeyCount}, '
          'errors=${rejoinResult.errorCount}, took ${rejoinMs}ms)',
        );

        if (needsGroupRecovery && rejoinResult.canAcknowledgeGroupRecovery) {
          final ackStart = DateTime.now();
          debugPrint(
            '[RESUME] Step 3b.1: callGroupAcknowledgeRecovery() starting...',
          );
          await callGroupAcknowledgeRecovery(bridge);
          final ackMs = DateTime.now().difference(ackStart).inMilliseconds;
          debugPrint(
            '[RESUME] Step 3b.1: callGroupAcknowledgeRecovery() done '
            '(took ${ackMs}ms)',
          );
        }

        final groupDrainStart = DateTime.now();
        debugPrint('[RESUME] Step 3c: drainGroupOfflineInbox() starting...');
        await drainGroupOfflineInbox(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
          groupMessageListener: groupMessageListener,
          mediaAttachmentRepo: mediaAttachmentRepo,
          reactionRepo: reactionRepo,
          pendingKeyRepairRepo: pendingKeyRepairRepo,
          historyGapRepairRepo: historyGapRepairRepo,
          requestGroupKeyRepair: requestGroupKeyRepair,
        );
        final groupDrainMs = DateTime.now()
            .difference(groupDrainStart)
            .inMilliseconds;
        debugPrint(
          '[RESUME] Step 3c: drainGroupOfflineInbox done (took ${groupDrainMs}ms)',
        );
      });
    } else if (groupRepo != null && resumeGroupRecoveryEnabled) {
      final needsGroupRecovery =
          p2pService.currentState.needsGroupRecovery ?? false;
      final recoveryMethod = p2pService.lastRecoveryMethod;
      final reason = needsGroupRecovery
          ? RejoinReason.nodeRequestedRecovery
          : recoveryMethod == 'watchdog_restart'
          ? RejoinReason.watchdogRestart
          : RejoinReason.inPlaceRecovery;

      debugPrint(
        '[RESUME] Step 3b: rejoinGroupTopics(reason=$reason, '
        'needsGroupRecovery=$needsGroupRecovery) starting...',
      );
      final rejoinStart = DateTime.now();
      final rejoinResult = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: reason,
      );
      final rejoinMs = DateTime.now().difference(rejoinStart).inMilliseconds;
      groupReregisterMs = rejoinMs;
      debugPrint(
        '[RESUME] Step 3b: rejoinGroupTopics done '
        '(joined=${rejoinResult.joinedGroupCount}, '
        'skippedNoKey=${rejoinResult.skippedNoKeyCount}, '
        'errors=${rejoinResult.errorCount}, took ${rejoinMs}ms)',
      );

      if (needsGroupRecovery && rejoinResult.canAcknowledgeGroupRecovery) {
        final ackStart = DateTime.now();
        debugPrint(
          '[RESUME] Step 3b.1: callGroupAcknowledgeRecovery() starting...',
        );
        await callGroupAcknowledgeRecovery(bridge);
        final ackMs = DateTime.now().difference(ackStart).inMilliseconds;
        debugPrint(
          '[RESUME] Step 3b.1: callGroupAcknowledgeRecovery() done '
          '(took ${ackMs}ms)',
        );
      }
    } else if (!resumeGroupRecoveryEnabled &&
        (groupRepo != null || groupMsgRepo != null)) {
      debugPrint(
        '[RESUME] Step 3b/3c: group recovery disabled by feature flag',
      );
    }

    if (groupRepo != null &&
        groupMsgRepo != null &&
        resumeGroupRecoveryEnabled) {
      // 3d. Recover stuck group 'sending' messages -> 'failed'
      if (recoverStuckSendingGroupMessagesFn != null) {
        try {
          final count = await recoverStuckSendingGroupMessagesFn();
          if (kDebugMode) {
            debugPrint(
              '[RESUME] Step 3d: recoverStuckSendingGroupMessages=$count',
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RECOVER_STUCK_SENDING_GROUP_RESUME_ERROR',
            details: {'error': e.toString()},
          );
          if (kDebugMode) {
            debugPrint(
              '[RESUME] Step 3d: recoverStuckSendingGroupMessages ERROR: $e',
            );
          }
        }
      }

      // 3e. Retry incomplete group media uploads from durable pending copies.
      if (retryIncompleteGroupUploadsFn != null) {
        try {
          final count = await retryIncompleteGroupUploadsFn();
          if (kDebugMode) {
            debugPrint('[RESUME] Step 3e: retryIncompleteGroupUploads=$count');
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_RESUME_ERROR',
            details: {'error': e.toString()},
          );
          if (kDebugMode) {
            debugPrint(
              '[RESUME] Step 3e: retryIncompleteGroupUploads ERROR: $e',
            );
          }
        }
      }

      // 3f. Retry failed group messages (text-only in this phase)
      if (retryFailedGroupMessagesFn != null) {
        try {
          final count = await retryFailedGroupMessagesFn();
          if (kDebugMode) {
            debugPrint('[RESUME] Step 3f: retryFailedGroupMessages=$count');
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_GROUP_MESSAGES_RESUME_ERROR',
            details: {'error': e.toString()},
          );
          if (kDebugMode) {
            debugPrint('[RESUME] Step 3f: retryFailedGroupMessages ERROR: $e');
          }
        }
      }
    }

    // 4. Retry incomplete key exchanges (contacts without ML-KEM key)
    if (contactRepo != null && identityRepo != null) {
      final retryStart = DateTime.now();
      debugPrint('[RESUME] Step 4: retryIncompleteKeyExchanges() starting...');
      final retried = retryIncompleteKeyExchangesFn != null
          ? await retryIncompleteKeyExchangesFn()
          : await retryIncompleteKeyExchanges(
              contactRepo: contactRepo,
              identityRepo: identityRepo,
              p2pService: p2pService,
              bridge: bridge,
            );
      final retryMs = DateTime.now().difference(retryStart).inMilliseconds;
      debugPrint(
        '[RESUME] Step 4: retryIncompleteKeyExchanges() done '
        '(retried=$retried, took ${retryMs}ms)',
      );
    }

    if (nearbyLocationService != null) {
      final nearbyStart = DateTime.now();
      debugPrint('[RESUME] Step 5: refreshSilentlyOnResume() starting...');
      try {
        await nearbyLocationService.refreshSilentlyOnResume();
        final nearbyMs = DateTime.now().difference(nearbyStart).inMilliseconds;
        debugPrint(
          '[RESUME] Step 5: refreshSilentlyOnResume() done '
          '(took ${nearbyMs}ms)',
        );
      } catch (e) {
        final nearbyMs = DateTime.now().difference(nearbyStart).inMilliseconds;
        debugPrint(
          '[RESUME] Step 5: refreshSilentlyOnResume() error '
          'after ${nearbyMs}ms: $e',
        );
      }
    }

    if (retryPendingPostMediaUploads != null) {
      final mediaRetryStart = DateTime.now();
      debugPrint('[RESUME] Step 6: retryPendingPostMediaUploads() starting...');
      final retried = await retryPendingPostMediaUploads();
      final mediaRetryMs = DateTime.now()
          .difference(mediaRetryStart)
          .inMilliseconds;
      debugPrint(
        '[RESUME] Step 6: retryPendingPostMediaUploads() done '
        '(retried=$retried, took ${mediaRetryMs}ms)',
      );
    }

    if (retryPendingPostDeliveries != null) {
      final postRetryStart = DateTime.now();
      debugPrint('[RESUME] Step 7: retryPendingPostDeliveries() starting...');
      final retried = await retryPendingPostDeliveries();
      final postRetryMs = DateTime.now()
          .difference(postRetryStart)
          .inMilliseconds;
      debugPrint(
        '[RESUME] Step 7: retryPendingPostDeliveries() done '
        '(retried=$retried, took ${postRetryMs}ms)',
      );
    }

    // Step 8 (NEW): Message recovery sweep -- strict ordering required.
    //
    // ORDERING CONTRACT (see Part D top-level callout):
    //   1. recoverStuckSendingMessages  -- 'sending' -> 'failed'
    //   2. retryIncompleteUploads       -- re-upload 'upload_pending' attachments
    //   3. retryFailedMessages          -- retry 'failed' messages (now with uploaded media)
    //   4. retryUnackedMessages         -- retry 'sent' but unacked messages
    //
    // Each step is fault-isolated: a throw in step N does not skip step N+1.

    // Step 8a: Recover stuck 'sending' messages -> 'failed'
    if (recoverStuckSendingMessagesFn != null) {
      try {
        final count = await recoverStuckSendingMessagesFn();
        if (kDebugMode)
          debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages=$count');
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RECOVER_STUCK_SENDING_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode)
          debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages ERROR: $e');
      }
    }

    // Step 8b: Re-upload incomplete attachment uploads (Part G).
    // MUST run after 8a (parent messages now 'failed') and BEFORE 8c
    // (so attachments have downloadStatus='done' when retryFailedMessages reads them).
    if (retryIncompleteUploadsFn != null) {
      try {
        final count = await retryIncompleteUploadsFn();
        if (kDebugMode)
          debugPrint('[RESUME] Step 8b: retryIncompleteUploads=$count');
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOADS_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode)
          debugPrint('[RESUME] Step 8b: retryIncompleteUploads ERROR: $e');
        // Non-fatal: continue to retryFailedMessages -- messages without
        // completed uploads will be retried as text-only or skipped by
        // Part F's decision tree, which is still better than not retrying at all.
      }
    }

    // Step 8c: Retry failed messages (with now-uploaded media attachments)
    if (retryFailedMessagesFn != null) {
      try {
        final count = await retryFailedMessagesFn();
        if (kDebugMode)
          debugPrint('[RESUME] Step 8c: retryFailedMessages=$count');
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode)
          debugPrint('[RESUME] Step 8c: retryFailedMessages ERROR: $e');
      }
    }

    // Step 8d: Retry sent-but-unacked messages
    if (retryUnackedMessagesFn != null) {
      try {
        final count = await retryUnackedMessagesFn();
        if (kDebugMode)
          debugPrint('[RESUME] Step 8d: retryUnackedMessages=$count');
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_MESSAGES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode)
          debugPrint('[RESUME] Step 8d: retryUnackedMessages ERROR: $e');
      }
    }

    // Step 8e: Retry pending introduction deliveries
    if (retryPendingIntroductionDeliveriesFn != null) {
      try {
        final count = await retryPendingIntroductionDeliveriesFn();
        if (kDebugMode) {
          debugPrint(
            '[RESUME] Step 8e: retryPendingIntroductionDeliveries=$count',
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_PENDING_INTRO_DELIVERIES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint(
            '[RESUME] Step 8e: retryPendingIntroductionDeliveries ERROR: $e',
          );
        }
      }
    }

    // Step 8f: Retry failed group inbox stores (Section 4)
    if (retryFailedGroupInboxStoresFn != null) {
      try {
        final count = await retryFailedGroupInboxStoresFn();
        if (kDebugMode)
          debugPrint('[RESUME] Step 8f: retryFailedGroupInboxStores=$count');
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_GROUP_INBOX_STORES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode)
          debugPrint('[RESUME] Step 8f: retryFailedGroupInboxStores ERROR: $e');
      }
    }

    final totalMs = DateTime.now().difference(resumeStart).inMilliseconds;
    debugPrint(
      '[RESUME] ====== APP RESUME COMPLETE ====== total ${totalMs}ms, bridgeWasHealthy=$bridgeOk',
    );
    debugPrint(
      '[RESUME] Final state: '
      'isStarted=${p2pService.currentState.isStarted}, '
      'circuitAddresses=${p2pService.currentState.circuitAddresses.length}, '
      'connections=${p2pService.currentState.connections.length}',
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_COMPLETE',
      details: {
        'bridgeWasHealthy': bridgeOk,
        'totalMs': totalMs,
        if (groupReregisterMs != null) 'groupReregisterMs': groupReregisterMs,
      },
    );

    return bridgeOk;
  } catch (e) {
    final totalMs = DateTime.now().difference(resumeStart).inMilliseconds;
    debugPrint(
      '[RESUME] ====== APP RESUME ERROR ====== after ${totalMs}ms: $e',
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_ERROR',
      details: {'error': e.toString()},
    );
    return null;
  } finally {
    if (!hadPendingResumeStarted) {
      readinessProofRecorder?.clearResumeStarted();
    }
  }
}
