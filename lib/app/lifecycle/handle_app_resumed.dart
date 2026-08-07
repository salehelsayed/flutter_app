import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/reconcile_missed_group_dissolves_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_history_gap_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';

bool _resumeGroupRecoveryEnabled(P2PService p2pService) {
  return p2pService.currentState.featureFlags?['enableResumeGroupRecovery'] ??
      true;
}

/// Runs one bounded durable-exit recovery pass in the only safe order.
///
/// Role broadcasts are attempted first. A discovery/drain failure is reported
/// but cannot strand unrelated native-leave or local-cleanup phases; queued
/// intents perform their own per-group role drain and remain fail-closed.
Future<void> runGroupExitIntentRecoveryPass({
  required Future<void> Function() drainPendingBroadcasts,
  required Future<void> Function() processExitIntents,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  try {
    await drainPendingBroadcasts();
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
  }
  try {
    await processExitIntents();
  } catch (error, stackTrace) {
    onError?.call(error, stackTrace);
  }
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
  Future<bool> Function(String groupId)? canRejoinForExitIntent,
  Future<void> Function(String groupId)? processExitIntent,
  GroupPendingKeyRepairRepository? pendingKeyRepairRepo,
  GroupHistoryGapRepairRepository? historyGapRepairRepo,
  RequestGroupKeyRepair? requestGroupKeyRepair,
  MediaAttachmentRepository? mediaAttachmentRepo,
  ReactionRepository? reactionRepo,
  // Plan 322: without this the drain DROPS a reaction whose target message has
  // not landed yet (unknownMessage), and the relay entry is already consumed.
  GroupPendingReactionRepository? pendingReactionRepo,
  NearbyLocationService? nearbyLocationService,
  Future<int> Function()? retryPendingPostMediaUploads,
  Future<int> Function()? retryPendingPostDeliveries,
  Future<int> Function()? retryIncompleteKeyExchangesFn,
  Future<int> Function()? recoverStuckSendingMessagesFn, // Part A
  Future<int> Function()? recoverStuckSendingGroupMessagesFn, // Section 1
  Future<int> Function()? retryIncompleteGroupUploadsFn, // Section 5
  Future<int> Function()? retryIncompleteGroupDownloadsFn, // Plan 269
  Future<int> Function()? retryFailedGroupMessagesFn, // Section 1
  Future<int> Function()? retryIncompleteUploadsFn, // Part G -- NEW
  Future<int> Function()? drainDirectInboxCustodyOutboxFn,
  Future<int> Function()? retryFailedMessagesFn, // Parts B/C
  Future<int> Function()? retryUnackedMessagesFn, // existing
  Future<int> Function()? verifyInboxCustodyFn,
  Future<int> Function()? retryPendingIntroductionDeliveriesFn,
  Future<int> Function()? retryFailedGroupInboxStoresFn, // Section 4
  Future<int> Function()? drainPendingKeyDistributionsFn, // Finding 03 Slice 2
  Future<int> Function()?
  retryAllPendingGroupKeyRepairsFn, // Finding 02 UDM-B (Step 8i)
  Future<void> Function()? retryPushRegistrationFn,
  bool skipDirectInboxDrain = false,
  bool skipGroupInboxDrain = false,
  bool awaitCanonicalInboxDrains = false,
  void Function(bool complete)? onCanonicalInboxDrainsSettled,
  AccountMigrationNetworkGate accountMigrationNetworkGate =
      allowAccountMigrationNetworkSideEffects,

  /// Restores active authority when a Move Account export pause is stuck
  /// (e.g. the restore write failed while the keychain was locked) and no
  /// export run is in flight. Must run BEFORE the network gate check, because
  /// the gate denies everything while the stale pause persists.
  Future<bool> Function()? recoverInterruptedExportPause,

  /// 235: one bounded pass over the group media deletion journal
  /// ([GroupMediaDeletionJournalReconciler.runBounded] in production). It is
  /// LOCAL-ONLY work (file/key/row cleanup for already-committed deletes), so
  /// it runs BEFORE the account-migration network gate — a denied gate must
  /// not leave committed deletions half-cleaned. Errors are isolated; resume
  /// proceeds regardless.
  Future<void> Function()? groupMediaDeletionCleanupFn,

  /// 234 Session 03: one bounded, local-only direct private-media lifecycle
  /// recovery pass. It terminalizes interrupted opening/viewing state, expires
  /// due disappearing media, and retries terminal file/key/row cleanup. This
  /// must run before the account-migration network gate so a denied network
  /// resume cannot strand already-local lifecycle work. Errors are isolated.
  Future<void> Function()? privateMediaLifecycleRecoveryFn,

  /// FDC-04 (DESIGN-3/SRC-1): resolves the single active conversation peer so
  /// resume can eagerly warm ONLY it (PS-4 — never the roster). In production
  /// wired to `ActiveConversationTracker.activePeerId`. Null / null-return /
  /// a `group:`-prefixed key ⇒ no warm. Fired UNAWAITED in the parallel
  /// re-prime block so it never adds latency to the resume future.
  String? Function()? activeConversationPeerId,
}) async {
  final resumeStart = DateTime.now();
  var canonicalInboxDrainsComplete = true;
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

  if (recoverInterruptedExportPause != null) {
    try {
      final recovered = await recoverInterruptedExportPause();
      if (recovered) {
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERED',
          details: {},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERY_FAILED',
        details: {'error': e.toString()},
      );
    }
  }

  // 235: local deletion-journal cleanup runs BEFORE the network gate — it has
  // no network side effect and must converge even while account migration
  // denies every networked resume step.
  if (groupMediaDeletionCleanupFn != null) {
    try {
      await groupMediaDeletionCleanupFn();
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_DONE',
        details: {},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_FAILED',
        details: {'error': e.toString()},
      );
    }
  }

  if (privateMediaLifecycleRecoveryFn != null) {
    try {
      await privateMediaLifecycleRecoveryFn();
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_PRIVATE_MEDIA_RECOVERY_DONE',
        details: {},
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_PRIVATE_MEDIA_RECOVERY_FAILED',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  final migrationAllowsNetwork = await accountMigrationNetworkGate(
    peerId: p2pService.currentState.peerId,
    operation: 'app_resume',
  );
  if (!migrationAllowsNetwork) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_ACCOUNT_MIGRATION_BLOCKED',
      details: {'peerId': p2pService.currentState.peerId},
    );
    debugPrint('[RESUME] skipped by account migration runtime network gate');
    onCanonicalInboxDrainsSettled?.call(false);
    return false;
  }

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
    // FDC-S1 Method 6: warm-resume control. Mirror the existing debugPrint as an
    // epoch-anchored flow-event so resume steps share the cold-start axis.
    emitFlowEvent(
      layer: 'FL',
      event: 'FDC_RESUME_STEP_TIMING',
      details: {'step': 'bridge_health', 'ms': healthMs},
    );

    if (!bridgeOk) {
      final reinitStart = DateTime.now();
      debugPrint('[RESUME] Step 1b: bridge.reinitialize() starting...');
      await bridge.reinitialize();
      final reinitMs = DateTime.now().difference(reinitStart).inMilliseconds;
      debugPrint(
        '[RESUME] Step 1b: bridge.reinitialize() done (took ${reinitMs}ms)',
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'FDC_RESUME_STEP_TIMING',
        details: {'step': 'bridge_reinit', 'ms': reinitMs},
      );
      readinessProofRecorder?.noteTransportSessionReset(
        trigger: 'bridge_reinitialize',
      );
    }

    // 2 + 3. Re-prime + inbox drain — run CONCURRENTLY (FDC-05 / proposal §6.4
    // recommendation P1-2). On HEAD these were strictly serial: the relay/mDNS
    // re-prime was awaited, then push, then an awaited inbox drain — so the
    // first post-resume send sat behind a multi-second awaited network drain
    // ("open app → send one message → close feels slow").
    //
    // Now: kick the bounded re-prime off, fire the inbox drain UNAWAITED, then
    // await ONLY the re-prime. `bridge.checkHealth()` above stays first — it is
    // a hard precondition both of these rely on. The Step-8 outbound recovery
    // sweep below stays strictly ordered and now runs while the drain is still
    // in flight (it is outbound-only and independent of incoming-drain results).
    final hcStart = DateTime.now();
    debugPrint('[RESUME] Step 2: performImmediateHealthCheck() starting...');
    debugPrint(
      '[RESUME] Step 2: state BEFORE health check: '
      'isStarted=${p2pService.currentState.isStarted}, '
      'circuitAddresses=${p2pService.currentState.circuitAddresses.length}',
    );
    // Re-dials relay, re-registers FCM, restarts mDNS advertising; coalesces
    // concurrent recovery internally. Kicked off here but NOT yet awaited.
    final reprime = p2pService.performImmediateHealthCheck();

    // FDC-04 (DESIGN-3/SRC-1): eagerly warm the ONE active conversation peer
    // (PS-4 — never the roster) so the first post-resume send hits the reuse
    // fast path. Placed AFTER the health-check kickoff (node confirmed started —
    // PS-3) and slotted into FDC-05's parallel block alongside the drain, fired
    // UNAWAITED so it never adds latency to the resume future. Null / empty /
    // a `group:` key ⇒ no warm (warmPeer is 1:1-only). warmPeer is itself
    // total/never-throws + debounced, so no extra error handling is needed.
    final activeWarmPeerId = activeConversationPeerId?.call();
    if (activeWarmPeerId != null &&
        activeWarmPeerId.isNotEmpty &&
        !activeWarmPeerId.startsWith('group:')) {
      unawaited(p2pService.warmPeer(activeWarmPeerId));
    }

    // 3. Drain offline inbox. Normal callers retain the latency-neutral
    // fire-and-forget path. An absolute notification reconciliation requests
    // the existing full-drain capability and waits for its truthful outcome.
    if (skipDirectInboxDrain) {
      canonicalInboxDrainsComplete = false;
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_RESUME_DIRECT_DRAIN_REPLACED',
        details: {'owner': 'dropped_push_recovery'},
      );
    } else {
      debugPrint('[RESUME] Step 3: drainOfflineInbox() starting...');
      if (awaitCanonicalInboxDrains) {
        if (p2pService case final P2PFullInboxDrain fullDrain) {
          try {
            final outcome = await fullDrain.drainOfflineInboxFully();
            canonicalInboxDrainsComplete =
                outcome.isSuccessful && !outcome.hasMore;
          } catch (e) {
            canonicalInboxDrainsComplete = false;
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_RESUME_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }
        } else {
          // A void-only drain cannot prove cursor exhaustion.
          await p2pService.drainOfflineInbox();
          canonicalInboxDrainsComplete = false;
        }
      } else {
        unawaited(
          p2pService.drainOfflineInbox().catchError((Object e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_RESUME_DRAIN_ERROR',
              details: {'error': e.toString()},
            );
          }),
        );
      }
    }

    // Observable discriminator that the parallel shape ran (vs HEAD's serial
    // re-prime → push → awaited drain). Both shapes still end with
    // APP_LIFECYCLE_RESUME_COMPLETE.
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_RESUME_REPRIME_PARALLEL',
      details: {},
    );

    // Await only the bounded re-prime (each step under the foreground 3s budgets
    // in go-mknoon/node/config.go); the drain continues in the background.
    await reprime;
    final hcMs = DateTime.now().difference(hcStart).inMilliseconds;
    debugPrint(
      '[RESUME] Step 2: performImmediateHealthCheck() done (took ${hcMs}ms)',
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'FDC_RESUME_STEP_TIMING',
      details: {'step': 'perform_immediate_health_check', 'ms': hcMs},
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

    final resumeGroupRecoveryEnabled = _resumeGroupRecoveryEnabled(p2pService);
    // Phase 2: captured out of the recovery gate so the background drain
    // continuation can be scheduled after the gate closes.
    var drainHasMorePages = false;
    var firstGroupDrainSuccessful = true;
    String? continuationSelfPeerId;

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

        final identity = await identityRepo?.loadIdentity();
        continuationSelfPeerId = identity?.peerId;
        debugPrint(
          '[RESUME] Step 3b: rejoinGroupTopics(reason=$reason, '
          'needsGroupRecovery=$needsGroupRecovery) starting...',
        );
        final rejoinStart = DateTime.now();
        final rejoinResult = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          reason: reason,
          canRejoinForExitIntent: canRejoinForExitIntent,
          processExitIntent: processExitIntent,
        );
        final rejoinMs = DateTime.now().difference(rejoinStart).inMilliseconds;
        groupReregisterMs = rejoinMs;
        debugPrint(
          '[RESUME] Step 3b: rejoinGroupTopics done '
          '(joined=${rejoinResult.joinedGroupCount}, '
          'skippedNoKey=${rejoinResult.skippedNoKeyCount}, '
          'errors=${rejoinResult.errorCount}, took ${rejoinMs}ms)',
        );

        // 123 S1 — after rejoin, reconcile any missed TERMINAL dissolve so a
        // group dissolved while backgrounded converges (and is left) instead of
        // staying live. AFTER rejoin so active groups re-subscribe immediately
        // (the inbox scan must not delay live-message reception — see IR-018).
        final groupMsgListener = groupMessageListener;
        if (groupMsgListener != null) {
          await reconcileMissedGroupDissolves(
            bridge: bridge,
            groupRepo: groupRepo,
            groupMessageListener: groupMsgListener,
            selfPeerId: identity?.peerId,
          );
        }

        final GroupOfflineInboxDrainResult groupDrainResult;
        if (skipGroupInboxDrain) {
          firstGroupDrainSuccessful = false;
          canonicalInboxDrainsComplete = false;
          groupDrainResult = const GroupOfflineInboxDrainResult(
            groupCount: 0,
            errorCount: 1,
            hasMorePages: true,
          );
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_RESUME_GROUP_DRAIN_REPLACED',
            details: {'owner': 'dropped_push_recovery'},
          );
        } else {
          final groupDrainStart = DateTime.now();
          debugPrint('[RESUME] Step 3c: drainGroupOfflineInbox() starting...');
          groupDrainResult = await drainGroupOfflineInbox(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: groupMsgRepo,
            groupMessageListener: groupMessageListener,
            mediaAttachmentRepo: mediaAttachmentRepo,
            reactionRepo: reactionRepo,
            pendingReactionRepo: pendingReactionRepo,
            pendingKeyRepairRepo: pendingKeyRepairRepo,
            historyGapRepairRepo: historyGapRepairRepo,
            requestGroupKeyRepair: requestGroupKeyRepair,
            selfPeerId: identity?.peerId,
            // Phase 2: fast first page on the resume budget; feeds ack
            // eligibility. Remaining pages drain after the recovery gate.
            drainAllPages: false,
          );
          firstGroupDrainSuccessful = groupDrainResult.isSuccessful;
          drainHasMorePages = groupDrainResult.hasMorePages;
          final groupDrainMs = DateTime.now()
              .difference(groupDrainStart)
              .inMilliseconds;
          debugPrint(
            '[RESUME] Step 3c: drainGroupOfflineInbox done '
            '(errors=${groupDrainResult.errorCount}, took ${groupDrainMs}ms)',
          );
        }

        // 269: duplicate replay enrichment commits attachment rows during the
        // inbox drain. Run the shared durable download coordinator only after
        // that first bounded page has settled, so the same resume can recover
        // newly enriched and previously interrupted ordinary group media.
        // The account-migration gate and bridge re-prime have already passed.
        if (retryIncompleteGroupDownloadsFn != null) {
          try {
            final count = await retryIncompleteGroupDownloadsFn();
            if (kDebugMode) {
              debugPrint(
                '[RESUME] Step 3c.1: retryIncompleteGroupDownloads=$count',
              );
            }
          } catch (e) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_DOWNLOADS_RESUME_ERROR',
              details: {'error': e.toString()},
            );
          }
        }

        if (needsGroupRecovery &&
            rejoinResult.canAcknowledgeGroupRecovery &&
            groupDrainResult.isSuccessful) {
          final ackStart = DateTime.now();
          debugPrint(
            '[RESUME] Step 3c.1: callGroupAcknowledgeRecovery() starting...',
          );
          await callGroupAcknowledgeRecovery(bridge);
          final ackMs = DateTime.now().difference(ackStart).inMilliseconds;
          debugPrint(
            '[RESUME] Step 3c.1: callGroupAcknowledgeRecovery() done '
            '(took ${ackMs}ms)',
          );
        } else if (needsGroupRecovery &&
            rejoinResult.canAcknowledgeGroupRecovery &&
            !groupDrainResult.isSuccessful) {
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED',
            details: {'reason': 'group_inbox_not_drained'},
          );
        }
      });

      // Phase 2: drain the long tail OUTSIDE the gate (fire-and-forget) only
      // when the fast first page left more pages on the relay. The recovery ack
      // above only cleared the node's needsGroupRecovery flag (not the relay
      // inbox) and the cursor advanced atomically, so this resumes from page 2
      // without re-processing page 1 and without blocking group mutations
      // behind the gate. Pages it does not reach are drained by a later
      // resume/retrier pass via the same persisted cursor.
      if (drainHasMorePages) {
        final continuation = drainGroupOfflineInboxContinuation(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
          groupMessageListener: groupMessageListener,
          mediaAttachmentRepo: mediaAttachmentRepo,
          reactionRepo: reactionRepo,
          pendingReactionRepo: pendingReactionRepo,
          pendingKeyRepairRepo: pendingKeyRepairRepo,
          historyGapRepairRepo: historyGapRepairRepo,
          requestGroupKeyRepair: requestGroupKeyRepair,
          selfPeerId: continuationSelfPeerId,
        );
        if (awaitCanonicalInboxDrains) {
          final result = await continuation;
          canonicalInboxDrainsComplete =
              canonicalInboxDrainsComplete &&
              result.isSuccessful &&
              !result.hasMorePages;
        } else {
          unawaited(continuation);
        }
      } else {
        canonicalInboxDrainsComplete =
            canonicalInboxDrainsComplete && firstGroupDrainSuccessful;
      }
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
        canRejoinForExitIntent: canRejoinForExitIntent,
        processExitIntent: processExitIntent,
      );
      final rejoinMs = DateTime.now().difference(rejoinStart).inMilliseconds;
      groupReregisterMs = rejoinMs;
      debugPrint(
        '[RESUME] Step 3b: rejoinGroupTopics done '
        '(joined=${rejoinResult.joinedGroupCount}, '
        'skippedNoKey=${rejoinResult.skippedNoKeyCount}, '
        'errors=${rejoinResult.errorCount}, took ${rejoinMs}ms)',
      );

      // 123 S1 — after rejoin, reconcile any missed TERMINAL dissolve (this
      // branch has no group message repo, but the dissolve probe only needs the
      // listener + bridge + group repo). AFTER rejoin so active groups
      // re-subscribe immediately.
      final groupMsgListener = groupMessageListener;
      if (groupMsgListener != null) {
        final identity = await identityRepo?.loadIdentity();
        await reconcileMissedGroupDissolves(
          bridge: bridge,
          groupRepo: groupRepo,
          groupMessageListener: groupMsgListener,
          selfPeerId: identity?.peerId,
        );
      }

      if (needsGroupRecovery && rejoinResult.canAcknowledgeGroupRecovery) {
        emitFlowEvent(
          layer: 'FL',
          event: 'APP_LIFECYCLE_RESUME_GROUP_ACK_SKIPPED',
          details: {'reason': 'missing_group_message_repository'},
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
      // Phase 1b: hold the recovery gate across the outbound-repair follow-ons
      // (recover-stuck, upload retry, failed-message retry) so
      // isGroupRecoveryInProgress() stays true while resume re-sends group
      // messages — matching the rejoin/drain/ack window above and the 30s
      // continuity sweep — and so these resends cannot overlap a concurrent
      // recovery pass (the serialized gate queues instead of interleaving).
      // Per-step try/catch fault isolation is preserved. Steps 8a-8i (including
      // finding-02's key-repair) stay outside: they are not message resends.
      await runWithGroupRecoveryGate(() async {
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
              debugPrint(
                '[RESUME] Step 3e: retryIncompleteGroupUploads=$count',
              );
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
              debugPrint(
                '[RESUME] Step 3f: retryFailedGroupMessages ERROR: $e',
              );
            }
          }
        }
      });
    }

    // 4. Retry incomplete key exchanges (contacts without ML-KEM key)
    if (contactRepo != null && identityRepo != null) {
      final retryStart = DateTime.now();
      debugPrint('[RESUME] Step 4: retryIncompleteKeyExchanges() starting...');
      try {
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
      } catch (e) {
        final retryMs = DateTime.now().difference(retryStart).inMilliseconds;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_KEY_EXCHANGES_RESUME_ERROR',
          details: {'errorType': e.runtimeType.toString()},
        );
        debugPrint(
          '[RESUME] Step 4: retryIncompleteKeyExchanges() error '
          'after ${retryMs}ms (${e.runtimeType})',
        );
      }
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
      try {
        final retried = await retryPendingPostMediaUploads();
        final mediaRetryMs = DateTime.now()
            .difference(mediaRetryStart)
            .inMilliseconds;
        debugPrint(
          '[RESUME] Step 6: retryPendingPostMediaUploads() done '
          '(retried=$retried, took ${mediaRetryMs}ms)',
        );
      } catch (e) {
        final mediaRetryMs = DateTime.now()
            .difference(mediaRetryStart)
            .inMilliseconds;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_PENDING_POST_MEDIA_UPLOADS_RESUME_ERROR',
          details: {'errorType': e.runtimeType.toString()},
        );
        debugPrint(
          '[RESUME] Step 6: retryPendingPostMediaUploads() error '
          'after ${mediaRetryMs}ms (${e.runtimeType})',
        );
      }
    }

    if (retryPendingPostDeliveries != null) {
      final postRetryStart = DateTime.now();
      debugPrint('[RESUME] Step 7: retryPendingPostDeliveries() starting...');
      try {
        final retried = await retryPendingPostDeliveries();
        final postRetryMs = DateTime.now()
            .difference(postRetryStart)
            .inMilliseconds;
        debugPrint(
          '[RESUME] Step 7: retryPendingPostDeliveries() done '
          '(retried=$retried, took ${postRetryMs}ms)',
        );
      } catch (e) {
        final postRetryMs = DateTime.now()
            .difference(postRetryStart)
            .inMilliseconds;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_PENDING_POST_DELIVERIES_RESUME_ERROR',
          details: {'errorType': e.runtimeType.toString()},
        );
        debugPrint(
          '[RESUME] Step 7: retryPendingPostDeliveries() error '
          'after ${postRetryMs}ms (${e.runtimeType})',
        );
      }
    }

    // Step 8 (NEW): Message recovery sweep -- strict ordering required.
    //
    // ORDERING CONTRACT (see Part D top-level callout):
    //   1. recoverStuckSendingMessages  -- 'sending' -> 'failed'
    //   2. retryIncompleteUploads       -- re-upload 'upload_pending' attachments
    //   3. drainDirectInboxCustody      -- replay immutable sender custody
    //   4. retryFailedMessages          -- retry 'failed' messages (now with uploaded media)
    //   5. retryUnackedMessages         -- retry 'sent' but unacked messages
    //   6. verifyInboxCustody           -- re-prove unconfirmed inbox custody
    //
    // Each step is fault-isolated: a throw in step N does not skip step N+1.

    // Step 8a: Recover stuck 'sending' messages -> 'failed'
    if (recoverStuckSendingMessagesFn != null) {
      try {
        final count = await recoverStuckSendingMessagesFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RECOVER_STUCK_SENDING_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages ERROR: $e');
        }
      }
    }

    // Step 8b: Re-upload incomplete attachment uploads (Part G).
    // MUST run after 8a (parent messages now 'failed') and BEFORE 8c
    // (so attachments have downloadStatus='done' when retryFailedMessages reads them).
    if (retryIncompleteUploadsFn != null) {
      try {
        final count = await retryIncompleteUploadsFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8b: retryIncompleteUploads=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOADS_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8b: retryIncompleteUploads ERROR: $e');
        }
        // Non-fatal: continue to retryFailedMessages -- messages without
        // completed uploads will be retried as text-only or skipped by
        // Part F's decision tree, which is still better than not retrying at all.
      }
    }

    // Step 8b.1: Retry immutable direct-text relay custody before either message
    // rebuild family. This is independently fault-isolated so one poison/drain
    // failure cannot suppress failed or unacked recovery on resume.
    if (drainDirectInboxCustodyOutboxFn != null) {
      try {
        final count = await drainDirectInboxCustodyOutboxFn();
        if (kDebugMode) {
          debugPrint(
            '[RESUME] Step 8b.1: drainDirectInboxCustodyOutbox=$count',
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DRAIN_DIRECT_INBOX_CUSTODY_RESUME_ERROR',
          details: {'errorType': e.runtimeType.toString()},
        );
        if (kDebugMode) {
          debugPrint(
            '[RESUME] Step 8b.1: drainDirectInboxCustodyOutbox ERROR '
            '(${e.runtimeType})',
          );
        }
      }
    }

    // Step 8c: Retry failed messages (with now-uploaded media attachments)
    if (retryFailedMessagesFn != null) {
      try {
        final count = await retryFailedMessagesFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8c: retryFailedMessages=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8c: retryFailedMessages ERROR: $e');
        }
      }
    }

    // Step 8d: Retry sent-but-unacked messages
    if (retryUnackedMessagesFn != null) {
      try {
        final count = await retryUnackedMessagesFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8d: retryUnackedMessages=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_MESSAGES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8d: retryUnackedMessages ERROR: $e');
        }
      }
    }

    // Step 8e: Verify unconfirmed relay-inbox custody.
    if (verifyInboxCustodyFn != null) {
      try {
        final count = await verifyInboxCustodyFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8e: verifyInboxCustody=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'INBOX_CUSTODY_VERIFY_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8e: verifyInboxCustody ERROR: $e');
        }
      }
    }

    // Step 8f: Retry pending introduction deliveries
    if (retryPendingIntroductionDeliveriesFn != null) {
      try {
        final count = await retryPendingIntroductionDeliveriesFn();
        if (kDebugMode) {
          debugPrint(
            '[RESUME] Step 8f: retryPendingIntroductionDeliveries=$count',
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
            '[RESUME] Step 8f: retryPendingIntroductionDeliveries ERROR: $e',
          );
        }
      }
    }

    // Step 8g: Retry failed group inbox stores (Section 4)
    if (retryFailedGroupInboxStoresFn != null) {
      try {
        final count = await retryFailedGroupInboxStoresFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8g: retryFailedGroupInboxStores=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_GROUP_INBOX_STORES_RESUME_ERROR',
          details: {'error': e.toString()},
        );
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8g: retryFailedGroupInboxStores ERROR: $e');
        }
      }
    }

    // Step 8h: Slice 2 (Finding 03) — drain deferred group key distributions so
    // keyless bystanders that regained a key while backgrounded converge.
    if (drainPendingKeyDistributionsFn != null) {
      try {
        final count = await drainPendingKeyDistributionsFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8h: drainPendingKeyDistributions=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DRAIN_PENDING_KEY_DISTRIBUTIONS_RESUME_ERROR',
          details: {'error': e.toString()},
        );
      }
    }

    // Step 8i: Finding 02 (UDM-B) — sweep ALL persisted pending group-key
    // repairs so they re-fire after resume even without a fresh
    // key-update/invite event for their exact (group, epoch). Ungated (matches
    // the Step 8h precedent); internally cheap when nothing is pending. Runs
    // AFTER the Step-3c group inbox drain and the Step 8h key-distribution drain
    // so any freshly-arrived keys are already present.
    if (retryAllPendingGroupKeyRepairsFn != null) {
      try {
        final count = await retryAllPendingGroupKeyRepairsFn();
        if (kDebugMode) {
          debugPrint('[RESUME] Step 8i: retryAllPendingGroupKeyRepairs=$count');
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_ALL_PENDING_GROUP_KEY_REPAIRS_RESUME_ERROR',
          details: {'error': e.toString()},
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
      details: {
        'bridgeWasHealthy': bridgeOk,
        'totalMs': totalMs,
        ...?(groupReregisterMs == null
            ? null
            : {'groupReregisterMs': groupReregisterMs}),
      },
    );

    onCanonicalInboxDrainsSettled?.call(canonicalInboxDrainsComplete);
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
    onCanonicalInboxDrainsSettled?.call(false);
    return null;
  } finally {
    if (!hadPendingResumeStarted) {
      readinessProofRecorder?.clearResumeStarted();
    }
  }
}
