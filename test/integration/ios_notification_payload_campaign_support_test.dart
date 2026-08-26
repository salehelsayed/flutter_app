import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/ios_notification_payload_campaign.dart';
import '../../tool/sims/device_criteria.dart';

const String _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _receiver = '00008150-001C3C6A3684401C';
const String _peer = 'android-peer-1234';
const String _runId = 'ios-payload-run-1234';
const String _nonce = 'nonce-123456789';
const String _recoveryRunId = 'ios-payload-recovery-1234';
const String _recoveryNonce = 'nonce-recovery-123456789';
const String _retryRunId = 'ios-payload-retry-1234';
const String _retryNonce = 'nonce-retry-123456789';

Map<String, Object?> _staging() => <String, Object?>{
  'schema': iosNotificationStagingManifestSchema,
  'environment': 'staging',
  'provider': 'apns',
  'providerConfigured': true,
  'providerCredentialsAvailable': true,
  'providerProbeSucceeded': true,
  'appSigningAvailable': true,
  'signingProbeSucceeded': true,
  'apnsEnvironment': 'development',
  'signingEntitlementEnvironment': 'development',
  'relayActive': true,
  'relayInboxSeedDriverAvailable': true,
  'dedicatedDisposableReceiver': true,
  'destructiveTestStateResetAuthorized': true,
  'providerCleanupAvailable': true,
  'productionDeploymentPerformed': false,
  'candidateAppRevision': 'candidate-app-1234',
  'candidateRelayRevision': 'v1.6.0',
  'candidateRelaySha256': _digestA,
  'signingIdentitySha256': _digestB,
  'payloadProducerSha256': _digestA,
  'bundleId': 'com.mknoon.app',
  'receiverDeviceId': _receiver,
  'peerDeviceId': _peer,
  'relayAddresses': <String>['/dns/staging.example/tcp/443/wss'],
};

Map<String, Object?> _request() => <String, Object?>{
  'schema': iosNotificationProviderRequestSchema,
  'expectedTitle': 'Fixture title',
  'expectedBody': 'Fixture body',
  'expectedMessageText': 'Fixture message',
  'receiverDeviceId': _receiver,
  'peerDeviceId': _peer,
};

Map<String, Object?> _providerReceipt() => <String, Object?>{
  'schema': iosNotificationProviderReceiptSchema,
  'status': 'accepted',
  'provider': 'apns',
  'relayInboxSeeded': true,
  'providerAccepted': true,
  'appSetupAutomated': true,
  'dedicatedDisposableReceiver': true,
  'cleanupDriverAvailable': true,
  'childBuildCount': 0,
  'manualActionCount': 0,
  'runId': _runId,
  'nonce': _nonce,
  'receiverDeviceIdSha256': sha256String(_receiver),
  'requestSha256': _digestA,
  'apnsPayloadSha256': _digestA,
  'receiverHandoffSha256': _digestB,
  'providerMessageIdSha256': _digestB,
  'collapseIdentitySha256': _digestA,
  'syntheticMessageIdSha256': _digestB,
  'submissionStage': 'first',
  'relayLogPath': 'relay.redacted.log',
  'relayLogSha256': _digestA,
  'stagedEnvelopeSha256': _digestB,
  'acceptedAt': '2026-07-15T10:00:00.000Z',
};

Map<String, Object?> _cleanupReceipt() => <String, Object?>{
  'schema': iosNotificationProviderCleanupReceiptSchema,
  'status': 'cleaned',
  'dedicatedDisposableReceiver': true,
  'relayFixtureCleared': true,
  'appTestStateCleared': true,
  'notificationStateCleared': true,
  'candidateAppRemoved': true,
  'childBuildCount': 0,
  'manualActionCount': 0,
  'runId': _runId,
  'nonce': _nonce,
  'receiverDeviceIdSha256': sha256String(_receiver),
  'providerReceiptSha256': _digestB,
  'apnsPayloadSha256': _digestA,
  'receiverHandoffSha256': _digestB,
  'cleanedAt': '2026-07-15T10:00:10.000Z',
};

Map<String, Object?> _providerRetryReceipt() => <String, Object?>{
  'schema': iosNotificationProviderRetryReceiptSchema,
  'action': 'retry',
  'status': 'accepted',
  'provider': 'apns',
  'runId': _retryRunId,
  'nonce': _retryNonce,
  'receiverDeviceIdSha256': sha256String(_receiver),
  'requestSha256': _digestA,
  'apnsPayloadSha256': _digestB,
  'receiverHandoffSha256': _digestA,
  'collapseIdentitySha256': _digestA,
  'firstProviderReceiptSha256': _digestB,
  'firstProviderMessageIdSha256': _digestA,
  'secondProviderMessageIdSha256': _digestB,
  'firstAcceptedAt': '2026-07-15T10:00:00.000Z',
  'secondAcceptedAt': '2026-07-15T10:00:03.000Z',
  'providerAcceptedCount': 2,
  'payloadBytesIdentical': true,
  'collapseIdentityReused': true,
  'providerIdsDistinct': true,
  'childBuildCount': 0,
  'manualActionCount': 0,
};

Map<String, Object?> _automationReceipt() => <String, Object?>{
  'schema': iosNotificationAutomationReceiptSchema,
  'scenario': iosNotificationPayloadScenario,
  'status': 'passed',
  'platform': 'ios',
  'receiverPhysical': true,
  'runId': _runId,
  'nonce': _nonce,
  'receiverDeviceId': _receiver,
  'peerDeviceId': _peer,
  'preparedApplicationSha256': _digestA,
  'providerRequestSha256': _digestB,
  'payloadProducerSha256': _digestA,
  'apnsPayloadSha256': _digestB,
  'childBuildCount': 0,
  'manualActionCount': 0,
  'checks': <String, Object?>{
    'appSetupAutomated': true,
    'notificationPermissionAutomated': true,
    'apnsDelivered': true,
    'nseProcessObserved': true,
    'nseStagingOn': true,
    'nse04P0WithStagingOn': true,
    'airplaneModeBeforeTap': true,
    'notificationTapAutomated': true,
    'messageVisibleFromStagedEnvelope': true,
    'relayDrainCountBeforeVisibility': 0,
    'networkRestored': true,
    'appTerminatedAfterCapture': true,
    'providerCleanupAutomated': true,
    'testStateCleared': true,
  },
  'timestamps': <String, Object?>{
    'providerAcceptedAt': '2026-07-15T10:00:00.000Z',
    'nseStagedAt': '2026-07-15T10:00:01.000Z',
    'apnsDeliveredAt': '2026-07-15T10:00:02.000Z',
    'airplaneEnabledAt': '2026-07-15T10:00:03.000Z',
    'notificationTappedAt': '2026-07-15T10:00:04.000Z',
    'messageVisibleAt': '2026-07-15T10:00:05.000Z',
    'networkRestoredAt': '2026-07-15T10:00:06.000Z',
  },
  'evidenceSha256': <String, Object?>{
    'preparedApplication': _digestA,
    'payloadProducer': _digestA,
    'apnsPayload': _digestB,
    'providerReceipt': _digestA,
    'providerCleanupReceipt': _digestA,
    'relayLog': _digestA,
    'nseLog': _digestA,
    'recipientLog': _digestA,
    'uiAutomationLog': _digestA,
    'stagedEnvelope': _digestA,
  },
};

Map<String, Object?> _successfulCleanupOwners() => <String, Object?>{
  for (final owner in const <String>['ui', 'sender', 'providerCleanup'])
    owner: <String, bool>{
      'required': true,
      'attempted': true,
      'completed': true,
    },
  for (final owner in const <String>['providerRecovery', 'directInstall'])
    owner: <String, bool>{
      'required': false,
      'attempted': false,
      'completed': false,
    },
};

Map<String, Object?> _recoveryAutomationReceipt() => <String, Object?>{
  'schema': iosNotificationRecoveryAutomationReceiptSchema,
  'scenario': iosNotificationPayloadScenario,
  'phase': 'recovery',
  'status': 'passed',
  'platform': 'ios',
  'receiverPhysical': true,
  'runId': _recoveryRunId,
  'nonce': _recoveryNonce,
  'receiverDeviceId': _receiver,
  'peerDeviceId': _peer,
  'preparedApplicationSha256': _digestA,
  'providerRequestSha256': _digestB,
  'payloadProducerSha256': _digestA,
  'apnsPayloadSha256': _digestB,
  'childBuildCount': 0,
  'manualActionCount': 0,
  'passDiagnosticRetained': true,
  'cleanupOwners': _successfulCleanupOwners(),
  'checks': <String, Object?>{
    'notificationPermissionAutomated': true,
    'badgePermissionEnabled': true,
    'providerPayloadBadgeAbsent': true,
    'deliveredNotificationBadgeWasNil': true,
    'apnsDelivered': true,
    'nseProcessObserved': true,
    'recoveryClaimUnique': true,
    'runnerAbsoluteBadgeConverged': true,
    'exactOwnedNotificationRetired': true,
    'unrelatedSentinelSurvived': true,
    'zeroBadgePublished': true,
    'providerCleanupAutomated': true,
    'testStateCleared': true,
    'sourceInventoryStable': true,
    'directSourceUsefulProviderOnly': true,
    'backgroundHandlerReached': true,
    'backgroundContenderSuppressed': true,
    'noMatchingLocalShow': true,
    'completeWindowNseBound': true,
  },
  'counts': <String, Object?>{
    'badgeBefore': 1,
    'badgeAfter': 0,
    'deliveredBefore': 1,
    'deliveredWithSentinel': 2,
    'deliveredAfter': 1,
    'matchingRemoteCount': 1,
    'matchingLocalCount': 0,
    'matchingUsefulProviderCount': 1,
    'matchingSanitizedProviderCount': 0,
    'matchingFlutterLocalCount': 0,
    'matchingUnknownCount': 0,
    'matchingTotalCount': 1,
    'stableSampleCount': 3,
    'stableSampleIntervalMilliseconds': 500,
    'settleDelayMilliseconds': 3000,
    'observationDeadlineMilliseconds': 8000,
    'backgroundHandlerCount': 1,
    'recentRemoteSuppressionCount': 1,
    'matchingNotificationShownCount': 0,
    'nseEnvelopeStagedCount': 1,
    'nseDecryptOkCount': 1,
    'nseAuthorizedHandoffCount': 1,
    'nseActiveHandoffCount': 1,
    'nseTrustedPassiveHandoffCount': 0,
    'nseSanitizedHandoffCount': 0,
  },
  'requestIdentifierSha256': <String>[_digestA],
  'timestamps': <String, Object?>{
    'providerAcceptedAt': '2026-07-15T10:00:00.000Z',
    'nseObservedAt': '2026-07-15T10:00:01.000Z',
    'cardObservedAt': '2026-07-15T10:00:02.000Z',
    'badgeObservedAt': '2026-07-15T10:00:03.000Z',
    'recoveryCompletedAt': '2026-07-15T10:00:04.000Z',
    'retirementObservedAt': '2026-07-15T10:00:05.000Z',
    'zeroBadgeObservedAt': '2026-07-15T10:00:06.000Z',
  },
  'evidenceSha256': <String, Object?>{
    'preparedApplication': _digestA,
    'payloadProducer': _digestA,
    'apnsPayload': _digestB,
    'providerReceipt': _digestA,
    'providerCleanupReceipt': _digestA,
    'notificationRecoveryReceipt': _digestB,
    'relayLog': _digestA,
    'nseLog': _digestA,
    'recipientLog': _digestA,
    'uiAutomationLog': _digestA,
    'stagedEnvelope': _digestA,
    'causalDiagnostic': _digestB,
  },
};

Map<String, Object?> _retryAutomationReceipt() => <String, Object?>{
  'schema': iosNotificationRetryAutomationReceiptSchema,
  'scenario': iosNotificationPayloadScenario,
  'phase': 'retry',
  'status': 'passed',
  'platform': 'ios',
  'receiverPhysical': true,
  'runId': _retryRunId,
  'nonce': _retryNonce,
  'receiverDeviceId': _receiver,
  'peerDeviceId': _peer,
  'preparedApplicationSha256': _digestA,
  'providerRequestSha256': _digestB,
  'payloadProducerSha256': _digestA,
  'apnsPayloadSha256': _digestB,
  'collapseIdentitySha256': _digestA,
  'requestIdentifierSha256': _digestA,
  'childBuildCount': 0,
  'manualActionCount': 0,
  'passDiagnosticRetained': true,
  'cleanupOwners': _successfulCleanupOwners(),
  'checks': <String, Object?>{
    'firstDeliveryFenced': true,
    'secondTrustedPassiveHandoff': true,
    'providerAcceptancesDistinct': true,
    'payloadBytesIdentical': true,
    'collapseIdentityReused': true,
    'finalRequestIdentifierMatchesCollapse': true,
    'samePayloadRetrySingleUsefulCard': true,
    'noSanitizedProviderCard': true,
    'noFlutterLocalCard': true,
    'noUnknownCard': true,
    'noMatchingLocalShow': true,
    'completeWindowNseBound': true,
    'providerCleanupAutomated': true,
    'testStateCleared': true,
  },
  'counts': <String, Object?>{
    'providerAcceptedCount': 2,
    'matchingUsefulProviderCount': 1,
    'matchingSanitizedProviderCount': 0,
    'matchingFlutterLocalCount': 0,
    'matchingUnknownCount': 0,
    'matchingTotalCount': 1,
    'stableSampleCount': 3,
    'nseEnvelopeStagedCount': 2,
    'nseDecryptOkCount': 2,
    'nseAuthorizedHandoffCount': 2,
    'nseActiveHandoffCount': 1,
    'nseTrustedPassiveHandoffCount': 1,
    'nseSanitizedHandoffCount': 0,
    'backgroundHandlerCount': 2,
    'recentRemoteSuppressionCount': 2,
    'matchingNotificationShownCount': 0,
  },
  'timestamps': <String, Object?>{
    'firstAcceptedAt': '2026-07-15T10:00:00.000Z',
    'firstNseObservedAt': '2026-07-15T10:00:01.000Z',
    'firstCardObservedAt': '2026-07-15T10:00:02.000Z',
    'secondAcceptedAt': '2026-07-15T10:00:03.000Z',
    'secondNseObservedAt': '2026-07-15T10:00:04.000Z',
    'secondCardObservedAt': '2026-07-15T10:00:05.000Z',
  },
  'providerMessageIdSha256': <String>[_digestA, _digestB],
  'evidenceSha256': <String, Object?>{
    'preparedApplication': _digestA,
    'payloadProducer': _digestA,
    'apnsPayload': _digestB,
    'firstProviderReceipt': _digestA,
    'secondProviderReceipt': _digestB,
    'providerCleanupReceipt': _digestA,
    'firstInventoryReceipt': _digestA,
    'secondInventoryReceipt': _digestB,
    'relayLog': _digestA,
    'nseLog': _digestA,
    'recipientLog': _digestA,
    'uiAutomationLog': _digestA,
    'causalDiagnostic': _digestB,
    'stagedEnvelope': _digestA,
  },
};

IosNotificationContractResult _validateRecovery(Map<String, Object?> receipt) =>
    validateIosNotificationRecoveryAutomationReceipt(
      receipt,
      runId: _recoveryRunId,
      nonce: _recoveryNonce,
      receiverDeviceId: _receiver,
      peerDeviceId: _peer,
      preparedApplicationSha256: _digestA,
      providerRequestSha256: _digestB,
      payloadProducerSha256: _digestA,
      apnsPayloadSha256: _digestB,
    );

IosNotificationContractResult _validateRetry(Map<String, Object?> receipt) =>
    validateIosNotificationRetryAutomationReceipt(
      receipt,
      runId: _retryRunId,
      nonce: _retryNonce,
      receiverDeviceId: _receiver,
      peerDeviceId: _peer,
      preparedApplicationSha256: _digestA,
      providerRequestSha256: _digestB,
      payloadProducerSha256: _digestA,
      apnsPayloadSha256: _digestB,
    );

void main() {
  test('accepts secret-free dedicated staging and provider contracts', () {
    expect(validateIosNotificationStagingManifest(_staging()).ok, isTrue);
    expect(validateIosNotificationProviderRequest(_request()).ok, isTrue);
    expect(
      validateIosNotificationProviderReceipt(
        _providerReceipt(),
        runId: _runId,
        nonce: _nonce,
        receiverDeviceId: _receiver,
        requestSha256: _digestA,
        apnsPayloadSha256: _digestA,
        receiverHandoffSha256: _digestB,
      ).ok,
      isTrue,
    );
    expect(
      validateIosNotificationProviderCleanupReceipt(
        _cleanupReceipt(),
        runId: _runId,
        nonce: _nonce,
        receiverDeviceId: _receiver,
        providerReceiptSha256: _digestB,
        apnsPayloadSha256: _digestA,
        receiverHandoffSha256: _digestB,
      ).ok,
      isTrue,
    );
    final retryValidation = validateIosNotificationProviderRetryReceipt(
      _providerRetryReceipt(),
      runId: _retryRunId,
      nonce: _retryNonce,
      receiverDeviceId: _receiver,
      requestSha256: _digestA,
      apnsPayloadSha256: _digestB,
      receiverHandoffSha256: _digestA,
      collapseIdentitySha256: _digestA,
      firstProviderReceiptSha256: _digestB,
      firstProviderMessageIdSha256: _digestA,
    );
    expect(retryValidation.ok, isTrue, reason: retryValidation.detail);
  });

  test('provider title stays within the disposable contact username bound', () {
    final request = _request()..['expectedTitle'] = 'a' * 31;
    expect(validateIosNotificationProviderRequest(request).ok, isFalse);

    request
      ..['expectedTitle'] = 'Fixture title'
      ..['expectedMessageText'] = 'm' * 141;
    expect(validateIosNotificationProviderRequest(request).ok, isFalse);

    request['expectedMessageText'] = ' leading-space';
    expect(validateIosNotificationProviderRequest(request).ok, isFalse);

    request['expectedMessageText'] = 'café';
    expect(validateIosNotificationProviderRequest(request).ok, isFalse);

    request
      ..['expectedMessageText'] = 'Fixture message'
      ..['expectedBody'] = 'fallback exposes Fixture message';
    expect(validateIosNotificationProviderRequest(request).ok, isFalse);
  });

  test(
    'dedicated device, provider cleanup, and secret rejection fail closed',
    () {
      final sharedDevice = _staging()..['dedicatedDisposableReceiver'] = false;
      expect(validateIosNotificationStagingManifest(sharedDevice).ok, isFalse);

      final secret = _staging()..['apnsToken'] = 'raw-token';
      expect(validateIosNotificationStagingManifest(secret).ok, isFalse);

      final unversionedRelay = _staging()
        ..['candidateRelayRevision'] = 'relay-git-sha';
      expect(
        validateIosNotificationStagingManifest(unversionedRelay).ok,
        isFalse,
      );

      for (final field in const <String>[
        'apnsEnvironment',
        'signingEntitlementEnvironment',
      ]) {
        final productionSigning = _staging()..[field] = 'production';
        expect(
          validateIosNotificationStagingManifest(productionSigning).ok,
          isFalse,
          reason: '$field must stay bound to the development APNs profile',
        );
      }

      final manualProvider = _providerReceipt()..['manualActionCount'] = 1;
      expect(
        validateIosNotificationProviderReceipt(
          manualProvider,
          runId: _runId,
          nonce: _nonce,
          receiverDeviceId: _receiver,
          requestSha256: _digestA,
          apnsPayloadSha256: _digestA,
          receiverHandoffSha256: _digestB,
        ).ok,
        isFalse,
      );

      final unboundProvider = _providerReceipt()
        ..remove('receiverHandoffSha256');
      expect(
        validateIosNotificationProviderReceipt(
          unboundProvider,
          runId: _runId,
          nonce: _nonce,
          receiverDeviceId: _receiver,
          requestSha256: _digestA,
          apnsPayloadSha256: _digestA,
          receiverHandoffSha256: _digestB,
        ).ok,
        isFalse,
      );

      final incompleteCleanup = _cleanupReceipt()
        ..['notificationStateCleared'] = false;
      expect(
        validateIosNotificationProviderCleanupReceipt(
          incompleteCleanup,
          runId: _runId,
          nonce: _nonce,
          receiverDeviceId: _receiver,
          providerReceiptSha256: _digestB,
          apnsPayloadSha256: _digestA,
          receiverHandoffSha256: _digestB,
        ).ok,
        isFalse,
      );
    },
  );

  test('automation receipt binds lifecycle, cleanup, and zero drain', () {
    expect(
      validateIosNotificationAutomationReceipt(
        _automationReceipt(),
        runId: _runId,
        nonce: _nonce,
        receiverDeviceId: _receiver,
        peerDeviceId: _peer,
        preparedApplicationSha256: _digestA,
        providerRequestSha256: _digestB,
        payloadProducerSha256: _digestA,
        apnsPayloadSha256: _digestB,
      ).ok,
      isTrue,
    );

    final drain = _automationReceipt();
    (drain['checks']! as Map)['relayDrainCountBeforeVisibility'] = 1;
    expect(
      validateIosNotificationAutomationReceipt(
        drain,
        runId: _runId,
        nonce: _nonce,
        receiverDeviceId: _receiver,
        peerDeviceId: _peer,
        preparedApplicationSha256: _digestA,
        providerRequestSha256: _digestB,
        payloadProducerSha256: _digestA,
        apnsPayloadSha256: _digestB,
      ).ok,
      isFalse,
    );

    final noCleanup = _automationReceipt();
    (noCleanup['checks']! as Map)['testStateCleared'] = false;
    expect(
      validateIosNotificationAutomationReceipt(
        noCleanup,
        runId: _runId,
        nonce: _nonce,
        receiverDeviceId: _receiver,
        peerDeviceId: _peer,
        preparedApplicationSha256: _digestA,
        providerRequestSha256: _digestB,
        payloadProducerSha256: _digestA,
        apnsPayloadSha256: _digestB,
      ).ok,
      isFalse,
    );
  });

  test('automation timestamps compare only within their clock domains', () {
    IosNotificationContractResult validate(Map<String, Object?> receipt) =>
        validateIosNotificationAutomationReceipt(
          receipt,
          runId: _runId,
          nonce: _nonce,
          receiverDeviceId: _receiver,
          peerDeviceId: _peer,
          preparedApplicationSha256: _digestA,
          providerRequestSha256: _digestB,
          payloadProducerSha256: _digestA,
          apnsPayloadSha256: _digestB,
        );

    final skewed = _automationReceipt();
    final timestamps = skewed['timestamps']! as Map;
    timestamps
      ..['apnsDeliveredAt'] = '2026-07-15T09:00:00.000Z'
      ..['airplaneEnabledAt'] = '2026-07-15T09:00:01.000Z'
      ..['notificationTappedAt'] = '2026-07-15T09:00:02.000Z'
      ..['messageVisibleAt'] = '2026-07-15T09:00:03.000Z'
      ..['networkRestoredAt'] = '2026-07-15T09:00:04.000Z';
    expect(validate(skewed).ok, isTrue);

    timestamps['notificationTappedAt'] = '2026-07-15T08:59:59.000Z';
    expect(validate(skewed).ok, isFalse);

    timestamps
      ..['notificationTappedAt'] = '2026-07-15T09:00:02.000Z'
      ..['networkRestoredAt'] = '2026-07-15T09:00:02.000Z';
    expect(validate(skewed).ok, isFalse);

    timestamps
      ..['networkRestoredAt'] = '2026-07-15T09:00:04.000Z'
      ..['nseStagedAt'] = '2026-07-15T09:59:59.000Z';
    expect(validate(skewed).ok, isFalse);
  });

  test('recovery automation receipt accepts the exact physical proof', () {
    expect(_validateRecovery(_recoveryAutomationReceipt()).ok, isTrue);
  });

  test('TC-396 duplicate source inventory cannot pass as one card', () {
    expect(
      _validateRecovery(_recoveryAutomationReceipt()).ok,
      isTrue,
      reason: 'the exact useful-provider-only source receipt must be accepted',
    );
    final duplicate = _recoveryAutomationReceipt();
    final counts = duplicate['counts']! as Map;
    counts
      ..['matchingLocalCount'] = 1
      ..['matchingFlutterLocalCount'] = 1
      ..['matchingTotalCount'] = 2;
    (duplicate['requestIdentifierSha256']! as List).add(_digestB);
    expect(_validateRecovery(duplicate).ok, isFalse);
  });

  test('recovery automation receipt fails closed on schema drift', () {
    final extraTopLevel = _recoveryAutomationReceipt()..['unexpected'] = true;
    expect(_validateRecovery(extraTopLevel).ok, isFalse);

    final missingTopLevel = _recoveryAutomationReceipt()
      ..remove('receiverPhysical');
    expect(_validateRecovery(missingTopLevel).ok, isFalse);

    final extraCheck = _recoveryAutomationReceipt();
    (extraCheck['checks']! as Map)['uncontractedCheck'] = true;
    expect(_validateRecovery(extraCheck).ok, isFalse);

    final extraCount = _recoveryAutomationReceipt();
    (extraCount['counts']! as Map)['otherDelivery'] = 0;
    expect(_validateRecovery(extraCount).ok, isFalse);

    final extraEvidence = _recoveryAutomationReceipt();
    (extraEvidence['evidenceSha256']! as Map)['debugLog'] = _digestA;
    expect(_validateRecovery(extraEvidence).ok, isFalse);
  });

  test('recovery automation receipt requires exact outcomes and bindings', () {
    final missingPermission = _recoveryAutomationReceipt();
    (missingPermission['checks']! as Map)['badgePermissionEnabled'] = false;
    expect(_validateRecovery(missingPermission).ok, isFalse);

    final badgeBearingDelivery = _recoveryAutomationReceipt();
    (badgeBearingDelivery['checks']!
            as Map)['deliveredNotificationBadgeWasNil'] =
        false;
    expect(_validateRecovery(badgeBearingDelivery).ok, isFalse);

    final wrongDeliveredCount = _recoveryAutomationReceipt();
    (wrongDeliveredCount['counts']! as Map)['deliveredAfter'] = 0;
    expect(_validateRecovery(wrongDeliveredCount).ok, isFalse);

    final unboundApp = _recoveryAutomationReceipt()
      ..['preparedApplicationSha256'] = _digestB;
    expect(_validateRecovery(unboundApp).ok, isFalse);

    final unboundEvidence = _recoveryAutomationReceipt();
    (unboundEvidence['evidenceSha256']! as Map)['apnsPayload'] = _digestA;
    expect(_validateRecovery(unboundEvidence).ok, isFalse);

    final secret = _recoveryAutomationReceipt()
      ..['checks'] = <String, Object?>{
        ...(_recoveryAutomationReceipt()['checks']! as Map)
            .cast<String, Object?>(),
        'privateKey': 'BEGIN PRIVATE KEY',
      };
    expect(_validateRecovery(secret).ok, isFalse);
  });

  test(
    'recovery and retry receipts expose pass diagnostics and exact state-aware cleanup owners',
    () {
      void expectExactCleanup(
        Map<String, Object?> Function() receiptBuilder,
        IosNotificationContractResult Function(Map<String, Object?>) validate,
      ) {
        final receipt = receiptBuilder();
        expect(validate(receipt).ok, isTrue);

        final missingPassDiagnostic = Map<String, Object?>.from(receipt)
          ..['passDiagnosticRetained'] = false;
        expect(validate(missingPassDiagnostic).ok, isFalse);

        final incompletePrimary = receiptBuilder();
        (((incompletePrimary['cleanupOwners']! as Map)['providerCleanup']
                as Map))['completed'] =
            false;
        expect(validate(incompletePrimary).ok, isFalse);

        final invokedFallback = receiptBuilder();
        (((invokedFallback['cleanupOwners']! as Map)['providerRecovery']
                as Map))['attempted'] =
            true;
        expect(validate(invokedFallback).ok, isFalse);

        final missingOwner = receiptBuilder();
        (missingOwner['cleanupOwners']! as Map).remove('sender');
        expect(validate(missingOwner).ok, isFalse);
      }

      expectExactCleanup(_recoveryAutomationReceipt, _validateRecovery);
      expectExactCleanup(_retryAutomationReceipt, _validateRetry);
    },
  );

  test('recovery timestamps preserve host and iPhone causal order', () {
    final hostSkew = _recoveryAutomationReceipt();
    final hostSkewTimestamps = hostSkew['timestamps']! as Map;
    hostSkewTimestamps
      ..['cardObservedAt'] = '2026-07-15T09:00:00.000Z'
      ..['badgeObservedAt'] = '2026-07-15T09:00:01.000Z'
      ..['recoveryCompletedAt'] = '2026-07-15T09:00:02.000Z'
      ..['retirementObservedAt'] = '2026-07-15T09:00:03.000Z'
      ..['zeroBadgeObservedAt'] = '2026-07-15T09:00:04.000Z';
    expect(_validateRecovery(hostSkew).ok, isTrue);

    final reversedHost = _recoveryAutomationReceipt();
    (reversedHost['timestamps']! as Map)['nseObservedAt'] =
        '2026-07-15T09:59:59.000Z';
    expect(_validateRecovery(reversedHost).ok, isFalse);

    final reversedDevice = _recoveryAutomationReceipt();
    (reversedDevice['timestamps']! as Map)['recoveryCompletedAt'] =
        '2026-07-15T10:00:02.000Z';
    expect(_validateRecovery(reversedDevice).ok, isFalse);

    final nonUtc = _recoveryAutomationReceipt();
    (nonUtc['timestamps']! as Map)['zeroBadgeObservedAt'] =
        '2026-07-15T10:00:06.000';
    expect(_validateRecovery(nonUtc).ok, isFalse);
  });

  test('TC-396 retry receipt requires two bound accepts and one card', () {
    final valid = _validateRetry(_retryAutomationReceipt());
    expect(valid.ok, isTrue, reason: valid.detail);

    final unfenced = _retryAutomationReceipt();
    (unfenced['checks']! as Map)['firstDeliveryFenced'] = false;
    expect(_validateRetry(unfenced).ok, isFalse);

    final duplicateProviderId = _retryAutomationReceipt()
      ..['providerMessageIdSha256'] = <String>[_digestA, _digestA];
    expect(_validateRetry(duplicateProviderId).ok, isFalse);

    final duplicateCard = _retryAutomationReceipt();
    (duplicateCard['counts']! as Map)
      ..['matchingUsefulProviderCount'] = 2
      ..['matchingTotalCount'] = 2;
    expect(_validateRetry(duplicateCard).ok, isFalse);

    final unboundCollapse = _retryAutomationReceipt()
      ..['requestIdentifierSha256'] = _digestB;
    expect(_validateRetry(unboundCollapse).ok, isFalse);

    for (final incompleteSuppressionCount in <int>[0, 1]) {
      final incompleteSuppression = _retryAutomationReceipt();
      (incompleteSuppression['counts']!
              as Map)['recentRemoteSuppressionCount'] =
          incompleteSuppressionCount;
      expect(_validateRetry(incompleteSuppression).ok, isFalse);
    }
  });

  test(
    'exact automation receipt produces validator-compatible TC-B12 proof',
    () {
      final artifact =
          buildIosNotificationArtifact(
            automationReceipt: _automationReceipt(),
            recoveryAutomationReceipt: _recoveryAutomationReceipt(),
            retryAutomationReceipt: _retryAutomationReceipt(),
            capturedAt: '2026-07-15T10:00:06.000Z',
          )..addAll(<String, Object?>{
            'schema': 'mknoon.sims.proof.v1',
            'capabilityId': iosNotificationPayloadCapabilityId,
            'validatorIds': <String>[iosNotificationPayloadValidator],
            'buildProfile': iosNotificationPayloadBuildProfile,
            'stagingEnvironment': 'staging',
            'candidateAppRevision': 'candidate-app-1234',
            'candidateRelayRevision': 'v1.6.0',
            'candidateRelaySha256': _digestA,
            'automationReceiptSha256': _digestB,
            'recoveryAutomationReceiptSha256': _digestA,
            'retryAutomationReceiptSha256': _digestB,
          });
      final durable = validateNotificationArtifact(artifact);
      expect(durable.ok, isTrue, reason: durable.detail);
      expect(artifact['childBuildCount'], 0);
      expect(artifact['manualActionCount'], 0);
      expect(artifact['messageVisibleAt'], '2026-07-15T10:00:05.000Z');
      expect(artifact['networkRestoredAt'], '2026-07-15T10:00:06.000Z');
      expect((artifact['checks']! as Map)['networkRestored'], isTrue);
      expect((artifact['checks']! as Map)['appTerminatedAfterCapture'], isTrue);
      expect(artifact['passDiagnosticRetained'], isTrue);
      expect(
        (artifact['cleanupOwners']! as Map).keys,
        unorderedEquals(<String>['recovery', 'retry']),
      );
      expect(
        ((artifact['cleanupOwners']! as Map)['retry']
            as Map)['providerCleanup'],
        <String, bool>{'required': true, 'attempted': true, 'completed': true},
      );
      expect(
        (artifact['checks']! as Map)['hostFailureDiagnosticRetentionContract'],
        isTrue,
      );
      expect(
        (artifact['checks']! as Map)['hostUnconditionalCleanupContract'],
        isTrue,
      );
      expect(
        (artifact['checks']! as Map).containsKey('failureDiagnosticRetained'),
        isFalse,
      );
    },
  );

  test('prepared app directory hash changes with cached product content', () {
    final root = Directory.systemTemp.createTempSync('ios-app-digest-');
    addTearDown(() => root.deleteSync(recursive: true));
    final app = Directory('${root.path}/Runner.app')..createSync();
    final executable = File('${app.path}/Runner')..writeAsStringSync('v1');
    final first = sha256FileSystemEntity(app);
    expect(first, hasLength(64));
    executable.writeAsStringSync('v2');
    expect(sha256FileSystemEntity(app), isNot(first));
  });
}
