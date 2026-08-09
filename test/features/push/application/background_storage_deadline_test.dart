import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/durable_conversation_notification_id_registry.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/background_storage_liveness_journal.dart';
import 'package:flutter_app/features/push/application/pending_conversation_notification_overlay.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/push_envelope_staging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  // These five values are ONE self-consistent set, not measurements of how
  // fast production is. `debugSetBackgroundStorageDeadlineDurations` below
  // INSTALLS the aggregate/phase deadlines the handler must honour, so
  // `observationBudget` is only "the installed aggregate plus slack" and
  // `lateEffectWindow` is "long enough for a released phase to misbehave".
  //
  // What every assertion here proves is BOUNDEDNESS, not speed: each held
  // resolver/stager is released strictly AFTER its `_completesWithin` check, so
  // the failure mode under guard is an UNBOUNDED wait. Scaling the installed
  // deadline and the observation window together therefore proves exactly the
  // same property — the handler still must fail closed at the deadline it was
  // given — while removing the wall-clock race.
  //
  // The original 270/250/380/60ms set lost that race in a batched `host-all`,
  // which runs four suites in parallel; the tests passed serially on the same
  // tree. Tune `deadlineScale` alone if a loaded host ever needs more headroom.
  const deadlineScale = 8;
  const storageAggregateBudget = Duration(milliseconds: 270 * deadlineScale);
  const storagePhaseBudget = Duration(milliseconds: 250 * deadlineScale);
  const observationBudget = Duration(milliseconds: 380 * deadlineScale);
  const lateEffectWindow = Duration(milliseconds: 60 * deadlineScale);
  // Must comfortably exceed observationBudget so teardown never masks a result.
  const cleanupBudget = Duration(seconds: 30);

  late Directory root;
  late Directory livenessJournalDirectory;
  late Directory ownerDirectory;
  late DurableNotificationToneLease coordinator;
  late DurableConversationNotificationIdRegistry notificationIdRegistry;
  late RecentBackgroundNotificationGate backgroundGate;
  late RecentRemoteNotificationGate remoteGate;
  late List<MethodCall> notificationCalls;
  late List<StagedPushEnvelope> staged;

  setUp(() {
    root = Directory.systemTemp.createTempSync('background-storage-deadline-');
    livenessJournalDirectory = Directory('${root.path}/liveness-journal');
    debugSetBackgroundStorageLivenessJournal(
      BackgroundStorageLivenessJournal(
        directoryResolver: () async => livenessJournalDirectory,
      ),
    );
    ownerDirectory = Directory('${root.path}/owners')..createSync();
    coordinator = DurableNotificationToneLease(
      directory: ownerDirectory,
      pendingClaimWait: Duration.zero,
      pendingToneReservationWait: Duration.zero,
    );
    final registryDirectory = Directory('${root.path}/notification-ids')
      ..createSync();
    notificationIdRegistry = DurableConversationNotificationIdRegistry(
      directory: registryDirectory,
    );
    backgroundGate = RecentBackgroundNotificationGate(
      filePath: '${root.path}/recent-background.json',
    );
    remoteGate = RecentRemoteNotificationGate(
      filePath: '${root.path}/recent-remote.json',
    );
    final overlay = PendingConversationNotificationOverlayStore(
      directory: Directory('${root.path}/overlay'),
      resolveBinding: () async => 'account-binding',
      secureStore: FakeSecureKeyStore(),
    );
    notificationCalls = <MethodCall>[];
    staged = <StagedPushEnvelope>[];

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    debugSetBackgroundStorageDeadlineDurations(
      aggregate: storageAggregateBudget,
      phase: storagePhaseBudget,
    );
    debugSetRecentBackgroundNotificationGate(backgroundGate);
    debugSetRecentRemoteNotificationGate(remoteGate);
    debugSetBackgroundMessageNotificationCoordinatorResolver(
      () async => coordinator,
    );
    debugSetBackgroundReactionNotificationCoordinatorResolver(
      () async => coordinator,
    );
    debugSetBackgroundConversationNotificationIdRegistryResolver(
      () async => notificationIdRegistry,
    );
    debugSetBackgroundAccountMigrationNetworkGate(({
      String? peerId,
      required String operation,
    }) async {
      return true;
    });
    debugSetBackgroundPushEnvelopeStager((entry) async {
      staged.add(entry);
    });
    debugSetBackgroundPendingConversationNotificationOverlayResolver(
      () async => overlay,
    );
    debugSetBackgroundPushNotificationDisplayEligibilityResolver(
      (_) async => const PushFallbackNotificationDisplayEligibility.allow(),
    );
    debugSetBackgroundPushNotificationResolver((message) async {
      return message.data['type'] == 'group_message'
          ? _groupFallback(message)
          : _directFallback(message);
    });
    debugSetBackgroundGroupNotificationPostShowValidator(
      (_) async => BackgroundGroupNotificationPostShowDecision.keep,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, (call) async {
          notificationCalls.add(call);
          if (call.method == 'initialize') return true;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    debugDefaultTargetPlatformOverride = null;
    debugResetRecentBackgroundNotificationGate();
    debugResetRecentRemoteNotificationGate();
    debugResetBackgroundPushNotificationResolver();
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundDirectMessageLocalStateResolver();
    debugResetBackgroundGroupMessageLocalStateResolver();
    debugResetBackgroundDirectReactionLocalStateResolver();
    debugResetBackgroundGroupReactionLocalStateResolver();
    debugResetBackgroundNotificationLocaleResolver();
    debugResetBackgroundGroupNotificationPostShowValidator();
    debugResetBackgroundMessageNotificationCoordinatorResolver();
    debugResetBackgroundReactionNotificationCoordinatorResolver();
    debugResetBackgroundConversationNotificationIdRegistryResolver();
    debugResetBackgroundAccountMigrationNetworkGate();
    debugResetBackgroundPushEnvelopeStager();
    debugResetBackgroundPendingConversationNotificationOverlayResolver();
    debugResetBackgroundStorageDeadlineDurations();
    debugResetBackgroundStorageLivenessJournal();
    debugResetBackgroundStorageMonotonicClockFactory();
    debugResetBackgroundNotificationsInitialization();
    await backgroundGate.clear();
    await remoteGate.clear();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('held initial direct staging fails closed before eligibility', () async {
    const message = RemoteMessage(
      messageId: 'transport-held-initial-stage',
      data: <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-held-initial-stage',
        'message_id': 'event-held-initial-stage',
        'kem': 'kem-held-initial-stage',
        'ciphertext': 'ciphertext-held-initial-stage',
        'nonce': 'nonce-held-initial-stage',
      },
    );
    final stageEntered = Completer<void>();
    final releaseStage = Completer<void>();
    var eligibilityCalls = 0;
    debugSetBackgroundPushEnvelopeStager((entry) {
      staged.add(entry);
      if (!stageEntered.isCompleted) stageEntered.complete();
      return releaseStage.future;
    });
    debugSetBackgroundPushNotificationDisplayEligibilityResolver((_) async {
      eligibilityCalls += 1;
      return const PushFallbackNotificationDisplayEligibility.allow();
    });

    final handler = firebaseMessagingBackgroundHandler(message);
    try {
      await _awaitSignal(stageEntered.future, 'initial direct stager');
      expect(await _completesWithin(handler, observationBudget), isTrue);
      expect(eligibilityCalls, 0);
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);

      releaseStage.complete();
      await Future<void>.delayed(lateEffectWindow);
      expect(eligibilityCalls, 0);
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);
    } finally {
      if (!releaseStage.isCompleted) releaseStage.complete();
      await handler.timeout(cleanupBudget);
    }
  });

  test('held resolved direct staging fails closed before claims', () async {
    const canonicalEventId = 'event-held-resolved-stage';
    const message = RemoteMessage(
      messageId: 'transport-held-resolved-stage',
      data: <String, dynamic>{
        'type': 'new_message',
        'sender_id': 'peer-held-resolved-stage',
        'kem': 'kem-held-resolved-stage',
        'ciphertext': 'ciphertext-held-resolved-stage',
        'nonce': 'nonce-held-resolved-stage',
      },
    );
    final promotedStageEntered = Completer<void>();
    final releasePromotedStage = Completer<void>();
    var stageCalls = 0;
    debugSetBackgroundPushEnvelopeStager((entry) {
      staged.add(entry);
      stageCalls += 1;
      if (stageCalls == 1) return Future<void>.value();
      if (!promotedStageEntered.isCompleted) promotedStageEntered.complete();
      return releasePromotedStage.future;
    });
    debugSetBackgroundPushNotificationResolver(
      (_) async => const BackgroundPushNotificationFallback(
        title: 'Alice',
        body: 'Alice: hello',
        payload: 'peer-held-resolved-stage',
        resolvedEventIdentity: ResolvedPushEventIdentity.authenticatedInner(
          kind: ConversationNotificationContentKind.message,
          canonicalEventId: canonicalEventId,
        ),
      ),
    );

    final handler = firebaseMessagingBackgroundHandler(message);
    try {
      await _awaitSignal(promotedStageEntered.future, 'resolved direct stager');
      expect(stageCalls, 2);
      expect(await _completesWithin(handler, observationBudget), isTrue);
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);

      releasePromotedStage.complete();
      await Future<void>.delayed(lateEffectWindow);
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);
    } finally {
      if (!releasePromotedStage.isCompleted) releasePromotedStage.complete();
      await handler.timeout(cleanupBudget);
    }
  });

  test(
    'direct staging precedes held eligibility with no late notification effects',
    () async {
      const eventId = 'direct-stage-before-eligibility';
      const message = RemoteMessage(
        messageId: 'transport-direct-stage',
        data: <String, dynamic>{
          'type': 'new_message',
          'sender_id': 'peer-alice',
          'message_id': eventId,
          'kem': 'kem-direct-stage',
          'ciphertext': 'ciphertext-direct-stage',
          'nonce': 'nonce-direct-stage',
        },
      );
      final eligibilityEntered = Completer<void>();
      final releaseEligibility =
          Completer<PushFallbackNotificationDisplayEligibility>();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver((_) {
        if (!eligibilityEntered.isCompleted) eligibilityEntered.complete();
        return releaseEligibility.future;
      });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(eligibilityEntered.future, 'eligibility resolver');

        expect(staged, hasLength(1));
        expect(staged.single.kind, 'chat');
        expect(staged.single.messageId, eventId);
        expect(staged.single.nonce, 'nonce-direct-stage');
        expect(
          await _completesWithin(handler, observationBudget),
          isTrue,
          reason: 'held eligibility must consume a bounded pre-show phase',
        );
        expect(_notificationEffects(notificationCalls), isEmpty);

        releaseEligibility.complete(
          const PushFallbackNotificationDisplayEligibility.allow(),
        );
        await Future<void>.delayed(lateEffectWindow);
        expect(_notificationEffects(notificationCalls), isEmpty);
      } finally {
        if (!releaseEligibility.isCompleted) {
          releaseEligibility.complete(
            const PushFallbackNotificationDisplayEligibility.allow(),
          );
        }
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test(
    'group eligibility timeout is relay-deferred without false stage',
    () async {
      const message = RemoteMessage(
        messageId: 'transport-group-eligibility',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-eligibility',
          'message_id': 'group-eligibility-event',
          'preview_unavailable': '1',
        },
      );
      final eligibilityEntered = Completer<void>();
      final releaseEligibility =
          Completer<PushFallbackNotificationDisplayEligibility>();
      debugSetBackgroundPushNotificationDisplayEligibilityResolver((_) {
        if (!eligibilityEntered.isCompleted) eligibilityEntered.complete();
        return releaseEligibility.future;
      });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(eligibilityEntered.future, 'eligibility resolver');
        expect(
          staged,
          isEmpty,
          reason: 'group relay custody is not local stage',
        );
        expect(
          await _completesWithin(handler, observationBudget),
          isTrue,
          reason: 'held group eligibility must return fail-closed',
        );
        expect(_eventClaimFiles(ownerDirectory), isEmpty);
        expect(_notificationEffects(notificationCalls), isEmpty);

        final journalFiles = livenessJournalDirectory
            .listSync()
            .whereType<File>()
            .toList(growable: false);
        expect(journalFiles, hasLength(1));
        final record = jsonDecode(await journalFiles.single.readAsString());
        expect(record, isA<Map<String, dynamic>>());
        expect(
          (record as Map<String, dynamic>).keys,
          unorderedEquals(<String>[
            'kind',
            'phase',
            'outcome',
            'elapsedBucket',
            'buildMode',
            'engineRole',
          ]),
        );
        expect(record['kind'], 'group_message');
        expect(record['phase'], 'display_eligibility');
        expect(record['outcome'], 'storage_deferred');
        expect(record['engineRole'], 'flutterfire_background');
        final encodedRecord = jsonEncode(record);
        expect(encodedRecord, isNot(contains('transport-group-eligibility')));
        expect(encodedRecord, isNot(contains('group-eligibility-event')));

        releaseEligibility.complete(
          const PushFallbackNotificationDisplayEligibility.allow(),
        );
        await Future<void>.delayed(lateEffectWindow);
        expect(staged, isEmpty);
        expect(_eventClaimFiles(ownerDirectory), isEmpty);
        expect(_notificationEffects(notificationCalls), isEmpty);
      } finally {
        if (!releaseEligibility.isCompleted) {
          releaseEligibility.complete(
            const PushFallbackNotificationDisplayEligibility.allow(),
          );
        }
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test(
    'pending overlay stall before claim is bounded and cannot republish late',
    () async {
      final monotonicClock = _FakeMonotonicClock();
      debugSetBackgroundStorageMonotonicClockFactory(
        () =>
            () => monotonicClock.elapsed,
      );
      const eventId = 'group-overlay-stall-event';
      const message = RemoteMessage(
        messageId: 'transport-group-overlay-stall',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-overlay-stall',
          'message_id': eventId,
          'preview_unavailable': '1',
        },
      );
      final overlayEntered = Completer<void>();
      final releaseOverlay =
          Completer<PendingConversationNotificationOverlayStore>();
      debugSetBackgroundPendingConversationNotificationOverlayResolver(() {
        if (!overlayEntered.isCompleted) overlayEntered.complete();
        return releaseOverlay.future;
      });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(overlayEntered.future, 'pending overlay resolver');
        expect(
          _eventClaimFiles(ownerDirectory),
          isEmpty,
          reason: 'overlay enrichment must precede provisional ownership',
        );
        expect(
          // The injected storage phase still expires after 250 ms. This outer
          // observer only distinguishes bounded completion from an indefinitely
          // retained callback, so leave enough scheduling margin for the full
          // concurrent groups gate.
          await _completesWithin(handler, observationBudget),
          isTrue,
          reason: 'secure overlay storage cannot retain the serial callback',
        );
        expect(_shownEventIdentities(notificationCalls), <String?>[eventId]);

        final committedDuplicate = await coordinator.acquireMessageEventClaim(
          type: 'group_message',
          eventIdentity: eventId,
        );
        expect(
          committedDuplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );

        releaseOverlay.complete(
          PendingConversationNotificationOverlayStore(
            directory: Directory('${root.path}/late-overlay'),
            resolveBinding: () async => 'account-binding',
            secureStore: FakeSecureKeyStore(),
          ),
        );
        await Future<void>.delayed(lateEffectWindow);
        expect(
          _shownEventIdentities(notificationCalls),
          <String?>[eventId],
          reason: 'late enrichment completion cannot publish a second card',
        );
      } finally {
        if (!releaseOverlay.isCompleted) {
          releaseOverlay.complete(
            PendingConversationNotificationOverlayStore(
              directory: Directory('${root.path}/late-overlay-cleanup'),
              resolveBinding: () async => 'account-binding',
              secureStore: FakeSecureKeyStore(),
            ),
          );
        }
        await handler.timeout(cleanupBudget);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    },
  );

  test(
    'reclaimed pre-show claim cannot publish from the stale producer',
    () async {
      const eventId = 'group-stale-owner-event';
      const message = RemoteMessage(
        messageId: 'transport-group-stale-owner',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-stale-owner',
          'message_id': eventId,
          'preview_unavailable': '1',
        },
      );
      var now = DateTime.utc(2026, 8, 3, 20);
      final toneReservationEntered = Completer<void>();
      final releaseToneReservation = Completer<void>();
      coordinator = DurableNotificationToneLease(
        directory: ownerDirectory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        beforeToneWrite: () {
          if (!toneReservationEntered.isCompleted) {
            toneReservationEntered.complete();
          }
          return releaseToneReservation.future;
        },
      );

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(
          toneReservationEntered.future,
          'tone reservation after event claim',
        );
        now = now.add(const Duration(seconds: 61));
        final replacement =
            await DurableNotificationToneLease(
              directory: ownerDirectory,
              now: () => now,
              pendingClaimWait: Duration.zero,
              claimTokenFactory: () => 'replacement-shown-owner',
            ).acquireMessageEventClaim(
              type: 'group_message',
              eventIdentity: eventId,
            );
        expect(
          replacement.disposition,
          DurableNotificationClaimDisposition.acquired,
        );
        expect(await replacement.claim!.commit(), isTrue);

        releaseToneReservation.complete();
        await handler.timeout(observationBudget);
        expect(
          _shownEventIdentities(notificationCalls),
          isEmpty,
          reason:
              'registry retirement may run first, but a producer that lost '
              'its exact token cannot invoke native show',
        );
      } finally {
        if (!releaseToneReservation.isCompleted) {
          releaseToneReservation.complete();
        }
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test(
    'registry retirement remains pre-publication and stale claim is reclaimable',
    () async {
      const eventId = 'group-publication-owner-event';
      const message = RemoteMessage(
        messageId: 'transport-group-publication-owner',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-publication-owner',
          'message_id': eventId,
          'preview_unavailable': '1',
        },
      );
      var now = DateTime.utc(2026, 8, 3, 20);
      coordinator = DurableNotificationToneLease(
        directory: ownerDirectory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'publication-owner',
      );
      final retireEntered = Completer<void>();
      final releaseRetire = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            notificationCalls.add(call);
            if (call.method == 'initialize') return true;
            if (call.method == 'cancel') {
              if (!retireEntered.isCompleted) retireEntered.complete();
              await releaseRetire.future;
            }
            return null;
          });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(
          retireEntered.future,
          'registry retirement before native publication',
        );
        now = now.add(const Duration(seconds: 61));
        final replacement =
            await DurableNotificationToneLease(
              directory: ownerDirectory,
              now: () => now,
              pendingClaimWait: Duration.zero,
              claimTokenFactory: () => 'reclaimed-publication-owner',
            ).acquireMessageEventClaim(
              type: 'group_message',
              eventIdentity: eventId,
            );
        expect(
          replacement.disposition,
          DurableNotificationClaimDisposition.acquired,
          reason: 'registry work must not move the exact owner into publishing',
        );
        expect(await replacement.claim!.commit(), isTrue);

        releaseRetire.complete();
        await handler.timeout(cleanupBudget);
        expect(
          _shownEventIdentities(notificationCalls),
          isEmpty,
          reason: 'the stale producer revalidates immediately before show',
        );
        final duplicate = await coordinator.acquireMessageEventClaim(
          type: 'group_message',
          eventIdentity: eventId,
        );
        expect(
          duplicate.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
      } finally {
        if (!releaseRetire.isCompleted) releaseRetire.complete();
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test(
    'aged native publication attempt becomes terminal instead of reclaimable',
    () async {
      const eventId = 'group-aged-publication-event';
      const message = RemoteMessage(
        messageId: 'transport-group-aged-publication',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-aged-publication',
          'message_id': eventId,
          'preview_unavailable': '1',
        },
      );
      var now = DateTime.utc(2026, 8, 3, 20);
      coordinator = DurableNotificationToneLease(
        directory: ownerDirectory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'native-publication-owner',
      );
      final showEntered = Completer<void>();
      final releaseShow = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            notificationCalls.add(call);
            if (call.method == 'initialize') return true;
            if (call.method == 'show') {
              if (!showEntered.isCompleted) showEntered.complete();
              await releaseShow.future;
            }
            return null;
          });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(showEntered.future, 'actual native show callback');
        final claimFile = File(
          '${ownerDirectory.path}/${DurableNotificationToneLease.eventClaimsDirectoryName}/'
          '${DurableNotificationToneLease.messageEventClaimFileName(type: 'group_message', eventIdentity: eventId)}',
        );
        expect(claimFile.readAsStringSync(), contains('"state":"publishing"'));

        now = now.add(const Duration(seconds: 61));
        final replacement =
            await DurableNotificationToneLease(
              directory: ownerDirectory,
              now: () => now,
              pendingClaimWait: Duration.zero,
              claimTokenFactory: () => 'must-not-reclaim',
            ).acquireMessageEventClaim(
              type: 'group_message',
              eventIdentity: eventId,
            );
        expect(
          replacement.disposition,
          DurableNotificationClaimDisposition.committedOrUnavailable,
        );
        final terminalRecord = claimFile.readAsStringSync();
        expect(terminalRecord, contains('"state":"committed"'));
        expect(terminalRecord, contains('"publicationOutcome":"unknown"'));
        expect(terminalRecord, isNot(contains('native-publication-owner')));

        releaseShow.complete();
        await handler.timeout(cleanupBudget);
        expect(_shownEventIdentities(notificationCalls), <String?>[eventId]);
      } finally {
        if (!releaseShow.isCompleted) releaseShow.complete();
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test(
    'reclaimed tone token forces a stale producer to publish silently',
    () async {
      const groupId = 'group-tone-owner';
      const eventId = 'group-tone-owner-event';
      const conversationKey = 'group:$groupId';
      const message = RemoteMessage(
        messageId: 'transport-group-tone-owner',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': groupId,
          'message_id': eventId,
          'preview_unavailable': '1',
        },
      );
      var now = DateTime.utc(2026, 8, 3, 20);
      coordinator = DurableNotificationToneLease(
        directory: ownerDirectory,
        now: () => now,
        pendingClaimWait: Duration.zero,
        pendingToneReservationWait: Duration.zero,
        claimTokenFactory: () => 'stale-tone-producer',
      );
      final idLookupEntered = Completer<void>();
      final releaseIdLookup = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notificationsChannel, (call) async {
            notificationCalls.add(call);
            if (call.method == 'initialize') return true;
            if (call.method == 'getActiveNotifications') {
              if (!idLookupEntered.isCompleted) idLookupEntered.complete();
              await releaseIdLookup.future;
            }
            return null;
          });

      final handler = firebaseMessagingBackgroundHandler(message);
      try {
        await _awaitSignal(
          idLookupEntered.future,
          'notification-id lookup after tone reservation',
        );
        now = now.add(const Duration(seconds: 61));
        final newerTone = await DurableNotificationToneLease(
          directory: ownerDirectory,
          now: () => now,
          pendingToneReservationWait: Duration.zero,
          claimTokenFactory: () => 'newer-tone-producer',
        ).reserveTone(conversationKey);
        expect(newerTone, isNotNull);
        final newerPublication = await newerTone!.publishAndCommit(() async {});
        expect(newerPublication.publishedAudibly, isTrue);
        expect(newerPublication.toneCommitted, isTrue);

        releaseIdLookup.complete();
        await handler.timeout(cleanupBudget);
        final show = notificationCalls.singleWhere(
          (call) => call.method == 'show',
        );
        final specifics = (show.arguments as Map)['platformSpecifics'] as Map;
        expect(
          specifics['playSound'],
          isFalse,
          reason: 'the producer that lost its exact tone token must not sound',
        );
      } finally {
        if (!releaseIdLookup.isCompleted) releaseIdLookup.complete();
        await handler.timeout(cleanupBudget);
      }
    },
  );

  test('second local-state read is bounded and cannot show late', () async {
    const message = RemoteMessage(
      messageId: 'transport-second-local-state',
      data: <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-second-local-state',
        'message_id': 'group-second-local-state-event',
        'preview_unavailable': '1',
      },
    );
    final secondReadEntered = Completer<void>();
    final releaseSecondRead = Completer<BackgroundGroupMessageLocalState?>();
    var readCount = 0;
    debugResetBackgroundPushNotificationDisplayEligibilityResolver();
    debugResetBackgroundPushNotificationResolver();
    debugSetBackgroundGroupMessageLocalStateResolver((message) {
      readCount += 1;
      if (readCount == 1) {
        return Future<BackgroundGroupMessageLocalState?>.value(
          _authorizedGroupMessageState(message),
        );
      }
      if (!secondReadEntered.isCompleted) secondReadEntered.complete();
      return releaseSecondRead.future;
    });

    final handler = firebaseMessagingBackgroundHandler(message);
    try {
      await _awaitSignal(secondReadEntered.future, 'second local-state read');
      expect(readCount, 2);
      expect(
        await _completesWithin(handler, observationBudget),
        isTrue,
        reason: 'the repeated preview read must share the storage deadline',
      );
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);

      releaseSecondRead.complete(_authorizedGroupMessageState(message));
      await Future<void>.delayed(lateEffectWindow);
      expect(_eventClaimFiles(ownerDirectory), isEmpty);
      expect(_notificationEffects(notificationCalls), isEmpty);
    } finally {
      if (!releaseSecondRead.isCompleted) {
        releaseSecondRead.complete(_authorizedGroupMessageState(message));
      }
      await handler.timeout(cleanupBudget);
    }
  });

  test('group post-show stall keeps committed generation', () async {
    final monotonicClock = _FakeMonotonicClock();
    debugSetBackgroundStorageMonotonicClockFactory(
      () =>
          () => monotonicClock.elapsed,
    );
    const eventId = 'group-post-show-event';
    const groupId = 'group-post-show';
    const message = RemoteMessage(
      messageId: 'transport-group-post-show',
      data: <String, dynamic>{
        'type': 'group_message',
        'groupId': groupId,
        'message_id': eventId,
        'preview_unavailable': '1',
      },
    );
    final validatorEntered = Completer<void>();
    final releaseValidator =
        Completer<BackgroundGroupNotificationPostShowDecision>();
    debugSetBackgroundGroupNotificationPostShowValidator((comparand) {
      expect(comparand, isA<BackgroundGroupMessageNotificationComparand>());
      final exact = comparand as BackgroundGroupMessageNotificationComparand;
      expect(exact.groupId, groupId);
      expect(exact.messageId, eventId);
      if (!validatorEntered.isCompleted) validatorEntered.complete();
      return releaseValidator.future;
    });

    final handler = firebaseMessagingBackgroundHandler(message);
    try {
      await _awaitSignal(validatorEntered.future, 'group post-show validator');
      final shown = _singleShownEnvelope(notificationCalls);
      expect(shown.conversationKey, 'group:$groupId');
      expect(shown.metadata.eventIdentity, eventId);
      expect(
        await _storedMetadata(notificationIdRegistry, shown.conversationKey),
        shown.metadata,
      );
      await _expectCommittedOwners(
        coordinator: coordinator,
        ownerDirectory: ownerDirectory,
        claimType: 'group_message',
        eventId: eventId,
        conversationKey: shown.conversationKey,
      );

      expect(
        await _completesWithin(handler, observationBudget),
        isTrue,
        reason: 'post-show validation must return unknown at its phase bound',
      );
      expect(_cancelCount(notificationCalls), 1);

      releaseValidator.complete(
        BackgroundGroupNotificationPostShowDecision.retire,
      );
      await Future<void>.delayed(lateEffectWindow);
      expect(_cancelCount(notificationCalls), 1);
      expect(
        await _storedMetadata(notificationIdRegistry, shown.conversationKey),
        shown.metadata,
      );
    } finally {
      if (!releaseValidator.isCompleted) {
        releaseValidator.complete(
          BackgroundGroupNotificationPostShowDecision.retire,
        );
      }
      await handler.timeout(cleanupBudget);
    }
  });

  test('direct post-show stall keeps committed generation', () async {
    const eventId = 'direct-post-show-event';
    const peerId = 'peer-direct-post-show';
    const message = RemoteMessage(
      messageId: 'transport-direct-post-show',
      data: <String, dynamic>{
        'type': 'new_message',
        'sender_id': peerId,
        'message_id': eventId,
        'kem': 'kem-direct-post-show',
        'ciphertext': 'ciphertext-direct-post-show',
        'nonce': 'nonce-direct-post-show',
      },
    );
    final secureReadEntered = Completer<void>();
    final releaseSecureRead = Completer<String?>();
    final monotonicClock = _FakeMonotonicClock();
    debugSetBackgroundStorageMonotonicClockFactory(
      () =>
          () => monotonicClock.elapsed,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>?;
          if (call.method == 'read' &&
              arguments?['key'] == 'db_encryption_key') {
            if (!secureReadEntered.isCompleted) secureReadEntered.complete();
            return releaseSecureRead.future;
          }
          return null;
        });

    final handler = firebaseMessagingBackgroundHandler(message);
    try {
      await _awaitSignal(secureReadEntered.future, 'direct post-show read');
      final shown = _singleShownEnvelope(notificationCalls);
      expect(shown.conversationKey, peerId);
      expect(shown.metadata.eventIdentity, eventId);
      expect(
        await _storedMetadata(notificationIdRegistry, shown.conversationKey),
        shown.metadata,
      );
      await _expectCommittedOwners(
        coordinator: coordinator,
        ownerDirectory: ownerDirectory,
        claimType: 'new_message',
        eventId: eventId,
        conversationKey: shown.conversationKey,
      );

      expect(
        await _completesWithin(handler, observationBudget),
        isTrue,
        reason: 'direct post-show storage must return unknown at its bound',
      );
      expect(_cancelCount(notificationCalls), 1);

      releaseSecureRead.complete(null);
      await Future<void>.delayed(lateEffectWindow);
      expect(_cancelCount(notificationCalls), 1);
      expect(
        await _storedMetadata(notificationIdRegistry, shown.conversationKey),
        shown.metadata,
      );
    } finally {
      if (!releaseSecureRead.isCompleted) releaseSecureRead.complete(null);
      await handler.timeout(cleanupBudget);
    }
  });

  test('iOS preserves the existing unbounded storage-call behavior', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const message = RemoteMessage(
      messageId: 'transport-ios-preservation',
      data: <String, dynamic>{
        'type': 'group_message',
        'groupId': 'group-ios-preservation',
        'message_id': 'event-ios-preservation',
        'preview_unavailable': '1',
      },
    );
    final eligibilityEntered = Completer<void>();
    final releaseEligibility =
        Completer<PushFallbackNotificationDisplayEligibility>();
    debugSetBackgroundPushNotificationDisplayEligibilityResolver((_) {
      if (!eligibilityEntered.isCompleted) eligibilityEntered.complete();
      return releaseEligibility.future;
    });

    var completed = false;
    final handler = firebaseMessagingBackgroundHandler(message);
    handler.then((_) => completed = true);
    try {
      await _awaitSignal(eligibilityEntered.future, 'iOS eligibility resolver');
      await Future<void>.delayed(
        storagePhaseBudget + const Duration(milliseconds: 80),
      );
      expect(
        completed,
        isFalse,
        reason: 'Plan 334 storage deadlines are Android-only',
      );
      expect(
        livenessJournalDirectory.existsSync()
            ? livenessJournalDirectory.listSync().whereType<File>()
            : const <File>[],
        isEmpty,
      );
      releaseEligibility.complete(
        const PushFallbackNotificationDisplayEligibility.suppressed(
          'ios_preservation_fixture',
        ),
      );
      await handler.timeout(cleanupBudget);
      expect(completed, isTrue);
    } finally {
      if (!releaseEligibility.isCompleted) {
        releaseEligibility.complete(
          const PushFallbackNotificationDisplayEligibility.suppressed(
            'ios_preservation_cleanup',
          ),
        );
      }
      await handler.timeout(cleanupBudget);
    }
  });

  test(
    'cumulative storage phases consume one budget and second event progresses',
    () async {
      const firstEventId = 'serial-first-held-event';
      const secondEventId = 'serial-second-progress-event';
      const first = RemoteMessage(
        messageId: 'transport-serial-first',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-serial-first',
          'message_id': firstEventId,
          'preview_unavailable': '1',
        },
      );
      const second = RemoteMessage(
        messageId: 'transport-serial-second',
        data: <String, dynamic>{
          'type': 'group_message',
          'groupId': 'group-serial-second',
          'message_id': secondEventId,
          'preview_unavailable': '1',
        },
      );
      final firstResolverEntered = Completer<void>();
      final releaseFirstResolver =
          Completer<BackgroundPushNotificationFallback>();
      final monotonicClock = _FakeMonotonicClock();
      debugSetBackgroundStorageMonotonicClockFactory(
        () =>
            () => monotonicClock.elapsed,
      );
      debugSetBackgroundPushNotificationDisplayEligibilityResolver((
        message,
      ) async {
        if (message.data['message_id'] == firstEventId) {
          monotonicClock.advance(const Duration(milliseconds: 240));
        }
        return const PushFallbackNotificationDisplayEligibility.allow();
      });
      debugSetBackgroundPushNotificationResolver((message) {
        if (message.data['message_id'] == firstEventId) {
          if (!firstResolverEntered.isCompleted) {
            firstResolverEntered.complete();
          }
          return releaseFirstResolver.future;
        }
        return Future<BackgroundPushNotificationFallback>.value(
          _groupFallback(message),
        );
      });
      final queue = _SerialBackgroundQueue();
      final firstHandler = queue.dispatch(first);
      final secondHandler = queue.dispatch(second);

      try {
        await _awaitSignal(firstResolverEntered.future, 'first resolver');
        expect(
          await _completesWithin(secondHandler, observationBudget),
          isTrue,
          reason:
              'the first callback must release the serial queue using one '
              'cumulative budget',
        );

        final shownEvents = _shownEventIdentities(notificationCalls);
        expect(shownEvents, <String?>[secondEventId]);
        expect(shownEvents, isNot(contains(firstEventId)));

        releaseFirstResolver.complete(_groupFallback(first));
        await Future<void>.delayed(lateEffectWindow);
        expect(_shownEventIdentities(notificationCalls), <String?>[
          secondEventId,
        ]);
      } finally {
        if (!releaseFirstResolver.isCompleted) {
          releaseFirstResolver.complete(_groupFallback(first));
        }
        await Future.wait<void>(<Future<void>>[
          firstHandler,
          secondHandler,
        ]).timeout(cleanupBudget);
      }
    },
  );
}

BackgroundPushNotificationFallback _directFallback(RemoteMessage message) {
  final peerId = message.data['sender_id']?.toString() ?? 'peer-direct';
  return BackgroundPushNotificationFallback(
    title: 'Alice',
    body: 'Alice: hello',
    payload: peerId,
  );
}

BackgroundPushNotificationFallback _groupFallback(RemoteMessage message) {
  final groupId = message.data['groupId']?.toString() ?? 'group-test';
  final eventId = message.data['message_id']?.toString() ?? 'event-test';
  return BackgroundPushNotificationFallback(
    title: 'Team',
    body: 'Alice: hello',
    payload: 'group:$groupId|message:$eventId',
    groupComparand: BackgroundGroupMessageNotificationComparand(
      groupId: groupId,
      messageId: eventId,
      senderPeerId: 'peer-alice',
    ),
  );
}

BackgroundGroupMessageLocalState _authorizedGroupMessageState(
  RemoteMessage message,
) {
  final groupId = message.data['groupId']?.toString() ?? 'group-test';
  final eventId = message.data['message_id']?.toString();
  return BackgroundGroupMessageLocalState(
    previewContext: GroupMessageNotificationContext(
      groupId: groupId,
      groupName: 'Team',
      localPeerId: 'peer-local',
      senderPeerId: 'peer-alice',
      senderUsername: 'Alice',
      expectedMessageId: eventId,
    ),
    groupKey: null,
    keyEpoch: null,
  );
}

Future<void> _awaitSignal(Future<void> signal, String label) {
  return signal.timeout(
    const Duration(seconds: 2),
    onTimeout: () => throw TestFailure('fixture never entered $label'),
  );
}

Future<bool> _completesWithin(Future<void> future, Duration duration) {
  return Future.any<bool>(<Future<bool>>[
    future.then((_) => true),
    Future<bool>.delayed(duration, () => false),
  ]);
}

List<MethodCall> _notificationEffects(List<MethodCall> calls) => calls
    .where((call) => call.method == 'show' || call.method == 'cancel')
    .toList(growable: false);

int _cancelCount(List<MethodCall> calls) =>
    calls.where((call) => call.method == 'cancel').length;

ConversationNotificationPayloadEnvelope _singleShownEnvelope(
  List<MethodCall> calls,
) {
  final show = calls.singleWhere((call) => call.method == 'show');
  final arguments = show.arguments as Map<Object?, Object?>;
  final envelope = decodeConversationNotificationPayload(
    arguments['payload'] as String?,
  );
  expect(envelope, isNotNull);
  return envelope!;
}

List<String?> _shownEventIdentities(List<MethodCall> calls) => calls
    .where((call) => call.method == 'show')
    .map((call) {
      final arguments = call.arguments as Map<Object?, Object?>;
      return decodeConversationNotificationPayload(
        arguments['payload'] as String?,
      )?.metadata.eventIdentity;
    })
    .toList(growable: false);

List<FileSystemEntity> _eventClaimFiles(Directory ownerDirectory) {
  final directory = Directory(
    '${ownerDirectory.path}/'
    '${DurableNotificationToneLease.eventClaimsDirectoryName}',
  );
  if (!directory.existsSync()) return const <FileSystemEntity>[];
  return directory.listSync().toList(growable: false);
}

Future<ConversationNotificationContentMetadata?> _storedMetadata(
  DurableConversationNotificationIdRegistry registry,
  String conversationKey,
) async {
  final notificationId = await registry.lookup(conversationKey);
  expect(notificationId, isNotNull);
  return registry.lookupContentMetadata(
    conversationKey: conversationKey,
    notificationId: notificationId!,
  );
}

Future<void> _expectCommittedOwners({
  required DurableNotificationToneLease coordinator,
  required Directory ownerDirectory,
  required String claimType,
  required String eventId,
  required String conversationKey,
}) async {
  final claimFile = File(
    '${ownerDirectory.path}/'
    '${DurableNotificationToneLease.eventClaimsDirectoryName}/'
    '${DurableNotificationToneLease.messageEventClaimFileName(type: claimType, eventIdentity: eventId)}',
  );
  expect(claimFile.existsSync(), isTrue);
  final claim = jsonDecode(await claimFile.readAsString());
  expect(claim, isA<Map<String, dynamic>>());
  expect(claim as Map<String, dynamic>, containsPair('state', 'committed'));
  expect(
    await coordinator.reserveTone(conversationKey),
    isNull,
    reason: 'the successful native show must retain its committed tone owner',
  );
}

final class _SerialBackgroundQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> dispatch(RemoteMessage message) {
    final current = _tail.then(
      (_) => firebaseMessagingBackgroundHandler(message),
    );
    _tail = current.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    return current;
  }
}

final class _FakeMonotonicClock {
  Duration _elapsed = Duration.zero;

  Duration get elapsed => _elapsed;

  void advance(Duration duration) {
    _elapsed += duration;
  }
}
