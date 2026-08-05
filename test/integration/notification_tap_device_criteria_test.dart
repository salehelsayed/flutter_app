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
          checks: const <String>[
            'androidReceiver',
            'fcmDelivered',
            'backgroundIsolateStaged',
            'airplaneModeBeforeTap',
            'messageVisibleFromStagedEnvelope',
            'noRelayDrainBeforeVisibility',
          ],
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

    test(
      'Android B12 cold requires terminated process, notification launch, and pre-drain visibility',
      () {
        final artifact = _notificationArtifact(
          scenario: 'payload_fast_path_cold_kill',
          checks: const <String>[
            'receiverTerminatedBeforeTap',
            'notificationTapColdLaunchedApp',
            'startupIngestRan',
            'messageVisibleFromStagedEnvelope',
            'noRelayDrainBeforeVisibility',
          ],
        );
        expect(validateNotificationArtifact(artifact).ok, isTrue);
      },
    );

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

Map<String, Object?> _notificationArtifact({
  required String scenario,
  required List<String> checks,
  String platform = 'android',
}) {
  return <String, Object?>{
    'scenario': scenario,
    'status': 'passed',
    'platform': platform,
    'devices': <String>['sender', 'receiver'],
    'capturedAt': '2026-07-14T12:00:00Z',
    'checks': <String, bool>{for (final check in checks) check: true},
  };
}
