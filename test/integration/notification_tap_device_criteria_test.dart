import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/device_criteria.dart';

void main() {
  group('Plan 258 notification device criteria', () {
    test(
      'Android A6 requires real relay replay, acknowledgement, purge, and dedupe',
      () {
        final artifact = _notificationArtifact(
          scenario: 'tc_a6_replay_before_ack_custody',
          checks: const <String>[
            'realGoBridgeClient',
            'realRelay',
            'relayInboxSeeded',
            'replayBeforeAckObserved',
            'firstDrainAckPurgedRelay',
            'secondDrainNoDuplicateRender',
          ],
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

    test(
      'Android B11 requires real crypto, staged visibility before drain, and dedupe',
      () {
        final artifact = _notificationArtifact(
          scenario: 'tc_b11_payload_persist_pre_drain',
          checks: const <String>[
            'realPeerCiphertext',
            'realGoBridgeClient',
            'realRelay',
            'stagedEnvelopeRead',
            'visibleBeforeDrain',
            'noDrainBeforeVisibility',
            'laterDrainNoDuplicate',
          ],
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

    test(
      'Android B12 warm requires FCM/background staging and offline tap visibility',
      () {
        final artifact = _notificationArtifact(
          scenario: 'payload_fast_path_android_receiver',
          checks: _warmChecks,
          evidence: <String, Object?>{'warmAlertChannel': 'mknoon_messages'},
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

    test(
      'Android B12 cold requires terminated process, notification launch, and pre-drain visibility',
      () {
        final artifact = _notificationArtifact(
          scenario: 'payload_fast_path_cold_kill',
          checks: _coldChecks,
          evidence: _coldEvidence,
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

    test('b12 warm artifact without the audible-channel check is rejected', () {
      final artifact = _notificationArtifact(
        scenario: 'payload_fast_path_android_receiver',
        checks: _warmChecks
            .where((check) => check != 'b12.warm_audible_channel')
            .toList(growable: false),
        evidence: <String, Object?>{'warmAlertChannel': 'mknoon_messages'},
      );
      final result = validateNotificationArtifact(artifact);
      expect(result.ok, isFalse);
      expect(result.detail, contains('b12.warm_audible_channel'));
    });

    test(
      'b12 warm artifact with the check but no measured evidence is rejected',
      () {
        final missingEvidence = _notificationArtifact(
          scenario: 'payload_fast_path_android_receiver',
          checks: _warmChecks,
        );
        final missingResult = validateNotificationArtifact(missingEvidence);
        expect(missingResult.ok, isFalse);
        expect(missingResult.detail, contains('warmAlertChannel'));

        final emptyEvidence = _notificationArtifact(
          scenario: 'payload_fast_path_android_receiver',
          checks: _warmChecks,
          evidence: const <String, Object?>{},
        );
        final emptyResult = validateNotificationArtifact(emptyEvidence);
        expect(emptyResult.ok, isFalse);
        expect(emptyResult.detail, contains('warmAlertChannel'));
      },
    );

    test('b12 artifacts measured on the silent channel are rejected', () {
      final warm = _notificationArtifact(
        scenario: 'payload_fast_path_android_receiver',
        checks: _warmChecks,
        evidence: <String, Object?>{
          'warmAlertChannel': 'mknoon_messages_silent',
        },
      );
      expect(validateNotificationArtifact(warm).ok, isFalse);

      final cold = _notificationArtifact(
        scenario: 'payload_fast_path_cold_kill',
        checks: _coldChecks,
        evidence: <String, Object?>{
          ..._coldEvidence,
          'coldAlertChannel': 'mknoon_messages_silent',
        },
      );
      final coldResult = validateNotificationArtifact(cold);
      expect(coldResult.ok, isFalse);
      expect(coldResult.detail, contains('coldAlertChannel'));
    });

    test('b12 cold artifact without its measured channel evidence is rejected', () {
      final artifact = _notificationArtifact(
        scenario: 'payload_fast_path_cold_kill',
        checks: _coldChecks,
      );
      final result = validateNotificationArtifact(artifact);
      expect(result.ok, isFalse);
      expect(result.detail, contains('coldAlertChannel'));

      final missingCheck = _notificationArtifact(
        scenario: 'payload_fast_path_cold_kill',
        checks: _coldChecks
            .where((check) => check != 'b12.cold_audible_channel')
            .toList(growable: false),
        evidence: _coldEvidence,
      );
      expect(validateNotificationArtifact(missingCheck).ok, isFalse);
    });

    // Plan 388 (TC-388-11). The cold leg's graded push is the FIRST wake after
    // an app kill, so it sits in the exact slot where the 2 s
    // display_eligibility budget can be exhausted. The leg already captures
    // that window; requiring the scan result is what stops an artifact from
    // claiming a clean cold wake it never looked for.
    test('cold-kill artifacts must carry a wake deferral scan result', () {
      final clean = _notificationArtifact(
        scenario: 'payload_fast_path_cold_kill',
        checks: _coldChecks,
        evidence: _coldEvidence,
      );
      expect(validateNotificationArtifact(clean).ok, isTrue);

      final missingScan = _notificationArtifact(
        scenario: 'payload_fast_path_cold_kill',
        checks: _coldChecks,
        evidence: <String, Object?>{'coldAlertChannel': 'mknoon_messages'},
      );
      final missingResult = validateNotificationArtifact(missingScan);
      expect(missingResult.ok, isFalse);
      expect(missingResult.detail, contains('coldWakeDeferralScan'));

      // Only a scan that found nothing counts. A deferred wake, an unscanned
      // wake, and a blank value are all rejections, not softer passes.
      for (final value in <Object?>[
        'deferred',
        'skipped',
        'unknown',
        '',
        false,
      ]) {
        final other = _notificationArtifact(
          scenario: 'payload_fast_path_cold_kill',
          checks: _coldChecks,
          evidence: <String, Object?>{
            ..._coldEvidence,
            'coldWakeDeferralScan': value,
          },
        );
        expect(
          validateNotificationArtifact(other).ok,
          isFalse,
          reason: 'coldWakeDeferralScan "$value" must not validate',
        );
      }
    });

    test('G7 permission-denied proof binds attempt, custody, and recovery', () {
      expect(
        validateNotificationArtifact(_permissionDeniedArtifact()).ok,
        isTrue,
      );

      for (final mutation in <void Function(Map<String, Object?>)>[
        // A zero-card census is vacuous without proof the push arrived.
        (artifact) => (artifact['evidence']! as Map).remove(
          'permissionDeniedBackgroundReceiptCount',
        ),
        // A wake receipt is not a post attempt.
        (artifact) => (artifact['evidence']! as Map).remove(
          'permissionDeniedPostAttemptEvent',
        ),
        (artifact) =>
            (artifact['evidence']! as Map)['permissionDeniedPostAttemptEvent'] =
                'PUSH_BACKGROUND_MESSAGE_RECEIVED',
        (artifact) =>
            (artifact['evidence']! as Map).remove('permissionDeniedHealthEvent'),
        (artifact) =>
            (artifact['evidence']! as Map)['permissionDeniedCardCount'] = 1,
        (artifact) =>
            (artifact['evidence']! as Map)['permissionRegrantAlertChannel'] =
                'mknoon_messages_silent',
        (artifact) => (artifact['checks']! as Map).remove(
          'g7.permission_denied_typed_health',
        ),
        (artifact) => artifact.remove('evidence'),
      ]) {
        final artifact = _permissionDeniedArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('G7 token refresh must be same-process and actually rotate', () {
      expect(validateNotificationArtifact(_tokenRefreshArtifact()).ok, isTrue);

      for (final mutation in <void Function(Map<String, Object?>)>[
        // A relaunch also traverses the stream path in the new process.
        (artifact) =>
            (artifact['evidence']! as Map)['tokenRefreshPidAfter'] = '5678',
        // deleteToken can return without the provider ever minting a new
        // token; an unchanged hash is not a rotation.
        (artifact) =>
            (artifact['evidence']! as Map)['tokenHashPrefixAfter'] =
                '0123456789ab',
        (artifact) =>
            (artifact['evidence']!
                as Map)['tokenRefreshStartupAttemptsInWindow'] = 1,
        (artifact) =>
            (artifact['evidence']! as Map)['tokenRefreshSuccessTrigger'] =
                'startup',
        (artifact) =>
            (artifact['evidence']! as Map).remove('tokenRefreshAlertChannel'),
        (artifact) => (artifact['checks']! as Map).remove(
          'g7.token_refresh_reregistered_same_process',
        ),
      ]) {
        final artifact = _tokenRefreshArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('G7 channel-disabled proof requires the measured importance probe', () {
      expect(
        validateNotificationArtifact(_channelDisabledArtifact()).ok,
        isTrue,
      );

      for (final mutation in <void Function(Map<String, Object?>)>[
        // A skipped Settings toggle leaves importance at 4.
        (artifact) =>
            (artifact['evidence']! as Map)['channelDisabledImportance'] = 4,
        (artifact) =>
            (artifact['evidence']! as Map)['channelDisabledCardCount'] = 1,
        (artifact) =>
            (artifact['evidence']! as Map)['channelReenabledImportance'] = 0,
        // Blocking the silent channel TOO would make the zero-card census
        // pass without the app changing anything, masking the very leak this
        // leg exists to catch — so a blocked silent channel is invalid
        // evidence, not a stricter run.
        (artifact) =>
            (artifact['evidence']! as Map)['channelDisabledSilentImportance'] =
                0,
        (artifact) =>
            (artifact['evidence']! as Map).remove(
              'channelDisabledSilentImportance',
            ),
        (artifact) =>
            (artifact['evidence']! as Map)['channelReenabledSilentImportance'] =
                0,
        (artifact) =>
            (artifact['evidence']! as Map).remove('channelDisabledImportance'),
        (artifact) =>
            (artifact['evidence']! as Map).remove(
              'channelDisabledPostAttemptEvent',
            ),
        (artifact) =>
            (artifact['checks']! as Map).remove('g7.channel_reenable_recovery'),
      ]) {
        final artifact = _channelDisabledArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('G7 Doze proof requires both idle boundaries and a typed arm', () {
      expect(validateNotificationArtifact(_dozeArtifact()).ok, isTrue);

      final deferred = _dozeArtifact();
      (deferred['evidence']! as Map)['dozeDisposition'] =
          'deferred_until_maintenance';
      (deferred['evidence']! as Map)['dozeStateAtObservation'] =
          'IDLE_MAINTENANCE';
      expect(validateNotificationArtifact(deferred).ok, isTrue);

      for (final mutation in <void Function(Map<String, Object?>)>[
        // A device that was never idle cannot claim delivery during idle.
        (artifact) =>
            (artifact['evidence']! as Map)['dozeStateBeforeSend'] = 'ACTIVE',
        (artifact) =>
            (artifact['evidence']! as Map).remove('dozeStateAtObservation'),
        // A device that woke up before delivery proves nothing about Doze.
        (artifact) =>
            (artifact['evidence']! as Map)['dozeStateAtObservation'] = 'ACTIVE',
        (artifact) =>
            (artifact['evidence']! as Map)['dozeDisposition'] = 'probably_fine',
        (artifact) =>
            (artifact['evidence']! as Map)['dozeConvergedCardCount'] = 2,
        (artifact) =>
            (artifact['checks']! as Map).remove('g7.doze_forced_idle_proven'),
      ]) {
        final artifact = _dozeArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('B13 dual-path proof binds its measured card count and channel', () {
      final artifact = _notificationArtifact(
        scenario: 'tc_b13_dual_path_single_alert',
        checks: const <String>[
          'b13.dual_attempt',
          'b13.single_card',
          'b13.single_audible_channel',
          'b13.losing_path_typed_suppression',
        ],
        evidence: <String, Object?>{
          'activeCardCount': 1,
          'alertSilent': false,
          'survivingCardChannel': 'mknoon_messages',
        },
      );
      expect(validateNotificationArtifact(artifact).ok, isTrue);

      // A silent SURVIVOR is accepted: the losing path's same-ID reconcile
      // moves the record after the alert has already been measured. A silent
      // ALERT is still a failure — that is the mutation below.
      final reconciled = _notificationArtifact(
        scenario: 'tc_b13_dual_path_single_alert',
        checks: const <String>[
          'b13.dual_attempt',
          'b13.single_card',
          'b13.single_audible_channel',
          'b13.losing_path_typed_suppression',
        ],
        evidence: <String, Object?>{
          'activeCardCount': 1,
          'alertSilent': false,
          'survivingCardChannel': 'mknoon_messages_silent',
        },
      );
      expect(validateNotificationArtifact(reconciled).ok, isTrue);

      for (final mutation in <void Function(Map<String, Object?>)>[
        (item) => (item['evidence']! as Map)['activeCardCount'] = 2,
        (item) => (item['evidence']! as Map)['alertSilent'] = true,
        (item) => (item['evidence']! as Map).remove('alertSilent'),
        (item) => (item['evidence']! as Map)['survivingCardChannel'] =
            'some_other_app_channel',
        (item) => (item['evidence']! as Map).remove('survivingCardChannel'),
        (item) => item.remove('evidence'),
      ]) {
        final mutated = _notificationArtifact(
          scenario: 'tc_b13_dual_path_single_alert',
          checks: const <String>[
            'b13.dual_attempt',
            'b13.single_card',
            'b13.single_audible_channel',
            'b13.losing_path_typed_suppression',
          ],
          evidence: <String, Object?>{
            'activeCardCount': 1,
            'alertSilent': false,
            'survivingCardChannel': 'mknoon_messages',
          },
        );
        mutation(mutated);
        expect(validateNotificationArtifact(mutated).ok, isFalse);
      }
    });

    test('iOS receiver requires the durable APNs/NSE proof chain', () {
      final artifact = _iosNotificationArtifact();
      expect(validateNotificationArtifact(artifact).ok, isTrue);

      artifact['platform'] = 'android';
      expect(validateNotificationArtifact(artifact).ok, isFalse);
    });

    test('iOS durable proof rejects missing or forged provenance', () {
      for (final mutation in <void Function(Map<String, Object?>)>[
        (artifact) => artifact.remove('automationReceiptSha256'),
        (artifact) => artifact['schema'] = 'mknoon.sims.proof.v0',
        (artifact) => artifact['capabilityId'] = 'notifications.other',
        (artifact) => artifact['validatorIds'] = <String>['forged'],
        (artifact) => artifact['buildProfile'] = 'ios.simulator.e2e',
        (artifact) => artifact['stagingEnvironment'] = 'production',
        (artifact) => artifact['childBuildCount'] = 1,
        (artifact) => artifact['manualActionCount'] = 1,
        (artifact) => artifact['runId'] = '../unsafe',
        (artifact) => artifact['nonce'] = 'unsafe token',
        (artifact) => artifact['candidateAppRevision'] = ' unsafe',
        (artifact) => artifact['candidateRelayRevision'] = 'unsafe\nvalue',
        (artifact) => artifact['unexpected'] = true,
      ]) {
        final artifact = _iosNotificationArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('iOS durable proof rejects incomplete or broken evidence digests', () {
      for (final mutation in <void Function(Map<String, Object?>)>[
        (artifact) =>
            (artifact['evidenceSha256']! as Map).remove('payloadProducer'),
        (artifact) =>
            (artifact['evidenceSha256']! as Map)['apnsPayload'] = 'not-a-sha',
        (artifact) =>
            (artifact['evidenceSha256']! as Map)['unexpected'] = _digest,
        (artifact) => artifact['preparedApplicationSha256'] = 'b' * 64,
        (artifact) => artifact['payloadProducerSha256'] = 'b' * 64,
        (artifact) => artifact['apnsPayloadSha256'] = 'b' * 64,
        (artifact) => artifact['providerRequestSha256'] = 'A' * 64,
        (artifact) => artifact['candidateRelaySha256'] = 'A' * 64,
        (artifact) => artifact['automationReceiptSha256'] = 'a' * 63,
      ]) {
        final artifact = _iosNotificationArtifact();
        mutation(artifact);
        expect(validateNotificationArtifact(artifact).ok, isFalse);
      }
    });

    test('notification proof rejects secret-bearing durable fields', () {
      final artifact = _iosNotificationArtifact()
        ..['apnsToken'] = 'raw-provider-token';
      final result = validateNotificationArtifact(artifact);
      expect(result.ok, isFalse);
      expect(result.detail, contains(r'$.apnsToken'));

      final privateKey = _iosNotificationArtifact()
        ..['candidateAppRevision'] = '-----BEGIN PRIVATE KEY-----';
      final privateKeyResult = validateNotificationArtifact(privateKey);
      expect(privateKeyResult.ok, isFalse);
      expect(privateKeyResult.detail, contains(r'$.candidateAppRevision'));
    });
  });
}

const String _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _iosNotificationArtifact() {
  return <String, Object?>{
    'schema': 'mknoon.sims.proof.v1',
    'capabilityId': 'notifications.ios_payload_fast_path',
    'validatorIds': <String>['validateNotificationArtifact'],
    'testCase': 'TC-B12',
    'recoveryTestCase': 'TC-333-08',
    'scenario': 'payload_fast_path_ios_receiver',
    'status': 'passed',
    'platform': 'ios',
    'devices': <String>['00008150-001C3C6A3684401C', 'android-peer-1234'],
    'capturedAt': '2026-07-14T12:00:00Z',
    'messageVisibleAt': '2026-07-14T11:59:58Z',
    'networkRestoredAt': '2026-07-14T11:59:59Z',
    'recoveryCompletedAt': '2026-07-14T12:00:01Z',
    'recoveryZeroBadgeObservedAt': '2026-07-14T12:00:02Z',
    'checks': <String, bool>{
      'iosReceiver': true,
      'apnsDelivered': true,
      'nseStagingOn': true,
      'nse04P0WithStagingOn': true,
      'airplaneModeBeforeTap': true,
      'messageVisibleFromStagedEnvelope': true,
      'noRelayDrainBeforeVisibility': true,
      'networkRestored': true,
      'appTerminatedAfterCapture': true,
      'badgePermissionEnabled': true,
      'providerPayloadBadgeAbsent': true,
      'deliveredNotificationBadgeWasNil': true,
      'recoveryClaimUnique': true,
      'runnerAbsoluteBadgeConverged': true,
      'exactOwnedNotificationRetired': true,
      'unrelatedSentinelSurvived': true,
      'zeroBadgePublished': true,
    },
    'runId': 'ios-payload-1234',
    'nonce': 'nonce-1234',
    'recoveryRunId': 'ios-payload-recovery-1234',
    'recoveryNonce': 'nonce-recovery-1234',
    'preparedApplicationSha256': _digest,
    'providerRequestSha256': _digest,
    'payloadProducerSha256': _digest,
    'apnsPayloadSha256': _digest,
    'recoveryApnsPayloadSha256': _digestB,
    'childBuildCount': 0,
    'manualActionCount': 0,
    'recoveryCounts': <String, int>{
      'badgeBefore': 1,
      'badgeAfter': 0,
      'deliveredBefore': 1,
      'deliveredWithSentinel': 2,
      'deliveredAfter': 1,
    },
    'evidenceSha256': <String, Object?>{
      'preparedApplication': _digest,
      'payloadProducer': _digest,
      'apnsPayload': _digest,
      'providerReceipt': _digest,
      'providerCleanupReceipt': _digest,
      'relayLog': _digest,
      'nseLog': _digest,
      'recipientLog': _digest,
      'uiAutomationLog': _digest,
      'stagedEnvelope': _digest,
      'recoveryPreparedApplication': _digest,
      'recoveryPayloadProducer': _digest,
      'recoveryApnsPayload': _digestB,
      'recoveryProviderReceipt': _digest,
      'recoveryProviderCleanupReceipt': _digest,
      'notificationRecoveryReceipt': _digest,
      'recoveryRelayLog': _digest,
      'recoveryNseLog': _digest,
      'recoveryRecipientLog': _digest,
      'recoveryUiAutomationLog': _digest,
      'recoveryStagedEnvelope': _digest,
    },
    'buildProfile': 'ios.device.production',
    'stagingEnvironment': 'staging',
    'candidateAppRevision': 'candidate-app-1234',
    'candidateRelayRevision': 'v1.6.0',
    'candidateRelaySha256': _digest,
    'automationReceiptSha256': _digest,
    'recoveryAutomationReceiptSha256': _digestB,
  };
}

Map<String, Object?> _permissionDeniedArtifact() => _notificationArtifact(
  scenario: 'tc_g7_permission_denied',
  checks: const <String>[
    'g7.permission_denied_no_post',
    'g7.permission_denied_typed_health',
    'g7.permission_custody_preserved',
    'g7.permission_regrant_recovery',
  ],
  evidence: <String, Object?>{
    'permissionDeniedBackgroundReceiptCount': 1,
    'permissionDeniedPostAttemptEvent': 'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
    'permissionDeniedHealthEvent': 'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED',
    'permissionDeniedHealthEventCount': 1,
    'permissionDeniedCardCount': 0,
    'permissionDeniedMessageCount': 1,
    'permissionRegrantAlertChannel': 'mknoon_messages',
  },
);

Map<String, Object?> _tokenRefreshArtifact() => _notificationArtifact(
  scenario: 'tc_g7_token_refresh_mid_session',
  checks: const <String>[
    'g7.token_refresh_event_observed',
    'g7.token_refresh_reregistered_same_process',
    'g7.token_refresh_new_token_delivery',
  ],
  evidence: <String, Object?>{
    'tokenRefreshEvent': 'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
    'tokenRefreshSuccessTrigger': 'token_refresh',
    'tokenRefreshStartupAttemptsInWindow': 0,
    'tokenRefreshPidBefore': '1234',
    'tokenRefreshPidAfter': '1234',
    'tokenHashPrefixBefore': '0123456789ab',
    'tokenHashPrefixAfter': 'ba9876543210',
    'tokenRefreshAlertChannel': 'mknoon_messages',
  },
);

Map<String, Object?> _channelDisabledArtifact() => _notificationArtifact(
  scenario: 'tc_g7_channel_disabled',
  checks: const <String>[
    'g7.channel_disabled_no_post',
    'g7.channel_custody_preserved',
    'g7.channel_reenable_recovery',
  ],
  evidence: <String, Object?>{
    'channelDisabledBackgroundReceiptCount': 1,
    'channelDisabledPostAttemptEvent': 'NOTIFICATION_SHOWN',
    'channelDisabledImportance': 0,
    'channelDisabledSilentImportance': 2,
    'channelDisabledCardCount': 0,
    'channelDisabledMessageCount': 1,
    'channelReenabledImportance': 4,
    'channelReenabledSilentImportance': 2,
    'channelReenabledAlertChannel': 'mknoon_messages',
  },
);

Map<String, Object?> _dozeArtifact() => _notificationArtifact(
  scenario: 'tc_g7_doze_delivery',
  checks: const <String>[
    'g7.doze_forced_idle_proven',
    'g7.doze_disposition_typed',
    'g7.doze_no_duplicate_render',
  ],
  evidence: <String, Object?>{
    'dozeStateBeforeSend': 'IDLE',
    'dozeStateAtObservation': 'IDLE',
    'dozeDisposition': 'delivered_during_idle',
    'dozeConvergedCardCount': 1,
    'dozeConvergedMessageCount': 1,
  },
);

const List<String> _warmChecks = <String>[
  'androidReceiver',
  'fcmDelivered',
  'backgroundIsolateStaged',
  'airplaneModeBeforeTap',
  'messageVisibleFromStagedEnvelope',
  'noRelayDrainBeforeVisibility',
  'b12.warm_audible_channel',
];

const Map<String, Object?> _coldEvidence = <String, Object?>{
  'coldAlertChannel': 'mknoon_messages',
  'coldWakeDeferralScan': 'clean',
};

const List<String> _coldChecks = <String>[
  'receiverTerminatedBeforeTap',
  'notificationTapColdLaunchedApp',
  'startupIngestRan',
  'messageVisibleFromStagedEnvelope',
  'noRelayDrainBeforeVisibility',
  'b12.cold_audible_channel',
];

Map<String, Object?> _notificationArtifact({
  required String scenario,
  required List<String> checks,
  String platform = 'android',
  Map<String, Object?>? evidence,
}) {
  return <String, Object?>{
    'scenario': scenario,
    'status': 'passed',
    'platform': platform,
    'devices': <String>['sender', 'receiver'],
    'capturedAt': '2026-07-14T12:00:00Z',
    'checks': <String, bool>{for (final check in checks) check: true},
    'evidence': ?evidence,
  };
}
