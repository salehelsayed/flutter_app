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

  test(
    'exact automation receipt produces validator-compatible TC-B12 proof',
    () {
      final artifact =
          buildIosNotificationArtifact(
            automationReceipt: _automationReceipt(),
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
          });
      expect(validateNotificationArtifact(artifact).ok, isTrue);
      expect(artifact['childBuildCount'], 0);
      expect(artifact['manualActionCount'], 0);
      expect(artifact['messageVisibleAt'], '2026-07-15T10:00:05.000Z');
      expect(artifact['networkRestoredAt'], '2026-07-15T10:00:06.000Z');
      expect((artifact['checks']! as Map)['networkRestored'], isTrue);
      expect((artifact['checks']! as Map)['appTerminatedAfterCapture'], isTrue);
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
