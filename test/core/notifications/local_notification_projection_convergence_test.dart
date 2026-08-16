import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_read_acknowledgement_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_reconciliation_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/android_recovery_alert_disposition.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_local_notification_effect_coordinator.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger.dart';
import 'package:flutter_app/core/notifications/local_notification_ledger_store.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome.dart';
import 'package:flutter_app/core/notifications/notification_completed_outcome_correlation.dart';
import 'package:flutter_app/core/notifications/canonical_recovery_runtime.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/groups/domain/models/group_notification_display_outbox_entry.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../shared/fakes/fake_notification_service.dart';

const _groupId = 'group-plan-372';
const _selfPeerId = 'peer-self';
const _senderPeerId = 'peer-sender';
const _physicalPeerId = 'physical-peer-plan-372';
const _directPeerId = 'direct-peer-plan-372';
const _timestamp = '2026-08-16T12:00:00.000Z';
const _completedAt = '2026-08-16T12:00:01.000Z';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'local-notification-projection-convergence-',
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'TC-372-04 final canonical facts and revision CAS prevent resurrection and stale cancellation',
    () async {
      await _verifyGroupFinalCanonicalReadBarrier(root);
      await _verifyGroupFinalCanonicalDeleteBarrier(root);
      await _verifyGroupMembershipRepairDeleteBarrier(root);
      await _verifyDirectFinalCanonicalReadBarrier(root);
      await _verifyDirectGenerationSiblingFence(root);
    },
  );

  test(
    'TC-372-05 one claim owner and deterministic publishing recovery across isolate arrival orders',
    () async {
      await _verifyGroupSingleEffectAndExactHandoff(root);
      await _verifyDirectSingleEffectAndExactHandoff(root);
      await _verifySpawnedIsolateOneOwner(root);
      await _verifyPublishingCrashCutMatrix(root);
      await _verifyDirectPublishingActiveProofRecovery(root);
    },
  );

  test(
    'TC-372-06 effect-terminal replay settles direct and group custody once and emits only approved enabled outcome',
    () async {
      await _verifyGroupEffectTerminalSqlReplay(root);
      await _verifyDirectEffectTerminalFreshProcessReplay(root);
      await _verifyDirectSettledSqlRetirementRecovery(root);
      await _verifyDirectReactionTerminalMutationCrashReplay(root);
    },
  );

  test(
    'TC-375-05 fixed generic stays silent in both orders while deletion ambiguity is never downgraded',
    () async {
      await _verifyFixedWakeSoundContractAcrossOrders();
      await _verifyFixedPointRetirementOrdering();
    },
  );
}

/// Mutable Plan-374 native marker surface: the one durable trigger record
/// whose kind and audible disposition the Dart tone gate reads live.
final class _FakeRecoveryMarker {
  int generation = 0;
  String? kind;
  bool mayHaveAlerted = false;
  bool present = false;
  bool throwOnRead = false;
  int reads = 0;

  Future<bool> readGenericMayHaveAlerted() async {
    reads++;
    if (throwOnRead) throw StateError('ambiguous native callback');
    if (!present) return false;
    return mayHaveAlerted;
  }

  void recordFixedWake() {
    generation += 1;
    // A fixed trigger is always requested silent; coalescing over an audible
    // ambiguity preserves it and never downgrades true (native TC-375-02).
    mayHaveAlerted = present && mayHaveAlerted;
    kind = 'fixed_wake';
    present = true;
  }

  void recordDeletion() {
    generation += 1;
    mayHaveAlerted = true;
    kind = 'deleted_batch';
    present = true;
  }
}

Future<void> _verifyFixedWakeSoundContractAcrossOrders() async {
  final marker = _FakeRecoveryMarker();
  final visibility = _BackgroundVisibility();

  Future<bool> lastShowSilent({NotificationToneTracker? tracker}) async {
    final service = FakeNotificationService();
    final result = await runWithAndroidRecoveryGenericAlertDisposition(
      reader: marker.readGenericMayHaveAlerted,
      action: () => maybeShowNotification(
        notificationService: service,
        appVisibility: visibility,
        contactPeerId: _directPeerId,
        senderUsername: 'Alice',
        messageText: 'Hello',
        toneTracker: tracker,
        backgroundDuplicateGuardDelay: Duration.zero,
      ),
    );
    expect(result, NotificationPresentationResult.osPosted);
    return service.shown.single.silent;
  }

  // Fixed-before-canonical: the identity-free fixed marker is explicitly
  // silent work, so the canonical event keeps its normal exact tone.
  marker.recordFixedWake();
  expect(marker.kind, 'fixed_wake');
  expect(marker.mayHaveAlerted, isFalse);
  expect(
    await lastShowSilent(),
    isFalse,
    reason: 'fixed-only work never suppresses the canonical tone',
  );

  // Canonical-before-fixed: a canonical tone already played, then a fixed
  // wake arrives; the next canonical event still arbitrates normally, so at
  // most one requested sound exists per arbitration window in both orders.
  final tracker = NotificationToneTracker();
  marker.present = false;
  expect(await lastShowSilent(tracker: tracker), isFalse);
  marker.recordFixedWake();
  expect(
    await lastShowSilent(tracker: tracker),
    isTrue,
    reason: 'the incumbent per-conversation tone window is not bypassed',
  );

  // A coalesced deletion marker may already have alerted: the final gate
  // retains the incumbent conservative silence for canonical work.
  marker.recordDeletion();
  expect(await lastShowSilent(), isTrue);

  // Fixed coalescing over that ambiguity never downgrades it.
  marker.recordFixedWake();
  expect(marker.kind, 'fixed_wake');
  expect(marker.mayHaveAlerted, isTrue);
  expect(
    await lastShowSilent(),
    isTrue,
    reason: 'a preserved deletion disposition keeps conservative silence',
  );

  // An ambiguous native callback fails toward silence, never toward a second
  // sound, and never synthesizes a correlation or recent-sound horizon.
  marker.throwOnRead = true;
  expect(await lastShowSilent(), isTrue);
  marker.throwOnRead = false;

  // Outside the one installed recovery generation the ambient gate is inert.
  final foregroundService = FakeNotificationService();
  await maybeShowNotification(
    notificationService: foregroundService,
    appVisibility: visibility,
    contactPeerId: _directPeerId,
    senderUsername: 'Alice',
    messageText: 'Hello',
    backgroundDuplicateGuardDelay: Duration.zero,
  );
  expect(foregroundService.shown.single.silent, isFalse);
  expect(marker.reads, greaterThanOrEqualTo(5));
}

/// The reserved generic card is retired only inside the exact marker+binding
/// acknowledgement after every page and custody store converges; partial
/// work, a newer generation, or enqueue-failure periodic continuation retains
/// both the marker and the card.
Future<void> _verifyFixedPointRetirementOrdering() async {
  const binding =
      'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final marker = _FakeRecoveryMarker()..recordFixedWake();
  final cancelledCards = <int>[];
  var custodyRows = 2;
  var directPages = 0;

  CanonicalRecoveryRuntime buildRuntime({required bool convergeCustody}) =>
      CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => binding,
        loadPendingMarker: () async => marker.present
            ? CanonicalRecoveryMarker(
                generation: marker.generation,
                binding: binding,
              )
            : null,
        acquireSession: ({required binding, required reason}) async =>
            _FixedPointSession(
              drainDirect: () async {
                directPages++;
                if (directPages == 1) {
                  return const CanonicalRecoveryDrainOutcome(
                    isSuccessful: true,
                    hasMore: true,
                  );
                }
                return const CanonicalRecoveryDrainOutcome(
                  isSuccessful: true,
                  hasMore: false,
                );
              },
              settle: () async {
                if (convergeCustody) custodyRows = 0;
                return CanonicalRecoveryProjectionOutcome(
                  isSuccessful: true,
                  hasPendingWork: custodyRows != 0,
                );
              },
            ),
        acknowledgeMarker: (acked, {authorityRevision}) async {
          // Exact CAS: only the current generation under the current binding
          // clears, and the reserved card cancels inside that callback.
          if (!marker.present ||
              acked.generation != marker.generation ||
              acked.binding != binding) {
            return false;
          }
          marker.present = false;
          cancelledCards.add(acked.generation);
          return true;
        },
      );

  // Partial custody retains marker and card: no ACK, no cancellation.
  final retained = await buildRuntime(
    convergeCustody: false,
  ).run(CanonicalRecoveryReason.fixedWake);
  expect(retained.disposition, CanonicalRecoveryDisposition.retry);
  expect(marker.present, isTrue);
  expect(cancelledCards, isEmpty);
  expect(directPages, greaterThanOrEqualTo(2), reason: 'multi-page drain ran');

  // Periodic continuation after an enqueue failure adopts the same durable
  // marker and performs the exact retirement only at full convergence.
  final converged = await buildRuntime(
    convergeCustody: true,
  ).run(CanonicalRecoveryReason.periodicSweep);
  expect(converged.disposition, CanonicalRecoveryDisposition.succeeded);
  expect(marker.present, isFalse);
  expect(cancelledCards, [1]);

  // A stale ACK for a superseded generation cannot clear the newer marker or
  // cancel its card.
  marker.recordFixedWake();
  final staleGeneration = marker.generation;
  marker.recordFixedWake();
  expect(marker.generation, greaterThan(staleGeneration));
  final stale =
      await CanonicalRecoveryRuntime(
        loadCurrentBinding: () async => binding,
        loadPendingMarker: () async => CanonicalRecoveryMarker(
          generation: marker.generation,
          binding: binding,
        ),
        acquireSession: ({required binding, required reason}) async =>
            _FixedPointSession(
              drainDirect: () async => const CanonicalRecoveryDrainOutcome(
                isSuccessful: true,
                hasMore: false,
              ),
              settle: () async => const CanonicalRecoveryProjectionOutcome(
                isSuccessful: true,
                hasPendingWork: false,
              ),
            ),
        acknowledgeMarker: (acked, {authorityRevision}) async {
          if (acked.generation != staleGeneration) return false;
          cancelledCards.add(acked.generation);
          return true;
        },
      ).run(
        CanonicalRecoveryReason.fixedWake,
        expectedBinding: binding,
        expectedMarker: CanonicalRecoveryMarker(
          generation: marker.generation,
          binding: binding,
        ),
      );
  expect(stale.disposition, CanonicalRecoveryDisposition.retry);
  expect(stale.failureReason, 'exact_ack_failed');
  expect(cancelledCards, [1], reason: 'a stale ACK cancels nothing');
}

final class _FixedPointSession implements CanonicalRecoverySession {
  _FixedPointSession({required this.drainDirect, required this.settle});

  final Future<CanonicalRecoveryDrainOutcome> Function() drainDirect;
  final Future<CanonicalRecoveryProjectionOutcome> Function() settle;

  @override
  Future<void> ensureRuntimeReady() async {}

  @override
  Future<void> ensureTransportHealthy() async {}

  @override
  Future<CanonicalRecoveryDrainOutcome> drainDirectInbox() => drainDirect();

  @override
  Future<CanonicalRecoveryDrainOutcome> drainGroupInbox() async =>
      const CanonicalRecoveryDrainOutcome(isSuccessful: true, hasMore: false);

  @override
  Future<CanonicalRecoveryProjectionOutcome> settleNotificationProjection() =>
      settle();

  @override
  Future<void> sealAdmissionAndAwaitInFlight() async {}

  @override
  Future<void> stopGroupMessageListener() async {}

  @override
  Future<void> disposeProjectionOwners() async {}

  @override
  Future<bool> quiesceRuntime() async => true;

  @override
  Future<bool> closeDatabase() async => true;

  @override
  Future<bool> releaseOwnership({required bool databaseClosed}) async => true;
}

Future<void> _verifyGroupFinalCanonicalReadBarrier(Directory root) async {
  final db = await _openDatabase('${root.path}/group-tc372-04.db');
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'group-message-read-race';
  var entry = await _stageReadyGroupMessage(db, messageId: messageId);
  final effect = await _GroupEffectFixture.open(
    Directory('${root.path}/group-tc372-04-ledger'),
    messageId: messageId,
  );
  await effect.initialize();
  entry = await _bindGroupDurableCorrelation(
    db,
    entry,
    effect.eventCorrelation,
  );
  BackgroundGroupNotificationPostShowDecision? finalDecision;
  var nativeEffects = 0;
  final context = effect.context(
    readFinal: () async {
      await dbRecordExactGroupNotificationReadAcknowledgement(
        db,
        groupId: _groupId,
        contentKind: 'message',
        eventIdentity: effect.eventCorrelation,
        generation: effect.contentGeneration,
        acknowledgedAt: _completedAt,
      );
      final acknowledgement =
          await dbLoadExactGroupNotificationReadAcknowledgement(
            db,
            groupId: _groupId,
            contentKind: 'message',
            eventIdentity: effect.eventCorrelation,
            generation: effect.contentGeneration,
          );
      final messageRows = await db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
        limit: 1,
      );
      finalDecision = evaluateBackgroundGroupNotificationPostShowState(
        comparand: const BackgroundGroupMessageNotificationComparand(
          groupId: _groupId,
          messageId: messageId,
          senderPeerId: _senderPeerId,
        ),
        localPeerId: _selfPeerId,
        groupRow: const <String, Object?>{
          'id': _groupId,
          'type': 'chat',
          'is_muted': 0,
          'is_archived': 0,
          'is_dissolved': 0,
        },
        localMemberRow: const <String, Object?>{
          'group_id': _groupId,
          'peer_id': _selfPeerId,
        },
        messageRow: messageRows.single,
        readAcknowledgementRow: acknowledgement == null
            ? null
            : const <String, Object?>{
                'group_id': _groupId,
                'content_kind': 'message',
                // The pure evaluator compares canonical/raw content identity;
                // the SQL lookup above is bound to the durable correlation.
                'event_identity': messageId,
              },
      );
      return finalDecision == BackgroundGroupNotificationPostShowDecision.read
          ? DurableLocalNotificationCanonicalDisposition.read
          : DurableLocalNotificationCanonicalDisposition.retryableUnknown;
    },
  );
  final result = await effect.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: effect.identity,
    conversationKey: 'group:$_groupId',
    notificationId: effect.notificationId,
    metadata: effect.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  expect(finalDecision, BackgroundGroupNotificationPostShowDecision.read);
  expect(
    result.disposition,
    DurableLocalNotificationEffectDisposition.cancelled,
  );
  expect(nativeEffects, 0);
  final readRecord = await effect.registry.lookupExactEffect(
    currentOpaqueBinding: effect.binding,
    eventCorrelation: effect.eventCorrelation,
    conversationDigest: effect.identity.digest,
    notificationId: effect.notificationId,
    contentGeneration: effect.contentGeneration,
  );
  expect(readRecord?.readState, LocalNotificationReadState.read);
  expect(
    await _handoffGroupMessage(
      db,
      entry,
      durableEventCorrelation: effect.eventCorrelation,
      outcome: null,
    ),
    DurableLocalNotificationSqlHandoffResult.committed,
  );
  expect(
    (await effect.registry.settleSqlReadyEffect(
      currentOpaqueBinding: effect.binding,
      eventCorrelation: effect.eventCorrelation,
      expectedRevision: result.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(
    await _retireGroupMessageAfterSettlement(
      db,
      entry,
      durableEventCorrelation: effect.eventCorrelation,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNull,
  );
  expect(
    await dbLoadGroupNotificationReconciliationOutboxEntry(db, _groupId),
    isNotNull,
  );
}

Future<void> _verifyGroupFinalCanonicalDeleteBarrier(Directory root) async {
  final db = await _openDatabase('${root.path}/group-delete-barrier.db');
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'group-message-delete-race';
  const siblingMessageId = 'group-message-newer-sibling';
  var entry = await _stageReadyGroupMessage(db, messageId: messageId);
  await _stageReadyGroupMessage(db, messageId: siblingMessageId);
  final effect = await _GroupEffectFixture.open(
    Directory('${root.path}/group-delete-barrier-ledger'),
    messageId: messageId,
  );
  await effect.initialize();
  entry = await _bindGroupDurableCorrelation(
    db,
    entry,
    effect.eventCorrelation,
  );
  var terminalEntry = entry;
  BackgroundGroupNotificationPostShowDecision? finalDecision;
  var nativeEffects = 0;
  final result = await effect.registry.runFinalEffect(
    context: effect.context(
      readFinal: () async {
        // runFinalEffect invokes this only after PUBLISHING is durable. The
        // canonical transaction retains exact READY and writes the deletion
        // tombstone before this final decision is returned.
        await dbDeleteGroupMessage(db, messageId);
        terminalEntry = GroupNotificationDisplayOutboxEntry.fromMap(
          (await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId))!,
        );
        final deletionRows = await db.query(
          'group_message_local_deletions',
          where: 'message_id = ? AND group_id = ?',
          whereArgs: const <Object?>[messageId, _groupId],
          limit: 1,
        );
        finalDecision = evaluateBackgroundGroupNotificationPostShowState(
          comparand: const BackgroundGroupMessageNotificationComparand(
            groupId: _groupId,
            messageId: messageId,
            senderPeerId: _senderPeerId,
          ),
          localPeerId: _selfPeerId,
          groupRow: const <String, Object?>{
            'id': _groupId,
            'type': 'chat',
            'is_muted': 0,
            'is_archived': 0,
            'is_dissolved': 0,
          },
          localMemberRow: const <String, Object?>{
            'group_id': _groupId,
            'peer_id': _selfPeerId,
          },
          messageRow: null,
          messageDeletionRow: deletionRows.single,
        );
        return finalDecision ==
                BackgroundGroupNotificationPostShowDecision.retire
            ? DurableLocalNotificationCanonicalDisposition.cancelled
            : DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      },
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: effect.identity,
    conversationKey: 'group:$_groupId',
    notificationId: effect.notificationId,
    metadata: effect.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  expect(finalDecision, BackgroundGroupNotificationPostShowDecision.retire);
  expect(
    result.disposition,
    DurableLocalNotificationEffectDisposition.cancelled,
  );
  expect(nativeEffects, 0, reason: 'post-PUBLISHING delete forbids stale post');
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNotNull,
    reason: 'canonical deletion retains exact raw READY until settlement',
  );
  expect(terminalEntry.revision, entry.revision + 1);
  expect(
    isGroupNotificationDisplayCanonicalRetiredMarker(
      terminalEntry.lastAttemptAt,
    ),
    isTrue,
  );
  expect(
    groupNotificationDisplayDurableCorrelationFromMarker(
      terminalEntry.lastAttemptAt,
    ),
    effect.eventCorrelation,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, siblingMessageId),
    isNotNull,
    reason: 'targeted deletion must not retire a newer sibling',
  );
  expect(
    await _handoffGroupMessage(
      db,
      terminalEntry,
      durableEventCorrelation: effect.eventCorrelation,
      outcome: null,
    ),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await effect.registry.settleSqlReadyEffect(
      currentOpaqueBinding: effect.binding,
      eventCorrelation: effect.eventCorrelation,
      expectedRevision: result.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(
    await _retireGroupMessageAfterSettlement(
      db,
      terminalEntry,
      durableEventCorrelation: effect.eventCorrelation,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNull,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, siblingMessageId),
    isNotNull,
  );
}

Future<void> _verifyGroupMembershipRepairDeleteBarrier(Directory root) async {
  final databasePath = '${root.path}/group-membership-repair.db';
  var db = await _openDatabase(databasePath);
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'group-message-membership-repair-race';
  var entry = await _stageReadyGroupMessage(db, messageId: messageId);
  final ledgerDirectory = Directory(
    '${root.path}/group-membership-repair-ledger',
  );
  final effect = await _GroupEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await effect.initialize();
  entry = await _bindGroupDurableCorrelation(
    db,
    entry,
    effect.eventCorrelation,
  );
  var terminalEntry = entry;
  var nativeEffects = 0;
  final terminal = await effect.registry.runFinalEffect(
    context: effect.context(
      readFinal: () async {
        await dbDeleteGroupMessageForMembershipRepair(db, messageId);
        terminalEntry = GroupNotificationDisplayOutboxEntry.fromMap(
          (await dbLoadGroupNotificationDisplayOutboxEntry(db, messageId))!,
        );
        return DurableLocalNotificationCanonicalDisposition.cancelled;
      },
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: effect.identity,
    conversationKey: 'group:$_groupId',
    notificationId: effect.notificationId,
    metadata: effect.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  expect(nativeEffects, 0);
  expect(
    terminal.disposition,
    DurableLocalNotificationEffectDisposition.cancelled,
  );
  expect(
    await db.query(
      'group_message_local_deletions',
      where: 'message_id = ? AND group_id = ?',
      whereArgs: const <Object?>[messageId, _groupId],
    ),
    isEmpty,
    reason: 'membership repair intentionally has no user deletion tombstone',
  );
  expect(
    groupNotificationDisplayDurableCorrelationFromMarker(
      terminalEntry.lastAttemptAt,
    ),
    effect.eventCorrelation,
  );

  // Crash after SQL transaction A / ledger EFFECT_TERMINAL. A later process
  // can restore buffered canonical content, but that must not reopen this old
  // correlation-bound notification attempt.
  await db.close();
  db = await _openDatabase(databasePath);
  await db.insert('group_messages', <String, Object?>{
    'id': messageId,
    'group_id': _groupId,
    'sender_peer_id': _senderPeerId,
    'text': 'restored after membership repair',
    'timestamp': _timestamp,
    'created_at': _timestamp,
  });
  final restarted = await _GroupEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: effect.notificationId,
  );
  var restartFinalReads = 0;
  final replay = await restarted.registry.runFinalEffect(
    context: restarted.context(
      readFinal: () async {
        restartFinalReads += 1;
        return DurableLocalNotificationCanonicalDisposition.eligible;
      },
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: restarted.identity,
    conversationKey: 'group:$_groupId',
    notificationId: restarted.notificationId,
    metadata: restarted.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    replay.disposition,
    DurableLocalNotificationEffectDisposition.cancelled,
  );
  expect(restartFinalReads, 0, reason: 'terminal replay is immutable');
  expect(nativeEffects, 0, reason: 'restart never re-enters native display');
  expect(
    await _handoffGroupMessage(
      db,
      terminalEntry,
      durableEventCorrelation: restarted.eventCorrelation,
      outcome: null,
    ),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await restarted.registry.settleSqlReadyEffect(
      currentOpaqueBinding: restarted.binding,
      eventCorrelation: restarted.eventCorrelation,
      expectedRevision: replay.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(
    await _retireGroupMessageAfterSettlement(
      db,
      terminalEntry,
      durableEventCorrelation: restarted.eventCorrelation,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, messageId),
    isNull,
  );
}

Future<void> _verifyDirectGenerationSiblingFence(Directory root) async {
  const messageId = 'direct-message-generation-race';
  final directory = Directory('${root.path}/direct-generation-race-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  var retiredPriorGeneration = 0;
  final newerMetadata = ConversationNotificationContentMetadata(
    kind: ConversationNotificationContentKind.message,
    eventIdentity: _digest('direct-newer-event'),
    generation: 'ledger:${_digest('direct-newer-generation')}',
  );
  var nativeEffects = 0;
  final result = await fixture.registry.runFinalEffect(
    context: fixture.context(
      readFinal: () async {
        await File(
          '${directory.path}/${fixture.notificationId}'
          '${DurableConversationNotificationIdRegistry.contentKindFileSuffix}',
        ).writeAsString(jsonEncode(newerMetadata.toJson()), flush: true);
        return DurableLocalNotificationCanonicalDisposition.eligible;
      },
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async => retiredPriorGeneration += 1,
    publishNative: () async => nativeEffects += 1,
  );

  expect(
    result.disposition,
    DurableLocalNotificationEffectDisposition.retryable,
  );
  expect(nativeEffects, 0);
  expect(
    retiredPriorGeneration,
    1,
    reason: 'only the pre-barrier prior generation is retired',
  );
  expect(
    await fixture.registry.lookupContentMetadata(
      conversationKey: _directPeerId,
      notificationId: fixture.notificationId,
    ),
    newerMetadata,
  );
}

Future<void> _verifyDirectFinalCanonicalReadBarrier(Directory root) async {
  final db = await _openDatabase('${root.path}/direct-tc372-04-read.db');
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'direct-message-read-race';
  final entry = await _stageReadyDirectMessage(db, messageId: messageId);
  final effect = await _DirectEffectFixture.open(
    Directory('${root.path}/direct-tc372-04-read-ledger'),
    messageId: messageId,
  );
  await effect.initialize();
  var nativeEffects = 0;
  final result = await effect.registry.runFinalEffect(
    context: effect.context(
      readFinal: () async {
        expect(
          await db.update(
            'messages',
            const <String, Object?>{'read_at': _completedAt},
            where:
                'id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
                'AND timestamp = ? AND read_at IS NULL',
            whereArgs: const <Object?>[
              messageId,
              _directPeerId,
              _directPeerId,
              _timestamp,
            ],
          ),
          1,
        );
        final exactReady = await dbLoadDirectNotificationDisplayOutboxEntry(
          db,
          peerId: entry.peerId,
          eventKind: entry.eventKind,
          eventId: entry.eventId,
        );
        final message = (await db.query(
          'messages',
          columns: const <String>['read_at'],
          where:
              'id = ? AND contact_peer_id = ? AND sender_peer_id = ? '
              'AND timestamp = ?',
          whereArgs: const <Object?>[
            messageId,
            _directPeerId,
            _directPeerId,
            _timestamp,
          ],
          limit: 1,
        )).single;
        return exactReady?['readiness'] ==
                    DirectNotificationDisplayOutboxReadiness.ready &&
                message['read_at'] != null
            ? DurableLocalNotificationCanonicalDisposition.read
            : DurableLocalNotificationCanonicalDisposition.retryableUnknown;
      },
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: effect.identity,
    conversationKey: _directPeerId,
    notificationId: effect.notificationId,
    metadata: effect.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  expect(
    result.disposition,
    DurableLocalNotificationEffectDisposition.cancelled,
  );
  expect(nativeEffects, 0);
  final readRecord = await effect.registry.lookupExactEffect(
    currentOpaqueBinding: effect.binding,
    eventCorrelation: effect.eventCorrelation,
    conversationDigest: effect.identity.digest,
    notificationId: effect.notificationId,
    contentGeneration: effect.contentGeneration,
  );
  expect(readRecord?.readState, LocalNotificationReadState.read);
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await effect.registry.settleSqlReadyEffect(
      currentOpaqueBinding: effect.binding,
      eventCorrelation: effect.eventCorrelation,
      expectedRevision: result.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(await _retireDirectMessageAfterSettlement(db, entry), isTrue);
}

Future<void> _verifyDirectPublishingActiveProofRecovery(Directory root) async {
  const messageId = 'direct-publishing-active-proof';
  final directory = Directory('${root.path}/direct-publishing-recovery-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  final ambiguous = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => throw StateError('native outcome unknown'),
  );
  expect(
    ambiguous.disposition,
    DurableLocalNotificationEffectDisposition.ambiguous,
  );

  var recoveryNativeCalls = 0;
  final recovered = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async => fail('active proof must not retire'),
    publishNative: () async => recoveryNativeCalls += 1,
    activeNotificationIds: () async => <Object?>[fixture.notificationId],
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(recovered.currentNativeEntryAttempted, isFalse);
  expect(recoveryNativeCalls, 0, reason: 'exact active proof avoids republish');
}

Future<void> _verifySpawnedIsolateOneOwner(Directory root) async {
  const messageId = 'direct-spawned-isolate-one-owner';
  final directory = Directory('${root.path}/direct-isolate-race-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final nativeEntries = <String>[];
  final nativePort = ReceivePort();
  final subscription = nativePort.listen((message) {
    if (message is String) nativeEntries.add(message);
  });
  addTearDown(() async {
    await subscription.cancel();
    nativePort.close();
  });
  final arguments = <String, Object?>{
    'directory': directory.path,
    'messageId': messageId,
    'notificationId': fixture.notificationId,
    'nativePort': nativePort.sendPort,
  };

  final results = await Future.wait(<Future<Map<String, Object?>>>[
    _runDirectFinalEffectInNewIsolate(arguments),
    _runDirectFinalEffectInNewIsolate(arguments),
  ]);
  await Future<void>.delayed(Duration.zero);

  expect(
    results.map((result) => result['disposition']),
    everyElement(DurableLocalNotificationEffectDisposition.osPosted.name),
  );
  expect(
    results.map((result) => result['recordRevision']).toSet(),
    hasLength(1),
  );
  expect(
    results.where((result) => result['enteredNative'] == true),
    hasLength(1),
  );
  expect(nativeEntries, hasLength(1));
}

Future<Map<String, Object?>> _runDirectFinalEffectInNewIsolate(
  Map<String, Object?> arguments,
) => Isolate.run(() => _runDirectFinalEffectInSpawnedIsolate(arguments));

Future<Map<String, Object?>> _runDirectFinalEffectInSpawnedIsolate(
  Map<String, Object?> arguments,
) async {
  final directory = Directory(arguments['directory']! as String);
  final messageId = arguments['messageId']! as String;
  final notificationId = arguments['notificationId']! as int;
  final nativePort = arguments['nativePort']! as SendPort;
  final fixture = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: notificationId,
  );
  var enteredNative = false;
  final result = await fixture.registry.runFinalEffect(
    context: fixture.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async {
      enteredNative = true;
      nativePort.send(messageId);
    },
  );
  return <String, Object?>{
    'disposition': result.disposition.name,
    'recordRevision': result.receipt?.recordRevision,
    'enteredNative': enteredNative,
  };
}

Future<void> _verifyPublishingCrashCutMatrix(Directory root) async {
  await _verifyClaimedCrashCut(root);
  await _verifyOldCardRetirementCrashCut(root);
  await _verifyMarkerActivationCrashCut(root);
  await _verifyNativeEntryCrashCut(root);
  await _verifyNativeReturnCrashCut(root);
  await _verifyEffectTerminalCrashCut(root);
}

Future<void> _verifyClaimedCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-claimed';
  final directory = Directory('${root.path}/direct-crash-cut-claimed-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  final claimedAt = DateTime.utc(2026, 8, 16, 11, 58);
  final claimed = LocalNotificationRecordV1(
    eventCorrelation: fixture.eventCorrelation,
    conversationDigest: fixture.identity.digest,
    producerKind: LocalNotificationProducerKind.directMessage,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    readState: LocalNotificationReadState.unread,
    presentationState: LocalNotificationPresentationState.notEvaluated,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    notificationId: fixture.notificationId,
    contentGeneration: fixture.contentGeneration,
    lastEvaluatedLifecycle: LocalNotificationEvaluatedLifecycle.unknown,
    visibilityRevision: null,
    lifecycleGeneration: null,
    effectPhase: LocalNotificationEffectPhase.claimed,
    attemptKind: LocalNotificationAttemptKind.postOrUpdate,
    effectToken: 'c' * 64,
    revision: 2,
    createdAtUtc: claimedAt.toIso8601String(),
    updatedAtUtc: claimedAt.toIso8601String(),
    terminalAtUtc: null,
    settledAtUtc: null,
  );
  expect(claimed.isValid, isTrue);
  expect(
    await LocalNotificationLedgerStore(directory: directory).mutate(
      currentOpaqueBinding: fixture.binding,
      mutation: (current) => current.copyWith(
        storeRevision: current.storeRevision + 1,
        records: <String, LocalNotificationRecordV1>{
          ...current.records,
          fixture.eventCorrelation: claimed,
        },
      ),
    ),
    isNotNull,
  );

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  var nativeEffects = 0;
  final recovered = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(nativeEffects, 1);
}

Future<void> _verifyOldCardRetirementCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-old-card';
  final directory = Directory('${root.path}/direct-crash-cut-old-card-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  const legacyIdentity = 'legacy-event-before-plan-372';
  await fixture.registry.recordContentMetadata(
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: const ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.message,
      eventIdentity: legacyIdentity,
      generation: 'legacy-generation-before-plan-372',
    ),
  );

  var retirementEntries = 0;
  final interrupted = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {
      retirementEntries += 1;
      throw StateError('crash after old-card retirement entry');
    },
    publishNative: () async => fail('marker was not activated yet'),
  );
  expect(
    interrupted.disposition,
    DurableLocalNotificationEffectDisposition.ambiguous,
  );
  expect(retirementEntries, 1);
  final interruptedRecord = await fixture.registry.lookupExactEffect(
    currentOpaqueBinding: fixture.binding,
    eventCorrelation: fixture.eventCorrelation,
    conversationDigest: fixture.identity.digest,
    notificationId: fixture.notificationId,
    contentGeneration: fixture.contentGeneration,
  );
  expect(
    interruptedRecord?.effectPhase,
    LocalNotificationEffectPhase.publishing,
  );
  expect(interruptedRecord?.attemptKind, LocalNotificationAttemptKind.cancel);

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  var ordinaryEffects = 0;
  var silentRepairs = 0;
  final recovered = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async => retirementEntries += 1,
    publishNative: () async => ordinaryEffects += 1,
    publishNativeSilently: () async => silentRepairs += 1,
    activeNotificationIds: () async => const <Object?>[],
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(retirementEntries, 2);
  expect(ordinaryEffects, 0);
  expect(silentRepairs, 1);
  expect(
    await reopened.registry.lookupContentMetadata(
      conversationKey: _directPeerId,
      notificationId: reopened.notificationId,
    ),
    reopened.metadata,
  );
  final intentFile = File(
    '${directory.path}/${fixture.notificationId}'
    '${DurableConversationNotificationIdRegistry.contentActivationIntentFileSuffix}',
  );
  expect(await intentFile.exists(), isFalse);
}

Future<void> _verifyMarkerActivationCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-marker';
  final directory = Directory('${root.path}/direct-crash-cut-marker-ledger');
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  final interrupted = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => fail('ordinary callback must stay outside cut'),
    publishNativeAtFinalBarrier: (authorize) async {
      expect(
        await fixture.registry.lookupContentMetadata(
          conversationKey: _directPeerId,
          notificationId: fixture.notificationId,
        ),
        fixture.metadata,
      );
      throw StateError('crash after marker activation before native entry');
    },
  );
  expect(
    interrupted.disposition,
    DurableLocalNotificationEffectDisposition.retryable,
  );

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  var ordinaryEffects = 0;
  var silentRepairs = 0;
  final recovered = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async {},
    publishNative: () async => ordinaryEffects += 1,
    publishNativeSilently: () async => silentRepairs += 1,
    activeNotificationIds: () async => const <Object?>[],
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(ordinaryEffects, 0);
  expect(silentRepairs, 1);
}

Future<void> _verifyNativeEntryCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-native-entry';
  final directory = Directory(
    '${root.path}/direct-crash-cut-native-entry-ledger',
  );
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  var nativeEntries = 0;
  final interrupted = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => fail('final-barrier callback owns this entry'),
    publishNativeAtFinalBarrier: (authorize) async {
      expect(await authorize(), isTrue);
      nativeEntries += 1;
      throw StateError('native acceptance is ambiguous');
    },
  );
  expect(
    interrupted.disposition,
    DurableLocalNotificationEffectDisposition.ambiguous,
  );
  expect(interrupted.currentNativeEntryAttempted, isTrue);
  expect(nativeEntries, 1);

  final laterCorrelation = _digest('direct-crash-cut-native-entry-later');
  final laterContext = DurableLocalNotificationEffectContext(
    currentOpaqueBinding: fixture.binding,
    eventCorrelation: laterCorrelation,
    conversationDigest: fixture.identity.digest,
    producerKind: LocalNotificationProducerKind.directMessage,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    readFinalCanonicalDisposition: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  final laterMetadata = ConversationNotificationContentMetadata(
    kind: ConversationNotificationContentKind.message,
    eventIdentity: laterCorrelation,
    generation: 'ledger:$laterCorrelation',
  );
  final blockedLater = await fixture.registry.runFinalEffect(
    context: laterContext,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: laterMetadata,
    retireCurrent: () async => fail('later event must not retire incumbent'),
    publishNative: () async => fail('later event must not enter native'),
  );
  expect(
    blockedLater.disposition,
    DurableLocalNotificationEffectDisposition.retryable,
  );
  expect(
    await fixture.registry.lookupContentMetadata(
      conversationKey: _directPeerId,
      notificationId: fixture.notificationId,
    ),
    fixture.metadata,
    reason:
        'a later READY event cannot overwrite an unresolved PUBLISHING card',
  );

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  final recovered = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async => fail('active proof must not retire'),
    publishNative: () async => fail('active proof must not republish'),
    activeNotificationIds: () async => <Object?>[fixture.notificationId],
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(recovered.currentNativeEntryAttempted, isFalse);
  expect(nativeEntries, 1);
}

Future<void> _verifyNativeReturnCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-native-return';
  final directory = Directory(
    '${root.path}/direct-crash-cut-native-return-ledger',
  );
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  var rejectTerminalPublication = true;
  final faultedStore = LocalNotificationLedgerStore(
    directory: directory,
    beforeRename: (prepared, target) async {
      final envelope = LocalNotificationLedgerCodecV1.tryDecode(
        await prepared.readAsString(),
      );
      final record = envelope?.records[fixture.eventCorrelation];
      if (rejectTerminalPublication &&
          record?.effectPhase == LocalNotificationEffectPhase.effectTerminal) {
        rejectTerminalPublication = false;
        throw FileSystemException('crash before effect-terminal publication');
      }
    },
  );
  final faultedRegistry = DurableConversationNotificationIdRegistry(
    directory: directory,
    localNotificationEffectCoordinator:
        DurableLocalNotificationEffectCoordinator(
          ledgerStore: faultedStore,
          nowUtc: () => DateTime.parse(_completedAt).toUtc(),
          effectTokenFactory: () => 'd' * 64,
        ),
  );
  var nativeEntries = 0;
  final interrupted = await faultedRegistry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEntries += 1,
  );
  expect(
    interrupted.disposition,
    DurableLocalNotificationEffectDisposition.ambiguous,
  );
  expect(interrupted.currentNativeEntryAttempted, isTrue);
  expect(nativeEntries, 1);
  final persisted = await LocalNotificationLedgerStore(
    directory: directory,
  ).read(currentOpaqueBinding: fixture.binding);
  expect(
    persisted?.records[fixture.eventCorrelation]?.effectPhase,
    LocalNotificationEffectPhase.publishing,
  );

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  final recovered = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async => fail('accepted card must not retire'),
    publishNative: () async => nativeEntries += 1,
    activeNotificationIds: () async => <Object?>[fixture.notificationId],
  );
  expect(
    recovered.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(recovered.currentNativeEntryAttempted, isFalse);
  expect(nativeEntries, 1);
}

Future<void> _verifyEffectTerminalCrashCut(Directory root) async {
  const messageId = 'direct-crash-cut-effect-terminal';
  final directory = Directory(
    '${root.path}/direct-crash-cut-effect-terminal-ledger',
  );
  final fixture = await _DirectEffectFixture.open(
    directory,
    messageId: messageId,
  );
  await fixture.initialize();
  final context = fixture.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  var nativeEffects = 0;
  final terminal = await fixture.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    terminal.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(nativeEffects, 1);

  final reopened = await _DirectEffectFixture.reopen(
    directory,
    messageId: messageId,
    notificationId: fixture.notificationId,
  );
  final replay = await reopened.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: reopened.identity,
    conversationKey: _directPeerId,
    notificationId: reopened.notificationId,
    metadata: reopened.metadata,
    retireCurrent: () async => fail('terminal replay must not retire'),
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    replay.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(replay.receipt?.recordRevision, terminal.receipt?.recordRevision);
  expect(nativeEffects, 1);
}

Future<void> _verifyGroupSingleEffectAndExactHandoff(Directory root) async {
  final db = await _openDatabase('${root.path}/group-tc372-05.db');
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'group-message-one-owner';
  var entry = await _stageReadyGroupMessage(db, messageId: messageId);
  final ledgerDirectory = Directory('${root.path}/group-tc372-05-ledger');
  final first = await _GroupEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await first.initialize();
  entry = await _bindGroupDurableCorrelation(db, entry, first.eventCorrelation);
  final second = await _GroupEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: first.notificationId,
  );
  var nativeEffects = 0;
  Future<DurableLocalNotificationEffectResult> run(
    _GroupEffectFixture fixture,
  ) => fixture.registry.runFinalEffect(
    context: fixture.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: 'group:$_groupId',
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  final effects = await Future.wait(
    <Future<DurableLocalNotificationEffectResult>>[run(first), run(second)],
  );
  expect(nativeEffects, 1);
  expect(
    effects.map((effect) => effect.disposition),
    everyElement(DurableLocalNotificationEffectDisposition.osPosted),
  );
  expect(
    effects.map((effect) => effect.receipt!.recordRevision).toSet(),
    hasLength(1),
  );

  final outcome = first.outcome(NotificationCompletedOutcomeCategory.osPosted);
  final handoffs =
      await Future.wait(<Future<DurableLocalNotificationSqlHandoffResult>>[
        _handoffGroupMessage(
          db,
          entry,
          durableEventCorrelation: first.eventCorrelation,
          outcome: outcome,
        ),
        _handoffGroupMessage(
          db,
          entry,
          durableEventCorrelation: first.eventCorrelation,
          outcome: outcome,
        ),
      ]);
  expect(handoffs.toSet(), <DurableLocalNotificationSqlHandoffResult>{
    DurableLocalNotificationSqlHandoffResult.committed,
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  });
  expect(
    (await first.registry.settleSqlReadyEffect(
      currentOpaqueBinding: first.binding,
      eventCorrelation: first.eventCorrelation,
      expectedRevision: effects.first.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(
    await _retireGroupMessageAfterSettlement(
      db,
      entry,
      durableEventCorrelation: first.eventCorrelation,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNull,
  );
  expect(
    await dbLoadGroupNotificationReconciliationOutboxEntry(db, _groupId),
    isNotNull,
  );
  expect(await db.query('notification_completed_outcome_outbox'), hasLength(1));
}

Future<void> _verifyGroupEffectTerminalSqlReplay(Directory root) async {
  final databasePath = '${root.path}/group-tc372-06.db';
  var db = await _openDatabase(databasePath);
  const messageId = 'group-message-crash-replay';
  var entry = await _stageReadyGroupMessage(db, messageId: messageId);
  final ledgerDirectory = Directory('${root.path}/group-tc372-06-ledger');
  final beforeCrash = await _GroupEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await beforeCrash.initialize();
  entry = await _bindGroupDurableCorrelation(
    db,
    entry,
    beforeCrash.eventCorrelation,
  );
  var nativeEffects = 0;
  final context = beforeCrash.context(
    readFinal: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  final terminal = await beforeCrash.registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: beforeCrash.identity,
    conversationKey: 'group:$_groupId',
    notificationId: beforeCrash.notificationId,
    metadata: beforeCrash.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  final outcome = beforeCrash.outcome(
    NotificationCompletedOutcomeCategory.osPosted,
  );
  expect(
    await _handoffGroupMessage(
      db,
      entry,
      durableEventCorrelation: beforeCrash.eventCorrelation,
      outcome: outcome,
    ),
    DurableLocalNotificationSqlHandoffResult.committed,
  );
  expect(nativeEffects, 1);
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNotNull,
    reason: 'transaction A retains raw READY custody until ledger settlement',
  );
  await db.close();

  // Fresh process/object: SQL committed, ledger still EFFECT_TERMINAL.
  db = await _openDatabase(databasePath);
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  final afterCrash = await _GroupEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: beforeCrash.notificationId,
  );
  final replay = await afterCrash.registry.runFinalEffect(
    context: afterCrash.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: afterCrash.identity,
    conversationKey: 'group:$_groupId',
    notificationId: afterCrash.notificationId,
    metadata: afterCrash.metadata,
    retireCurrent: () async => fail('terminal replay must not retire'),
    publishNative: () async => nativeEffects += 1,
  );
  expect(nativeEffects, 1, reason: 'EFFECT_TERMINAL replay is zero-effect');
  expect(replay.receipt?.recordRevision, terminal.receipt?.recordRevision);
  expect(
    await _handoffGroupMessage(
      db,
      entry,
      durableEventCorrelation: afterCrash.eventCorrelation,
      outcome: outcome,
    ),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await afterCrash.registry.settleSqlReadyEffect(
      currentOpaqueBinding: afterCrash.binding,
      eventCorrelation: afterCrash.eventCorrelation,
      expectedRevision: replay.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(await db.query('notification_completed_outcome_outbox'), hasLength(1));

  // A second fresh process/object observes SETTLED plus redundant READY after
  // the crash cut between ledger settlement and transaction B. It verifies
  // SQL, settles idempotently, and only then exact-deletes READY.
  await db.close();
  db = await _openDatabase(databasePath);
  final afterSettlementCrash = await _GroupEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: beforeCrash.notificationId,
  );
  final settledTerminals = await afterSettlementCrash.registry
      .listSqlReadyEffectTerminals(
        currentOpaqueBinding: afterSettlementCrash.binding,
      );
  final exactSettledTerminals = settledTerminals
      .where(
        (record) =>
            record.eventCorrelation == afterSettlementCrash.eventCorrelation,
      )
      .toList(growable: false);
  expect(
    exactSettledTerminals,
    hasLength(1),
    reason:
        'SETTLED plus retained SQL READY custody must remain discoverable '
        'after a fresh-process crash cut',
  );
  expect(
    exactSettledTerminals.single.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  final settledReplay = await afterSettlementCrash.registry.runFinalEffect(
    context: afterSettlementCrash.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: afterSettlementCrash.identity,
    conversationKey: 'group:$_groupId',
    notificationId: afterSettlementCrash.notificationId,
    metadata: afterSettlementCrash.metadata,
    retireCurrent: () async => fail('settled replay must not retire'),
    publishNative: () async => nativeEffects += 1,
  );
  expect(nativeEffects, 1, reason: 'SETTLED replay is zero-effect');
  expect(
    await _handoffGroupMessage(
      db,
      entry,
      durableEventCorrelation: afterSettlementCrash.eventCorrelation,
      outcome: outcome,
    ),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await afterSettlementCrash.registry.settleSqlReadyEffect(
      currentOpaqueBinding: afterSettlementCrash.binding,
      eventCorrelation: afterSettlementCrash.eventCorrelation,
      expectedRevision: settledReplay.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  final readyBeforeFailedB = await dbLoadGroupNotificationDisplayOutboxEntry(
    db,
    entry.eventId,
  );
  expect(readyBeforeFailedB, isNotNull);
  await db.execute('''
    CREATE TRIGGER fail_group_transaction_b
    BEFORE DELETE ON group_notification_display_outbox
    BEGIN
      SELECT RAISE(ABORT, 'injected transaction B failure');
    END
  ''');
  await expectLater(
    _retireGroupMessageAfterSettlement(
      db,
      entry,
      durableEventCorrelation: afterSettlementCrash.eventCorrelation,
    ),
    throwsA(anything),
  );
  final readyAfterFailedB = await dbLoadGroupNotificationDisplayOutboxEntry(
    db,
    entry.eventId,
  );
  expect(readyAfterFailedB?['revision'], readyBeforeFailedB?['revision']);
  expect(
    readyAfterFailedB?['last_attempt_at'],
    readyBeforeFailedB?['last_attempt_at'],
    reason: 'transaction-B failure cannot manufacture a new READY attempt',
  );
  await db.execute('DROP TRIGGER fail_group_transaction_b');
  expect(
    await _retireGroupMessageAfterSettlement(
      db,
      entry,
      durableEventCorrelation: afterSettlementCrash.eventCorrelation,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, entry.eventId),
    isNull,
  );
  expect(
    await dbLoadGroupNotificationReconciliationOutboxEntry(db, _groupId),
    isNotNull,
  );

  final conflicting = afterCrash.outcome(
    NotificationCompletedOutcomeCategory.inChat,
  );
  expect(
    await _handoffGroupMessage(
      db,
      entry,
      durableEventCorrelation: afterSettlementCrash.eventCorrelation,
      outcome: conflicting,
    ),
    DurableLocalNotificationSqlHandoffResult.retryableMismatch,
  );
  expect(
    (await db.query('notification_completed_outcome_outbox')).single['outcome'],
    NotificationCompletedOutcomeCategory.osPosted.wireValue,
  );
}

Future<void> _verifyDirectSingleEffectAndExactHandoff(Directory root) async {
  final db = await _openDatabase('${root.path}/direct-tc372-05.db');
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'direct-message-one-owner';
  final entry = await _stageReadyDirectMessage(db, messageId: messageId);
  final ledgerDirectory = Directory('${root.path}/direct-tc372-05-ledger');
  final first = await _DirectEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await first.initialize();
  final second = await _DirectEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: first.notificationId,
  );
  var nativeEffects = 0;
  Future<DurableLocalNotificationEffectResult> run(
    _DirectEffectFixture fixture,
  ) => fixture.registry.runFinalEffect(
    context: fixture.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: fixture.identity,
    conversationKey: _directPeerId,
    notificationId: fixture.notificationId,
    metadata: fixture.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );

  final effects = await Future.wait(
    <Future<DurableLocalNotificationEffectResult>>[run(first), run(second)],
  );
  expect(nativeEffects, 1);
  expect(
    effects.map((effect) => effect.disposition),
    everyElement(DurableLocalNotificationEffectDisposition.osPosted),
  );
  expect(
    effects.map((effect) => effect.receipt!.recordRevision).toSet(),
    hasLength(1),
  );

  final outcome = first.outcome(NotificationCompletedOutcomeCategory.osPosted);
  final handoffs =
      await Future.wait(<Future<DurableLocalNotificationSqlHandoffResult>>[
        _handoffDirectMessage(db, entry, outcome: outcome),
        _handoffDirectMessage(db, entry, outcome: outcome),
      ]);
  expect(handoffs.toSet(), <DurableLocalNotificationSqlHandoffResult>{
    DurableLocalNotificationSqlHandoffResult.committed,
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  });
  expect(
    (await first.registry.settleSqlReadyEffect(
      currentOpaqueBinding: first.binding,
      eventCorrelation: first.eventCorrelation,
      expectedRevision: effects.first.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(await db.query('notification_completed_outcome_outbox'), hasLength(1));
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _directPeerId),
    isNotNull,
  );
}

Future<void> _verifyDirectEffectTerminalFreshProcessReplay(
  Directory root,
) async {
  final databasePath = '${root.path}/direct-tc372-06.db';
  var db = await _openDatabase(databasePath);
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'direct-message-crash-replay';
  final entry = await _stageReadyDirectMessage(db, messageId: messageId);
  await db.delete(
    'direct_notification_reconciliation_outbox',
    where: 'peer_id = ?',
    whereArgs: const <Object?>[_directPeerId],
  );
  final ledgerDirectory = Directory('${root.path}/direct-tc372-06-ledger');
  final beforeCrash = await _DirectEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await beforeCrash.initialize();
  var nativeEffects = 0;
  final terminal = await beforeCrash.registry.runFinalEffect(
    context: beforeCrash.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: beforeCrash.identity,
    conversationKey: _directPeerId,
    notificationId: beforeCrash.notificationId,
    metadata: beforeCrash.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.committed,
  );
  expect(nativeEffects, 1);
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _directPeerId),
    isNull,
    reason: 'transaction A cannot signal cleanup before ledger settlement',
  );
  expect(
    await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    ),
    isNotNull,
    reason: 'transaction A retains exact raw READY custody across the crash',
  );
  await db.close();

  // A fresh owner enumerates ledger terminals and typed SQL evidence. It does
  // not re-enter runFinalEffect, the display projection, or the native API.
  db = await _openDatabase(databasePath);
  final afterCrash = await _DirectEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: beforeCrash.notificationId,
  );
  final ledgerTerminals = await afterCrash.registry.listSqlReadyEffectTerminals(
    currentOpaqueBinding: afterCrash.binding,
  );
  final effectTerminal = ledgerTerminals.singleWhere(
    (record) =>
        record.eventCorrelation == afterCrash.eventCorrelation &&
        record.producerKind == LocalNotificationProducerKind.directMessage,
  );
  final sqlTerminals =
      await dbLoadDirectNotificationCommittedSqlTerminalsForPeer(
        db,
        peerId: _directPeerId,
      );
  final sqlTerminal = sqlTerminals.singleWhere(
    (record) =>
        record.eventKind == DirectNotificationDisplayOutboxKind.message &&
        record.messageId == messageId,
  );
  expect(
    tryComputeNotificationCompletedOutcomeCorrelation(
      physicalPeerId: _physicalPeerId,
      producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
      eventKey: sqlTerminal.messageId,
    ),
    effectTerminal.eventCorrelation,
    reason: 'fresh recovery must reconstruct correlation from the raw key',
  );
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
  );
  expect(
    (await afterCrash.registry.settleSqlReadyEffect(
      currentOpaqueBinding: afterCrash.binding,
      eventCorrelation: effectTerminal.eventCorrelation,
      expectedRevision: effectTerminal.revision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(await _retireDirectMessageAfterSettlement(db, entry), isTrue);
  expect(
    await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    ),
    isNull,
  );
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _directPeerId),
    isNotNull,
    reason: 'transaction B atomically retires READY and signals reconciliation',
  );
  final awaitingSqlRetirement = await afterCrash.registry
      .listSqlReadyEffectTerminals(currentOpaqueBinding: afterCrash.binding);
  expect(awaitingSqlRetirement, hasLength(1));
  expect(
    awaitingSqlRetirement.single.effectPhase,
    LocalNotificationEffectPhase.settled,
    reason: 'SETTLED remains immutable audit/recovery authority after SQL B',
  );
  expect(
    nativeEffects,
    1,
    reason: 'fresh SQL repair is a zero-native-effect path',
  );
  expect(terminal.receipt?.recordRevision, effectTerminal.revision);
  expect(
    await db.query('notification_completed_outcome_outbox'),
    isEmpty,
    reason: 'the default-off path must not synthesize a v116 outcome',
  );
}

Future<void> _verifyDirectSettledSqlRetirementRecovery(Directory root) async {
  final databasePath = '${root.path}/direct-settled-tc372-06.db';
  var db = await _openDatabase(databasePath);
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'direct-message-settled-before-sql-b';
  final entry = await _stageReadyDirectMessage(db, messageId: messageId);
  await db.delete(
    'direct_notification_reconciliation_outbox',
    where: 'peer_id = ?',
    whereArgs: const <Object?>[_directPeerId],
  );
  final ledgerDirectory = Directory(
    '${root.path}/direct-settled-tc372-06-ledger',
  );
  final beforeCrash = await _DirectEffectFixture.open(
    ledgerDirectory,
    messageId: messageId,
  );
  await beforeCrash.initialize();
  var nativeEffects = 0;
  final terminal = await beforeCrash.registry.runFinalEffect(
    context: beforeCrash.context(
      readFinal: () async =>
          DurableLocalNotificationCanonicalDisposition.eligible,
    ),
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: beforeCrash.identity,
    conversationKey: _directPeerId,
    notificationId: beforeCrash.notificationId,
    metadata: beforeCrash.metadata,
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.committed,
  );
  expect(
    (await beforeCrash.registry.settleSqlReadyEffect(
      currentOpaqueBinding: beforeCrash.binding,
      eventCorrelation: beforeCrash.eventCorrelation,
      expectedRevision: terminal.receipt!.recordRevision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );

  // A failed SQL-B CAS cannot mutate or revise the retained raw READY. This
  // models the retryable failure immediately before a process crash.
  expect(
    await _retireDirectMessageAfterSettlement(
      db,
      entry.copyWith(revision: entry.revision + 1),
    ),
    isFalse,
  );
  final retainedBeforeCrash = DirectNotificationDisplayOutboxEntry.fromMap(
    (await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    ))!,
  );
  expect(retainedBeforeCrash.revision, entry.revision);
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _directPeerId),
    isNull,
  );
  await db.close();

  // Fresh recovery enumerates SETTLED itself and performs transaction B
  // directly. It must not re-run transaction A, ledger settlement, or native
  // publication.
  db = await _openDatabase(databasePath);
  final afterCrash = await _DirectEffectFixture.reopen(
    ledgerDirectory,
    messageId: messageId,
    notificationId: beforeCrash.notificationId,
  );
  final settled =
      (await afterCrash.registry.listSqlReadyEffectTerminals(
        currentOpaqueBinding: afterCrash.binding,
      )).singleWhere(
        (record) => record.eventCorrelation == afterCrash.eventCorrelation,
      );
  expect(settled.effectPhase, LocalNotificationEffectPhase.settled);
  expect(await _retireDirectMessageAfterSettlement(db, entry), isTrue);
  expect(
    await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    ),
    isNull,
  );
  expect(
    await dbLoadDirectNotificationReconciliationOutboxEntry(db, _directPeerId),
    isNotNull,
  );
  expect(nativeEffects, 1, reason: 'SETTLED recovery is zero-native-effect');
  expect(
    settled.revision,
    terminal.receipt!.recordRevision + 1,
    reason: 'SETTLED is the one monotonic transition after effect terminal',
  );
  expect(
    retainedBeforeCrash.revision,
    entry.revision,
    reason:
        'ledger settlement and failed SQL B never advance SQL READY revision',
  );
  expect(
    settled.eventCorrelation,
    beforeCrash.eventCorrelation,
    reason: 'SQL-B recovery consumes the original immutable correlation',
  );
}

Future<void> _verifyDirectReactionTerminalMutationCrashReplay(
  Directory root,
) async {
  final databasePath = '${root.path}/direct-reaction-tc372-06.db';
  var db = await _openDatabase(databasePath);
  addTearDown(() async {
    if (db.isOpen) await db.close();
  });
  const messageId = 'direct-reaction-target-crash-replay';
  const reactionId = 'direct-reaction-generation-a';
  const eventId = 'direct-reaction-display-a';
  await db.insert('contacts', <String, Object?>{
    'peer_id': _directPeerId,
    'public_key': 'public-direct-reaction-plan-372',
    'rendezvous': 'relay-direct-reaction-plan-372',
    'username': 'Direct Reaction Plan 372',
    'signature': 'signature-direct-reaction-plan-372',
    'scanned_at': _timestamp,
  });
  await db.insert('messages', <String, Object?>{
    'id': messageId,
    'contact_peer_id': _directPeerId,
    'sender_peer_id': _selfPeerId,
    'text': 'outgoing reaction target',
    'timestamp': _timestamp,
    'status': 'delivered',
    'is_incoming': 0,
    'created_at': _timestamp,
  });
  await db.insert('message_reactions', <String, Object?>{
    'id': reactionId,
    'message_id': messageId,
    'emoji': '\u{1f44d}',
    'sender_peer_id': _directPeerId,
    'timestamp': _timestamp,
    'created_at': _timestamp,
  });
  const entry = DirectNotificationDisplayOutboxEntry.reaction(
    eventId: eventId,
    peerId: _directPeerId,
    messageId: messageId,
    actorPeerId: _directPeerId,
    eventTimestamp: _timestamp,
    reactionId: reactionId,
    reactionAction: 'add',
    reactionTombstone: false,
    readiness: DirectNotificationDisplayOutboxReadiness.ready,
    createdAt: _timestamp,
    updatedAt: _timestamp,
  );
  const sibling = DirectNotificationDisplayOutboxEntry.reaction(
    eventId: 'direct-reaction-display-sibling',
    peerId: _directPeerId,
    messageId: messageId,
    actorPeerId: _directPeerId,
    eventTimestamp: _completedAt,
    reactionId: 'direct-reaction-generation-sibling',
    reactionAction: 'add',
    reactionTombstone: false,
    readiness: DirectNotificationDisplayOutboxReadiness.ready,
    revision: 4,
    createdAt: _completedAt,
    updatedAt: _completedAt,
  );
  await db.insert('direct_notification_display_outbox', entry.toMap());
  await db.insert('direct_notification_display_outbox', sibling.toMap());

  final ledgerDirectory = Directory(
    '${root.path}/direct-reaction-tc372-06-ledger',
  );
  final registry = DurableConversationNotificationIdRegistry(
    directory: ledgerDirectory,
    localNotificationEffectCoordinator:
        DurableLocalNotificationEffectCoordinator(
          ledgerStore: LocalNotificationLedgerStore(directory: ledgerDirectory),
          nowUtc: () => DateTime.parse(_completedAt).toUtc(),
          effectTokenFactory: () => 'a' * 64,
        ),
  );
  final notificationId = await registry.resolve(
    _directPeerId,
    activeNotificationIds: () async => const <Object?>[],
  );
  final binding = 'v1:${_digest('direct-reaction-binding')}';
  expect(
    await LocalNotificationLedgerStore(
      directory: ledgerDirectory,
    ).initializeOrRebind(currentOpaqueBinding: binding),
    isNotNull,
  );
  final correlation = tryComputeNotificationCompletedOutcomeCorrelation(
    physicalPeerId: _physicalPeerId,
    producerKind: NotificationCompletedOutcomeProducerKind.directReaction,
    eventKey: reactionId,
  )!;
  final identity = AppVisibilityConversationIdentity.tryParse(
    lane: AppVisibilityConversationLane.direct,
    value: _directPeerId,
  )!;
  final context = DurableLocalNotificationEffectContext(
    currentOpaqueBinding: binding,
    eventCorrelation: correlation,
    conversationDigest: identity.digest,
    producerKind: LocalNotificationProducerKind.directReaction,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    readFinalCanonicalDisposition: () async =>
        DurableLocalNotificationCanonicalDisposition.eligible,
  );
  var nativeEffects = 0;
  final terminal = await registry.runFinalEffect(
    context: context,
    appVisibility: _BackgroundVisibility(),
    conversationIdentity: identity,
    conversationKey: _directPeerId,
    notificationId: notificationId,
    metadata: ConversationNotificationContentMetadata(
      kind: ConversationNotificationContentKind.reaction,
      eventIdentity: correlation,
      generation: 'ledger:$correlation',
    ),
    retireCurrent: () async {},
    publishNative: () async => nativeEffects += 1,
  );
  expect(
    terminal.disposition,
    DurableLocalNotificationEffectDisposition.osPosted,
  );
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.committed,
  );
  expect(
    await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: entry.peerId,
      eventKind: entry.eventKind,
      eventId: entry.eventId,
    ),
    isNotNull,
  );

  // The next canonical mutation invalidates the mutable one-row terminal.
  // Exact READY remains the immutable event authority across this crash cut.
  expect(
    await db.update(
      'message_reactions',
      const <String, Object?>{'removed_at': _completedAt},
      where: 'id = ? AND message_id = ? AND sender_peer_id = ?',
      whereArgs: const <Object?>[reactionId, messageId, _directPeerId],
    ),
    1,
  );
  await db.delete(
    'direct_notification_reaction_terminal_events',
    where: 'peer_id = ? AND message_id = ? AND actor_peer_id = ?',
    whereArgs: const <Object?>[_directPeerId, messageId, _directPeerId],
  );
  await db.close();

  db = await _openDatabase(databasePath);
  final freshRegistry = DurableConversationNotificationIdRegistry(
    directory: ledgerDirectory,
    localNotificationEffectCoordinator:
        DurableLocalNotificationEffectCoordinator(
          ledgerStore: LocalNotificationLedgerStore(directory: ledgerDirectory),
          nowUtc: () => DateTime.parse(_completedAt).toUtc(),
          effectTokenFactory: () => 'b' * 64,
        ),
  );
  final effectTerminal = (await freshRegistry.listSqlReadyEffectTerminals(
    currentOpaqueBinding: binding,
  )).singleWhere((record) => record.eventCorrelation == correlation);
  expect(
    await _handoffDirectMessage(db, entry, outcome: null),
    DurableLocalNotificationSqlHandoffResult.alreadyCommitted,
    reason:
        'exact READY plus canonical removal survives mutable terminal deletion',
  );
  expect(
    (await freshRegistry.settleSqlReadyEffect(
      currentOpaqueBinding: binding,
      eventCorrelation: correlation,
      expectedRevision: effectTerminal.revision,
    ))?.effectPhase,
    LocalNotificationEffectPhase.settled,
  );
  expect(await _retireDirectMessageAfterSettlement(db, entry), isTrue);
  expect(
    await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: sibling.peerId,
      eventKind: sibling.eventKind,
      eventId: sibling.eventId,
    ),
    isNotNull,
    reason: 'transaction B never deletes a stale/newer sibling',
  );
  expect(nativeEffects, 1, reason: 'fresh settlement is zero-native-effect');
}

Future<Database> _openDatabase(String path) => databaseFactoryFfi.openDatabase(
  path,
  options: OpenDatabaseOptions(
    version: currentIdentityDatabaseVersion,
    singleInstance: false,
    onCreate: runProductionOnCreate,
    onUpgrade: runProductionOnUpgrade,
    onDowngrade: onDatabaseVersionChangeError,
  ),
);

Future<GroupNotificationDisplayOutboxEntry> _stageReadyGroupMessage(
  Database db, {
  required String messageId,
}) async {
  await db.insert('groups', const <String, Object?>{
    'id': _groupId,
    'type': 'chat',
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('group_messages', <String, Object?>{
    'id': messageId,
    'group_id': _groupId,
    'sender_peer_id': _senderPeerId,
    'text': 'identifier-only convergence fixture',
    'timestamp': _timestamp,
    'created_at': _timestamp,
  });
  final staged = GroupNotificationDisplayOutboxEntry.message(
    eventId: messageId,
    groupId: _groupId,
    messageId: messageId,
    actorPeerId: _senderPeerId,
    eventTimestamp: _timestamp,
    createdAt: _timestamp,
    updatedAt: _timestamp,
  );
  await dbStageGroupNotificationDisplayOutboxEntry(db, staged.toMap());
  expect(
    await dbPromoteGroupNotificationDisplayOutboxReadyIfExact(
      db,
      eventId: messageId,
      expectedRevision: 1,
      updatedAt: _completedAt,
    ),
    isTrue,
  );
  return GroupNotificationDisplayOutboxEntry.fromMap(
    (await dbLoadGroupNotificationDisplayOutboxEntry(db, messageId))!,
  );
}

Future<GroupNotificationDisplayOutboxEntry> _bindGroupDurableCorrelation(
  Database db,
  GroupNotificationDisplayOutboxEntry entry,
  String durableEventCorrelation,
) async {
  final row =
      await dbBindGroupNotificationDisplayOutboxDurableCorrelationIfExact(
        db,
        eventId: entry.eventId,
        expectedRevision: entry.revision,
        expectedEventKind: entry.eventKind,
        expectedGroupId: entry.groupId,
        expectedMessageId: entry.messageId,
        expectedActorPeerId: entry.actorPeerId,
        expectedEventTimestamp: entry.eventTimestamp,
        expectedReactionId: entry.reactionId,
        expectedReactionAction: entry.reactionAction,
        expectedReactionTombstone: entry.reactionTombstone,
        durableEventCorrelation: durableEventCorrelation,
        updatedAt: _completedAt,
      );
  expect(row, isNotNull);
  return GroupNotificationDisplayOutboxEntry.fromMap(row!);
}

Future<DirectNotificationDisplayOutboxEntry> _stageReadyDirectMessage(
  Database db, {
  required String messageId,
}) async {
  await db.insert('contacts', <String, Object?>{
    'peer_id': _directPeerId,
    'public_key': 'public-direct-plan-372',
    'rendezvous': 'relay-direct-plan-372',
    'username': 'Direct Plan 372',
    'signature': 'signature-direct-plan-372',
    'scanned_at': _timestamp,
  });
  await db.insert('messages', <String, Object?>{
    'id': messageId,
    'contact_peer_id': _directPeerId,
    'sender_peer_id': _directPeerId,
    'text': 'identifier-only direct convergence fixture',
    'timestamp': _timestamp,
    'status': 'delivered',
    'is_incoming': 1,
    'created_at': _timestamp,
  });
  final staged = DirectNotificationDisplayOutboxEntry.message(
    eventId: messageId,
    peerId: _directPeerId,
    messageId: messageId,
    actorPeerId: _directPeerId,
    eventTimestamp: _timestamp,
    createdAt: _timestamp,
    updatedAt: _timestamp,
  );
  await dbStageDirectNotificationDisplayOutboxEntry(db, staged.toMap());
  expect(
    await dbPromoteDirectNotificationDisplayOutboxReadyIfExact(
      db,
      peerId: _directPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.message,
      eventId: messageId,
      expectedRevision: 1,
      updatedAt: _completedAt,
    ),
    isTrue,
  );
  return DirectNotificationDisplayOutboxEntry.fromMap(
    (await dbLoadDirectNotificationDisplayOutboxEntry(
      db,
      peerId: _directPeerId,
      eventKind: DirectNotificationDisplayOutboxKind.message,
      eventId: messageId,
    ))!,
  );
}

Future<DurableLocalNotificationSqlHandoffResult> _handoffGroupMessage(
  Database db,
  GroupNotificationDisplayOutboxEntry entry, {
  required String durableEventCorrelation,
  required NotificationCompletedOutcomeCandidate? outcome,
}) => dbCompleteOrVerifyGroupNotificationDisplayOutboxEntryIfExact(
  db,
  eventId: entry.eventId,
  expectedRevision: entry.revision,
  expectedEventKind: entry.eventKind,
  expectedGroupId: entry.groupId,
  expectedMessageId: entry.messageId,
  expectedActorPeerId: entry.actorPeerId,
  expectedEventTimestamp: entry.eventTimestamp,
  expectedReactionId: entry.reactionId,
  expectedReactionAction: entry.reactionAction,
  expectedReactionTombstone: entry.reactionTombstone,
  completedAt: _completedAt,
  outcome: outcome,
  durableEventCorrelation: durableEventCorrelation,
);

Future<bool> _retireGroupMessageAfterSettlement(
  Database db,
  GroupNotificationDisplayOutboxEntry entry, {
  required String durableEventCorrelation,
}) => dbRetireGroupNotificationDisplayOutboxAfterDurableSettlementIfExact(
  db,
  eventId: entry.eventId,
  expectedRevision: entry.revision,
  expectedEventKind: entry.eventKind,
  expectedGroupId: entry.groupId,
  expectedMessageId: entry.messageId,
  expectedActorPeerId: entry.actorPeerId,
  expectedEventTimestamp: entry.eventTimestamp,
  expectedReactionId: entry.reactionId,
  expectedReactionAction: entry.reactionAction,
  expectedReactionTombstone: entry.reactionTombstone,
  durableEventCorrelation: durableEventCorrelation,
);

Future<DurableLocalNotificationSqlHandoffResult> _handoffDirectMessage(
  Database db,
  DirectNotificationDisplayOutboxEntry entry, {
  required NotificationCompletedOutcomeCandidate? outcome,
}) => dbHandoffDirectNotificationDisplayOutboxEntryIfExact(
  db,
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
  completedAt: _completedAt,
  outcome: outcome,
);

Future<bool> _retireDirectMessageAfterSettlement(
  Database db,
  DirectNotificationDisplayOutboxEntry entry,
) => dbRetireDirectNotificationDisplayOutboxAfterDurableSettlementIfExact(
  db,
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
);

final class _GroupEffectFixture {
  const _GroupEffectFixture({
    required this.directory,
    required this.registry,
    required this.notificationId,
    required this.messageId,
  });

  final Directory directory;
  final DurableConversationNotificationIdRegistry registry;
  final int notificationId;
  final String messageId;

  String get binding => 'v1:${_digest('group-binding')}';
  String get eventCorrelation =>
      tryComputeNotificationCompletedOutcomeCorrelation(
        physicalPeerId: _physicalPeerId,
        producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
        eventKey: messageId,
      )!;
  String get contentGeneration => 'ledger:$eventCorrelation';
  AppVisibilityConversationIdentity get identity =>
      AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.group,
        value: 'group:$_groupId',
      )!;
  ConversationNotificationContentMetadata get metadata =>
      ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: eventCorrelation,
        generation: contentGeneration,
      );

  static DurableConversationNotificationIdRegistry _registry(
    Directory directory,
  ) => DurableConversationNotificationIdRegistry(
    directory: directory,
    localNotificationEffectCoordinator:
        DurableLocalNotificationEffectCoordinator(
          ledgerStore: LocalNotificationLedgerStore(directory: directory),
          nowUtc: () => DateTime.parse(_completedAt).toUtc(),
          effectTokenFactory: () => 'e' * 64,
        ),
  );

  static Future<_GroupEffectFixture> open(
    Directory directory, {
    required String messageId,
  }) async {
    final registry = _registry(directory);
    final notificationId = await registry.resolve(
      'group:$_groupId',
      activeNotificationIds: () async => const <Object?>[],
    );
    return _GroupEffectFixture(
      directory: directory,
      registry: registry,
      notificationId: notificationId,
      messageId: messageId,
    );
  }

  static Future<_GroupEffectFixture> reopen(
    Directory directory, {
    required String messageId,
    required int notificationId,
  }) async => _GroupEffectFixture(
    directory: directory,
    registry: _registry(directory),
    notificationId: notificationId,
    messageId: messageId,
  );

  Future<void> initialize() async {
    expect(
      await LocalNotificationLedgerStore(
        directory: directory,
      ).initializeOrRebind(currentOpaqueBinding: binding),
      isNotNull,
    );
  }

  DurableLocalNotificationEffectContext context({
    required ReadDurableLocalNotificationCanonicalDisposition readFinal,
  }) => DurableLocalNotificationEffectContext(
    currentOpaqueBinding: binding,
    eventCorrelation: eventCorrelation,
    conversationDigest: identity.digest,
    producerKind: LocalNotificationProducerKind.groupMessage,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    readFinalCanonicalDisposition: readFinal,
  );

  NotificationCompletedOutcomeCandidate outcome(
    NotificationCompletedOutcomeCategory category,
  ) => NotificationCompletedOutcomeCandidate(
    physicalPeerId: _physicalPeerId,
    producerKind: NotificationCompletedOutcomeProducerKind.groupMessage,
    eventKey: messageId,
    outcome: category,
    completedAt: DateTime.parse(_completedAt).toUtc(),
  );
}

final class _DirectEffectFixture {
  const _DirectEffectFixture({
    required this.directory,
    required this.registry,
    required this.notificationId,
    required this.messageId,
  });

  final Directory directory;
  final DurableConversationNotificationIdRegistry registry;
  final int notificationId;
  final String messageId;

  String get binding => 'v1:${_digest('direct-binding')}';
  String get eventCorrelation =>
      tryComputeNotificationCompletedOutcomeCorrelation(
        physicalPeerId: _physicalPeerId,
        producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
        eventKey: messageId,
      )!;
  String get contentGeneration => 'ledger:$eventCorrelation';
  AppVisibilityConversationIdentity get identity =>
      AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.direct,
        value: _directPeerId,
      )!;
  ConversationNotificationContentMetadata get metadata =>
      ConversationNotificationContentMetadata(
        kind: ConversationNotificationContentKind.message,
        eventIdentity: eventCorrelation,
        generation: contentGeneration,
      );

  static DurableConversationNotificationIdRegistry _registry(
    Directory directory,
  ) => DurableConversationNotificationIdRegistry(
    directory: directory,
    localNotificationEffectCoordinator:
        DurableLocalNotificationEffectCoordinator(
          ledgerStore: LocalNotificationLedgerStore(directory: directory),
          nowUtc: () => DateTime.parse(_completedAt).toUtc(),
          effectTokenFactory: () => 'd' * 64,
        ),
  );

  static Future<_DirectEffectFixture> open(
    Directory directory, {
    required String messageId,
  }) async {
    final registry = _registry(directory);
    final notificationId = await registry.resolve(
      _directPeerId,
      activeNotificationIds: () async => const <Object?>[],
    );
    return _DirectEffectFixture(
      directory: directory,
      registry: registry,
      notificationId: notificationId,
      messageId: messageId,
    );
  }

  static Future<_DirectEffectFixture> reopen(
    Directory directory, {
    required String messageId,
    required int notificationId,
  }) async => _DirectEffectFixture(
    directory: directory,
    registry: _registry(directory),
    notificationId: notificationId,
    messageId: messageId,
  );

  Future<void> initialize() async {
    expect(
      await LocalNotificationLedgerStore(
        directory: directory,
      ).initializeOrRebind(currentOpaqueBinding: binding),
      isNotNull,
    );
  }

  DurableLocalNotificationEffectContext context({
    required ReadDurableLocalNotificationCanonicalDisposition readFinal,
  }) => DurableLocalNotificationEffectContext(
    currentOpaqueBinding: binding,
    eventCorrelation: eventCorrelation,
    conversationDigest: identity.digest,
    producerKind: LocalNotificationProducerKind.directMessage,
    sourceCustody: LocalNotificationSourceCustody.sqlReady,
    presentationOwner: LocalNotificationPresentationOwner.mainApp,
    readFinalCanonicalDisposition: readFinal,
  );

  NotificationCompletedOutcomeCandidate outcome(
    NotificationCompletedOutcomeCategory category,
  ) => NotificationCompletedOutcomeCandidate(
    physicalPeerId: _physicalPeerId,
    producerKind: NotificationCompletedOutcomeProducerKind.directMessage,
    eventKey: messageId,
    outcome: category,
    completedAt: DateTime.parse(_completedAt).toUtc(),
  );
}

final class _BackgroundVisibility extends AppVisibilitySuppressionReader {
  @override
  Future<AppVisibilityEvaluation> evaluate(
    AppVisibilityConversationIdentity? identity,
  ) async => const AppVisibilityEvaluation(
    isForegroundActive: false,
    maySuppress: false,
    lifecycle: AppVisibilityLifecycle.background,
    revision: 1,
    lifecycleGeneration: 1,
  );
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
