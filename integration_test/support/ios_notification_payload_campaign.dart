import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String iosNotificationPayloadScenario = 'payload_fast_path_ios_receiver';
const String iosNotificationPayloadCapabilityId =
    'notifications.ios_payload_fast_path';
const String iosNotificationPayloadBuildProfile = 'ios.device.production';
const String iosNotificationPayloadValidator = 'validateNotificationArtifact';

const String iosNotificationStagingManifestSchema =
    'mknoon.sims.ios-payload-fast-path-staging.v1';
const String iosNotificationProviderRequestSchema =
    'mknoon.sims.ios-payload-fast-path-provider-request.v1';
const String iosNotificationProviderReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-provider-receipt.v2';
const String iosNotificationProviderRetryReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-provider-retry-receipt.v1';
const String iosNotificationProviderCleanupReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-provider-cleanup-receipt.v1';
const String iosNotificationAutomationReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-automation-receipt.v1';
const String iosNotificationRecoveryAutomationReceiptSchema =
    'mknoon.sims.ios-notification-recovery-automation-receipt.v2';
const String iosNotificationRetryAutomationReceiptSchema =
    'mknoon.sims.ios-notification-retry-automation-receipt.v1';

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

const Set<String> _iosNotificationCleanupOwnerKeys = <String>{
  'ui',
  'sender',
  'providerCleanup',
  'providerRecovery',
  'directInstall',
};
const Set<String> _iosNotificationRequiredCleanupOwners = <String>{
  'ui',
  'sender',
  'providerCleanup',
};
const Set<String> _iosNotificationCleanupStateKeys = <String>{
  'required',
  'attempted',
  'completed',
};

final class IosNotificationContractResult {
  const IosNotificationContractResult._(this.ok, this.detail);

  const IosNotificationContractResult.pass(String detail)
    : this._(true, detail);

  const IosNotificationContractResult.fail(String detail)
    : this._(false, detail);

  final bool ok;
  final String detail;
}

IosNotificationContractResult validateIosNotificationStagingManifest(
  Map<String, Object?> manifest,
) {
  final secret = findIosNotificationSecretBearingField(manifest);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'staging manifest contains forbidden secret-bearing field $secret',
    );
  }
  const exact = <String, Object?>{
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
  };
  for (final entry in exact.entries) {
    if (manifest[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'staging manifest ${entry.key} must equal ${entry.value}',
      );
    }
  }
  for (final key in const <String>[
    'candidateAppRevision',
    'candidateRelayRevision',
    'bundleId',
    'receiverDeviceId',
    'peerDeviceId',
  ]) {
    if (!_isSafeNonemptyString(manifest[key])) {
      return IosNotificationContractResult.fail(
        'staging manifest $key must be a safe nonempty string',
      );
    }
  }
  if (manifest['bundleId'] != 'com.mknoon.app') {
    return const IosNotificationContractResult.fail(
      'staging manifest bundleId must identify the production app',
    );
  }
  if (!_isSha256(manifest['candidateRelaySha256'])) {
    return const IosNotificationContractResult.fail(
      'staging manifest candidateRelaySha256 must be lowercase SHA-256',
    );
  }
  if (manifest['candidateRelayRevision'] is! String ||
      !RegExp(
        r'^v[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$',
      ).hasMatch(manifest['candidateRelayRevision']! as String)) {
    return const IosNotificationContractResult.fail(
      'staging manifest candidateRelayRevision must be an exact v-version token',
    );
  }
  if (!_isSha256(manifest['signingIdentitySha256'])) {
    return const IosNotificationContractResult.fail(
      'staging manifest signingIdentitySha256 must be lowercase SHA-256',
    );
  }
  if (!_isSha256(manifest['payloadProducerSha256'])) {
    return const IosNotificationContractResult.fail(
      'staging manifest payloadProducerSha256 must be lowercase SHA-256',
    );
  }
  final relayAddresses = manifest['relayAddresses'];
  if (relayAddresses is! List ||
      relayAddresses.isEmpty ||
      relayAddresses.any((value) => !_isSafeRelayAddress(value))) {
    return const IosNotificationContractResult.fail(
      'staging manifest relayAddresses must be a nonempty safe string array',
    );
  }
  return const IosNotificationContractResult.pass(
    'staging APNs, relay, and provider prerequisites are explicit',
  );
}

IosNotificationContractResult validateIosNotificationProviderRequest(
  Map<String, Object?> request,
) {
  if (request['schema'] != iosNotificationProviderRequestSchema) {
    return const IosNotificationContractResult.fail(
      'provider request schema is unsupported',
    );
  }
  const exactKeys = <String>{
    'schema',
    'expectedTitle',
    'expectedBody',
    'expectedMessageText',
    'receiverDeviceId',
    'peerDeviceId',
  };
  if (request.keys.toSet().difference(exactKeys).isNotEmpty ||
      exactKeys.difference(request.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'provider request fields must match the exact private fixture schema',
    );
  }
  for (final entry in const <String, int>{
    'expectedTitle': 30,
    'expectedBody': 512,
    'expectedMessageText': 140,
  }.entries) {
    final value = request[entry.key];
    if (!_isAsciiFixtureText(value, maximum: entry.value)) {
      return IosNotificationContractResult.fail(
        'provider request ${entry.key} must be canonical bounded ASCII text',
      );
    }
  }
  for (final key in const <String>['receiverDeviceId', 'peerDeviceId']) {
    final value = request[key];
    if (value is! String || value.trim().isEmpty || value.length > 512) {
      return IosNotificationContractResult.fail(
        'provider request $key must be a bounded nonempty string',
      );
    }
  }
  final messageText = request['expectedMessageText']! as String;
  if ((request['expectedTitle']! as String).contains(messageText) ||
      (request['expectedBody']! as String).contains(messageText)) {
    return const IosNotificationContractResult.fail(
      'provider request alert must not expose expectedMessageText',
    );
  }
  return const IosNotificationContractResult.pass(
    'private provider request contains the bounded UI fixture contract',
  );
}

IosNotificationContractResult validateIosNotificationProviderReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String requestSha256,
  required String apnsPayloadSha256,
  required String receiverHandoffSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'provider receipt contains forbidden secret-bearing field $secret',
    );
  }
  const requiredKeys = <String>{
    'schema',
    'status',
    'provider',
    'relayInboxSeeded',
    'providerAccepted',
    'appSetupAutomated',
    'dedicatedDisposableReceiver',
    'cleanupDriverAvailable',
    'childBuildCount',
    'manualActionCount',
    'runId',
    'nonce',
    'receiverDeviceIdSha256',
    'requestSha256',
    'apnsPayloadSha256',
    'receiverHandoffSha256',
    'providerMessageIdSha256',
    'collapseIdentitySha256',
    'syntheticMessageIdSha256',
    'submissionStage',
    'relayLogPath',
    'relayLogSha256',
    'stagedEnvelopeSha256',
    'acceptedAt',
  };
  if (receipt.keys.toSet().difference(requiredKeys).isNotEmpty ||
      requiredKeys.difference(receipt.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'provider receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
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
    'submissionStage': 'first',
  };
  for (final entry in exact.entries) {
    if (receipt[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'provider receipt ${entry.key} must equal ${entry.value}',
      );
    }
  }
  if (receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceIdSha256'] != sha256String(receiverDeviceId) ||
      receipt['requestSha256'] != requestSha256 ||
      !_isSha256(apnsPayloadSha256) ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256 ||
      !_isSha256(receiverHandoffSha256) ||
      receipt['receiverHandoffSha256'] != receiverHandoffSha256) {
    return const IosNotificationContractResult.fail(
      'provider receipt is not bound to the exact run, target, request, '
      'payload, and receiver handoff',
    );
  }
  if (!_isSha256(receipt['providerMessageIdSha256']) ||
      !_isSha256(receipt['collapseIdentitySha256']) ||
      !_isSha256(receipt['syntheticMessageIdSha256'])) {
    return const IosNotificationContractResult.fail(
      'provider receipt requires redacted provider, collapse, and synthetic ID hashes',
    );
  }
  if (!_isSafeNonemptyString(receipt['relayLogPath']) ||
      !_isSha256(receipt['relayLogSha256']) ||
      !_isSha256(receipt['stagedEnvelopeSha256'])) {
    return const IosNotificationContractResult.fail(
      'provider receipt requires a redacted relay log and staged-envelope hashes',
    );
  }
  if (_utcTimestamp(receipt['acceptedAt']) == null) {
    return const IosNotificationContractResult.fail(
      'provider receipt acceptedAt must be a UTC timestamp',
    );
  }
  return const IosNotificationContractResult.pass(
    'provider receipt proves relay custody and APNs acceptance for this run',
  );
}

IosNotificationContractResult validateIosNotificationProviderRetryReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String requestSha256,
  required String apnsPayloadSha256,
  required String receiverHandoffSha256,
  required String collapseIdentitySha256,
  required String firstProviderReceiptSha256,
  required String firstProviderMessageIdSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'provider retry receipt contains forbidden secret-bearing field $secret',
    );
  }
  const exactKeys = <String>{
    'schema',
    'action',
    'status',
    'provider',
    'runId',
    'nonce',
    'receiverDeviceIdSha256',
    'requestSha256',
    'apnsPayloadSha256',
    'receiverHandoffSha256',
    'collapseIdentitySha256',
    'firstProviderReceiptSha256',
    'firstProviderMessageIdSha256',
    'secondProviderMessageIdSha256',
    'firstAcceptedAt',
    'secondAcceptedAt',
    'providerAcceptedCount',
    'payloadBytesIdentical',
    'collapseIdentityReused',
    'providerIdsDistinct',
    'childBuildCount',
    'manualActionCount',
  };
  if (!_hasExactKeys(receipt, exactKeys)) {
    return const IosNotificationContractResult.fail(
      'provider retry receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
    'schema': iosNotificationProviderRetryReceiptSchema,
    'action': 'retry',
    'status': 'accepted',
    'provider': 'apns',
    'providerAcceptedCount': 2,
    'payloadBytesIdentical': true,
    'collapseIdentityReused': true,
    'providerIdsDistinct': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
  };
  if (exact.entries.any((entry) => receipt[entry.key] != entry.value) ||
      receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceIdSha256'] != sha256String(receiverDeviceId) ||
      receipt['requestSha256'] != requestSha256 ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256 ||
      receipt['receiverHandoffSha256'] != receiverHandoffSha256 ||
      receipt['collapseIdentitySha256'] != collapseIdentitySha256 ||
      receipt['firstProviderReceiptSha256'] != firstProviderReceiptSha256 ||
      receipt['firstProviderMessageIdSha256'] != firstProviderMessageIdSha256 ||
      !_isSha256(receipt['secondProviderMessageIdSha256']) ||
      receipt['secondProviderMessageIdSha256'] ==
          firstProviderMessageIdSha256) {
    return const IosNotificationContractResult.fail(
      'provider retry receipt is not bound to two distinct identical-payload submissions',
    );
  }
  final first = _utcTimestamp(receipt['firstAcceptedAt']);
  final second = _utcTimestamp(receipt['secondAcceptedAt']);
  if (first == null || second == null || second.isBefore(first)) {
    return const IosNotificationContractResult.fail(
      'provider retry acceptance timestamps are invalid or out of order',
    );
  }
  return const IosNotificationContractResult.pass(
    'provider retry receipt binds two distinct APNs acceptances to identical bytes and collapse identity',
  );
}

IosNotificationContractResult validateIosNotificationProviderCleanupReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String providerReceiptSha256,
  required String apnsPayloadSha256,
  required String receiverHandoffSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'provider cleanup receipt contains forbidden secret-bearing field '
      '$secret',
    );
  }
  const requiredKeys = <String>{
    'schema',
    'status',
    'dedicatedDisposableReceiver',
    'relayFixtureCleared',
    'appTestStateCleared',
    'notificationStateCleared',
    'candidateAppRemoved',
    'childBuildCount',
    'manualActionCount',
    'runId',
    'nonce',
    'receiverDeviceIdSha256',
    'providerReceiptSha256',
    'apnsPayloadSha256',
    'receiverHandoffSha256',
    'cleanedAt',
  };
  if (receipt.keys.toSet().difference(requiredKeys).isNotEmpty ||
      requiredKeys.difference(receipt.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'provider cleanup receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
    'schema': iosNotificationProviderCleanupReceiptSchema,
    'status': 'cleaned',
    'dedicatedDisposableReceiver': true,
    'relayFixtureCleared': true,
    'appTestStateCleared': true,
    'notificationStateCleared': true,
    'candidateAppRemoved': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
  };
  for (final entry in exact.entries) {
    if (receipt[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'provider cleanup receipt ${entry.key} must equal ${entry.value}',
      );
    }
  }
  if (receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceIdSha256'] != sha256String(receiverDeviceId) ||
      receipt['providerReceiptSha256'] != providerReceiptSha256 ||
      !_isSha256(apnsPayloadSha256) ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256 ||
      !_isSha256(receiverHandoffSha256) ||
      receipt['receiverHandoffSha256'] != receiverHandoffSha256) {
    return const IosNotificationContractResult.fail(
      'provider cleanup receipt is not bound to the exact run, target, '
      'payload, and receiver handoff',
    );
  }
  if (_utcTimestamp(receipt['cleanedAt']) == null) {
    return const IosNotificationContractResult.fail(
      'provider cleanup receipt cleanedAt must be a UTC timestamp',
    );
  }
  return const IosNotificationContractResult.pass(
    'dedicated iPhone relay, app, notification, and fixture state was cleared',
  );
}

IosNotificationContractResult validateIosNotificationAutomationReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String peerDeviceId,
  required String preparedApplicationSha256,
  required String providerRequestSha256,
  required String payloadProducerSha256,
  required String apnsPayloadSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'automation receipt contains forbidden secret-bearing field $secret',
    );
  }
  const requiredKeys = <String>{
    'schema',
    'scenario',
    'status',
    'platform',
    'receiverPhysical',
    'runId',
    'nonce',
    'receiverDeviceId',
    'peerDeviceId',
    'preparedApplicationSha256',
    'providerRequestSha256',
    'payloadProducerSha256',
    'apnsPayloadSha256',
    'childBuildCount',
    'manualActionCount',
    'checks',
    'timestamps',
    'evidenceSha256',
  };
  if (receipt.keys.toSet().difference(requiredKeys).isNotEmpty ||
      requiredKeys.difference(receipt.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'automation receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
    'schema': iosNotificationAutomationReceiptSchema,
    'scenario': iosNotificationPayloadScenario,
    'status': 'passed',
    'platform': 'ios',
    'receiverPhysical': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
  };
  for (final entry in exact.entries) {
    if (receipt[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'automation receipt ${entry.key} must equal ${entry.value}',
      );
    }
  }
  if (receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceId'] != receiverDeviceId ||
      receipt['peerDeviceId'] != peerDeviceId ||
      receipt['preparedApplicationSha256'] != preparedApplicationSha256 ||
      receipt['providerRequestSha256'] != providerRequestSha256 ||
      !_isSha256(payloadProducerSha256) ||
      receipt['payloadProducerSha256'] != payloadProducerSha256 ||
      !_isSha256(apnsPayloadSha256) ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256) {
    return const IosNotificationContractResult.fail(
      'automation receipt is not bound to the exact run, targets, and app',
    );
  }

  final checksValue = receipt['checks'];
  if (checksValue is! Map) {
    return const IosNotificationContractResult.fail(
      'automation receipt checks must be an object',
    );
  }
  const requiredChecks = <String>{
    'appSetupAutomated',
    'notificationPermissionAutomated',
    'apnsDelivered',
    'nseProcessObserved',
    'nseStagingOn',
    'nse04P0WithStagingOn',
    'airplaneModeBeforeTap',
    'notificationTapAutomated',
    'messageVisibleFromStagedEnvelope',
    'networkRestored',
    'appTerminatedAfterCapture',
    'providerCleanupAutomated',
    'testStateCleared',
  };
  const allChecks = <String>{
    ...requiredChecks,
    'relayDrainCountBeforeVisibility',
  };
  if (checksValue.keys.toSet().difference(allChecks).isNotEmpty ||
      allChecks.difference(checksValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'automation receipt checks fields must match the exact schema',
    );
  }
  final missing = requiredChecks
      .where((key) => checksValue[key] != true)
      .toList(growable: false);
  if (missing.isNotEmpty) {
    return IosNotificationContractResult.fail(
      'automation receipt is missing checks: ${missing.join(', ')}',
    );
  }
  if (checksValue['relayDrainCountBeforeVisibility'] != 0) {
    return const IosNotificationContractResult.fail(
      'automation receipt observed a relay drain before staged visibility',
    );
  }

  final timestampsValue = receipt['timestamps'];
  if (timestampsValue is! Map) {
    return const IosNotificationContractResult.fail(
      'automation receipt timestamps must be an object',
    );
  }
  const timestampKeys = <String>{
    'providerAcceptedAt',
    'nseStagedAt',
    'apnsDeliveredAt',
    'airplaneEnabledAt',
    'notificationTappedAt',
    'messageVisibleAt',
    'networkRestoredAt',
  };
  if (timestampsValue.keys.toSet().difference(timestampKeys).isNotEmpty ||
      timestampKeys.difference(timestampsValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'automation receipt timestamp fields must match the exact schema',
    );
  }
  final providerAcceptedAt = _utcTimestamp(
    timestampsValue['providerAcceptedAt'],
  );
  final nseStagedAt = _utcTimestamp(timestampsValue['nseStagedAt']);
  final deviceTimestamps = <DateTime?>[
    _utcTimestamp(timestampsValue['apnsDeliveredAt']),
    _utcTimestamp(timestampsValue['airplaneEnabledAt']),
    _utcTimestamp(timestampsValue['notificationTappedAt']),
    _utcTimestamp(timestampsValue['messageVisibleAt']),
    _utcTimestamp(timestampsValue['networkRestoredAt']),
  ];
  if (providerAcceptedAt == null ||
      nseStagedAt == null ||
      deviceTimestamps.any((value) => value == null)) {
    return const IosNotificationContractResult.fail(
      'automation receipt requires seven UTC lifecycle timestamps',
    );
  }
  // Provider acceptance and NSE observation are stamped by the host. The
  // remaining markers are stamped by the iPhone. Compare ordering only within
  // each clock domain so harmless device/host skew cannot reject a real run.
  if (nseStagedAt.isBefore(providerAcceptedAt)) {
    return const IosNotificationContractResult.fail(
      'host provider acceptance and NSE observation timestamps are out of order',
    );
  }
  for (var index = 1; index < deviceTimestamps.length; index += 1) {
    if (deviceTimestamps[index]!.isBefore(deviceTimestamps[index - 1]!)) {
      return const IosNotificationContractResult.fail(
        'iPhone APNs, airplane, tap, visibility, and restoration timestamps '
        'are out of order',
      );
    }
  }

  final evidenceValue = receipt['evidenceSha256'];
  if (evidenceValue is! Map) {
    return const IosNotificationContractResult.fail(
      'automation receipt evidenceSha256 must be an object',
    );
  }
  const requiredEvidence = <String>{
    'preparedApplication',
    'payloadProducer',
    'apnsPayload',
    'providerReceipt',
    'providerCleanupReceipt',
    'relayLog',
    'nseLog',
    'recipientLog',
    'uiAutomationLog',
    'stagedEnvelope',
  };
  if (evidenceValue.keys.toSet().difference(requiredEvidence).isNotEmpty ||
      requiredEvidence.difference(evidenceValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'automation receipt evidenceSha256 fields are not exact',
    );
  }
  for (final key in requiredEvidence) {
    if (!_isSha256(evidenceValue[key])) {
      return IosNotificationContractResult.fail(
        'automation receipt evidenceSha256.$key is invalid',
      );
    }
  }
  if (evidenceValue['preparedApplication'] != preparedApplicationSha256 ||
      evidenceValue['payloadProducer'] != payloadProducerSha256 ||
      evidenceValue['apnsPayload'] != apnsPayloadSha256) {
    return const IosNotificationContractResult.fail(
      'automation evidence hashes do not match the executed app, producer, '
      'and encrypted APNs payload',
    );
  }
  return const IosNotificationContractResult.pass(
    'physical APNs/NSE staged-envelope airplane-tap lifecycle is complete',
  );
}

IosNotificationContractResult validateIosNotificationRecoveryAutomationReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String peerDeviceId,
  required String preparedApplicationSha256,
  required String providerRequestSha256,
  required String payloadProducerSha256,
  required String apnsPayloadSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'recovery automation receipt contains forbidden secret-bearing field '
      '$secret',
    );
  }
  const requiredKeys = <String>{
    'schema',
    'scenario',
    'phase',
    'status',
    'platform',
    'receiverPhysical',
    'runId',
    'nonce',
    'receiverDeviceId',
    'peerDeviceId',
    'preparedApplicationSha256',
    'providerRequestSha256',
    'payloadProducerSha256',
    'apnsPayloadSha256',
    'childBuildCount',
    'manualActionCount',
    'passDiagnosticRetained',
    'cleanupOwners',
    'checks',
    'counts',
    'requestIdentifierSha256',
    'timestamps',
    'evidenceSha256',
  };
  if (receipt.keys.toSet().difference(requiredKeys).isNotEmpty ||
      requiredKeys.difference(receipt.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
    'schema': iosNotificationRecoveryAutomationReceiptSchema,
    'scenario': iosNotificationPayloadScenario,
    'phase': 'recovery',
    'status': 'passed',
    'platform': 'ios',
    'receiverPhysical': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
    'passDiagnosticRetained': true,
  };
  for (final entry in exact.entries) {
    if (receipt[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'recovery automation receipt ${entry.key} must equal ${entry.value}',
      );
    }
  }
  if (!_isSha256(preparedApplicationSha256) ||
      !_isSha256(providerRequestSha256) ||
      !_isSha256(payloadProducerSha256) ||
      !_isSha256(apnsPayloadSha256) ||
      receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceId'] != receiverDeviceId ||
      receipt['peerDeviceId'] != peerDeviceId ||
      receipt['preparedApplicationSha256'] != preparedApplicationSha256 ||
      receipt['providerRequestSha256'] != providerRequestSha256 ||
      receipt['payloadProducerSha256'] != payloadProducerSha256 ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt is not bound to the exact run, targets, '
      'app, request, producer, and APNs payload',
    );
  }

  final checksValue = receipt['checks'];
  if (checksValue is! Map) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt checks must be an object',
    );
  }
  const requiredChecks = <String>{
    'notificationPermissionAutomated',
    'badgePermissionEnabled',
    'providerPayloadBadgeAbsent',
    'deliveredNotificationBadgeWasNil',
    'apnsDelivered',
    'nseProcessObserved',
    'recoveryClaimUnique',
    'runnerAbsoluteBadgeConverged',
    'exactOwnedNotificationRetired',
    'unrelatedSentinelSurvived',
    'zeroBadgePublished',
    'providerCleanupAutomated',
    'testStateCleared',
    'sourceInventoryStable',
    'directSourceUsefulProviderOnly',
    'backgroundHandlerReached',
    'backgroundContenderSuppressed',
    'noMatchingLocalShow',
    'completeWindowNseBound',
  };
  if (checksValue.keys.toSet().difference(requiredChecks).isNotEmpty ||
      requiredChecks.difference(checksValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt checks fields must match the exact schema',
    );
  }
  final failedChecks = requiredChecks
      .where((key) => checksValue[key] != true)
      .toList(growable: false);
  if (failedChecks.isNotEmpty) {
    return IosNotificationContractResult.fail(
      'recovery automation receipt is missing checks: '
      '${failedChecks.join(', ')}',
    );
  }
  if (!_hasExpectedSuccessfulIosNotificationCleanupOwners(
    receipt['cleanupOwners'],
  )) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt cleanupOwners must expose exact successful '
      'per-owner required, attempted, and completed state',
    );
  }

  final countsValue = receipt['counts'];
  if (countsValue is! Map) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt counts must be an object',
    );
  }
  const exactCounts = <String, int>{
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
  };
  if (countsValue.keys
          .toSet()
          .difference(exactCounts.keys.toSet())
          .isNotEmpty ||
      exactCounts.keys
          .toSet()
          .difference(countsValue.keys.toSet())
          .isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt count fields must match the exact schema',
    );
  }
  for (final entry in exactCounts.entries) {
    if (countsValue[entry.key] != entry.value) {
      return IosNotificationContractResult.fail(
        'recovery automation receipt count ${entry.key} must equal '
        '${entry.value}',
      );
    }
  }
  final requestHashes = receipt['requestIdentifierSha256'];
  if (requestHashes is! List ||
      requestHashes.length != 1 ||
      requestHashes.toSet().length != 1 ||
      !_isSha256(requestHashes.single)) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt requires one bounded hashed request identity',
    );
  }

  final timestampsValue = receipt['timestamps'];
  if (timestampsValue is! Map) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt timestamps must be an object',
    );
  }
  const timestampKeys = <String>{
    'providerAcceptedAt',
    'nseObservedAt',
    'cardObservedAt',
    'badgeObservedAt',
    'recoveryCompletedAt',
    'retirementObservedAt',
    'zeroBadgeObservedAt',
  };
  if (timestampsValue.keys.toSet().difference(timestampKeys).isNotEmpty ||
      timestampKeys.difference(timestampsValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt timestamp fields must match the exact schema',
    );
  }
  final providerAcceptedAt = _utcTimestamp(
    timestampsValue['providerAcceptedAt'],
  );
  final nseObservedAt = _utcTimestamp(timestampsValue['nseObservedAt']);
  final deviceTimestamps = <DateTime?>[
    _utcTimestamp(timestampsValue['cardObservedAt']),
    _utcTimestamp(timestampsValue['badgeObservedAt']),
    _utcTimestamp(timestampsValue['recoveryCompletedAt']),
    _utcTimestamp(timestampsValue['retirementObservedAt']),
    _utcTimestamp(timestampsValue['zeroBadgeObservedAt']),
  ];
  if (providerAcceptedAt == null ||
      nseObservedAt == null ||
      deviceTimestamps.any((value) => value == null)) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt requires seven UTC lifecycle timestamps',
    );
  }
  // Provider and NSE timestamps use the host clock. Recovery observation and
  // mutation timestamps use the iPhone clock. Preserve causality within each
  // domain without rejecting a valid run because the two devices are skewed.
  if (nseObservedAt.isBefore(providerAcceptedAt)) {
    return const IosNotificationContractResult.fail(
      'host provider acceptance and NSE observation timestamps are out of order',
    );
  }
  for (var index = 1; index < deviceTimestamps.length; index += 1) {
    if (deviceTimestamps[index]!.isBefore(deviceTimestamps[index - 1]!)) {
      return const IosNotificationContractResult.fail(
        'iPhone recovery observation, convergence, retirement, and zero-badge '
        'timestamps are out of order',
      );
    }
  }

  final evidenceValue = receipt['evidenceSha256'];
  if (evidenceValue is! Map) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt evidenceSha256 must be an object',
    );
  }
  const requiredEvidence = <String>{
    'preparedApplication',
    'payloadProducer',
    'apnsPayload',
    'providerReceipt',
    'providerCleanupReceipt',
    'notificationRecoveryReceipt',
    'relayLog',
    'nseLog',
    'recipientLog',
    'uiAutomationLog',
    'stagedEnvelope',
    'causalDiagnostic',
  };
  if (evidenceValue.keys.toSet().difference(requiredEvidence).isNotEmpty ||
      requiredEvidence.difference(evidenceValue.keys.toSet()).isNotEmpty) {
    return const IosNotificationContractResult.fail(
      'recovery automation receipt evidenceSha256 fields are not exact',
    );
  }
  for (final key in requiredEvidence) {
    if (!_isSha256(evidenceValue[key])) {
      return IosNotificationContractResult.fail(
        'recovery automation receipt evidenceSha256.$key is invalid',
      );
    }
  }
  if (evidenceValue['preparedApplication'] != preparedApplicationSha256 ||
      evidenceValue['payloadProducer'] != payloadProducerSha256 ||
      evidenceValue['apnsPayload'] != apnsPayloadSha256) {
    return const IosNotificationContractResult.fail(
      'recovery evidence hashes do not match the executed app, producer, and '
      'APNs payload',
    );
  }
  return const IosNotificationContractResult.pass(
    'physical APNs recovery proved one stable useful provider source, one '
    'background-handler contender suppression, and exact retirement',
  );
}

IosNotificationContractResult validateIosNotificationRetryAutomationReceipt(
  Map<String, Object?> receipt, {
  required String runId,
  required String nonce,
  required String receiverDeviceId,
  required String peerDeviceId,
  required String preparedApplicationSha256,
  required String providerRequestSha256,
  required String payloadProducerSha256,
  required String apnsPayloadSha256,
}) {
  final secret = findIosNotificationSecretBearingField(receipt);
  if (secret != null) {
    return IosNotificationContractResult.fail(
      'retry automation receipt contains forbidden secret-bearing field $secret',
    );
  }
  const exactKeys = <String>{
    'schema',
    'scenario',
    'phase',
    'status',
    'platform',
    'receiverPhysical',
    'runId',
    'nonce',
    'receiverDeviceId',
    'peerDeviceId',
    'preparedApplicationSha256',
    'providerRequestSha256',
    'payloadProducerSha256',
    'apnsPayloadSha256',
    'collapseIdentitySha256',
    'requestIdentifierSha256',
    'childBuildCount',
    'manualActionCount',
    'passDiagnosticRetained',
    'cleanupOwners',
    'checks',
    'counts',
    'timestamps',
    'providerMessageIdSha256',
    'evidenceSha256',
  };
  if (!_hasExactKeys(receipt, exactKeys)) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt fields must match the exact schema',
    );
  }
  const exact = <String, Object?>{
    'schema': iosNotificationRetryAutomationReceiptSchema,
    'scenario': iosNotificationPayloadScenario,
    'phase': 'retry',
    'status': 'passed',
    'platform': 'ios',
    'receiverPhysical': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
    'passDiagnosticRetained': true,
  };
  if (exact.entries.any((entry) => receipt[entry.key] != entry.value) ||
      receipt['runId'] != runId ||
      receipt['nonce'] != nonce ||
      receipt['receiverDeviceId'] != receiverDeviceId ||
      receipt['peerDeviceId'] != peerDeviceId ||
      receipt['preparedApplicationSha256'] != preparedApplicationSha256 ||
      receipt['providerRequestSha256'] != providerRequestSha256 ||
      receipt['payloadProducerSha256'] != payloadProducerSha256 ||
      receipt['apnsPayloadSha256'] != apnsPayloadSha256 ||
      !_isSha256(receipt['collapseIdentitySha256']) ||
      receipt['requestIdentifierSha256'] != receipt['collapseIdentitySha256']) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt is not bound to the exact run and final collapse identity',
    );
  }
  const requiredChecks = <String>{
    'firstDeliveryFenced',
    'secondTrustedPassiveHandoff',
    'providerAcceptancesDistinct',
    'payloadBytesIdentical',
    'collapseIdentityReused',
    'finalRequestIdentifierMatchesCollapse',
    'samePayloadRetrySingleUsefulCard',
    'noSanitizedProviderCard',
    'noFlutterLocalCard',
    'noUnknownCard',
    'noMatchingLocalShow',
    'completeWindowNseBound',
    'providerCleanupAutomated',
    'testStateCleared',
  };
  final checks = receipt['checks'];
  if (checks is! Map ||
      !_hasExactKeys(checks, requiredChecks) ||
      requiredChecks.any((key) => checks[key] != true)) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt requires every exact retry and cleanup check',
    );
  }
  if (!_hasExpectedSuccessfulIosNotificationCleanupOwners(
    receipt['cleanupOwners'],
  )) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt cleanupOwners must expose exact successful '
      'per-owner required, attempted, and completed state',
    );
  }
  const exactCounts = <String, int>{
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
  };
  final counts = receipt['counts'];
  if (counts is! Map ||
      !_hasExactKeys(counts, exactCounts.keys.toSet()) ||
      exactCounts.entries.any((entry) => counts[entry.key] != entry.value)) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt counts do not prove the complete two-send window',
    );
  }
  final providerIds = receipt['providerMessageIdSha256'];
  if (providerIds is! List ||
      providerIds.length != 2 ||
      providerIds.toSet().length != 2 ||
      providerIds.any((value) => !_isSha256(value))) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt requires two distinct hashed provider IDs',
    );
  }
  const timestampKeys = <String>{
    'firstAcceptedAt',
    'firstNseObservedAt',
    'firstCardObservedAt',
    'secondAcceptedAt',
    'secondNseObservedAt',
    'secondCardObservedAt',
  };
  final timestamps = receipt['timestamps'];
  if (timestamps is! Map || !_hasExactKeys(timestamps, timestampKeys)) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt timestamps must match the exact schema',
    );
  }
  final firstAccepted = _utcTimestamp(timestamps['firstAcceptedAt']);
  final firstNse = _utcTimestamp(timestamps['firstNseObservedAt']);
  final firstCard = _utcTimestamp(timestamps['firstCardObservedAt']);
  final secondAccepted = _utcTimestamp(timestamps['secondAcceptedAt']);
  final secondNse = _utcTimestamp(timestamps['secondNseObservedAt']);
  final secondCard = _utcTimestamp(timestamps['secondCardObservedAt']);
  if (<DateTime?>[
        firstAccepted,
        firstNse,
        firstCard,
        secondAccepted,
        secondNse,
        secondCard,
      ].any((value) => value == null) ||
      firstNse!.isBefore(firstAccepted!) ||
      secondAccepted!.isBefore(firstAccepted) ||
      secondNse!.isBefore(secondAccepted) ||
      secondCard!.isBefore(firstCard!)) {
    return const IosNotificationContractResult.fail(
      'retry automation receipt timestamps do not fence first then second delivery',
    );
  }
  const evidenceKeys = <String>{
    'preparedApplication',
    'payloadProducer',
    'apnsPayload',
    'firstProviderReceipt',
    'secondProviderReceipt',
    'providerCleanupReceipt',
    'firstInventoryReceipt',
    'secondInventoryReceipt',
    'relayLog',
    'nseLog',
    'recipientLog',
    'uiAutomationLog',
    'causalDiagnostic',
    'stagedEnvelope',
  };
  final evidence = receipt['evidenceSha256'];
  if (evidence is! Map ||
      !_hasExactKeys(evidence, evidenceKeys) ||
      evidenceKeys.any((key) => !_isSha256(evidence[key])) ||
      evidence['preparedApplication'] != preparedApplicationSha256 ||
      evidence['payloadProducer'] != payloadProducerSha256 ||
      evidence['apnsPayload'] != apnsPayloadSha256) {
    return const IosNotificationContractResult.fail(
      'retry automation evidence hashes are incomplete or unbound',
    );
  }
  return const IosNotificationContractResult.pass(
    'two accepted identical APNs requests fenced active then trusted-passive handoffs and one useful card',
  );
}

Map<String, Object?> buildIosNotificationArtifact({
  required Map<String, Object?> automationReceipt,
  required Map<String, Object?> recoveryAutomationReceipt,
  required Map<String, Object?> retryAutomationReceipt,
  required String capturedAt,
}) {
  final checks = Map<String, Object?>.from(automationReceipt['checks']! as Map);
  final recoveryChecks = Map<String, Object?>.from(
    recoveryAutomationReceipt['checks']! as Map,
  );
  final retryChecks = Map<String, Object?>.from(
    retryAutomationReceipt['checks']! as Map,
  );
  final timestamps = Map<String, Object?>.from(
    automationReceipt['timestamps']! as Map,
  );
  final recoveryTimestamps = Map<String, Object?>.from(
    recoveryAutomationReceipt['timestamps']! as Map,
  );
  final fastEvidence = Map<String, Object?>.from(
    automationReceipt['evidenceSha256']! as Map,
  );
  final recoveryEvidence = Map<String, Object?>.from(
    recoveryAutomationReceipt['evidenceSha256']! as Map,
  );
  final retryEvidence = Map<String, Object?>.from(
    retryAutomationReceipt['evidenceSha256']! as Map,
  );
  final recoveryCleanupOwners = _copyIosNotificationCleanupOwners(
    recoveryAutomationReceipt['cleanupOwners']! as Map,
  );
  final retryCleanupOwners = _copyIosNotificationCleanupOwners(
    retryAutomationReceipt['cleanupOwners']! as Map,
  );
  final artifact = <String, Object?>{
    'testCase': 'TC-B12',
    'recoveryTestCase': 'TC-333-08',
    'directSourceTestCase': 'TC-396-03',
    'retryTestCase': 'TC-396-04',
    'scenario': iosNotificationPayloadScenario,
    'status': 'passed',
    'platform': 'ios',
    'capturedAt': capturedAt,
    'devices': <String>[
      automationReceipt['receiverDeviceId']! as String,
      automationReceipt['peerDeviceId']! as String,
    ],
    'checks': <String, Object?>{
      'iosReceiver': true,
      'apnsDelivered': checks['apnsDelivered'] == true,
      'nseStagingOn': checks['nseStagingOn'] == true,
      'nse04P0WithStagingOn': checks['nse04P0WithStagingOn'] == true,
      'airplaneModeBeforeTap': checks['airplaneModeBeforeTap'] == true,
      'messageVisibleFromStagedEnvelope':
          checks['messageVisibleFromStagedEnvelope'] == true,
      'noRelayDrainBeforeVisibility':
          checks['relayDrainCountBeforeVisibility'] == 0,
      'networkRestored': checks['networkRestored'] == true,
      'appTerminatedAfterCapture': checks['appTerminatedAfterCapture'] == true,
      'badgePermissionEnabled':
          recoveryChecks['badgePermissionEnabled'] == true,
      'providerPayloadBadgeAbsent':
          recoveryChecks['providerPayloadBadgeAbsent'] == true,
      'deliveredNotificationBadgeWasNil':
          recoveryChecks['deliveredNotificationBadgeWasNil'] == true,
      'recoveryClaimUnique': recoveryChecks['recoveryClaimUnique'] == true,
      'runnerAbsoluteBadgeConverged':
          recoveryChecks['runnerAbsoluteBadgeConverged'] == true,
      'exactOwnedNotificationRetired':
          recoveryChecks['exactOwnedNotificationRetired'] == true,
      'unrelatedSentinelSurvived':
          recoveryChecks['unrelatedSentinelSurvived'] == true,
      'zeroBadgePublished': recoveryChecks['zeroBadgePublished'] == true,
      'directSourceUsefulProviderOnly':
          recoveryChecks['directSourceUsefulProviderOnly'] == true,
      'backgroundContenderSuppressed':
          recoveryChecks['backgroundContenderSuppressed'] == true,
      'samePayloadRetrySingleUsefulCard':
          retryChecks['samePayloadRetrySingleUsefulCard'] == true,
      'retryReceiptsDistinctAndBound':
          retryChecks['providerAcceptancesDistinct'] == true &&
          retryChecks['payloadBytesIdentical'] == true &&
          retryChecks['collapseIdentityReused'] == true &&
          retryChecks['finalRequestIdentifierMatchesCollapse'] == true,
      'hostFailureDiagnosticRetentionContract': true,
      'hostUnconditionalCleanupContract': true,
    },
    'passDiagnosticRetained':
        recoveryAutomationReceipt['passDiagnosticRetained'] == true &&
        retryAutomationReceipt['passDiagnosticRetained'] == true,
    'cleanupOwners': <String, Object?>{
      'recovery': recoveryCleanupOwners,
      'retry': retryCleanupOwners,
    },
    'messageVisibleAt': timestamps['messageVisibleAt'],
    'networkRestoredAt': timestamps['networkRestoredAt'],
    'recoveryCompletedAt': recoveryTimestamps['recoveryCompletedAt'],
    'recoveryZeroBadgeObservedAt': recoveryTimestamps['zeroBadgeObservedAt'],
    'preparedApplicationSha256': automationReceipt['preparedApplicationSha256'],
    'runId': automationReceipt['runId'],
    'nonce': automationReceipt['nonce'],
    'recoveryRunId': recoveryAutomationReceipt['runId'],
    'recoveryNonce': recoveryAutomationReceipt['nonce'],
    'retryRunId': retryAutomationReceipt['runId'],
    'retryNonce': retryAutomationReceipt['nonce'],
    'providerRequestSha256': automationReceipt['providerRequestSha256'],
    'payloadProducerSha256': automationReceipt['payloadProducerSha256'],
    'apnsPayloadSha256': automationReceipt['apnsPayloadSha256'],
    'recoveryApnsPayloadSha256': recoveryAutomationReceipt['apnsPayloadSha256'],
    'retryApnsPayloadSha256': retryAutomationReceipt['apnsPayloadSha256'],
    'retryCollapseIdentitySha256':
        retryAutomationReceipt['collapseIdentitySha256'],
    'retryRequestIdentifierSha256':
        retryAutomationReceipt['requestIdentifierSha256'],
    'retryProviderMessageIdSha256':
        retryAutomationReceipt['providerMessageIdSha256'],
    'childBuildCount': automationReceipt['childBuildCount'],
    'manualActionCount': automationReceipt['manualActionCount'],
    'recoveryCounts': recoveryAutomationReceipt['counts'],
    'retryCounts': retryAutomationReceipt['counts'],
    'evidenceSha256': <String, Object?>{
      ...fastEvidence,
      'recoveryPreparedApplication': recoveryEvidence['preparedApplication'],
      'recoveryPayloadProducer': recoveryEvidence['payloadProducer'],
      'recoveryApnsPayload': recoveryEvidence['apnsPayload'],
      'recoveryProviderReceipt': recoveryEvidence['providerReceipt'],
      'recoveryProviderCleanupReceipt':
          recoveryEvidence['providerCleanupReceipt'],
      'notificationRecoveryReceipt':
          recoveryEvidence['notificationRecoveryReceipt'],
      'recoveryRelayLog': recoveryEvidence['relayLog'],
      'recoveryNseLog': recoveryEvidence['nseLog'],
      'recoveryRecipientLog': recoveryEvidence['recipientLog'],
      'recoveryUiAutomationLog': recoveryEvidence['uiAutomationLog'],
      'recoveryStagedEnvelope': recoveryEvidence['stagedEnvelope'],
      'recoveryCausalDiagnostic': recoveryEvidence['causalDiagnostic'],
      'retryPreparedApplication': retryEvidence['preparedApplication'],
      'retryPayloadProducer': retryEvidence['payloadProducer'],
      'retryApnsPayload': retryEvidence['apnsPayload'],
      'retryFirstProviderReceipt': retryEvidence['firstProviderReceipt'],
      'retrySecondProviderReceipt': retryEvidence['secondProviderReceipt'],
      'retryProviderCleanupReceipt': retryEvidence['providerCleanupReceipt'],
      'retryFirstInventoryReceipt': retryEvidence['firstInventoryReceipt'],
      'retrySecondInventoryReceipt': retryEvidence['secondInventoryReceipt'],
      'retryRelayLog': retryEvidence['relayLog'],
      'retryNseLog': retryEvidence['nseLog'],
      'retryRecipientLog': retryEvidence['recipientLog'],
      'retryUiAutomationLog': retryEvidence['uiAutomationLog'],
      'retryCausalDiagnostic': retryEvidence['causalDiagnostic'],
      'retryStagedEnvelope': retryEvidence['stagedEnvelope'],
    },
  };
  return artifact;
}

String? findIosNotificationSecretBearingField(
  Object? value, [
  String path = r'$',
]) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toLowerCase();
      if (_forbiddenSecretKeys.contains(normalized) && entry.value != null) {
        return '$path.$key';
      }
      final nested = findIosNotificationSecretBearingField(
        entry.value,
        '$path.$key',
      );
      if (nested != null) return nested;
    }
    return null;
  }
  if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      final nested = findIosNotificationSecretBearingField(
        item,
        '$path[$index]',
      );
      if (nested != null) return nested;
      index += 1;
    }
    return null;
  }
  if (value is String &&
      (value.contains('BEGIN PRIVATE KEY') ||
          value.contains('BEGIN EC PRIVATE KEY'))) {
    return path;
  }
  return null;
}

const Set<String> _forbiddenSecretKeys = <String>{
  'token',
  'apnstoken',
  'fcmtoken',
  'ciphertext',
  'privatekey',
  'secret',
  'secretkey',
  'mnemonic',
  'authorization',
  'password',
};

String sha256String(String value) {
  return sha256.convert(utf8.encode(value)).toString();
}

String sha256FileSystemEntity(FileSystemEntity entity) {
  final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    return sha256.convert(File(entity.path).readAsBytesSync()).toString();
  }
  if (type != FileSystemEntityType.directory) {
    throw const FormatException(
      'prepared application must be a regular file or directory',
    );
  }
  final root = Directory(entity.path).absolute;
  final records = <String>[];
  final entries = root.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entry in entries) {
    final relative = entry.path.substring(root.path.length + 1);
    final entryType = FileSystemEntity.typeSync(entry.path, followLinks: false);
    if (entryType == FileSystemEntityType.file) {
      records.add(
        'file\t$relative\t'
        '${sha256.convert(File(entry.path).readAsBytesSync())}',
      );
    } else if (entryType == FileSystemEntityType.directory) {
      records.add('directory\t$relative');
    } else {
      throw FormatException(
        'prepared application contains unsupported entry $relative',
      );
    }
  }
  return sha256.convert(utf8.encode(records.join('\n'))).toString();
}

bool _isSha256(Object? value) =>
    value is String && _sha256Pattern.hasMatch(value);

bool _hasExactKeys(Map value, Set<String> expected) {
  if (value.keys.any((key) => key is! String)) return false;
  final actual = value.keys.cast<String>().toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

bool _hasExpectedSuccessfulIosNotificationCleanupOwners(Object? value) {
  if (value is! Map ||
      !_hasExactKeys(value, _iosNotificationCleanupOwnerKeys)) {
    return false;
  }
  for (final owner in _iosNotificationCleanupOwnerKeys) {
    final state = value[owner];
    if (state is! Map ||
        !_hasExactKeys(state, _iosNotificationCleanupStateKeys)) {
      return false;
    }
    final required = _iosNotificationRequiredCleanupOwners.contains(owner);
    if (state['required'] != required ||
        state['attempted'] != required ||
        state['completed'] != required) {
      return false;
    }
  }
  return true;
}

Map<String, Object?> _copyIosNotificationCleanupOwners(Map value) =>
    <String, Object?>{
      for (final owner in _iosNotificationCleanupOwnerKeys)
        owner: Map<String, Object?>.from(value[owner]! as Map),
    };

bool _isSafeNonemptyString(Object? value) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.length <= 256 &&
    !value.contains(RegExp(r'[\r\n]'));

bool _isAsciiFixtureText(Object? value, {required int maximum}) =>
    value is String &&
    value.isNotEmpty &&
    value == value.trim() &&
    value.length <= maximum &&
    value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e);

bool _isSafeRelayAddress(Object? value) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.length <= 512 &&
    !value.contains(RegExp(r'[\r\n]'));

DateTime? _utcTimestamp(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) return null;
  return parsed;
}
