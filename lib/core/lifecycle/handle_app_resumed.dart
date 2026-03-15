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
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
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
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  NearbyLocationService? nearbyLocationService,
}) async {
  final resumeStart = DateTime.now();
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

  try {
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

    // 3. Drain offline inbox (messages queued while backgrounded)
    final drainStart = DateTime.now();
    debugPrint('[RESUME] Step 3: drainOfflineInbox() starting...');
    await p2pService.drainOfflineInbox();
    final drainMs = DateTime.now().difference(drainStart).inMilliseconds;
    debugPrint('[RESUME] Step 3: drainOfflineInbox() done (took ${drainMs}ms)');

    final resumeGroupRecoveryEnabled = _resumeGroupRecoveryEnabled(p2pService);

    // 3b. Group recovery: rejoin topics if watchdog restart occurred
    if (groupRepo != null && resumeGroupRecoveryEnabled) {
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
      debugPrint(
        '[RESUME] Step 3b: rejoinGroupTopics done '
        '(joined=${rejoinResult.joinedGroupCount}, '
        'skippedNoKey=${rejoinResult.skippedNoKeyCount}, '
        'errors=${rejoinResult.errorCount}, took ${rejoinMs}ms)',
      );

      if (needsGroupRecovery && rejoinResult.errorCount == 0) {
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
    }

    // 3c. Group inbox drain: catch up on missed group messages
    if (groupRepo != null &&
        groupMsgRepo != null &&
        resumeGroupRecoveryEnabled) {
      final groupDrainStart = DateTime.now();
      debugPrint('[RESUME] Step 3c: drainGroupOfflineInbox() starting...');
      await drainGroupOfflineInbox(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        reactionRepo: reactionRepo,
      );
      final groupDrainMs = DateTime.now()
          .difference(groupDrainStart)
          .inMilliseconds;
      debugPrint(
        '[RESUME] Step 3c: drainGroupOfflineInbox done (took ${groupDrainMs}ms)',
      );
    } else if (!resumeGroupRecoveryEnabled &&
        (groupRepo != null || groupMsgRepo != null)) {
      debugPrint(
        '[RESUME] Step 3b/3c: group recovery disabled by feature flag',
      );
    }

    // 4. Retry incomplete key exchanges (contacts without ML-KEM key)
    if (contactRepo != null && identityRepo != null) {
      final retryStart = DateTime.now();
      debugPrint('[RESUME] Step 4: retryIncompleteKeyExchanges() starting...');
      final retried = await retryIncompleteKeyExchanges(
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
      details: {'bridgeWasHealthy': bridgeOk, 'totalMs': totalMs},
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
  }
}
