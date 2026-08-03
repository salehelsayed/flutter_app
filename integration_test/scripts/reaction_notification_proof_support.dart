import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';

const String plan256ArtifactSchema = 'mknoon.plan256.device-proof.v1';
const String backgroundCryptoPreflightBundleSchema =
    'mknoon.android-background-crypto-preflight.v3';
const String backgroundCryptoCleanupArtifactSchema =
    'mknoon.android-background-crypto-cleanup.v1';
const String backgroundCryptoSetupArtifactSchema =
    'mknoon.android-background-crypto-setup.v1';
const String backgroundCryptoResetArtifactSchema =
    'mknoon.android-background-crypto-reset.v1';
const String backgroundCryptoProviderResultSchema =
    'mknoon.fcm-provider-result.v1';
const String backgroundCryptoProviderDiagnosticArtifactSchema =
    'mknoon.android-provider-diagnostic.v2';
const String backgroundCryptoPushRelayRegistrationArtifactSchema =
    'mknoon.android-push-relay-registration.v1';
const String backgroundCryptoPushRelayRegistrationArtifactSchemaV2 =
    'mknoon.android-push-relay-registration.v2';
const String backgroundCryptoPushRelayRegistrationReceiptSchema =
    'mknoon.push-relay-registration-receipt.v1';
const String backgroundCryptoPushRelayRegistrationReceiptSchemaV2 =
    'mknoon.push-relay-registration-receipt.v2';
const Duration backgroundCryptoPushRelayReceiptFutureClockSkew = Duration(
  seconds: 5,
);
const String backgroundCryptoPushRelayRegistrationCommandSchema =
    'mknoon.tc256-push-relay-registration-command.v1';
const String backgroundCryptoPushRelayRegistrationCommandSchemaV2 =
    'mknoon.tc256-push-relay-registration-command.v2';
const String backgroundCryptoCurrentTokenAuthorizationKind =
    'sdk_current_validate_only';
const Duration backgroundCryptoCurrentTokenAuthorizationMaxAge = Duration(
  minutes: 30,
);
const String directTextRelayTokenProofCommandSchema =
    'mknoon.direct-text-relay-token-command.v1';
const String directTextRelayTokenProofCommandSchemaV2 =
    'mknoon.direct-text-relay-token-command.v2';
const String directTextRelayTokenProofReceiptSchema =
    'mknoon.direct-text-relay-token-receipt.v1';
const String directTextRelayTokenProofReceiptSchemaV2 =
    'mknoon.direct-text-relay-token-receipt.v2';
const Duration directTextRelayTokenReceiptFutureClockSkew = Duration(
  seconds: 5,
);
const String backgroundCryptoFcmRefreshCommandSchema =
    'mknoon.tc256-fcm-refresh-command.v2';
const String backgroundCryptoFcmTokenObservationSchema =
    'mknoon.tc256-fcm-token-observation.v1';

const Set<String> backgroundCryptoProviderStages = <String>{
  'oauth',
  'fcm',
  'request_prepare',
};
const Set<String> backgroundCryptoProviderRpcStatuses = <String>{
  'OK',
  'CANCELLED',
  'UNKNOWN',
  'INVALID_ARGUMENT',
  'DEADLINE_EXCEEDED',
  'NOT_FOUND',
  'ALREADY_EXISTS',
  'PERMISSION_DENIED',
  'RESOURCE_EXHAUSTED',
  'FAILED_PRECONDITION',
  'ABORTED',
  'OUT_OF_RANGE',
  'UNIMPLEMENTED',
  'INTERNAL',
  'UNAVAILABLE',
  'DATA_LOSS',
  'UNAUTHENTICATED',
};
const Set<String> backgroundCryptoProviderReasons = <String>{
  'UNSPECIFIED_ERROR',
  'INVALID_ARGUMENT',
  'UNREGISTERED',
  'SENDER_ID_MISMATCH',
  'QUOTA_EXCEEDED',
  'UNAVAILABLE',
  'INTERNAL',
  'THIRD_PARTY_AUTH_ERROR',
  'APNS_AUTH_ERROR',
  'INVALID_GRANT',
  'INVALID_CLIENT',
  'UNAUTHORIZED_CLIENT',
  'INVALID_SCOPE',
  'TEMPORARILY_UNAVAILABLE',
  'SERVER_ERROR',
  'NETWORK_ERROR',
  'MALFORMED_RESPONSE',
  'RESPONSE_TOO_LARGE',
  'BAD_REQUEST_PAYLOAD',
  'UNKNOWN',
};
const Set<String> backgroundCryptoProviderResultKeys = <String>{
  'schema',
  'ok',
  'stage',
  'operation',
  'validateOnly',
  'validationResult',
  'httpClass',
  'httpStatus',
  'rpcStatus',
  'reason',
  'requestIdSha256',
};

Map<String, Object?> parseBackgroundCryptoProviderResult(
  String raw, {
  required int exitCode,
  required bool expectValidateOnly,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw.trim());
  } on FormatException {
    throw const FormatException('provider result is not one JSON object');
  }
  if (decoded is! Map) {
    throw const FormatException('provider result is not an object');
  }
  final result = decoded.cast<String, Object?>();
  if (result.keys.toSet().length != backgroundCryptoProviderResultKeys.length ||
      !result.keys.toSet().containsAll(backgroundCryptoProviderResultKeys) ||
      result['schema'] != backgroundCryptoProviderResultSchema ||
      result['ok'] is! bool ||
      !backgroundCryptoProviderStages.contains(result['stage']) ||
      !<String>{'deliver', 'validate_only'}.contains(result['operation']) ||
      result['validateOnly'] is! bool ||
      result['validateOnly'] != expectValidateOnly ||
      result['operation'] !=
          (expectValidateOnly ? 'validate_only' : 'deliver') ||
      !<String>{
        'accepted',
        'rejected',
        'not_run',
      }.contains(result['validationResult'])) {
    throw const FormatException('provider result schema rejected');
  }
  final status = result['httpStatus'];
  final statusClass = result['httpClass'];
  final validStatus =
      status == null || (status is int && status >= 100 && status <= 599);
  final expectedClass = status is int ? '${status ~/ 100}xx' : null;
  if (!validStatus ||
      !<String>{
        '1xx',
        '2xx',
        '3xx',
        '4xx',
        '5xx',
        'network',
        'unknown',
      }.contains(statusClass) ||
      (status is int && statusClass != expectedClass) ||
      (status == null &&
          statusClass != 'network' &&
          statusClass != 'unknown')) {
    throw const FormatException('provider HTTP diagnostic rejected');
  }
  final rpcStatus = result['rpcStatus'];
  final reason = result['reason'];
  final requestIdHash = result['requestIdSha256'];
  if ((rpcStatus != null &&
          (rpcStatus is! String ||
              !backgroundCryptoProviderRpcStatuses.contains(rpcStatus))) ||
      (reason != null &&
          (reason is! String ||
              !backgroundCryptoProviderReasons.contains(reason))) ||
      (requestIdHash != null &&
          (requestIdHash is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(requestIdHash)))) {
    throw const FormatException('provider finite diagnostic rejected');
  }
  final ok = result['ok']! as bool;
  final stage = result['stage']! as String;
  final validationResult = result['validationResult']! as String;
  final expectedExitStage = switch (exitCode) {
    0 => 'fcm',
    70 => 'oauth',
    71 => 'fcm',
    72 => 'request_prepare',
    _ => null,
  };
  if (expectedExitStage == null ||
      stage != expectedExitStage ||
      ok != (exitCode == 0) ||
      (ok &&
          (status is! int ||
              status < 200 ||
              status >= 300 ||
              rpcStatus != 'OK' ||
              reason != null)) ||
      (!ok && reason == null) ||
      (expectValidateOnly &&
          validationResult != (ok ? 'accepted' : 'rejected')) ||
      (!expectValidateOnly && validationResult != 'not_run')) {
    throw const FormatException('provider result and exit code disagree');
  }
  return Map<String, Object?>.unmodifiable(result);
}

const Set<String> _backgroundCryptoUnregisteredDiagnosticKeys = <String>{
  'testCase',
  'scenario',
  'schema',
  'status',
  'capturedAt',
  'mode',
  'setupReady',
  'fixtureCaseId',
  'providerValidationAttempts',
  'providerValidationSucceeded',
  'providerDiagnostic',
  'subjectTokenSha256',
  'deliveryAttempted',
  'providerRequestsAttempted',
  'providerRequestsSucceeded',
  'reactionCasesExecuted',
  'ordinaryCasesExecuted',
  'negativeCasesExecuted',
  'callbacksObserved',
  'notificationCardsObserved',
  'successfulCleanupEvidence',
  'cleanup',
  'redaction',
  'containsSecrets',
  'privateProviderTempDeleted',
  'successfulRestorationEvidence',
};

/// Accepts only the sanitized, delivery-free UNREGISTERED diagnostic that may
/// authorize one bounded FCM token regeneration. This deliberately rejects
/// partial or hand-authored summaries of the provider result.
Map<String, Object?> parseBackgroundCryptoUnregisteredDiagnosticAuthorization(
  Object? raw, {
  required DateTime now,
}) {
  if (raw is! Map) {
    throw const FormatException('prior provider diagnostic is not an object');
  }
  final artifact = raw.cast<String, Object?>();
  if (artifact.keys.toSet().length !=
          _backgroundCryptoUnregisteredDiagnosticKeys.length ||
      !artifact.keys.toSet().containsAll(
        _backgroundCryptoUnregisteredDiagnosticKeys,
      ) ||
      artifact['schema'] != backgroundCryptoProviderDiagnosticArtifactSchema ||
      artifact['testCase'] != 'TC-07-provider-diagnostic' ||
      artifact['scenario'] != 'android_provider_validate_only' ||
      artifact['status'] != 'completed' ||
      artifact['mode'] != 'provider-diagnostic-only' ||
      artifact['setupReady'] != true ||
      artifact['fixtureCaseId'] != 'direct-text' ||
      artifact['providerValidationAttempts'] != 1 ||
      artifact['providerValidationSucceeded'] != 0 ||
      artifact['subjectTokenSha256'] is! String ||
      !RegExp(
        r'^[0-9a-f]{64}$',
      ).hasMatch(artifact['subjectTokenSha256']! as String) ||
      artifact['deliveryAttempted'] != false ||
      artifact['providerRequestsAttempted'] != 0 ||
      artifact['providerRequestsSucceeded'] != 0 ||
      artifact['reactionCasesExecuted'] != 0 ||
      artifact['ordinaryCasesExecuted'] != 0 ||
      artifact['negativeCasesExecuted'] != 0 ||
      artifact['callbacksObserved'] != 0 ||
      artifact['notificationCardsObserved'] != 0 ||
      artifact['containsSecrets'] != false ||
      artifact['privateProviderTempDeleted'] != true) {
    throw const FormatException(
      'prior provider diagnostic does not authorize registration refresh',
    );
  }
  final capturedAt = artifact['capturedAt'];
  final parsedCapturedAt = capturedAt is String
      ? DateTime.tryParse(capturedAt)
      : null;
  if (parsedCapturedAt == null || !parsedCapturedAt.isUtc) {
    throw const FormatException('prior provider diagnostic time is invalid');
  }
  final diagnosticAge = now.toUtc().difference(parsedCapturedAt);
  if (diagnosticAge.isNegative || diagnosticAge > const Duration(minutes: 30)) {
    throw const FormatException('prior provider diagnostic is stale');
  }
  final diagnostic = artifact['providerDiagnostic'];
  if (diagnostic is! Map) {
    throw const FormatException('prior provider result is missing');
  }
  final parsed = diagnostic.cast<String, Object?>();
  if (parsed.keys.toSet().length != backgroundCryptoProviderResultKeys.length ||
      !parsed.keys.toSet().containsAll(backgroundCryptoProviderResultKeys) ||
      parsed['schema'] != backgroundCryptoProviderResultSchema ||
      parsed['ok'] != false ||
      parsed['stage'] != 'fcm' ||
      parsed['operation'] != 'validate_only' ||
      parsed['validateOnly'] != true ||
      parsed['validationResult'] != 'rejected' ||
      parsed['httpClass'] != '4xx' ||
      parsed['httpStatus'] != 404 ||
      parsed['rpcStatus'] != 'NOT_FOUND' ||
      parsed['reason'] != 'UNREGISTERED' ||
      parsed['requestIdSha256'] != null) {
    throw const FormatException(
      'prior provider result is not exact UNREGISTERED evidence',
    );
  }
  final cleanup = artifact['cleanup'];
  if (cleanup is! Map ||
      backgroundCryptoCleanupZeroCountFields.any(
        (field) => cleanup[field] != 0,
      ) ||
      cleanup['privateProviderBundleDeleted'] != true ||
      cleanup['cleanupIndexDeleted'] != true ||
      cleanup['clearNotificationsMarkerDeleted'] != true ||
      cleanup['privateProviderTempDeleted'] != true ||
      cleanup['installedCandidateRestored'] != true ||
      cleanup['localBuildArtifactRestoredToPriorState'] != true ||
      cleanup['notificationPermissionRestored'] != true) {
    throw const FormatException(
      'prior provider diagnostic cleanup is incomplete',
    );
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'capturedAt': capturedAt,
    'reason': 'UNREGISTERED',
    'httpStatus': 404,
    'rpcStatus': 'NOT_FOUND',
    'subjectTokenSha256': artifact['subjectTokenSha256']! as String,
  });
}

/// Accepts only a complete, delivery-free provider validation of the SDK token
/// that was current when the diagnostic was captured. The returned digest is
/// authorization input, not proof that the production app still has the same
/// token; Gate A must independently compare it with FirebaseMessaging.getToken.
Map<String, Object?> parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
  List<int> rawBytes, {
  required DateTime now,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 64 * 1024) {
    throw const FormatException('current-token diagnostic size rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('current-token diagnostic JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('current-token diagnostic root rejected');
  }
  final artifact = decoded.cast<String, Object?>();
  final subjectTokenSha256 = artifact['subjectTokenSha256'];
  if (!_hasExactKeys(artifact, _backgroundCryptoUnregisteredDiagnosticKeys) ||
      artifact['schema'] != backgroundCryptoProviderDiagnosticArtifactSchema ||
      artifact['testCase'] != 'TC-07-provider-diagnostic' ||
      artifact['scenario'] != 'android_provider_validate_only' ||
      artifact['status'] != 'completed' ||
      artifact['mode'] != 'provider-diagnostic-only' ||
      artifact['setupReady'] != true ||
      artifact['fixtureCaseId'] != 'direct-text' ||
      artifact['providerValidationAttempts'] != 1 ||
      artifact['providerValidationSucceeded'] != 1 ||
      !_isLowerSha256(subjectTokenSha256) ||
      artifact['deliveryAttempted'] != false ||
      artifact['providerRequestsAttempted'] != 0 ||
      artifact['providerRequestsSucceeded'] != 0 ||
      artifact['reactionCasesExecuted'] != 0 ||
      artifact['ordinaryCasesExecuted'] != 0 ||
      artifact['negativeCasesExecuted'] != 0 ||
      artifact['callbacksObserved'] != 0 ||
      artifact['notificationCardsObserved'] != 0 ||
      artifact['privateProviderTempDeleted'] != true ||
      artifact['containsSecrets'] != false) {
    throw const FormatException('current-token diagnostic contract rejected');
  }

  final capturedAt = DateTime.tryParse(
    artifact['capturedAt']?.toString() ?? '',
  );
  if (capturedAt == null || !capturedAt.isUtc) {
    throw const FormatException('current-token diagnostic time rejected');
  }
  final age = now.toUtc().difference(capturedAt);
  if (age.isNegative || age > backgroundCryptoCurrentTokenAuthorizationMaxAge) {
    throw const FormatException('current-token diagnostic is stale');
  }

  final provider = artifact['providerDiagnostic'];
  if (provider is! Map ||
      !_hasExactKeys(
        provider.cast<String, Object?>(),
        backgroundCryptoProviderResultKeys,
      ) ||
      provider['schema'] != backgroundCryptoProviderResultSchema ||
      provider['ok'] != true ||
      provider['stage'] != 'fcm' ||
      provider['operation'] != 'validate_only' ||
      provider['validateOnly'] != true ||
      provider['validationResult'] != 'accepted' ||
      provider['httpClass'] != '2xx' ||
      provider['httpStatus'] != 200 ||
      provider['rpcStatus'] != 'OK' ||
      provider['reason'] != null ||
      provider['requestIdSha256'] != null) {
    throw const FormatException('current-token provider acceptance rejected');
  }

  _validateCurrentTokenDiagnosticCleanup(artifact);
  _validateCurrentTokenDiagnosticRedaction(artifact['redaction']);

  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
    'authorizationArtifactSha256': sha256.convert(rawBytes).toString(),
    'capturedAt': capturedAt.toIso8601String(),
    'tokenSha256': subjectTokenSha256! as String,
    'providerOperation': 'validate_only',
    'providerValidationResult': 'accepted',
    'providerHttpStatus': 200,
    'providerRpcStatus': 'OK',
    'deliveryAttempted': false,
  });
}

Map<String, Object?>
revalidateBackgroundCryptoCurrentTokenDiagnosticAuthorization(
  List<int> immutableRawBytes, {
  required DateTime now,
  required String expectedArtifactSha256,
  required Map<String, Object?> expectedAuthorization,
}) {
  final currentArtifactSha256 = sha256.convert(immutableRawBytes).toString();
  if (currentArtifactSha256 != expectedArtifactSha256) {
    throw const FormatException('current-token diagnostic bytes changed');
  }
  final current = parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
    immutableRawBytes,
    now: now,
  );
  if (current['authorizationArtifactSha256'] != currentArtifactSha256 ||
      !_mapsHaveSameScalarEntries(
        current.cast<String, dynamic>(),
        expectedAuthorization.cast<String, dynamic>(),
      )) {
    throw const FormatException('current-token authorization changed');
  }
  return current;
}

void _validateCurrentTokenDiagnosticCleanup(Map<String, Object?> artifact) {
  final cleanup = artifact['cleanup'];
  final expectedCleanupKeys = <String>{
    ...backgroundCryptoCleanupZeroCountFields,
    'privateProviderBundleDeleted',
    'cleanupIndexDeleted',
    'fcmRefreshCommandDeleted',
    'clearNotificationsMarkerDeleted',
    'privateProviderTempDeleted',
    'boundedReactionClaimsVerified',
    'bothRecentGatesScrubbed',
    'notificationPermissionRestored',
    'installedCandidateRestored',
    'installedCandidateBytesVerified',
    'installedCandidateApkSha256',
    'localBuildArtifactRestoredToPriorState',
    'localBuildArtifactBytesVerified',
    'notificationPermissionInitiallyGranted',
  };
  const requiredTrueKeys = <String>{
    'privateProviderBundleDeleted',
    'cleanupIndexDeleted',
    'fcmRefreshCommandDeleted',
    'clearNotificationsMarkerDeleted',
    'privateProviderTempDeleted',
    'boundedReactionClaimsVerified',
    'bothRecentGatesScrubbed',
    'notificationPermissionRestored',
    'installedCandidateRestored',
    'installedCandidateBytesVerified',
    'localBuildArtifactRestoredToPriorState',
    'localBuildArtifactBytesVerified',
  };
  if (cleanup is! Map) {
    throw const FormatException('current-token cleanup is missing');
  }
  final cleanupMap = cleanup.cast<String, Object?>();
  final apkHashes = cleanupMap['installedCandidateApkSha256'];
  if (!_hasExactKeys(cleanupMap, expectedCleanupKeys) ||
      backgroundCryptoCleanupZeroCountFields.any(
        (field) => cleanupMap[field] != 0,
      ) ||
      requiredTrueKeys.any((field) => cleanupMap[field] != true) ||
      cleanupMap['notificationPermissionInitiallyGranted'] is! bool ||
      apkHashes is! List ||
      apkHashes.isEmpty ||
      apkHashes.any((value) => !_isLowerSha256(value))) {
    throw const FormatException('current-token cleanup rejected');
  }

  final cleanupEvidence = artifact['successfulCleanupEvidence'];
  if (cleanupEvidence is! List || cleanupEvidence.length != 1) {
    throw const FormatException('current-token cleanup receipt rejected');
  }
  final rawReceipt = cleanupEvidence.single;
  if (rawReceipt is! Map) {
    throw const FormatException('current-token cleanup receipt rejected');
  }
  final receipt = rawReceipt.cast<String, Object?>();
  final expectedReceiptKeys = <String>{
    'mode',
    'commandId',
    'commandSha256',
    'commandByteLength',
    'receiptsMatched',
    'mainReexecuted',
    'reservedOnly',
    'privateProviderBundleDeleted',
    'cleanupIndexDeleted',
    'fcmRefreshCommandDeleted',
    'clearNotificationsMarkerDeleted',
    'boundedReactionClaimsVerified',
    'dedupeGatesRestored',
    'dedupeGatesScrubbed',
    ...backgroundCryptoCleanupZeroCountFields,
  };
  final commandId = receipt['commandId'];
  final commandByteLength = receipt['commandByteLength'];
  if (!_hasExactKeys(receipt, expectedReceiptKeys) ||
      receipt['mode'] != 'recovery' ||
      commandId is! String ||
      !RegExp(r'^tc256-[0-9]{12,20}-[0-9]{1,10}$').hasMatch(commandId) ||
      !_isLowerSha256(receipt['commandSha256']) ||
      commandByteLength is! int ||
      commandByteLength <= 0 ||
      commandByteLength > 16 * 1024 ||
      receipt['receiptsMatched'] != true ||
      receipt['mainReexecuted'] != true ||
      receipt['reservedOnly'] != true ||
      receipt['privateProviderBundleDeleted'] != true ||
      receipt['cleanupIndexDeleted'] != true ||
      receipt['fcmRefreshCommandDeleted'] != true ||
      receipt['clearNotificationsMarkerDeleted'] != true ||
      receipt['boundedReactionClaimsVerified'] != true ||
      receipt['dedupeGatesRestored'] != 2 ||
      receipt['dedupeGatesScrubbed'] != 2 ||
      backgroundCryptoCleanupZeroCountFields.any(
        (field) => receipt[field] != 0,
      )) {
    throw const FormatException('current-token cleanup receipt rejected');
  }

  final restoration = artifact['successfulRestorationEvidence'];
  const restorationKeys = <String>{
    'installedCandidateRestored',
    'installedCandidateBytesVerified',
    'installedCandidateApkSha256',
    'localBuildArtifactRestoredToPriorState',
    'localBuildArtifactBytesVerified',
    'notificationPermissionRestored',
    'notificationPermissionInitiallyGranted',
  };
  if (restoration is! Map) {
    throw const FormatException('current-token restoration rejected');
  }
  final restorationMap = restoration.cast<String, Object?>();
  if (!_hasExactKeys(restorationMap, restorationKeys) ||
      restorationMap['installedCandidateRestored'] != true ||
      restorationMap['installedCandidateBytesVerified'] != true ||
      restorationMap['localBuildArtifactRestoredToPriorState'] != true ||
      restorationMap['localBuildArtifactBytesVerified'] != true ||
      restorationMap['notificationPermissionRestored'] != true ||
      restorationMap['notificationPermissionInitiallyGranted'] !=
          cleanupMap['notificationPermissionInitiallyGranted'] ||
      jsonEncode(restorationMap['installedCandidateApkSha256']) !=
          jsonEncode(apkHashes)) {
    throw const FormatException('current-token restoration rejected');
  }
}

void _validateCurrentTokenDiagnosticRedaction(Object? raw) {
  const redactionKeys = <String>{
    'providerMessagePersisted',
    'fcmTokenPersisted',
    'credentialPersisted',
    'jwtPersisted',
    'providerUrlPersisted',
    'payloadPersisted',
    'rawHeaderPersisted',
  };
  if (raw is! Map) {
    throw const FormatException('current-token redaction rejected');
  }
  final redaction = raw.cast<String, Object?>();
  if (!_hasExactKeys(redaction, redactionKeys) ||
      redaction.values.any((value) => value != false)) {
    throw const FormatException('current-token redaction rejected');
  }
}

Map<String, Object?> parseBackgroundCryptoRelayRegistrationAuthorization(
  List<int> rawBytes, {
  required DateTime now,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 64 * 1024) {
    throw const FormatException('refresh artifact size rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('refresh artifact JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('refresh artifact is not an object');
  }
  final artifact = decoded.cast<String, Object?>();
  final expectedKeys = <String>{
    ..._backgroundCryptoUnregisteredDiagnosticKeys,
    'tokenRegistration',
  };
  final hashPattern = RegExp(r'^[0-9a-f]{64}$');
  final subjectTokenSha256 = artifact['subjectTokenSha256'];
  if (artifact.keys.toSet().length != expectedKeys.length ||
      !artifact.keys.toSet().containsAll(expectedKeys) ||
      artifact['schema'] != backgroundCryptoProviderDiagnosticArtifactSchema ||
      artifact['testCase'] != 'TC-07-provider-diagnostic' ||
      artifact['scenario'] != 'android_provider_validate_only' ||
      artifact['status'] != 'completed' ||
      artifact['mode'] != 'provider-diagnostic-only' ||
      artifact['setupReady'] != true ||
      artifact['fixtureCaseId'] != 'direct-text' ||
      artifact['providerValidationAttempts'] != 1 ||
      artifact['providerValidationSucceeded'] != 1 ||
      subjectTokenSha256 is! String ||
      !hashPattern.hasMatch(subjectTokenSha256) ||
      artifact['deliveryAttempted'] != false ||
      artifact['providerRequestsAttempted'] != 0 ||
      artifact['providerRequestsSucceeded'] != 0 ||
      artifact['reactionCasesExecuted'] != 0 ||
      artifact['ordinaryCasesExecuted'] != 0 ||
      artifact['negativeCasesExecuted'] != 0 ||
      artifact['callbacksObserved'] != 0 ||
      artifact['notificationCardsObserved'] != 0 ||
      artifact['containsSecrets'] != false ||
      artifact['privateProviderTempDeleted'] != true) {
    throw const FormatException('refresh artifact contract rejected');
  }
  final capturedAtRaw = artifact['capturedAt'];
  final capturedAt = capturedAtRaw is String
      ? DateTime.tryParse(capturedAtRaw)
      : null;
  if (capturedAt == null || !capturedAt.isUtc) {
    throw const FormatException('refresh artifact time rejected');
  }
  final artifactAge = now.toUtc().difference(capturedAt);
  if (artifactAge.isNegative || artifactAge > const Duration(hours: 1)) {
    throw const FormatException('refresh artifact is stale');
  }
  final provider = artifact['providerDiagnostic'];
  if (provider is! Map ||
      provider.keys.toSet().length !=
          backgroundCryptoProviderResultKeys.length ||
      !provider.keys.toSet().containsAll(backgroundCryptoProviderResultKeys) ||
      provider['schema'] != backgroundCryptoProviderResultSchema ||
      provider['ok'] != true ||
      provider['stage'] != 'fcm' ||
      provider['operation'] != 'validate_only' ||
      provider['validateOnly'] != true ||
      provider['validationResult'] != 'accepted' ||
      provider['httpClass'] != '2xx' ||
      provider['httpStatus'] != 200 ||
      provider['rpcStatus'] != 'OK' ||
      provider['reason'] != null ||
      provider['requestIdSha256'] != null) {
    throw const FormatException('refresh provider acceptance rejected');
  }
  final tokenRegistration = artifact['tokenRegistration'];
  const tokenRegistrationKeys = <String>{
    'schema',
    'source',
    'observedAt',
    'generationId',
    'tokenSha256',
    'priorTokenSha256',
    'refreshSignal',
    'commandIssuedAt',
    'commandAgeAtObservationMs',
    'priorDiagnosticSha256',
  };
  if (tokenRegistration is! Map ||
      tokenRegistration.keys.toSet().length != tokenRegistrationKeys.length ||
      !tokenRegistration.keys.toSet().containsAll(tokenRegistrationKeys) ||
      tokenRegistration['schema'] !=
          backgroundCryptoFcmTokenObservationSchema ||
      tokenRegistration['source'] != 'forced_reregistration' ||
      tokenRegistration['tokenSha256'] != subjectTokenSha256 ||
      tokenRegistration['priorTokenSha256'] is! String ||
      !hashPattern.hasMatch(tokenRegistration['priorTokenSha256']! as String) ||
      tokenRegistration['priorTokenSha256'] == subjectTokenSha256 ||
      tokenRegistration['generationId'] is! String ||
      !RegExp(
        r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(tokenRegistration['generationId']! as String) ||
      !<String>{
        'poll',
        'on_token_refresh',
      }.contains(tokenRegistration['refreshSignal']) ||
      tokenRegistration['priorDiagnosticSha256'] is! String ||
      !hashPattern.hasMatch(
        tokenRegistration['priorDiagnosticSha256']! as String,
      ) ||
      tokenRegistration['commandAgeAtObservationMs'] is! int ||
      (tokenRegistration['commandAgeAtObservationMs']! as int) < 0 ||
      (tokenRegistration['commandAgeAtObservationMs']! as int) > 165000) {
    throw const FormatException('refresh token registration rejected');
  }
  final observedAt = DateTime.tryParse(
    tokenRegistration['observedAt']?.toString() ?? '',
  );
  final commandIssuedAt = DateTime.tryParse(
    tokenRegistration['commandIssuedAt']?.toString() ?? '',
  );
  if (observedAt == null ||
      !observedAt.isUtc ||
      commandIssuedAt == null ||
      !commandIssuedAt.isUtc ||
      observedAt.difference(commandIssuedAt).inMilliseconds !=
          tokenRegistration['commandAgeAtObservationMs']) {
    throw const FormatException('refresh token registration time rejected');
  }
  final cleanup = artifact['cleanup'];
  if (cleanup is! Map ||
      backgroundCryptoCleanupZeroCountFields.any(
        (field) => cleanup[field] != 0,
      ) ||
      cleanup['privateProviderBundleDeleted'] != true ||
      cleanup['cleanupIndexDeleted'] != true ||
      cleanup['fcmRefreshCommandDeleted'] != true ||
      cleanup['clearNotificationsMarkerDeleted'] != true ||
      cleanup['privateProviderTempDeleted'] != true ||
      cleanup['boundedReactionClaimsVerified'] != true ||
      cleanup['bothRecentGatesScrubbed'] != true ||
      cleanup['notificationPermissionRestored'] != true ||
      cleanup['installedCandidateRestored'] != true ||
      cleanup['installedCandidateBytesVerified'] != true ||
      cleanup['localBuildArtifactRestoredToPriorState'] != true ||
      cleanup['localBuildArtifactBytesVerified'] != true) {
    throw const FormatException('refresh cleanup evidence rejected');
  }
  final redaction = artifact['redaction'];
  if (redaction is! Map || redaction.values.any((value) => value != false)) {
    throw const FormatException('refresh redaction evidence rejected');
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'refreshArtifactSha256': sha256.convert(rawBytes).toString(),
    'capturedAt': capturedAt.toIso8601String(),
    'tokenSha256': subjectTokenSha256,
    'priorTokenSha256': tokenRegistration['priorTokenSha256']! as String,
    'tokenGenerationId': tokenRegistration['generationId']! as String,
    'refreshSignal': tokenRegistration['refreshSignal']! as String,
  });
}

Map<String, Object?> revalidateBackgroundCryptoRelayRegistrationAuthorization(
  List<int> immutableRawBytes, {
  required DateTime now,
  required String expectedArtifactSha256,
  required Map<String, Object?> expectedAuthorization,
}) {
  final currentArtifactSha256 = sha256.convert(immutableRawBytes).toString();
  if (currentArtifactSha256 != expectedArtifactSha256) {
    throw const FormatException('refresh artifact bytes changed');
  }
  final currentAuthorization =
      parseBackgroundCryptoRelayRegistrationAuthorization(
        immutableRawBytes,
        now: now,
      );
  if (currentAuthorization['refreshArtifactSha256'] != currentArtifactSha256 ||
      !_mapsHaveSameScalarEntries(
        currentAuthorization.cast<String, dynamic>(),
        expectedAuthorization.cast<String, dynamic>(),
      )) {
    throw const FormatException('refresh authorization changed');
  }
  return currentAuthorization;
}

Map<String, Object?> parseDirectTextGateAAuthorization(
  List<int> rawBytes, {
  required DateTime now,
  required String expectedArtifactSha256,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 64 * 1024) {
    throw const FormatException('Gate A artifact size rejected');
  }
  final artifactSha256 = sha256.convert(rawBytes).toString();
  if (artifactSha256 != expectedArtifactSha256) {
    throw const FormatException('Gate A artifact SHA-256 rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('Gate A artifact JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('Gate A artifact root rejected');
  }
  final artifact = decoded.cast<String, Object?>();
  if (artifact['schema'] ==
      backgroundCryptoPushRelayRegistrationArtifactSchemaV2) {
    return _parseDirectTextGateAAuthorizationV2(
      artifact,
      now: now,
      artifactSha256: artifactSha256,
    );
  }
  const topKeys = <String>{
    'schema',
    'status',
    'capturedAt',
    'mode',
    'recipient',
    'refreshAuthorization',
    'command',
    'flowEvidence',
    'receipt',
    'relayClaim',
    'relayPersistenceProvenByThisGate',
    'downstreamDeliveryStillRequired',
    'productionPath',
    'notificationState',
    'cleanup',
    'intentionalPersistentEffects',
    'redaction',
    'containsSecrets',
  };
  final capturedAt = DateTime.tryParse(
    artifact['capturedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(artifact, topKeys) ||
      artifact['schema'] !=
          backgroundCryptoPushRelayRegistrationArtifactSchema ||
      artifact['status'] != 'passed' ||
      artifact['mode'] != 'instrumented-production-main' ||
      capturedAt == null ||
      !capturedAt.isUtc ||
      artifact['relayClaim'] != 'relay_frame_status_ok' ||
      artifact['relayPersistenceProvenByThisGate'] != false ||
      artifact['downstreamDeliveryStillRequired'] != true ||
      artifact['containsSecrets'] != false) {
    throw const FormatException('Gate A artifact contract rejected');
  }
  final age = now.toUtc().difference(capturedAt);
  final futureSkew = capturedAt.difference(now.toUtc());
  if (futureSkew > const Duration(seconds: 5) ||
      age > const Duration(hours: 1)) {
    throw const FormatException('Gate A artifact is stale');
  }

  final recipient = _stringObjectMap(artifact['recipient']);
  if (!_hasExactKeys(recipient, const <String>{
        'deviceId',
        'platform',
        'targetPlatform',
      }) ||
      recipient['deviceId'] is! String ||
      (recipient['deviceId']! as String).trim().isEmpty ||
      recipient['platform'] != 'android' ||
      recipient['targetPlatform'] is! String ||
      !(recipient['targetPlatform']! as String).startsWith('android-')) {
    throw const FormatException('Gate A recipient binding rejected');
  }

  final refresh = _stringObjectMap(artifact['refreshAuthorization']);
  const refreshKeys = <String>{
    'refreshArtifactSha256',
    'capturedAt',
    'tokenSha256',
    'priorTokenSha256',
    'tokenGenerationId',
    'refreshSignal',
  };
  final originalRefreshCapturedAt = DateTime.tryParse(
    refresh['capturedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(refresh, refreshKeys) ||
      !_isLowerSha256(refresh['refreshArtifactSha256']) ||
      !_isLowerSha256(refresh['tokenSha256']) ||
      !_isLowerSha256(refresh['priorTokenSha256']) ||
      refresh['priorTokenSha256'] == refresh['tokenSha256'] ||
      refresh['tokenGenerationId'] is! String ||
      !RegExp(
        r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(refresh['tokenGenerationId']! as String) ||
      !<String>{
        'poll',
        'on_token_refresh',
      }.contains(refresh['refreshSignal']) ||
      originalRefreshCapturedAt == null ||
      !originalRefreshCapturedAt.isUtc ||
      originalRefreshCapturedAt.difference(capturedAt) >
          const Duration(seconds: 5) ||
      capturedAt.difference(originalRefreshCapturedAt) >
          const Duration(hours: 1)) {
    throw const FormatException('Gate A refresh binding rejected');
  }

  final command = _stringObjectMap(artifact['command']);
  if (!_hasExactKeys(command, const <String>{
        'commandId',
        'commandSha256',
        'mode',
        'deleted',
      }) ||
      command['commandId'] is! String ||
      !RegExp(
        r'^tc256-relay-registration-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(command['commandId']! as String) ||
      !_isLowerSha256(command['commandSha256']) ||
      command['mode'] != '0600' ||
      command['deleted'] != true) {
    throw const FormatException('Gate A command binding rejected');
  }

  final flow = _stringObjectMap(artifact['flowEvidence']);
  const flowKeys = <String>{
    'proofSchema',
    'commandId',
    'tokenSha256',
    'tokenGenerationId',
    'refreshArtifactSha256',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'coordinatorSuccess',
    'orderedEventCount',
  };
  if (!_hasExactKeys(flow, flowKeys) ||
      flow['proofSchema'] !=
          backgroundCryptoPushRelayRegistrationCommandSchema ||
      flow['commandId'] != command['commandId'] ||
      flow['commandSha256'] != command['commandSha256'] ||
      flow['tokenSha256'] != refresh['tokenSha256'] ||
      flow['tokenGenerationId'] != refresh['tokenGenerationId'] ||
      flow['refreshArtifactSha256'] != refresh['refreshArtifactSha256'] ||
      flow['platform'] != 'android' ||
      !_isLowerSha256(flow['accountIdentitySha256']) ||
      !_isLowerSha256(flow['transportIdentitySha256']) ||
      flow['relayFrameAccepted'] != true ||
      flow['tokenPersisted'] != true ||
      flow['commandDeleted'] != true ||
      flow['coordinatorSuccess'] != true ||
      flow['orderedEventCount'] != 13) {
    throw const FormatException('Gate A flow binding rejected');
  }

  final receipt = _stringObjectMap(artifact['receipt']);
  const receiptKeys = <String>{
    'schema',
    'status',
    'completedAt',
    'proofSchema',
    'commandId',
    'tokenSha256',
    'tokenGenerationId',
    'refreshArtifactSha256',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'containsSecrets',
  };
  final completedAt = DateTime.tryParse(
    receipt['completedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(receipt, receiptKeys) ||
      receipt['schema'] != backgroundCryptoPushRelayRegistrationReceiptSchema ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['proofSchema'] != flow['proofSchema'] ||
      receipt['commandId'] != flow['commandId'] ||
      receipt['commandSha256'] != flow['commandSha256'] ||
      receipt['tokenSha256'] != flow['tokenSha256'] ||
      receipt['tokenGenerationId'] != flow['tokenGenerationId'] ||
      receipt['refreshArtifactSha256'] != flow['refreshArtifactSha256'] ||
      receipt['platform'] != 'android' ||
      receipt['accountIdentitySha256'] != flow['accountIdentitySha256'] ||
      receipt['transportIdentitySha256'] != flow['transportIdentitySha256'] ||
      receipt['relayFrameAccepted'] != true ||
      receipt['tokenPersisted'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false ||
      completedAt.difference(capturedAt) > const Duration(seconds: 5) ||
      capturedAt.difference(completedAt) > const Duration(minutes: 30)) {
    throw const FormatException('Gate A receipt binding rejected');
  }

  final production = _stringObjectMap(artifact['productionPath']);
  if (!_hasExactKeys(production, const <String>{
        'entrypoint',
        'kE2ETestMode',
        'compileGate',
        'byteIdenticalToRestoredCandidate',
      }) ||
      production['entrypoint'] != 'lib/main.dart' ||
      production['kE2ETestMode'] != false ||
      production['compileGate'] != 'MKNOON_PUSH_RELAY_REGISTRATION_PROOF' ||
      production['byteIdenticalToRestoredCandidate'] != false) {
    throw const FormatException('Gate A production path rejected');
  }
  final notification = _stringObjectMap(artifact['notificationState']);
  if (!_hasExactKeys(notification, const <String>{
        'baselineSha256',
        'finalSha256',
        'unchanged',
      }) ||
      !_isLowerSha256(notification['baselineSha256']) ||
      notification['finalSha256'] != notification['baselineSha256'] ||
      notification['unchanged'] != true) {
    throw const FormatException('Gate A notification cleanup rejected');
  }
  final cleanup = _stringObjectMap(artifact['cleanup']);
  const cleanupTrueKeys = <String>{
    'appIdle',
    'commandDeleted',
    'receiptDeleted',
    'receiptTempDeleted',
    'notificationStateUnchanged',
    'installedCandidateRestored',
    'installedCandidateBytesVerified',
    'localBuildArtifactRestoredToPriorState',
    'localBuildArtifactBytesVerified',
    'notificationPermissionRestored',
    'backupDirectoryDeleted',
  };
  const cleanupKeys = <String>{
    ...cleanupTrueKeys,
    'installedCandidateApkSha256',
    'notificationPermissionInitiallyGranted',
  };
  final installedHashes = cleanup['installedCandidateApkSha256'];
  if (!_hasExactKeys(cleanup, cleanupKeys) ||
      cleanupTrueKeys.any((key) => cleanup[key] != true) ||
      installedHashes is! List ||
      installedHashes.isEmpty ||
      installedHashes.any((value) => !_isLowerSha256(value)) ||
      cleanup['notificationPermissionInitiallyGranted'] is! bool) {
    throw const FormatException('Gate A exact restoration rejected');
  }
  final effects = artifact['intentionalPersistentEffects'];
  if (effects is! List ||
      jsonEncode(effects) !=
          jsonEncode(const <String>[
            'relay_registration_frame_accepted',
            'push_token_store_updated',
          ])) {
    throw const FormatException('Gate A effects rejected');
  }
  final redaction = _stringObjectMap(artifact['redaction']);
  if (!_hasExactKeys(redaction, const <String>{
        'rawTokenPersisted',
        'peerIdPersisted',
        'commandPayloadPersisted',
        'rawLogPersisted',
      }) ||
      redaction.values.any((value) => value != false)) {
    throw const FormatException('Gate A redaction rejected');
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'gateAArtifactSha256': artifactSha256,
    'gateACapturedAt': capturedAt.toIso8601String(),
    'tokenSha256': refresh['tokenSha256']! as String,
    'priorTokenSha256': refresh['priorTokenSha256']! as String,
    'tokenGenerationId': refresh['tokenGenerationId']! as String,
    'originalRefreshArtifactSha256':
        refresh['refreshArtifactSha256']! as String,
    'accountIdentitySha256': flow['accountIdentitySha256']! as String,
    'transportIdentitySha256': flow['transportIdentitySha256']! as String,
    'gateACommandSha256': command['commandSha256']! as String,
    'downstreamDeliveryStillRequired': true,
  });
}

Map<String, Object?> _parseDirectTextGateAAuthorizationV2(
  Map<String, Object?> artifact, {
  required DateTime now,
  required String artifactSha256,
}) {
  const topKeys = <String>{
    'schema',
    'status',
    'capturedAt',
    'mode',
    'recipient',
    'currentTokenAuthorization',
    'command',
    'flowEvidence',
    'receipt',
    'relayClaim',
    'relayPersistenceProvenByThisGate',
    'downstreamDeliveryStillRequired',
    'productionPath',
    'notificationState',
    'cleanup',
    'intentionalPersistentEffects',
    'redaction',
    'containsSecrets',
  };
  final capturedAt = DateTime.tryParse(
    artifact['capturedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(artifact, topKeys) ||
      artifact['schema'] !=
          backgroundCryptoPushRelayRegistrationArtifactSchemaV2 ||
      artifact['status'] != 'passed' ||
      artifact['mode'] != 'instrumented-production-main' ||
      capturedAt == null ||
      !capturedAt.isUtc ||
      artifact['relayClaim'] != 'relay_frame_status_ok' ||
      artifact['relayPersistenceProvenByThisGate'] != false ||
      artifact['downstreamDeliveryStillRequired'] != true ||
      artifact['containsSecrets'] != false) {
    throw const FormatException('Gate A v2 artifact contract rejected');
  }
  final age = now.toUtc().difference(capturedAt);
  final futureSkew = capturedAt.difference(now.toUtc());
  if (futureSkew > const Duration(seconds: 5) ||
      age > const Duration(hours: 1)) {
    throw const FormatException('Gate A v2 artifact is stale');
  }

  final recipient = _stringObjectMap(artifact['recipient']);
  if (!_hasExactKeys(recipient, const <String>{
        'deviceId',
        'platform',
        'targetPlatform',
      }) ||
      recipient['deviceId'] is! String ||
      (recipient['deviceId']! as String).trim().isEmpty ||
      recipient['platform'] != 'android' ||
      recipient['targetPlatform'] is! String ||
      !(recipient['targetPlatform']! as String).startsWith('android-')) {
    throw const FormatException('Gate A v2 recipient binding rejected');
  }

  final authorization = _stringObjectMap(artifact['currentTokenAuthorization']);
  const authorizationKeys = <String>{
    'authorizationKind',
    'authorizationArtifactSha256',
    'capturedAt',
    'tokenSha256',
    'providerOperation',
    'providerValidationResult',
    'providerHttpStatus',
    'providerRpcStatus',
    'deliveryAttempted',
  };
  final authorizationCapturedAt = DateTime.tryParse(
    authorization['capturedAt']?.toString() ?? '',
  );
  final authorizationAge = authorizationCapturedAt == null
      ? null
      : now.toUtc().difference(authorizationCapturedAt);
  if (!_hasExactKeys(authorization, authorizationKeys) ||
      authorization['authorizationKind'] !=
          backgroundCryptoCurrentTokenAuthorizationKind ||
      !_isLowerSha256(authorization['authorizationArtifactSha256']) ||
      authorizationCapturedAt == null ||
      !authorizationCapturedAt.isUtc ||
      !_isLowerSha256(authorization['tokenSha256']) ||
      authorization['providerOperation'] != 'validate_only' ||
      authorization['providerValidationResult'] != 'accepted' ||
      authorization['providerHttpStatus'] != 200 ||
      authorization['providerRpcStatus'] != 'OK' ||
      authorization['deliveryAttempted'] != false ||
      authorizationAge == null ||
      authorizationAge.isNegative ||
      authorizationAge > backgroundCryptoCurrentTokenAuthorizationMaxAge ||
      authorizationCapturedAt.isAfter(capturedAt) ||
      capturedAt.difference(authorizationCapturedAt) >
          backgroundCryptoCurrentTokenAuthorizationMaxAge) {
    throw const FormatException('Gate A v2 authorization binding rejected');
  }

  final command = _stringObjectMap(artifact['command']);
  if (!_hasExactKeys(command, const <String>{
        'commandId',
        'gateACommandGenerationId',
        'commandSha256',
        'mode',
        'deleted',
      }) ||
      command['commandId'] is! String ||
      !RegExp(
        r'^tc256-relay-registration-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(command['commandId']! as String) ||
      command['gateACommandGenerationId'] is! String ||
      !RegExp(
        r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(command['gateACommandGenerationId']! as String) ||
      !_isLowerSha256(command['commandSha256']) ||
      command['mode'] != '0600' ||
      command['deleted'] != true) {
    throw const FormatException('Gate A v2 command binding rejected');
  }

  final flow = _stringObjectMap(artifact['flowEvidence']);
  const flowKeys = <String>{
    'proofSchema',
    'commandId',
    'tokenSha256',
    'authorizationKind',
    'authorizationArtifactSha256',
    'gateACommandGenerationId',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'coordinatorSuccess',
    'orderedEventCount',
  };
  if (!_hasExactKeys(flow, flowKeys) ||
      flow['proofSchema'] !=
          backgroundCryptoPushRelayRegistrationCommandSchemaV2 ||
      flow['commandId'] != command['commandId'] ||
      flow['commandSha256'] != command['commandSha256'] ||
      flow['tokenSha256'] != authorization['tokenSha256'] ||
      flow['authorizationKind'] != authorization['authorizationKind'] ||
      flow['authorizationArtifactSha256'] !=
          authorization['authorizationArtifactSha256'] ||
      flow['gateACommandGenerationId'] != command['gateACommandGenerationId'] ||
      flow['platform'] != 'android' ||
      !_isLowerSha256(flow['accountIdentitySha256']) ||
      !_isLowerSha256(flow['transportIdentitySha256']) ||
      flow['relayFrameAccepted'] != true ||
      flow['tokenPersisted'] != true ||
      flow['commandDeleted'] != true ||
      flow['coordinatorSuccess'] != true ||
      flow['orderedEventCount'] != 13) {
    throw const FormatException('Gate A v2 flow binding rejected');
  }

  final receipt = _stringObjectMap(artifact['receipt']);
  const receiptKeys = <String>{
    'schema',
    'status',
    'completedAt',
    'proofSchema',
    'commandId',
    'tokenSha256',
    'authorizationKind',
    'authorizationArtifactSha256',
    'gateACommandGenerationId',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'containsSecrets',
  };
  final completedAt = DateTime.tryParse(
    receipt['completedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(receipt, receiptKeys) ||
      receipt['schema'] !=
          backgroundCryptoPushRelayRegistrationReceiptSchemaV2 ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['proofSchema'] != flow['proofSchema'] ||
      receipt['commandId'] != flow['commandId'] ||
      receipt['commandSha256'] != flow['commandSha256'] ||
      receipt['tokenSha256'] != flow['tokenSha256'] ||
      receipt['authorizationKind'] != flow['authorizationKind'] ||
      receipt['authorizationArtifactSha256'] !=
          flow['authorizationArtifactSha256'] ||
      receipt['gateACommandGenerationId'] != flow['gateACommandGenerationId'] ||
      receipt['platform'] != 'android' ||
      receipt['accountIdentitySha256'] != flow['accountIdentitySha256'] ||
      receipt['transportIdentitySha256'] != flow['transportIdentitySha256'] ||
      receipt['relayFrameAccepted'] != true ||
      receipt['tokenPersisted'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false ||
      completedAt.difference(capturedAt) > const Duration(seconds: 5) ||
      capturedAt.difference(completedAt) > const Duration(minutes: 30)) {
    throw const FormatException('Gate A v2 receipt binding rejected');
  }

  final production = _stringObjectMap(artifact['productionPath']);
  if (!_hasExactKeys(production, const <String>{
        'entrypoint',
        'kE2ETestMode',
        'compileGate',
        'byteIdenticalToRestoredCandidate',
      }) ||
      production['entrypoint'] != 'lib/main.dart' ||
      production['kE2ETestMode'] != false ||
      production['compileGate'] != 'MKNOON_PUSH_RELAY_REGISTRATION_PROOF' ||
      production['byteIdenticalToRestoredCandidate'] != false) {
    throw const FormatException('Gate A v2 production path rejected');
  }
  final notification = _stringObjectMap(artifact['notificationState']);
  if (!_hasExactKeys(notification, const <String>{
        'baselineSha256',
        'finalSha256',
        'unchanged',
      }) ||
      !_isLowerSha256(notification['baselineSha256']) ||
      notification['finalSha256'] != notification['baselineSha256'] ||
      notification['unchanged'] != true) {
    throw const FormatException('Gate A v2 notification cleanup rejected');
  }
  final cleanup = _stringObjectMap(artifact['cleanup']);
  const cleanupTrueKeys = <String>{
    'appIdle',
    'commandDeleted',
    'receiptDeleted',
    'receiptTempDeleted',
    'notificationStateUnchanged',
    'installedCandidateRestored',
    'installedCandidateBytesVerified',
    'localBuildArtifactRestoredToPriorState',
    'localBuildArtifactBytesVerified',
    'notificationPermissionRestored',
    'backupDirectoryDeleted',
  };
  const cleanupKeys = <String>{
    ...cleanupTrueKeys,
    'installedCandidateApkSha256',
    'notificationPermissionInitiallyGranted',
  };
  final installedHashes = cleanup['installedCandidateApkSha256'];
  if (!_hasExactKeys(cleanup, cleanupKeys) ||
      cleanupTrueKeys.any((key) => cleanup[key] != true) ||
      installedHashes is! List ||
      installedHashes.isEmpty ||
      installedHashes.any((value) => !_isLowerSha256(value)) ||
      cleanup['notificationPermissionInitiallyGranted'] is! bool) {
    throw const FormatException('Gate A v2 exact restoration rejected');
  }
  final effects = artifact['intentionalPersistentEffects'];
  if (effects is! List ||
      jsonEncode(effects) !=
          jsonEncode(const <String>[
            'relay_registration_frame_accepted',
            'push_token_store_updated',
          ])) {
    throw const FormatException('Gate A v2 effects rejected');
  }
  final redaction = _stringObjectMap(artifact['redaction']);
  if (!_hasExactKeys(redaction, const <String>{
        'rawTokenPersisted',
        'peerIdPersisted',
        'commandPayloadPersisted',
        'rawLogPersisted',
      }) ||
      redaction.values.any((value) => value != false)) {
    throw const FormatException('Gate A v2 redaction rejected');
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'gateAArtifactSha256': artifactSha256,
    'gateACapturedAt': capturedAt.toIso8601String(),
    'authorizationKind': authorization['authorizationKind']! as String,
    'authorizationArtifactSha256':
        authorization['authorizationArtifactSha256']! as String,
    'tokenSha256': authorization['tokenSha256']! as String,
    'gateACommandGenerationId': command['gateACommandGenerationId']! as String,
    'accountIdentitySha256': flow['accountIdentitySha256']! as String,
    'transportIdentitySha256': flow['transportIdentitySha256']! as String,
    'gateACommandSha256': command['commandSha256']! as String,
    'downstreamDeliveryStillRequired': true,
  });
}

Map<String, Object?> revalidateDirectTextGateAAuthorization(
  List<int> immutableRawBytes, {
  required DateTime now,
  required String expectedArtifactSha256,
  required Map<String, Object?> expectedAuthorization,
}) {
  final current = parseDirectTextGateAAuthorization(
    immutableRawBytes,
    now: now,
    expectedArtifactSha256: expectedArtifactSha256,
  );
  if (!_mapsHaveSameScalarEntries(
    current.cast<String, dynamic>(),
    expectedAuthorization.cast<String, dynamic>(),
  )) {
    throw const FormatException('Gate A authorization changed');
  }
  return current;
}

Map<String, Object?> _stringObjectMap(Object? value) {
  if (value is! Map) throw const FormatException('Gate A object rejected');
  return value.cast<String, Object?>();
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.keys.toSet().length == expected.length &&
    value.keys.toSet().containsAll(expected);

bool _isLowerSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool hasAttachedAndroidActivity(String dumpsysActivities, String packageName) {
  final cutoff = dumpsysActivities.indexOf('mRemoteInsetsControlTarget=');
  final activeSection = cutoff < 0
      ? dumpsysActivities
      : dumpsysActivities.substring(0, cutoff);
  final package = RegExp.escape(packageName);
  return RegExp(
    '(?:ActivityRecord\\{|mResumedActivity|topResumedActivity|mFocusedApp)'
    '[^\\n]*$package(?:/|\\b)',
  ).hasMatch(activeSection);
}

bool isAndroidAppProcessAndActivityAbsent({
  required String pidOutput,
  required String dumpsysActivities,
  required String packageName,
}) =>
    pidOutput.trim().isEmpty &&
    !hasAttachedAndroidActivity(dumpsysActivities, packageName);

Map<String, Object?> parseBackgroundCryptoPushRelayRegistrationReceipt(
  List<int> rawBytes, {
  required DateTime now,
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String tokenGenerationId,
  required String refreshArtifactSha256,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 64 * 1024) {
    throw const FormatException('push relay receipt size rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('push relay receipt JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('push relay receipt is not an object');
  }
  final receipt = decoded.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'status',
    'completedAt',
    'proofSchema',
    'commandId',
    'tokenSha256',
    'tokenGenerationId',
    'refreshArtifactSha256',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'containsSecrets',
  };
  final hashPattern = RegExp(r'^[0-9a-f]{64}$');
  final completedAtRaw = receipt['completedAt'];
  final completedAt = completedAtRaw is String
      ? DateTime.tryParse(completedAtRaw)
      : null;
  if (receipt.keys.toSet().length != keys.length ||
      !receipt.keys.toSet().containsAll(keys) ||
      receipt['schema'] != backgroundCryptoPushRelayRegistrationReceiptSchema ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['proofSchema'] !=
          backgroundCryptoPushRelayRegistrationCommandSchema ||
      receipt['commandId'] != commandId ||
      receipt['commandSha256'] != commandSha256 ||
      receipt['tokenSha256'] != tokenSha256 ||
      receipt['tokenGenerationId'] != tokenGenerationId ||
      receipt['refreshArtifactSha256'] != refreshArtifactSha256 ||
      receipt['platform'] != 'android' ||
      receipt['accountIdentitySha256'] is! String ||
      !hashPattern.hasMatch(receipt['accountIdentitySha256']! as String) ||
      receipt['transportIdentitySha256'] is! String ||
      !hashPattern.hasMatch(receipt['transportIdentitySha256']! as String) ||
      receipt['relayFrameAccepted'] != true ||
      receipt['tokenPersisted'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false) {
    throw const FormatException('push relay receipt contract rejected');
  }
  final age = now.toUtc().difference(completedAt);
  final futureClockSkew = completedAt.difference(now.toUtc());
  if (futureClockSkew > backgroundCryptoPushRelayReceiptFutureClockSkew ||
      age > const Duration(minutes: 5)) {
    throw const FormatException('push relay receipt is stale');
  }
  return Map<String, Object?>.unmodifiable(receipt);
}

Map<String, Object?> parseBackgroundCryptoPushRelayRegistrationReceiptV2(
  List<int> rawBytes, {
  required DateTime now,
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String authorizationArtifactSha256,
  required String gateACommandGenerationId,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 64 * 1024) {
    throw const FormatException('push relay v2 receipt size rejected');
  }
  if (!RegExp(
        r'^tc256-relay-registration-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      !_isLowerSha256(commandSha256) ||
      !_isLowerSha256(tokenSha256) ||
      !_isLowerSha256(authorizationArtifactSha256) ||
      !RegExp(
        r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(gateACommandGenerationId)) {
    throw const FormatException('push relay v2 expected binding rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('push relay v2 receipt JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('push relay v2 receipt is not an object');
  }
  final receipt = decoded.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'status',
    'completedAt',
    'proofSchema',
    'commandId',
    'tokenSha256',
    'authorizationKind',
    'authorizationArtifactSha256',
    'gateACommandGenerationId',
    'commandSha256',
    'platform',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'relayFrameAccepted',
    'tokenPersisted',
    'commandDeleted',
    'containsSecrets',
  };
  final completedAt = DateTime.tryParse(
    receipt['completedAt']?.toString() ?? '',
  );
  if (!_hasExactKeys(receipt, keys) ||
      receipt['schema'] !=
          backgroundCryptoPushRelayRegistrationReceiptSchemaV2 ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['proofSchema'] !=
          backgroundCryptoPushRelayRegistrationCommandSchemaV2 ||
      receipt['commandId'] != commandId ||
      receipt['commandSha256'] != commandSha256 ||
      receipt['tokenSha256'] != tokenSha256 ||
      receipt['authorizationKind'] !=
          backgroundCryptoCurrentTokenAuthorizationKind ||
      receipt['authorizationArtifactSha256'] != authorizationArtifactSha256 ||
      receipt['gateACommandGenerationId'] != gateACommandGenerationId ||
      receipt['platform'] != 'android' ||
      !_isLowerSha256(receipt['accountIdentitySha256']) ||
      !_isLowerSha256(receipt['transportIdentitySha256']) ||
      receipt['relayFrameAccepted'] != true ||
      receipt['tokenPersisted'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false) {
    throw const FormatException('push relay v2 receipt contract rejected');
  }
  final age = now.toUtc().difference(completedAt);
  final futureClockSkew = completedAt.difference(now.toUtc());
  if (futureClockSkew > backgroundCryptoPushRelayReceiptFutureClockSkew ||
      age > const Duration(minutes: 5)) {
    throw const FormatException('push relay v2 receipt is stale');
  }
  return Map<String, Object?>.unmodifiable(receipt);
}

Map<String, Object?> parseDirectTextRelayTokenProofReceipt(
  List<int> rawBytes, {
  required DateTime now,
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String tokenGenerationId,
  required String refreshArtifactSha256,
  required String gateAArtifactSha256,
  required String accountIdentitySha256,
  required String transportIdentitySha256,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 16 * 1024) {
    throw const FormatException('direct-text token receipt size rejected');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('direct-text token receipt JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException('direct-text token receipt is not an object');
  }
  final receipt = decoded.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'status',
    'completedAt',
    'commandId',
    'commandSha256',
    'tokenSha256',
    'tokenGenerationId',
    'refreshArtifactSha256',
    'gateAArtifactSha256',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'tokenSha256Matched',
    'commandDeleted',
    'containsSecrets',
  };
  final completedAtRaw = receipt['completedAt'];
  final completedAt = completedAtRaw is String
      ? DateTime.tryParse(completedAtRaw)
      : null;
  if (receipt.keys.toSet().length != keys.length ||
      !receipt.keys.toSet().containsAll(keys) ||
      receipt['schema'] != directTextRelayTokenProofReceiptSchema ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['commandId'] != commandId ||
      receipt['commandSha256'] != commandSha256 ||
      receipt['tokenSha256'] != tokenSha256 ||
      receipt['tokenGenerationId'] != tokenGenerationId ||
      receipt['refreshArtifactSha256'] != refreshArtifactSha256 ||
      receipt['gateAArtifactSha256'] != gateAArtifactSha256 ||
      receipt['accountIdentitySha256'] != accountIdentitySha256 ||
      receipt['transportIdentitySha256'] != transportIdentitySha256 ||
      receipt['tokenSha256Matched'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false) {
    throw const FormatException('direct-text token receipt contract rejected');
  }
  final age = now.toUtc().difference(completedAt);
  final futureClockSkew = completedAt.difference(now.toUtc());
  if (futureClockSkew > directTextRelayTokenReceiptFutureClockSkew ||
      age > const Duration(minutes: 5)) {
    throw const FormatException('direct-text token receipt is stale');
  }
  return Map<String, Object?>.unmodifiable(receipt);
}

Map<String, Object?> parseDirectTextRelayTokenProofReceiptV2(
  List<int> rawBytes, {
  required DateTime now,
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String authorizationKind,
  required String authorizationArtifactSha256,
  required String gateACommandGenerationId,
  required String gateAArtifactSha256,
  required String accountIdentitySha256,
  required String transportIdentitySha256,
}) {
  if (rawBytes.isEmpty || rawBytes.length > 16 * 1024) {
    throw const FormatException('direct-text token receipt v2 size rejected');
  }
  if (!RegExp(
        r'^direct-text-relay-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      !_isLowerSha256(commandSha256) ||
      !_isLowerSha256(tokenSha256) ||
      authorizationKind != backgroundCryptoCurrentTokenAuthorizationKind ||
      !_isLowerSha256(authorizationArtifactSha256) ||
      !RegExp(
        r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(gateACommandGenerationId) ||
      !_isLowerSha256(gateAArtifactSha256) ||
      !_isLowerSha256(accountIdentitySha256) ||
      !_isLowerSha256(transportIdentitySha256)) {
    throw const FormatException(
      'direct-text token receipt v2 expected binding rejected',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('direct-text token receipt v2 JSON rejected');
  }
  if (decoded is! Map) {
    throw const FormatException(
      'direct-text token receipt v2 is not an object',
    );
  }
  final receipt = decoded.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'status',
    'completedAt',
    'commandId',
    'commandSha256',
    'tokenSha256',
    'authorizationKind',
    'authorizationArtifactSha256',
    'gateACommandGenerationId',
    'gateAArtifactSha256',
    'accountIdentitySha256',
    'transportIdentitySha256',
    'tokenSha256Matched',
    'commandDeleted',
    'containsSecrets',
  };
  final completedAtRaw = receipt['completedAt'];
  final completedAt = completedAtRaw is String
      ? DateTime.tryParse(completedAtRaw)
      : null;
  if (receipt.keys.toSet().length != keys.length ||
      !receipt.keys.toSet().containsAll(keys) ||
      receipt['schema'] != directTextRelayTokenProofReceiptSchemaV2 ||
      receipt['status'] != 'completed' ||
      completedAt == null ||
      !completedAt.isUtc ||
      receipt['commandId'] != commandId ||
      receipt['commandSha256'] != commandSha256 ||
      receipt['tokenSha256'] != tokenSha256 ||
      receipt['authorizationKind'] != authorizationKind ||
      receipt['authorizationArtifactSha256'] != authorizationArtifactSha256 ||
      receipt['gateACommandGenerationId'] != gateACommandGenerationId ||
      receipt['gateAArtifactSha256'] != gateAArtifactSha256 ||
      receipt['accountIdentitySha256'] != accountIdentitySha256 ||
      receipt['transportIdentitySha256'] != transportIdentitySha256 ||
      receipt['tokenSha256Matched'] != true ||
      receipt['commandDeleted'] != true ||
      receipt['containsSecrets'] != false) {
    throw const FormatException(
      'direct-text token receipt v2 contract rejected',
    );
  }
  final age = now.toUtc().difference(completedAt);
  final futureClockSkew = completedAt.difference(now.toUtc());
  if (futureClockSkew > directTextRelayTokenReceiptFutureClockSkew ||
      age > const Duration(minutes: 5)) {
    throw const FormatException('direct-text token receipt v2 is stale');
  }
  return Map<String, Object?>.unmodifiable(receipt);
}

Map<String, Object?> backgroundCryptoPushRelayProofEvidenceFromLog(
  String log, {
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String tokenGenerationId,
  required String refreshArtifactSha256,
}) => _backgroundCryptoPushRelayProofEvidenceFromLog(
  log,
  safeExpected: <String, Object?>{
    'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchema,
    'commandId': commandId,
    'tokenSha256': tokenSha256,
    'tokenGenerationId': tokenGenerationId,
    'refreshArtifactSha256': refreshArtifactSha256,
    'commandSha256': commandSha256,
    'platform': 'android',
  },
);

Map<String, Object?> backgroundCryptoPushRelayProofEvidenceFromLogV2(
  String log, {
  required String commandId,
  required String commandSha256,
  required String tokenSha256,
  required String authorizationArtifactSha256,
  required String gateACommandGenerationId,
}) => _backgroundCryptoPushRelayProofEvidenceFromLog(
  log,
  safeExpected: <String, Object?>{
    'proofSchema': backgroundCryptoPushRelayRegistrationCommandSchemaV2,
    'commandId': commandId,
    'tokenSha256': tokenSha256,
    'authorizationKind': backgroundCryptoCurrentTokenAuthorizationKind,
    'authorizationArtifactSha256': authorizationArtifactSha256,
    'gateACommandGenerationId': gateACommandGenerationId,
    'commandSha256': commandSha256,
    'platform': 'android',
  },
);

Map<String, Object?> _backgroundCryptoPushRelayProofEvidenceFromLog(
  String log, {
  required Map<String, Object?> safeExpected,
}) {
  final isV2 =
      safeExpected['proofSchema'] ==
      backgroundCryptoPushRelayRegistrationCommandSchemaV2;
  final expectedKeys = isV2
      ? const <String>{
          'proofSchema',
          'commandId',
          'tokenSha256',
          'authorizationKind',
          'authorizationArtifactSha256',
          'gateACommandGenerationId',
          'commandSha256',
          'platform',
        }
      : const <String>{
          'proofSchema',
          'commandId',
          'tokenSha256',
          'tokenGenerationId',
          'refreshArtifactSha256',
          'commandSha256',
          'platform',
        };
  final commandId = safeExpected['commandId'];
  if (!_hasExactKeys(safeExpected, expectedKeys) ||
      commandId is! String ||
      !RegExp(
        r'^tc256-relay-registration-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      !_isLowerSha256(safeExpected['tokenSha256']) ||
      !_isLowerSha256(safeExpected['commandSha256']) ||
      safeExpected['platform'] != 'android' ||
      (isV2
          ? safeExpected['authorizationKind'] !=
                    backgroundCryptoCurrentTokenAuthorizationKind ||
                !_isLowerSha256(safeExpected['authorizationArtifactSha256']) ||
                safeExpected['gateACommandGenerationId'] is! String ||
                !RegExp(
                  r'^tc256-gate-a-command-[0-9]{12,20}-[0-9]{1,10}$',
                ).hasMatch(safeExpected['gateACommandGenerationId']! as String)
          : safeExpected['proofSchema'] !=
                    backgroundCryptoPushRelayRegistrationCommandSchema ||
                !_isLowerSha256(safeExpected['refreshArtifactSha256']) ||
                safeExpected['tokenGenerationId'] is! String ||
                !RegExp(
                  r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
                ).hasMatch(safeExpected['tokenGenerationId']! as String))) {
    throw const FormatException('push relay expected binding rejected');
  }
  final events = <Map<String, dynamic>>[];
  for (final line in log.split('\n')) {
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line.substring(marker + '[FLOW] '.length).trim());
    } on FormatException {
      continue;
    }
    if (decoded is Map<String, dynamic> && decoded['layer'] == 'FL') {
      events.add(decoded);
    }
  }
  const orderedNames = <String>[
    'PUSH_REGISTER_RELAY_PROOF_ARMED',
    'PUSH_REGISTER_COORDINATOR_ATTEMPT',
    'PUSH_REGISTER_TOKEN_BEGIN',
    'PUSH_REGISTER_RELAY_PROOF_TOKEN_MATCHED',
    'P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN',
    'P2P_INBOX_REGISTER_TOKEN_REQUEST',
    'P2P_INBOX_REGISTER_TOKEN_RESPONSE',
    'P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS',
    'PUSH_REGISTER_TOKEN_SUCCESS',
    'PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED',
    'PUSH_REGISTER_TOKEN_PERSISTED',
    'PUSH_REGISTER_RELAY_PROOF_COMPLETE',
    'PUSH_REGISTER_COORDINATOR_SUCCESS',
  ];
  const mayHaveEarlierOrAdditionalAttempts = <String>{
    'P2P_SERVICE_REGISTER_PUSH_TOKEN_BEGIN',
    'P2P_INBOX_REGISTER_TOKEN_REQUEST',
    'P2P_INBOX_REGISTER_TOKEN_RESPONSE',
    'P2P_SERVICE_REGISTER_PUSH_TOKEN_SUCCESS',
  };
  final indices = <String, int>{};
  var previousIndex = -1;
  for (final name in orderedNames) {
    final matches = <int>[];
    for (var index = 0; index < events.length; index++) {
      if (events[index]['event'] == name) matches.add(index);
    }
    if (!mayHaveEarlierOrAdditionalAttempts.contains(name) &&
        matches.length != 1) {
      throw FormatException('push relay event $name count rejected');
    }
    final orderedMatches = matches.where((index) => index > previousIndex);
    if (orderedMatches.isEmpty) {
      throw FormatException('push relay event $name order rejected');
    }
    final selectedIndex = orderedMatches.first;
    indices[name] = selectedIndex;
    previousIndex = selectedIndex;
  }
  Map<String, dynamic> details(String event) {
    final payload = events[indices[event]!]['details'];
    if (payload is! Map) {
      throw FormatException('push relay event $event details rejected');
    }
    return payload.cast<String, dynamic>();
  }

  void requireBoundDetails(String event, {required Set<String> extraKeys}) {
    final actual = details(event);
    final expectedKeys = <String>{
      ...safeExpected.keys,
      'accountIdentitySha256',
      'transportIdentitySha256',
      ...extraKeys,
    };
    final hashPattern = RegExp(r'^[0-9a-f]{64}$');
    if (actual.keys.toSet().length != expectedKeys.length ||
        !actual.keys.toSet().containsAll(expectedKeys) ||
        safeExpected.entries.any((entry) => actual[entry.key] != entry.value) ||
        actual['accountIdentitySha256'] is! String ||
        !hashPattern.hasMatch(actual['accountIdentitySha256']! as String) ||
        actual['transportIdentitySha256'] is! String ||
        !hashPattern.hasMatch(actual['transportIdentitySha256']! as String)) {
      throw FormatException('push relay event $event binding rejected');
    }
  }

  final armed = details('PUSH_REGISTER_RELAY_PROOF_ARMED');
  if (armed.keys.toSet().length != safeExpected.length ||
      safeExpected.entries.any((entry) => armed[entry.key] != entry.value)) {
    throw const FormatException('push relay armed binding rejected');
  }
  requireBoundDetails(
    'PUSH_REGISTER_RELAY_PROOF_TOKEN_MATCHED',
    extraKeys: const <String>{},
  );
  requireBoundDetails(
    'PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED',
    extraKeys: const <String>{'relayFrameAccepted'},
  );
  requireBoundDetails(
    'PUSH_REGISTER_RELAY_PROOF_COMPLETE',
    extraKeys: const <String>{
      'relayFrameAccepted',
      'tokenPersisted',
      'commandDeleted',
    },
  );
  final relayAccepted = details(
    'PUSH_REGISTER_RELAY_PROOF_RELAY_FRAME_ACCEPTED',
  );
  final tokenMatched = details('PUSH_REGISTER_RELAY_PROOF_TOKEN_MATCHED');
  final complete = details('PUSH_REGISTER_RELAY_PROOF_COMPLETE');
  if (tokenMatched['accountIdentitySha256'] !=
          relayAccepted['accountIdentitySha256'] ||
      tokenMatched['transportIdentitySha256'] !=
          relayAccepted['transportIdentitySha256'] ||
      relayAccepted['accountIdentitySha256'] !=
          complete['accountIdentitySha256'] ||
      relayAccepted['transportIdentitySha256'] !=
          complete['transportIdentitySha256'] ||
      relayAccepted['relayFrameAccepted'] != true ||
      complete['relayFrameAccepted'] != true ||
      complete['tokenPersisted'] != true ||
      complete['commandDeleted'] != true ||
      details('P2P_INBOX_REGISTER_TOKEN_RESPONSE')['ok'] != true ||
      details('PUSH_REGISTER_COORDINATOR_ATTEMPT')['trigger'] != 'startup') {
    throw const FormatException('push relay success semantics rejected');
  }
  final coordinator = details('PUSH_REGISTER_COORDINATOR_SUCCESS');
  if (coordinator['trigger'] != 'startup') {
    throw const FormatException('push relay coordinator trigger rejected');
  }
  final coordinatorWithoutTrigger = Map<String, dynamic>.from(coordinator)
    ..remove('trigger');
  final completedWithoutFlags = Map<String, dynamic>.from(complete)
    ..remove('relayFrameAccepted')
    ..remove('tokenPersisted')
    ..remove('commandDeleted');
  if (!_mapsHaveSameScalarEntries(
    coordinatorWithoutTrigger,
    completedWithoutFlags,
  )) {
    throw const FormatException('push relay coordinator binding rejected');
  }
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    ...safeExpected,
    'accountIdentitySha256': complete['accountIdentitySha256']! as String,
    'transportIdentitySha256': complete['transportIdentitySha256']! as String,
    'relayFrameAccepted': true,
    'tokenPersisted': true,
    'commandDeleted': true,
    'coordinatorSuccess': true,
    'orderedEventCount': orderedNames.length,
  });
}

bool _mapsHaveSameScalarEntries(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) =>
    left.keys.toSet().length == right.keys.toSet().length &&
    left.keys.toSet().containsAll(right.keys) &&
    left.entries.every((entry) => right[entry.key] == entry.value);

class BackgroundCryptoFcmRefreshCommand {
  const BackgroundCryptoFcmRefreshCommand({
    required this.commandId,
    required this.issuedAt,
    required this.maxAge,
    required this.rawSha256,
    required this.subjectTokenSha256,
  });

  final String commandId;
  final DateTime issuedAt;
  final Duration maxAge;
  final String rawSha256;
  final String subjectTokenSha256;
}

BackgroundCryptoFcmRefreshCommand parseBackgroundCryptoFcmRefreshCommand(
  List<int> rawBytes, {
  required DateTime now,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(rawBytes, allowMalformed: false));
  } on Object {
    throw const FormatException('invalid FCM refresh command JSON');
  }
  if (decoded is! Map) {
    throw const FormatException('FCM refresh command is not an object');
  }
  final command = decoded.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'commandId',
    'issuedAt',
    'maxAgeSeconds',
    'subjectTokenSha256',
  };
  final commandId = command['commandId'];
  final issuedAtRaw = command['issuedAt'];
  final maxAgeSeconds = command['maxAgeSeconds'];
  final subjectTokenSha256 = command['subjectTokenSha256'];
  final issuedAt = issuedAtRaw is String
      ? DateTime.tryParse(issuedAtRaw)
      : null;
  if (command.keys.toSet().length != keys.length ||
      !command.keys.toSet().containsAll(keys) ||
      command['schema'] != backgroundCryptoFcmRefreshCommandSchema ||
      commandId is! String ||
      !RegExp(
        r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(commandId) ||
      issuedAt == null ||
      !issuedAt.isUtc ||
      maxAgeSeconds is! int ||
      maxAgeSeconds < 30 ||
      maxAgeSeconds > 180 ||
      subjectTokenSha256 is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(subjectTokenSha256)) {
    throw const FormatException('invalid FCM refresh command fields');
  }
  final age = now.toUtc().difference(issuedAt);
  if (age.isNegative || age > Duration(seconds: maxAgeSeconds)) {
    throw const FormatException('expired FCM refresh command');
  }
  return BackgroundCryptoFcmRefreshCommand(
    commandId: commandId,
    issuedAt: issuedAt,
    maxAge: Duration(seconds: maxAgeSeconds),
    rawSha256: sha256.convert(rawBytes).toString(),
    subjectTokenSha256: subjectTokenSha256,
  );
}

bool backgroundCryptoFcmRefreshSubjectMatches({
  required String currentToken,
  required String subjectTokenSha256,
}) {
  if (currentToken.trim().isEmpty ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(subjectTokenSha256)) {
    return false;
  }
  return sha256.convert(utf8.encode(currentToken.trim())).toString() ==
      subjectTokenSha256;
}

class BackgroundCryptoFreshTokenObservation {
  const BackgroundCryptoFreshTokenObservation({
    required this.token,
    required this.source,
    required this.observedAt,
    required this.tokenSha256,
    required this.priorTokenSha256,
  });

  final String token;
  final String source;
  final DateTime observedAt;
  final String tokenSha256;
  final String priorTokenSha256;
}

/// Invalidates exactly once after subscribing, then races onTokenRefresh with
/// bounded polling. Only a non-empty token whose hash differs from the prior
/// SDK token can win.
Future<BackgroundCryptoFreshTokenObservation>
acquireBackgroundCryptoFreshFcmToken({
  required String previousToken,
  required String expectedSubjectTokenSha256,
  required Stream<String> tokenRefreshes,
  required Future<void> Function() invalidateToken,
  required Future<String?> Function() pollToken,
  required DateTime Function() now,
  Duration timeout = const Duration(seconds: 45),
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  if (!backgroundCryptoFcmRefreshSubjectMatches(
        currentToken: previousToken,
        subjectTokenSha256: expectedSubjectTokenSha256,
      ) ||
      timeout <= Duration.zero ||
      pollInterval < Duration.zero) {
    throw ArgumentError('fresh FCM token acquisition arguments are invalid');
  }
  final normalizedPreviousToken = previousToken.trim();
  final priorHash = sha256
      .convert(utf8.encode(normalizedPreviousToken))
      .toString();
  final result = Completer<BackgroundCryptoFreshTokenObservation>();
  var stopped = false;
  var invalidationStarted = false;

  void consider(String? candidate, String source) {
    if (stopped ||
        !invalidationStarted ||
        result.isCompleted ||
        candidate == null) {
      return;
    }
    final normalized = candidate.trim();
    if (normalized.isEmpty) return;
    final candidateHash = sha256.convert(utf8.encode(normalized)).toString();
    if (candidateHash == priorHash) return;
    result.complete(
      BackgroundCryptoFreshTokenObservation(
        token: normalized,
        source: source,
        observedAt: now().toUtc(),
        tokenSha256: candidateHash,
        priorTokenSha256: priorHash,
      ),
    );
  }

  late final StreamSubscription<String> subscription;
  subscription = tokenRefreshes.listen(
    (token) => consider(token, 'on_token_refresh'),
    onError: (_) {},
  );
  final timeoutTimer = Timer(timeout, () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('fresh FCM token was not observed', timeout),
      );
    }
  });
  try {
    invalidationStarted = true;
    await invalidateToken();
    Future<void>(() async {
      while (!stopped && !result.isCompleted) {
        try {
          consider(await pollToken(), 'poll');
        } on Object {
          // A transient poll failure cannot outrank a later refresh callback.
        }
        if (!stopped && !result.isCompleted && pollInterval > Duration.zero) {
          await Future<void>.delayed(pollInterval);
        }
      }
    });
    return await result.future;
  } finally {
    stopped = true;
    timeoutTimer.cancel();
    await subscription.cancel();
  }
}

const Set<String> backgroundCryptoCleanupCommandModes = <String>{
  'cleanup-only',
  'setup-only',
  'recovery',
  'post-proof',
};

enum BackgroundCryptoFixtureStartupIntent {
  cleanupCommand,
  clearNotifications,
  setup,
}

BackgroundCryptoFixtureStartupIntent backgroundCryptoFixtureStartupIntent({
  required bool hasValidatedCleanupCommand,
  required bool hasClearNotificationsMarker,
}) {
  if (hasValidatedCleanupCommand) {
    return BackgroundCryptoFixtureStartupIntent.cleanupCommand;
  }
  if (hasClearNotificationsMarker) {
    return BackgroundCryptoFixtureStartupIntent.clearNotifications;
  }
  return BackgroundCryptoFixtureStartupIntent.setup;
}

const String backgroundCryptoPreflightActorPeerId = 'tc256-preflight-actor';
const String backgroundCryptoPreflightActorTransportPeerId =
    'tc256-preflight-actor-transport';
const String backgroundCryptoPreflightLocalTransportPeerId =
    'tc256-preflight-local-transport';
const String backgroundCryptoPreflightNonAdminActorPeerId =
    'tc256-preflight-writer';
const String backgroundCryptoPreflightNonAdminTransportPeerId =
    'tc256-preflight-writer-transport';
const String backgroundCryptoPreflightUnknownTransportPeerId =
    'tc256-preflight-unknown-transport';
const String backgroundCryptoPreflightGroupId = 'tc256-preflight-group';
const String backgroundCryptoPreflightAnnouncementId =
    'tc256-preflight-announcement';
const String backgroundCryptoPreflightDirectTrustedTitle = 'TC256 Alice';
const String backgroundCryptoPreflightGroupTrustedTitle = 'TC256 Trusted Group';
const String backgroundCryptoPreflightAnnouncementTrustedTitle =
    'TC256 Trusted Announcements';
const String backgroundCryptoPreflightMaliciousOuterName =
    'TC256 ATTACKER OUTER NAME';
const String backgroundCryptoPreflightMaliciousDecryptedName =
    'TC256 ATTACKER DECRYPTED NAME';
const String backgroundCryptoPreflightMaliciousDecryptedGroupName =
    'TC256 ATTACKER DECRYPTED GROUP';

enum BackgroundCryptoSetupReason {
  operationFailed('operation_failed'),
  schemaGuard('schema_guard'),
  missingIdentity('missing_identity'),
  missingMlKemPublic('missing_mlkem_public'),
  missingMlKemSecret('missing_mlkem_secret'),
  missingFcmToken('missing_fcm_token'),
  fixtureSeed('fixture_seed'),
  appLaunch('app_launch'),
  quiescenceFailed('quiescence_failed'),
  unknown('unknown');

  const BackgroundCryptoSetupReason(this.wireName);

  final String wireName;
}

enum BackgroundCryptoSetupPhase {
  appInit('app_init'),
  appQuiescence('app_quiescence'),
  firebaseInit('firebase_init'),
  secureStorage('secure_storage'),
  dbKey('db_key'),
  dbOpen('db_open'),
  dbSchema('db_schema'),
  identityLoad('identity_load'),
  mlKemPublic('mlkem_public'),
  mlKemSecret('mlkem_secret'),
  fixtureSeed('fixture_seed'),
  fcmToken('fcm_token'),
  bundleValidation('bundle_validation');

  const BackgroundCryptoSetupPhase(this.wireName);

  final String wireName;
}

enum BackgroundCryptoCleanupReason {
  operationFailed('operation_failed'),
  commandStagingFailed('command_staging_failed'),
  quiescenceFailed('quiescence_failed'),
  logResetFailed('log_reset_failed'),
  appLaunchFailed('app_launch_failed'),
  acknowledgementFailed('acknowledgement_failed'),
  privateResidueVerificationFailed('private_residue_verification_failed');

  const BackgroundCryptoCleanupReason(this.wireName);

  final String wireName;
}

enum BackgroundCryptoCleanupPhase {
  commandStaging('command_staging'),
  appQuiescence('app_quiescence'),
  logReset('log_reset'),
  appLaunch('app_launch'),
  acknowledgement('acknowledgement'),
  privateResidueVerification('private_residue_verification');

  const BackgroundCryptoCleanupPhase(this.wireName);

  final String wireName;
}

enum BackgroundCryptoCampaignReason {
  operationFailed('operation_failed'),
  headlessQuiescenceFailed('headless_quiescence_failed'),
  requestPrepareFailed('request_prepare_failed'),
  deliveryEligibilityFailed('delivery_eligibility_failed'),
  oauthFailed('oauth_failed'),
  providerSendFailed('provider_send_failed'),
  receiveTimeout('receive_timeout'),
  cryptoTimeout('crypto_timeout'),
  eligibilityFailed('eligibility_failed'),
  cardVerificationFailed('card_verification_failed'),
  routeVerificationFailed('route_verification_failed');

  const BackgroundCryptoCampaignReason(this.wireName);

  final String wireName;
}

enum BackgroundCryptoCampaignPhase {
  headlessQuiescence('headless_quiescence'),
  requestPrepare('request_prepare'),
  deliveryEligibility('delivery_eligibility'),
  oauth('oauth'),
  providerSend('provider_send'),
  receiveWait('receive_wait'),
  cryptoWait('crypto_wait'),
  eligibility('eligibility'),
  cardVerify('card_verify'),
  routeVerify('route_verify');

  const BackgroundCryptoCampaignPhase(this.wireName);

  final String wireName;
}

enum BackgroundCryptoNotificationClearPhase {
  knownIdLoad('known_id_load'),
  activeQuery('active_query'),
  classify('classify'),
  cancel('cancel'),
  toneCleanup('tone_cleanup'),
  markerWrite('marker_write');

  const BackgroundCryptoNotificationClearPhase(this.wireName);
  final String wireName;
}

enum BackgroundCryptoNotificationClearReason {
  operationFailed('operation_failed'),
  knownIdLoadFailed('known_id_load_failed'),
  activeQueryFailed('active_query_failed'),
  classifyFailed('classify_failed'),
  cancelFailed('cancel_failed'),
  toneCleanupFailed('tone_cleanup_failed'),
  markerWriteFailed('marker_write_failed'),
  missingMarker('missing_marker'),
  rejectedSchema('rejected_schema');

  const BackgroundCryptoNotificationClearReason(this.wireName);
  final String wireName;
}

enum BackgroundCryptoNotificationClearBoundary {
  commandDelivery('command_delivery'),
  commandAck('command_ack'),
  appLaunch('app_launch'),
  appPhase('app_phase'),
  completionSchema('completion_schema');

  const BackgroundCryptoNotificationClearBoundary(this.wireName);
  final String wireName;
}

enum BackgroundCryptoNotificationClearObservation {
  observed('observed'),
  notObserved('not_observed');

  const BackgroundCryptoNotificationClearObservation(this.wireName);
  final String wireName;
}

enum BackgroundCryptoPostClearBoundary {
  deliveryQuiescence('delivery_quiescence'),
  processAbsence('process_absence'),
  baselinePolling('baseline_polling'),
  convergence('convergence');

  const BackgroundCryptoPostClearBoundary(this.wireName);
  final String wireName;
}

enum BackgroundCryptoPostClearReason {
  deliveryQuiescenceFailed('delivery_quiescence_failed'),
  processAbsenceFailed('process_absence_failed'),
  processAbsenceTimeout('process_absence_timeout'),
  baselinePollFailed('baseline_poll_failed'),
  convergenceTimeout('convergence_timeout');

  const BackgroundCryptoPostClearReason(this.wireName);
  final String wireName;
}

enum BackgroundCryptoPostClearObservation {
  observed('observed'),
  notObserved('not_observed');

  const BackgroundCryptoPostClearObservation(this.wireName);
  final String wireName;
}

BackgroundCryptoNotificationClearPhase?
backgroundCryptoNotificationClearPhaseFromWire(Object? value) {
  final wire = value is String ? value.trim() : '';
  for (final phase in BackgroundCryptoNotificationClearPhase.values) {
    if (phase.wireName == wire) return phase;
  }
  return null;
}

BackgroundCryptoNotificationClearReason?
backgroundCryptoNotificationClearReasonFromWire(Object? value) {
  final wire = value is String ? value.trim() : '';
  for (final reason in BackgroundCryptoNotificationClearReason.values) {
    if (reason.wireName == wire) return reason;
  }
  return null;
}

BackgroundCryptoNotificationClearReason
backgroundCryptoNotificationClearReasonForPhase(
  BackgroundCryptoNotificationClearPhase phase,
) => switch (phase) {
  BackgroundCryptoNotificationClearPhase.knownIdLoad =>
    BackgroundCryptoNotificationClearReason.knownIdLoadFailed,
  BackgroundCryptoNotificationClearPhase.activeQuery =>
    BackgroundCryptoNotificationClearReason.activeQueryFailed,
  BackgroundCryptoNotificationClearPhase.classify =>
    BackgroundCryptoNotificationClearReason.classifyFailed,
  BackgroundCryptoNotificationClearPhase.cancel =>
    BackgroundCryptoNotificationClearReason.cancelFailed,
  BackgroundCryptoNotificationClearPhase.toneCleanup =>
    BackgroundCryptoNotificationClearReason.toneCleanupFailed,
  BackgroundCryptoNotificationClearPhase.markerWrite =>
    BackgroundCryptoNotificationClearReason.markerWriteFailed,
};

const List<String> backgroundCryptoNotificationClearCountFields = <String>[
  'fixtureNotificationCardsCleared',
  'fixtureNotificationRouteOwnedCardsCleared',
  'fixtureNotificationCopyOwnedCardsCleared',
  'fixtureNotificationKnownIdOwnedCardsCleared',
];

bool backgroundCryptoNotificationClearCommandAckFromLog(String log) {
  for (final line in log.split('\n')) {
    if (!line.contains('MKNOON_256_CRYPTO_PREFLIGHT')) continue;
    final start = line.indexOf('{');
    final end = line.lastIndexOf('}');
    if (start < 0 || end <= start) continue;
    try {
      final decoded = jsonDecode(line.substring(start, end + 1));
      if (decoded is Map<String, dynamic> &&
          decoded['event'] == 'notification_clear_command_ack' &&
          decoded['schema'] == 'mknoon.tc256-notification-clear.v1') {
        return true;
      }
    } on FormatException {
      continue;
    }
  }
  return false;
}

Map<String, dynamic>? backgroundCryptoNotificationClearCompletionFromLog(
  String log,
) {
  for (final line in log.split('\n').reversed) {
    if (!line.contains('MKNOON_256_CRYPTO_PREFLIGHT')) continue;
    final start = line.indexOf('{');
    final end = line.lastIndexOf('}');
    if (start < 0 || end <= start) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line.substring(start, end + 1));
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['event'] != 'notification_clear_phase' ||
        decoded['phase'] !=
            BackgroundCryptoNotificationClearPhase.markerWrite.wireName) {
      continue;
    }
    final marker = decoded;
    if (marker['completed'] != true ||
        backgroundCryptoNotificationClearCountFields.any(
          (field) => marker[field] is! int || (marker[field]! as int) < 0,
        )) {
      throw const FormatException(
        'notification clear completion marker schema rejected',
      );
    }
    return marker;
  }
  return null;
}

BackgroundCryptoSetupReason backgroundCryptoSetupReasonFromWire(Object? value) {
  final wire = value is String ? value.trim() : '';
  return BackgroundCryptoSetupReason.values.firstWhere(
    (reason) => reason.wireName == wire,
    orElse: () => BackgroundCryptoSetupReason.unknown,
  );
}

BackgroundCryptoSetupPhase? backgroundCryptoSetupPhaseFromWire(Object? value) {
  final wire = value is String ? value.trim() : '';
  for (final phase in BackgroundCryptoSetupPhase.values) {
    if (phase.wireName == wire) return phase;
  }
  return null;
}

BackgroundCryptoSetupReason backgroundCryptoTerminalSetupReason({
  required BackgroundCryptoSetupPhase phase,
  required BackgroundCryptoSetupReason reason,
}) => reason == BackgroundCryptoSetupReason.unknown
    ? BackgroundCryptoSetupReason.operationFailed
    : reason;

({BackgroundCryptoSetupPhase phase, BackgroundCryptoSetupReason reason})
backgroundCryptoHostSetupFailure({
  BackgroundCryptoSetupPhase? lastObservedPhase,
  BackgroundCryptoSetupReason? reason,
}) {
  final phase = lastObservedPhase ?? BackgroundCryptoSetupPhase.appInit;
  final candidate =
      reason ??
      (lastObservedPhase == null
          ? BackgroundCryptoSetupReason.appLaunch
          : BackgroundCryptoSetupReason.operationFailed);
  return (
    phase: phase,
    reason: backgroundCryptoTerminalSetupReason(
      phase: phase,
      reason: candidate,
    ),
  );
}

enum BackgroundCryptoTransportChannel { adb, shell, runAs }

class BackgroundCryptoTransportInvocation {
  const BackgroundCryptoTransportInvocation(this.channel, this.arguments);

  final BackgroundCryptoTransportChannel channel;
  final List<String> arguments;
}

class BackgroundCryptoTransportResult {
  const BackgroundCryptoTransportResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef BackgroundCryptoTransportRunner =
    Future<BackgroundCryptoTransportResult> Function(
      BackgroundCryptoTransportInvocation invocation,
    );

class BackgroundCryptoStagedFileFailure implements Exception {
  const BackgroundCryptoStagedFileFailure({
    this.primaryStage,
    required this.primaryType,
    required this.cleanupStages,
  });

  final String? primaryStage;
  final String? primaryType;
  final List<String> cleanupStages;
}

class BackgroundCryptoStagedFileReceipt {
  const BackgroundCryptoStagedFileReceipt({
    required this.byteLength,
    required this.sha256,
  });

  final int byteLength;
  final String sha256;
}

const String backgroundCryptoAppPrivateCommandPath =
    'files/tc256_post_foreground';
const String backgroundCryptoAppPrivateFcmRefreshCommandPath =
    'files/tc256_fcm_refresh_command.json';
const String backgroundCryptoAppPrivatePushRelayCommandPath =
    'files/tc256_push_relay_registration_proof_command.json';
const String backgroundCryptoAppPrivatePushRelayReceiptPath =
    'files/tc256_push_relay_registration_receipt.json';
const String backgroundCryptoAppPrivatePushRelayReceiptTempPath =
    'files/tc256_push_relay_registration_receipt.json.tmp';
const String directTextRelayTokenProofCommandPath =
    'app_flutter/intro_e2e_config.json';
const String directTextRelayTokenProofReceiptPath =
    'app_flutter/intro_e2e_result.json';
const String directTextRelayTokenProofReceiptTempPath =
    'app_flutter/intro_e2e_result.json.tmp';
const List<String> backgroundCryptoRecoveryPrivateArtifactPaths = <String>[
  'files/tc256_reaction_preflight_request.json',
  'files/tc256_cleanup_index.json',
  backgroundCryptoAppPrivateCommandPath,
  'files/tc256_clear_notifications',
  backgroundCryptoAppPrivateFcmRefreshCommandPath,
  backgroundCryptoAppPrivatePushRelayCommandPath,
  backgroundCryptoAppPrivatePushRelayReceiptPath,
  backgroundCryptoAppPrivatePushRelayReceiptTempPath,
];

bool backgroundCryptoRecoveryFallbackIsVerified({
  required int removalExitCode,
  required Map<String, int> absenceProbeExitCodes,
}) {
  if (absenceProbeExitCodes.keys.toSet().length !=
          backgroundCryptoRecoveryPrivateArtifactPaths.length ||
      !absenceProbeExitCodes.keys.toSet().containsAll(
        backgroundCryptoRecoveryPrivateArtifactPaths,
      )) {
    throw ArgumentError('recovery private residue probes are incomplete');
  }
  return removalExitCode == 0 &&
      backgroundCryptoRecoveryPrivateArtifactPaths.every(
        (path) => absenceProbeExitCodes[path] == 0,
      );
}

const String _backgroundCryptoHostStagePrefix = 'mknoon tc256 command owned-';
const String _backgroundCryptoHostOwnerMarker = '.mknoon-tc256-command-owner';
const String _backgroundCryptoDeviceStagePrefix =
    '/data/local/tmp/mknoon-tc256-command-';

bool isBackgroundCryptoOwnedDeviceStagePath(String path) {
  final match = RegExp(
    r'^/data/local/tmp/mknoon-tc256-command-[0-9a-f]{32}\.bin$',
  ).firstMatch(path);
  return match != null && match.start == 0 && match.end == path.length;
}

bool isBackgroundCryptoOwnedAppPrivateCommandPath(String path) =>
    path == backgroundCryptoAppPrivateCommandPath ||
    path == backgroundCryptoAppPrivateFcmRefreshCommandPath ||
    path == backgroundCryptoAppPrivatePushRelayCommandPath ||
    path == directTextRelayTokenProofCommandPath;

String _backgroundCryptoRandomHex(int byteLength) {
  final random = Random.secure();
  return List<int>.generate(
    byteLength,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

bool _isDirectOwnedHostStage({
  required String systemTempCanonicalPath,
  required String stageCanonicalPath,
}) {
  final prefix = systemTempCanonicalPath.endsWith(Platform.pathSeparator)
      ? systemTempCanonicalPath
      : '$systemTempCanonicalPath${Platform.pathSeparator}';
  if (!stageCanonicalPath.startsWith(prefix)) return false;
  final relative = stageCanonicalPath.substring(prefix.length);
  return RegExp(
    '^${RegExp.escape(_backgroundCryptoHostStagePrefix)}[A-Za-z0-9]+\$',
  ).hasMatch(relative);
}

/// Copies private bytes into an app-private file without putting their content
/// in an adb argument or a remote shell command. Both staging locations are
/// removed on success and on every failure path.
Future<BackgroundCryptoStagedFileReceipt>
copyBackgroundCryptoCommandBytesToAppPrivateFile({
  required List<int> bytes,
  required BackgroundCryptoTransportRunner run,
  String appPrivatePath = backgroundCryptoAppPrivateCommandPath,
}) async {
  Directory? hostStageDirectory;
  String? hostStageCanonicalPath;
  String? hostOwnerToken;
  File? hostOwnerMarker;
  File? hostStageFile;
  String? deviceStagePath;
  late final String expectedHash;
  String? primaryStage;
  String? primaryType;
  final cleanupStages = <String>[];

  Future<BackgroundCryptoTransportResult> invoke(
    String stage,
    BackgroundCryptoTransportChannel channel,
    List<String> arguments,
  ) async {
    primaryStage = stage;
    final result = await run(
      BackgroundCryptoTransportInvocation(
        channel,
        List<String>.unmodifiable(arguments),
      ),
    );
    if (result.exitCode != 0) {
      throw StateError('transport command failed');
    }
    return result;
  }

  String verifiedHash(String stage, BackgroundCryptoTransportResult result) {
    final fields = result.stdout.trim().split(RegExp(r'\s+'));
    final actual = fields.isEmpty ? '' : fields.first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(actual) || actual != expectedHash) {
      primaryStage = stage;
      throw StateError('transport hash mismatch');
    }
    return actual;
  }

  try {
    primaryStage = 'host_stage_create';
    hostStageDirectory = await Directory.systemTemp.createTemp(
      _backgroundCryptoHostStagePrefix,
    );
    final systemTempCanonicalPath = await Directory.systemTemp
        .resolveSymbolicLinks();
    hostStageCanonicalPath = await hostStageDirectory.resolveSymbolicLinks();
    if (!_isDirectOwnedHostStage(
      systemTempCanonicalPath: systemTempCanonicalPath,
      stageCanonicalPath: hostStageCanonicalPath,
    )) {
      throw StateError('host staging ownership validation failed');
    }
    hostOwnerToken = _backgroundCryptoRandomHex(32);
    hostOwnerMarker = File(
      '$hostStageCanonicalPath${Platform.pathSeparator}'
      '$_backgroundCryptoHostOwnerMarker',
    );
    await hostOwnerMarker.writeAsString(hostOwnerToken, flush: true);
    hostStageFile = File(
      '$hostStageCanonicalPath${Platform.pathSeparator}command.bin',
    );
    deviceStagePath =
        '$_backgroundCryptoDeviceStagePrefix'
        '${_backgroundCryptoRandomHex(16)}.bin';
    if (!isBackgroundCryptoOwnedDeviceStagePath(deviceStagePath) ||
        !isBackgroundCryptoOwnedAppPrivateCommandPath(appPrivatePath)) {
      throw StateError('fixed staging path validation failed');
    }
    primaryStage = 'payload_hash';
    expectedHash = sha256.convert(bytes).toString();
    primaryStage = 'host_stage_write';
    await hostStageFile.writeAsBytes(bytes, flush: true);
    await invoke(
      'device_stage_push',
      BackgroundCryptoTransportChannel.adb,
      <String>['push', hostStageFile.path, deviceStagePath],
    );
    await invoke(
      'device_stage_chmod',
      BackgroundCryptoTransportChannel.shell,
      <String>['chmod', '0644', deviceStagePath],
    );
    final stagedHash = await invoke(
      'device_stage_hash',
      BackgroundCryptoTransportChannel.shell,
      <String>['sha256sum', deviceStagePath],
    );
    verifiedHash('device_stage_hash', stagedHash);
    await invoke(
      'app_private_mkdir',
      BackgroundCryptoTransportChannel.runAs,
      <String>['mkdir', '-p', appPrivatePath.split('/').first],
    );
    await invoke(
      'app_private_copy',
      BackgroundCryptoTransportChannel.runAs,
      <String>['cp', deviceStagePath, appPrivatePath],
    );
    final privateHash = await invoke(
      'app_private_hash',
      BackgroundCryptoTransportChannel.runAs,
      <String>['sha256sum', appPrivatePath],
    );
    verifiedHash('app_private_hash', privateHash);
    primaryStage = null;
  } on Object catch (error) {
    primaryType = error.runtimeType.toString();
  } finally {
    if (deviceStagePath != null &&
        isBackgroundCryptoOwnedDeviceStagePath(deviceStagePath)) {
      try {
        final cleanup = await run(
          BackgroundCryptoTransportInvocation(
            BackgroundCryptoTransportChannel.shell,
            List<String>.unmodifiable(<String>['rm', '-f', deviceStagePath]),
          ),
        );
        if (cleanup.exitCode != 0) cleanupStages.add('device_stage_delete');
      } on Object {
        cleanupStages.add('device_stage_delete');
      }
    }
    try {
      if (hostStageDirectory != null &&
          hostStageCanonicalPath != null &&
          hostOwnerToken != null &&
          hostOwnerMarker != null &&
          await hostStageDirectory.exists()) {
        final currentCanonicalPath = await hostStageDirectory
            .resolveSymbolicLinks();
        final systemTempCanonicalPath = await Directory.systemTemp
            .resolveSymbolicLinks();
        final ownerMatches =
            await hostOwnerMarker.exists() &&
            await hostOwnerMarker.readAsString() == hostOwnerToken;
        if (currentCanonicalPath != hostStageCanonicalPath ||
            !_isDirectOwnedHostStage(
              systemTempCanonicalPath: systemTempCanonicalPath,
              stageCanonicalPath: currentCanonicalPath,
            ) ||
            !ownerMatches) {
          throw StateError('host staging ownership changed');
        }
        await hostStageDirectory.delete(recursive: true);
      } else if (hostStageDirectory != null &&
          await hostStageDirectory.exists()) {
        throw StateError('host staging ownership unavailable');
      }
    } on Object {
      cleanupStages.add('host_stage_owned_delete');
    }
  }

  if (primaryType != null || cleanupStages.isNotEmpty) {
    throw BackgroundCryptoStagedFileFailure(
      primaryStage: primaryType == null ? null : primaryStage,
      primaryType: primaryType,
      cleanupStages: List<String>.unmodifiable(cleanupStages),
    );
  }
  return BackgroundCryptoStagedFileReceipt(
    byteLength: bytes.length,
    sha256: expectedHash,
  );
}

bool backgroundCryptoCleanupReceiptsMatch(
  String log, {
  required String commandId,
  required String commandSha256,
}) {
  if (!RegExp(r'^[a-z0-9-]{12,96}$').hasMatch(commandId) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(commandSha256)) {
    return false;
  }
  final matched = <String>{};
  for (final line in log.split('\n')) {
    if (!line.contains('MKNOON_256_CRYPTO_PREFLIGHT')) continue;
    final start = line.indexOf('{');
    final end = line.lastIndexOf('}');
    if (start < 0 || end <= start) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line.substring(start, end + 1));
    } on FormatException {
      continue;
    }
    if (decoded is! Map) continue;
    final event = decoded['event'];
    if (event != 'cleanup_started' && event != 'cleanup_complete') continue;
    if (decoded['commandId'] != commandId) continue;
    if (decoded['commandSha256'] != commandSha256) return false;
    matched.add(event as String);
  }
  return matched.contains('cleanup_started') &&
      matched.contains('cleanup_complete');
}

const List<String> backgroundCryptoCleanupZeroCountFields = <String>[
  'fixtureDbRowsRemaining',
  'fixtureGroupKeyRefsRemaining',
  'fixtureClaimsRemaining',
  'fixtureToneSidecarsRemaining',
  'fixtureStagedEnvelopesRemaining',
  'fixtureGateEntriesRemaining',
  'fixtureNotificationCardsRemaining',
  'fixtureNotificationRouteOwnedCardsRemaining',
  'fixtureNotificationCopyOwnedCardsRemaining',
  'fixtureNotificationKnownIdOwnedCardsRemaining',
  'fixtureNotificationIdOwnersRemaining',
];

Map<String, Object?> backgroundCryptoCleanupEvidenceFromLog(
  String log, {
  required String commandId,
  required String commandSha256,
  required int commandByteLength,
  required String mode,
}) {
  if (!backgroundCryptoCleanupCommandModes.contains(mode) ||
      commandByteLength <= 0 ||
      !backgroundCryptoCleanupReceiptsMatch(
        log,
        commandId: commandId,
        commandSha256: commandSha256,
      )) {
    throw const FormatException('cleanup receipt contract failed');
  }
  Map<String, dynamic>? started;
  Map<String, dynamic>? complete;
  var startedCount = 0;
  var completeCount = 0;
  for (final line in log.split('\n')) {
    if (!line.contains('MKNOON_256_CRYPTO_PREFLIGHT')) continue;
    final start = line.indexOf('{');
    final end = line.lastIndexOf('}');
    if (start < 0 || end <= start) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line.substring(start, end + 1));
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['commandId'] != commandId ||
        decoded['commandSha256'] != commandSha256) {
      continue;
    }
    if (decoded['event'] == 'cleanup_started') {
      startedCount++;
      started = decoded;
    } else if (decoded['event'] == 'cleanup_complete') {
      completeCount++;
      complete = decoded;
    }
  }
  if (startedCount != 1 ||
      completeCount != 1 ||
      started == null ||
      complete == null ||
      started['mode'] != mode ||
      started['mainReexecuted'] != true ||
      complete['mode'] != mode ||
      complete['mainReexecuted'] != true ||
      complete['reservedOnly'] != true ||
      complete['privateBundleDeleted'] != true ||
      complete['cleanupIndexDeleted'] != true ||
      complete['fcmRefreshCommandDeleted'] != true ||
      complete['clearNotificationsMarkerDeleted'] != true ||
      complete['boundedReactionClaimsVerified'] != true ||
      complete['dedupeGatesRestored'] is! int ||
      complete['dedupeGatesRestored'] != 2 ||
      complete['dedupeGatesScrubbed'] is! int ||
      complete['dedupeGatesScrubbed'] != 2 ||
      backgroundCryptoCleanupZeroCountFields.any(
        (field) => complete![field] is! int || complete[field] != 0,
      )) {
    throw const FormatException('cleanup completion contract failed');
  }
  return <String, Object?>{
    'mode': mode,
    'commandId': commandId,
    'commandSha256': commandSha256,
    'commandByteLength': commandByteLength,
    'receiptsMatched': true,
    'mainReexecuted': true,
    'reservedOnly': true,
    'privateProviderBundleDeleted': true,
    'cleanupIndexDeleted': true,
    'fcmRefreshCommandDeleted': true,
    'clearNotificationsMarkerDeleted': true,
    'boundedReactionClaimsVerified': true,
    'dedupeGatesRestored': 2,
    'dedupeGatesScrubbed': 2,
    for (final field in backgroundCryptoCleanupZeroCountFields) field: 0,
  };
}

class BackgroundCryptoPreflightRow {
  const BackgroundCryptoPreflightRow({
    required this.context,
    required this.modality,
    required this.providerKind,
    required this.remoteType,
  });

  final String context;
  final String modality;
  final String providerKind;
  final String remoteType;

  String get id => '$context-$modality';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'context': context,
    'modality': modality,
    'providerKind': providerKind,
    'remoteType': remoteType,
  };
}

class BackgroundCryptoPreflightNegativeRow {
  const BackgroundCryptoPreflightNegativeRow({
    required this.id,
    required this.context,
    required this.providerKind,
    required this.rejectionReason,
  });

  final String id;
  final String context;
  final String providerKind;
  final String rejectionReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'context': context,
    'providerKind': providerKind,
    'rejectionReason': rejectionReason,
  };
}

const List<BackgroundCryptoPreflightRow> backgroundCryptoPreflightOrdinaryRows =
    <BackgroundCryptoPreflightRow>[
      BackgroundCryptoPreflightRow(
        context: 'direct',
        modality: 'text',
        providerKind: 'chat',
        remoteType: 'new_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'direct',
        modality: 'image',
        providerKind: 'chat',
        remoteType: 'new_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'direct',
        modality: 'video',
        providerKind: 'chat',
        remoteType: 'new_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'direct',
        modality: 'voice',
        providerKind: 'chat',
        remoteType: 'new_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'group',
        modality: 'text',
        providerKind: 'group',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'group',
        modality: 'image',
        providerKind: 'group',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'group',
        modality: 'video',
        providerKind: 'group',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'group',
        modality: 'voice',
        providerKind: 'group',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'announcement',
        modality: 'text',
        providerKind: 'announcement',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'announcement',
        modality: 'image',
        providerKind: 'announcement',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'announcement',
        modality: 'video',
        providerKind: 'announcement',
        remoteType: 'group_message',
      ),
      BackgroundCryptoPreflightRow(
        context: 'announcement',
        modality: 'voice',
        providerKind: 'announcement',
        remoteType: 'group_message',
      ),
    ];

const List<BackgroundCryptoPreflightNegativeRow>
backgroundCryptoPreflightNegativeRows = <BackgroundCryptoPreflightNegativeRow>[
  BackgroundCryptoPreflightNegativeRow(
    id: 'group-missing-transport',
    context: 'group',
    providerKind: 'group',
    rejectionReason: 'missing_transport',
  ),
  BackgroundCryptoPreflightNegativeRow(
    id: 'group-unknown-transport',
    context: 'group',
    providerKind: 'group',
    rejectionReason: 'unknown_transport',
  ),
  BackgroundCryptoPreflightNegativeRow(
    id: 'announcement-non-admin',
    context: 'announcement',
    providerKind: 'announcement',
    rejectionReason: 'non_admin_announcement',
  ),
];

bool isBackgroundCryptoSyntheticCaseId(String value) =>
    value == 'reaction' ||
    backgroundCryptoPreflightOrdinaryRows.any((row) => row.id == value) ||
    backgroundCryptoPreflightNegativeRows.any((row) => row.id == value);

List<String> backgroundCryptoCampaignCaseOrder({required bool ordinaryOnly}) =>
    List<String>.unmodifiable(<String>[
      if (!ordinaryOnly) 'reaction',
      if (ordinaryOnly)
        ...backgroundCryptoPreflightOrdinaryRows.map((row) => row.id),
      ...backgroundCryptoPreflightNegativeRows.map((row) => row.id),
      if (!ordinaryOnly)
        ...backgroundCryptoPreflightOrdinaryRows.map((row) => row.id),
    ]);

Map<String, Object?> backgroundCryptoPreflightDryRunManifest({
  bool cleanupOnly = false,
  bool setupOnly = false,
  bool ordinaryOnly = false,
  bool resetOnly = false,
  bool providerDiagnosticOnly = false,
  bool refreshUnregisteredToken = false,
}) => <String, Object?>{
  'schema': cleanupOnly
      ? backgroundCryptoCleanupArtifactSchema
      : setupOnly
      ? backgroundCryptoSetupArtifactSchema
      : resetOnly
      ? backgroundCryptoResetArtifactSchema
      : providerDiagnosticOnly
      ? backgroundCryptoProviderDiagnosticArtifactSchema
      : backgroundCryptoPreflightBundleSchema,
  'mode': cleanupOnly
      ? 'cleanup-only-dry-run'
      : setupOnly
      ? 'setup-only-dry-run'
      : resetOnly
      ? 'reset-only-dry-run'
      : providerDiagnosticOnly
      ? 'provider-diagnostic-only-dry-run'
      : ordinaryOnly
      ? 'ordinary-only-dry-run'
      : 'dry-run',
  'ordinaryCaseCount':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? 0
      : backgroundCryptoPreflightOrdinaryRows.length,
  'negativeCaseCount':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? 0
      : backgroundCryptoPreflightNegativeRows.length,
  'reactionRows':
      cleanupOnly ||
          setupOnly ||
          ordinaryOnly ||
          resetOnly ||
          providerDiagnosticOnly
      ? 0
      : 1,
  'providerRowsPlanned':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? 0
      : backgroundCryptoPreflightOrdinaryRows.length +
            backgroundCryptoPreflightNegativeRows.length +
            (ordinaryOnly ? 0 : 1),
  'providerValidationRowsPlanned': providerDiagnosticOnly ? 1 : 0,
  if (providerDiagnosticOnly) 'deliveryRowsPlanned': 0,
  if (providerDiagnosticOnly) 'diagnosticFixtureCaseId': 'direct-text',
  'caseExecutionOrder':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? const <String>[]
      : backgroundCryptoCampaignCaseOrder(ordinaryOnly: ordinaryOnly),
  'firstOrdinaryCaseId':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? null
      : backgroundCryptoPreflightOrdinaryRows.first.id,
  'contexts': cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? const <String>[]
      : const <String>['direct', 'group', 'announcement'],
  'modalities': cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? const <String>[]
      : const <String>['text', 'image', 'video', 'voice'],
  'cases': cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? const <Object?>[]
      : backgroundCryptoPreflightOrdinaryRows
            .map((row) => row.toJson())
            .toList(growable: false),
  'negativeCases':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? const <Object?>[]
      : backgroundCryptoPreflightNegativeRows
            .map((row) => row.toJson())
            .toList(growable: false),
  'groupTransportContract':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? 'not-executed'
      : 'authenticated-active-device-roster',
  'groupSenderAccountField':
      cleanupOnly || setupOnly || resetOnly || providerDiagnosticOnly
      ? 'not-executed'
      : 'omitted',
  'performsBuild': false,
  'usesDevice': false,
  'contactsProvider': false,
  'performsOrdinaryProof': false,
  'cleanupOnly': cleanupOnly,
  'setupOnly': setupOnly,
  'ordinaryOnly': ordinaryOnly,
  'resetOnly': resetOnly,
  'providerDiagnosticOnly': providerDiagnosticOnly,
  'refreshUnregisteredToken': refreshUnregisteredToken,
  'performsRegistrationRefresh': false,
  'containsSecrets': false,
};

class BackgroundCryptoFailureRecord {
  const BackgroundCryptoFailureRecord({
    required this.stage,
    required this.type,
    this.environmentBlocked = false,
    this.setupReason,
    this.setupPhase,
    this.cleanupReason,
    this.cleanupPhase,
    this.campaignReason,
    this.campaignPhase,
    this.syntheticCaseId,
    this.notificationClearReason,
    this.notificationClearPhase,
    this.notificationClearBoundary,
    this.notificationClearObservation,
    this.postClearReason,
    this.postClearBoundary,
    this.postClearObservation,
    this.postClearPollCount,
    this.postClearBaselineCount,
    this.postClearBaselineHash,
  });

  final String stage;
  final String type;
  final bool environmentBlocked;
  final BackgroundCryptoSetupReason? setupReason;
  final BackgroundCryptoSetupPhase? setupPhase;
  final BackgroundCryptoCleanupReason? cleanupReason;
  final BackgroundCryptoCleanupPhase? cleanupPhase;
  final BackgroundCryptoCampaignReason? campaignReason;
  final BackgroundCryptoCampaignPhase? campaignPhase;
  final String? syntheticCaseId;
  final BackgroundCryptoNotificationClearReason? notificationClearReason;
  final BackgroundCryptoNotificationClearPhase? notificationClearPhase;
  final BackgroundCryptoNotificationClearBoundary? notificationClearBoundary;
  final BackgroundCryptoNotificationClearObservation?
  notificationClearObservation;
  final BackgroundCryptoPostClearReason? postClearReason;
  final BackgroundCryptoPostClearBoundary? postClearBoundary;
  final BackgroundCryptoPostClearObservation? postClearObservation;
  final int? postClearPollCount;
  final int? postClearBaselineCount;
  final String? postClearBaselineHash;

  BackgroundCryptoSetupPhase? get redactedSetupPhase =>
      setupPhase ??
      (stage == 'setup' ? BackgroundCryptoSetupPhase.appInit : null);

  BackgroundCryptoSetupReason? get redactedSetupReason =>
      setupReason ??
      (stage == 'setup' ? BackgroundCryptoSetupReason.operationFailed : null);

  BackgroundCryptoCleanupReason? get redactedCleanupReason => cleanupReason;

  BackgroundCryptoCleanupPhase? get redactedCleanupPhase => cleanupPhase;

  Map<String, Object?> toJson() {
    final phase = redactedSetupPhase;
    final rawReason = redactedSetupReason;
    if (phase != null && rawReason == BackgroundCryptoSetupReason.unknown) {
      throw StateError('known setup phase must have a terminal reason');
    }
    final reason = rawReason;
    if ((redactedCleanupPhase == null) != (redactedCleanupReason == null)) {
      throw StateError('cleanup phase and reason must be persisted together');
    }
    if ((campaignPhase == null) != (campaignReason == null)) {
      throw StateError('campaign phase and reason must be persisted together');
    }
    final hasClearFailure = notificationClearReason != null;
    if (hasClearFailure != (notificationClearBoundary != null) ||
        hasClearFailure != (notificationClearObservation != null) ||
        (notificationClearPhase != null && !hasClearFailure)) {
      throw StateError(
        'notification clear diagnostics must be persisted together',
      );
    }
    final hasPostClearFailure = postClearReason != null;
    final hasBaselineCount = postClearBaselineCount != null;
    final hasBaselineHash = postClearBaselineHash != null;
    if (hasPostClearFailure != (postClearBoundary != null) ||
        hasPostClearFailure != (postClearObservation != null) ||
        (!hasPostClearFailure &&
            (postClearPollCount != null ||
                hasBaselineCount ||
                hasBaselineHash)) ||
        hasBaselineCount != hasBaselineHash ||
        (postClearPollCount != null && postClearPollCount! < 0) ||
        (postClearBaselineCount != null && postClearBaselineCount! < 0) ||
        (postClearBaselineHash != null &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(postClearBaselineHash!)) ||
        ((postClearBoundary ==
                    BackgroundCryptoPostClearBoundary.baselinePolling ||
                postClearBoundary ==
                    BackgroundCryptoPostClearBoundary.convergence) &&
            postClearPollCount == null)) {
      throw StateError('post-clear diagnostics must be finite and redacted');
    }
    final caseId = syntheticCaseId;
    if (campaignPhase != null &&
        (caseId == null || !isBackgroundCryptoSyntheticCaseId(caseId))) {
      throw StateError('campaign case ID must be reserved and phase-bound');
    }
    if (campaignPhase == null && caseId != null) {
      throw StateError('campaign case ID must be reserved and phase-bound');
    }
    return <String, Object?>{
      'stage': stage,
      'type':
          reason == null &&
              redactedCleanupReason == null &&
              campaignReason == null &&
              notificationClearReason == null &&
              postClearReason == null
          ? type
          : '_CampaignFailure',
      'environmentBlocked': environmentBlocked,
      if (phase != null) 'setupPhase': phase.wireName,
      if (reason != null) 'setupReason': reason.wireName,
      if (redactedCleanupPhase case final cleanupPhase?)
        'cleanupPhase': cleanupPhase.wireName,
      if (redactedCleanupReason case final cleanupReason?)
        'cleanupReason': cleanupReason.wireName,
      if (campaignPhase case final campaignPhase?)
        'campaignPhase': campaignPhase.wireName,
      if (campaignReason case final campaignReason?)
        'campaignReason': campaignReason.wireName,
      if (notificationClearPhase case final clearPhase?)
        'notificationClearPhase': clearPhase.wireName,
      if (notificationClearReason case final clearReason?)
        'notificationClearReason': clearReason.wireName,
      if (notificationClearBoundary case final clearBoundary?)
        'notificationClearBoundary': clearBoundary.wireName,
      if (notificationClearObservation case final clearObservation?)
        'notificationClearObservation': clearObservation.wireName,
      if (postClearReason case final reason?)
        'postClearReason': reason.wireName,
      if (postClearBoundary case final boundary?)
        'postClearBoundary': boundary.wireName,
      if (postClearObservation case final observation?)
        'postClearObservation': observation.wireName,
      'postClearPollCount': ?postClearPollCount,
      'postClearBaselineCount': ?postClearBaselineCount,
      'postClearBaselineHash': ?postClearBaselineHash,
      'syntheticCaseId': ?caseId,
    };
  }
}

String backgroundCryptoCompositeFailureVerdict({
  BackgroundCryptoFailureRecord? primary,
  BackgroundCryptoFailureRecord? cleanup,
  BackgroundCryptoFailureRecord? restoration,
}) {
  final failed = <String>[
    if (primary != null) 'primary',
    if (cleanup != null) 'cleanup',
    if (restoration != null) 'restoration',
  ];
  if (failed.isEmpty) return 'passed';
  return '${failed.join('_and_')}_failed';
}

int backgroundCryptoCompositeExitCode({
  BackgroundCryptoFailureRecord? primary,
  BackgroundCryptoFailureRecord? cleanup,
  BackgroundCryptoFailureRecord? restoration,
}) {
  final failures = <BackgroundCryptoFailureRecord>[
    ?primary,
    ?cleanup,
    ?restoration,
  ];
  if (failures.isEmpty) return 0;
  return failures.every((failure) => failure.environmentBlocked) ? 78 : 1;
}

Map<String, Object?> buildBackgroundCryptoCompositeFailureArtifact({
  required DateTime capturedAt,
  BackgroundCryptoFailureRecord? primary,
  BackgroundCryptoFailureRecord? cleanup,
  BackgroundCryptoFailureRecord? restoration,
}) {
  final verdict = backgroundCryptoCompositeFailureVerdict(
    primary: primary,
    cleanup: cleanup,
    restoration: restoration,
  );
  if (verdict == 'passed') {
    throw ArgumentError('at least one campaign failure is required');
  }
  return <String, Object?>{
    'testCase': 'TC-07',
    'scenario': 'android_background_crypto_preflight',
    'status': 'failed',
    'stage': 'composite',
    'verdict': verdict,
    'exitCode': backgroundCryptoCompositeExitCode(
      primary: primary,
      cleanup: cleanup,
      restoration: restoration,
    ),
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'primaryFailure': primary?.toJson(),
    'cleanupFailure': cleanup?.toJson(),
    'restorationFailure': restoration?.toJson(),
  };
}

bool androidProcessAndTaskAreAbsent({
  required int pidExitCode,
  required String pidOutput,
  required String pidStderr,
  required String activityDump,
  required String packageName,
}) =>
    pidExitCode == 1 &&
    pidOutput.trim().isEmpty &&
    pidStderr.trim().isEmpty &&
    !androidActivityIsAttached(activityDump, packageName: packageName);

bool isBackgroundCryptoFixtureRoutePayload(String? payload) {
  final normalized = payload?.trim();
  if (normalized == null || normalized.isEmpty) return false;
  bool groupRoute(String id) =>
      normalized == 'group:$id' || normalized.startsWith('group:$id|');
  return normalized == backgroundCryptoPreflightActorPeerId ||
      groupRoute(backgroundCryptoPreflightGroupId) ||
      groupRoute(backgroundCryptoPreflightAnnouncementId);
}

bool isBackgroundCryptoFixtureGateKey(String key) {
  final normalized = key.trim();
  if (normalized.isEmpty) return false;
  bool routeToken(String route) =>
      normalized.contains('payload=$route|') ||
      normalized.endsWith('payload=$route') ||
      normalized.contains('payload:$route|') ||
      normalized.endsWith('payload:$route') ||
      normalized.contains('message:$route|') ||
      normalized.endsWith('message:$route');
  return routeToken(backgroundCryptoPreflightActorPeerId) ||
      routeToken('group:$backgroundCryptoPreflightGroupId') ||
      routeToken('group:$backgroundCryptoPreflightAnnouncementId') ||
      backgroundCryptoFixtureIdentityPrefixes.any(
        (prefix) =>
            normalized.contains('id=$prefix') ||
            normalized.contains('|message:$prefix'),
      );
}

const List<String> backgroundCryptoFixtureIdentityPrefixes = <String>[
  'tc256-reaction-',
  'tc256-target-',
  'tc256-direct-',
  'tc256-group-',
  'tc256-announcement-',
];

bool isBackgroundCryptoFixtureIdentity(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return false;
  return backgroundCryptoFixtureIdentityPrefixes.any(normalized.startsWith);
}

bool backgroundCryptoReactionTargetHaveParity({
  required String? eventId,
  required String? targetMessageId,
}) {
  String? suffix(String? value, String prefix) {
    final normalized = value?.trim();
    if (normalized == null || !normalized.startsWith(prefix)) return null;
    final suffix = normalized.substring(prefix.length);
    return RegExp(r'^\d+$').hasMatch(suffix) ? suffix : null;
  }

  final eventSuffix = suffix(eventId, 'tc256-reaction-');
  final targetSuffix = suffix(targetMessageId, 'tc256-target-');
  return eventSuffix != null && eventSuffix == targetSuffix;
}

class BackgroundCryptoCleanupIndexValidation {
  const BackgroundCryptoCleanupIndexValidation({
    required this.errors,
    required this.eventIds,
    required this.boundedClaimNames,
  });

  final List<String> errors;
  final Set<String> eventIds;
  final Set<String> boundedClaimNames;

  bool get isValid => errors.isEmpty;
}

BackgroundCryptoCleanupIndexValidation validateBackgroundCryptoCleanupIndex(
  Object? decoded, {
  required String Function(String eventId) boundedClaimName,
  bool? requireReaction = true,
}) {
  final errors = <String>[];
  final eventIds = <String>{};
  final boundedClaims = <String>{};
  if (decoded is! Map ||
      decoded['schema'] != 'mknoon.tc256-cleanup-index.v2' ||
      decoded['reactionEventIds'] is! List ||
      decoded['reactionTargetMessageIds'] is! List ||
      decoded['boundedReactionClaimNames'] is! List ||
      decoded['ordinaryMessageIds'] is! List ||
      decoded['negativeMessageIds'] is! List) {
    errors.add('invalid reserved cleanup index schema');
    return BackgroundCryptoCleanupIndexValidation(
      errors: List<String>.unmodifiable(errors),
      eventIds: const <String>{},
      boundedClaimNames: const <String>{},
    );
  }
  final events = decoded['reactionEventIds']! as List;
  final targets = decoded['reactionTargetMessageIds']! as List;
  final storedClaims = decoded['boundedReactionClaimNames']! as List;
  final ordinaryIds = decoded['ordinaryMessageIds']! as List;
  final negativeIds = decoded['negativeMessageIds']! as List;
  final reactionCountIsValid = requireReaction == null
      ? events.length <= 1
      : events.length == (requireReaction ? 1 : 0);
  if (!reactionCountIsValid ||
      targets.length != events.length ||
      storedClaims.length != events.length) {
    errors.add('cleanup index reaction/target cardinality is invalid');
  }
  if (events.any((value) => value is! String) ||
      targets.any((value) => value is! String) ||
      storedClaims.any((value) => value is! String) ||
      ordinaryIds.any((value) => value is! String) ||
      negativeIds.any((value) => value is! String)) {
    errors.add('cleanup index members must all be strings');
  }
  if (errors.isEmpty) {
    for (var index = 0; index < events.length; index++) {
      final eventId = (events[index] as String).trim();
      final targetId = (targets[index] as String).trim();
      if (!backgroundCryptoReactionTargetHaveParity(
        eventId: eventId,
        targetMessageId: targetId,
      )) {
        errors.add('cleanup index reaction/target parity failed');
      }
      eventIds.add(eventId);
    }
    if (eventIds.length != events.length) {
      errors.add('cleanup index reaction IDs must be unique');
    }
    final normalizedOrdinary = ordinaryIds
        .cast<String>()
        .map((value) => value.trim())
        .toList(growable: false);
    if (normalizedOrdinary.length !=
        backgroundCryptoPreflightOrdinaryRows.length) {
      errors.add('cleanup index ordinary matrix cardinality is invalid');
    }
    for (final row in backgroundCryptoPreflightOrdinaryRows) {
      final prefix = 'tc256-${row.id}-';
      if (normalizedOrdinary
              .where((value) => value.startsWith(prefix))
              .length !=
          1) {
        errors.add('cleanup index ordinary matrix must contain one $prefix ID');
      }
    }
    final normalizedNegative = negativeIds
        .cast<String>()
        .map((value) => value.trim())
        .toList(growable: false);
    if (normalizedNegative.length !=
        backgroundCryptoPreflightNegativeRows.length) {
      errors.add('cleanup index negative matrix cardinality is invalid');
    }
    for (final row in backgroundCryptoPreflightNegativeRows) {
      final prefix = 'tc256-${row.context}-negative-${row.rejectionReason}-';
      if (normalizedNegative
              .where((value) => value.startsWith(prefix))
              .length !=
          1) {
        errors.add('cleanup index negative matrix must contain one $prefix ID');
      }
    }
    final derivedClaims = eventIds.map(boundedClaimName).toSet();
    boundedClaims.addAll(
      storedClaims.cast<String>().map((value) => value.trim()),
    );
    if (boundedClaims.length != storedClaims.length ||
        boundedClaims.length != derivedClaims.length ||
        !boundedClaims.containsAll(derivedClaims)) {
      errors.add('cleanup index bounded claims do not match reaction IDs');
    }
  }
  return BackgroundCryptoCleanupIndexValidation(
    errors: List<String>.unmodifiable(errors),
    eventIds: Set<String>.unmodifiable(eventIds),
    boundedClaimNames: Set<String>.unmodifiable(boundedClaims),
  );
}

Map<String, Object?> removeBackgroundCryptoFixtureGateEntries(
  Map<String, Object?> entries,
) => <String, Object?>{
  for (final entry in entries.entries)
    if (!isBackgroundCryptoFixtureGateKey(entry.key)) entry.key: entry.value,
};

bool isBackgroundCryptoFixtureClaimFileName(String fileName) {
  final normalized = fileName.trim();
  if (normalized.isEmpty) return false;
  return normalized.startsWith('message_reaction-tc256-reaction-') ||
      normalized.startsWith('new_message-tc256-direct-') ||
      normalized.startsWith('group_message-tc256-group-') ||
      normalized.startsWith('group_message-tc256-announcement-');
}

bool isBackgroundCryptoFixtureEnvelope({
  required String senderPeerId,
  String? messageId,
  String? eventId,
  String? targetMessageId,
}) {
  return senderPeerId.trim() == backgroundCryptoPreflightActorPeerId ||
      isBackgroundCryptoFixtureIdentity(messageId) ||
      isBackgroundCryptoFixtureIdentity(eventId) ||
      isBackgroundCryptoFixtureIdentity(targetMessageId);
}

Map<String, Object?> encodeBackgroundCryptoFileBaselines(
  Map<String, List<int>?> files,
) => <String, Object?>{
  'schema': 'mknoon.tc256-dedupe-gate-backup.v2',
  'files': <String, Object?>{
    for (final entry in files.entries)
      entry.key: <String, Object?>{
        'existed': entry.value != null,
        if (entry.value != null) 'contentsBase64': base64Encode(entry.value!),
      },
  },
};

Map<String, List<int>?> decodeBackgroundCryptoFileBaselines(
  Object? encoded, {
  required Set<String> expectedFileNames,
}) {
  if (encoded is! Map ||
      encoded['schema'] != 'mknoon.tc256-dedupe-gate-backup.v2' ||
      encoded['files'] is! Map) {
    throw const FormatException('invalid dedupe-gate baseline bundle');
  }
  final files = encoded['files']! as Map;
  final decoded = <String, List<int>?>{};
  for (final fileName in expectedFileNames) {
    final rawRecord = files[fileName];
    if (rawRecord is! Map || rawRecord['existed'] is! bool) {
      throw FormatException('invalid $fileName baseline metadata');
    }
    final existed = rawRecord['existed']! as bool;
    final contents = rawRecord['contentsBase64'];
    if (existed && contents is! String) {
      throw FormatException('invalid $fileName baseline contents');
    }
    decoded[fileName] = existed ? base64Decode(contents! as String) : null;
  }
  return Map<String, List<int>?>.unmodifiable(decoded);
}

Map<String, Object?> parseBackgroundCryptoFcmTokenObservation(
  Map<String, dynamic> bundle, {
  String? expectedGenerationId,
  String? expectedPriorTokenSha256,
  bool requireForcedRefresh = false,
  DateTime? now,
}) {
  final token = bundle['token'];
  final raw = bundle['tokenMetadata'];
  if (token is! String || token.trim().isEmpty || raw is! Map) {
    throw const FormatException('private FCM token observation is missing');
  }
  final observation = raw.cast<String, Object?>();
  const keys = <String>{
    'schema',
    'source',
    'observedAt',
    'generationId',
    'tokenSha256',
    'priorTokenSha256',
    'refreshSignal',
  };
  final source = observation['source'];
  final observedAtRaw = observation['observedAt'];
  final observedAt = observedAtRaw is String
      ? DateTime.tryParse(observedAtRaw)
      : null;
  final generationId = observation['generationId'];
  final tokenHash = observation['tokenSha256'];
  final priorHash = observation['priorTokenSha256'];
  final refreshSignal = observation['refreshSignal'];
  final calculatedHash = sha256.convert(utf8.encode(token.trim())).toString();
  if (observation.keys.toSet().length != keys.length ||
      !observation.keys.toSet().containsAll(keys) ||
      observation['schema'] != backgroundCryptoFcmTokenObservationSchema ||
      !<String>{'sdk_current', 'forced_reregistration'}.contains(source) ||
      observedAt == null ||
      !observedAt.isUtc ||
      tokenHash is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(tokenHash) ||
      tokenHash != calculatedHash ||
      (priorHash != null &&
          (priorHash is! String ||
              !RegExp(r'^[0-9a-f]{64}$').hasMatch(priorHash))) ||
      !<String>{
        'initial_get_token',
        'on_token_refresh',
        'poll',
      }.contains(refreshSignal)) {
    throw const FormatException('private FCM token observation is invalid');
  }
  if (source == 'sdk_current') {
    if (generationId != null ||
        priorHash != null ||
        refreshSignal != 'initial_get_token') {
      throw const FormatException(
        'current FCM token observation is incoherent',
      );
    }
  } else if (generationId is! String ||
      !RegExp(
        r'^tc256-token-refresh-[0-9]{12,20}-[0-9]{1,10}$',
      ).hasMatch(generationId) ||
      priorHash is! String ||
      priorHash == tokenHash ||
      !<String>{'on_token_refresh', 'poll'}.contains(refreshSignal)) {
    throw const FormatException(
      'refreshed FCM token observation is incoherent',
    );
  }
  if (requireForcedRefresh && source != 'forced_reregistration') {
    throw const FormatException('forced FCM token refresh was not observed');
  }
  if (expectedGenerationId != null && generationId != expectedGenerationId) {
    throw const FormatException('FCM token generation does not match command');
  }
  if (expectedPriorTokenSha256 != null &&
      priorHash != expectedPriorTokenSha256) {
    throw const FormatException(
      'FCM token prior hash does not match authorized subject',
    );
  }
  if (now != null) {
    final age = now.toUtc().difference(observedAt);
    if (age.isNegative || age > const Duration(minutes: 2)) {
      throw const FormatException('FCM token observation is stale');
    }
  }
  return Map<String, Object?>.unmodifiable(observation);
}

List<String> validateBackgroundCryptoPreflightBundle(
  Map<String, dynamic> bundle, {
  bool? requireReaction = true,
}) {
  final errors = <String>[];
  if (bundle['schema'] != backgroundCryptoPreflightBundleSchema) {
    errors.add(
      'bundle.schema must equal $backgroundCryptoPreflightBundleSchema',
    );
  }
  final token = bundle['token'];
  if (token is! String || token.trim().isEmpty) {
    errors.add('bundle.token must be a non-empty private string');
  }
  if (bundle.containsKey('tokenMetadata')) {
    try {
      parseBackgroundCryptoFcmTokenObservation(bundle);
    } on FormatException {
      errors.add('bundle.tokenMetadata must be a valid redacted observation');
    }
  }
  if (requireReaction == true ||
      (requireReaction == null && bundle.containsKey('reaction'))) {
    final reaction = bundle['reaction'];
    final reactionData = reaction is Map ? reaction['data'] : null;
    if (reactionData is! Map) {
      errors.add('bundle.reaction.data must be an object');
    } else {
      final data = reactionData.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (data.values.any((value) => value is! String)) {
        errors.add('bundle.reaction.data values must all be strings');
      }
      if (data['type'] != 'message_reaction') {
        errors.add('bundle.reaction.data.type must equal message_reaction');
      }
      for (final key in <String>[
        'sender_id',
        'event_id',
        'target_message_id',
        'action',
        'kem',
        'ciphertext',
        'nonce',
      ]) {
        final value = data[key];
        if (value is! String || value.trim().isEmpty) {
          errors.add('bundle.reaction.data.$key must be non-empty');
        }
      }
      if (data['action'] != 'add') {
        errors.add('bundle.reaction.data.action must equal add');
      }
      if (data['sender_id'] != backgroundCryptoPreflightActorPeerId) {
        errors.add(
          'bundle.reaction.data.sender_id must equal the reserved actor',
        );
      }
      if (data['event_id'] is! String ||
          !(data['event_id']! as String).startsWith('tc256-reaction-')) {
        errors.add(
          'bundle.reaction.data.event_id must use the reserved reaction prefix',
        );
      }
      if (data['target_message_id'] is! String ||
          !(data['target_message_id']! as String).startsWith('tc256-target-')) {
        errors.add(
          'bundle.reaction.data.target_message_id must use the reserved target prefix',
        );
      }
      if (!backgroundCryptoReactionTargetHaveParity(
        eventId: data['event_id']?.toString(),
        targetMessageId: data['target_message_id']?.toString(),
      )) {
        errors.add(
          'bundle.reaction event/target IDs must share one numeric fixture suffix',
        );
      }
    }
  }
  final ordinary = bundle['ordinaryCases'];
  if (ordinary is! List) {
    errors.add('bundle.ordinaryCases must be a list');
    return List<String>.unmodifiable(errors);
  }
  if (ordinary.length != backgroundCryptoPreflightOrdinaryRows.length) {
    errors.add(
      'bundle.ordinaryCases must contain exactly '
      '${backgroundCryptoPreflightOrdinaryRows.length} rows',
    );
  }
  final expected = <String, BackgroundCryptoPreflightRow>{
    for (final row in backgroundCryptoPreflightOrdinaryRows) row.id: row,
  };
  final seen = <String>{};
  final seenMessageIds = <String>{};
  for (var index = 0; index < ordinary.length; index++) {
    final value = ordinary[index];
    if (value is! Map) {
      errors.add('bundle.ordinaryCases[$index] must be an object');
      continue;
    }
    final row = value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final id = row['id'];
    if (id is! String || id.trim().isEmpty) {
      errors.add('bundle.ordinaryCases[$index].id must be non-empty');
      continue;
    }
    if (!seen.add(id)) errors.add('duplicate ordinary case id: $id');
    final contract = expected[id];
    if (contract == null) {
      errors.add('unexpected ordinary case id: $id');
      continue;
    }
    for (final entry in <(String, String)>[
      ('context', contract.context),
      ('modality', contract.modality),
      ('providerKind', contract.providerKind),
      ('remoteType', contract.remoteType),
    ]) {
      if (row[entry.$1] != entry.$2) {
        errors.add('$id.${entry.$1} must equal ${entry.$2}');
      }
    }
    for (final key in <String>[
      'conversationKey',
      'messageId',
      'expectedTitle',
      'expectedBody',
      'expectedPayload',
      'expectedCategory',
    ]) {
      final field = row[key];
      if (field is! String || field.trim().isEmpty) {
        errors.add('$id.$key must be a non-empty string');
      }
    }
    final messageId = row['messageId'];
    if (messageId is String &&
        messageId.isNotEmpty &&
        !seenMessageIds.add(messageId)) {
      errors.add('duplicate ordinary messageId: $messageId');
    }
    final reservedMessagePrefix = switch (contract.context) {
      'direct' => 'tc256-direct-',
      'group' => 'tc256-group-',
      'announcement' => 'tc256-announcement-',
      _ => '',
    };
    if (messageId is! String || !messageId.startsWith(reservedMessagePrefix)) {
      errors.add('$id.messageId must use $reservedMessagePrefix');
    }
    if (row['expectedCategory'] != 'msg') {
      errors.add('$id.expectedCategory must equal msg');
    }
    final trustedTitle = switch (contract.context) {
      'direct' => backgroundCryptoPreflightDirectTrustedTitle,
      'group' => backgroundCryptoPreflightGroupTrustedTitle,
      'announcement' => backgroundCryptoPreflightAnnouncementTrustedTitle,
      _ => '',
    };
    if (row['expectedTitle'] != trustedTitle) {
      errors.add('$id.expectedTitle must equal the fixed trusted DB title');
    }
    final expectedBody = contract.context == 'direct'
        ? contract.modality == 'text'
              ? 'TC256 encrypted direct text'
              : null
        : contract.modality == 'text'
        ? '$backgroundCryptoPreflightDirectTrustedTitle: '
              'TC256 encrypted ${contract.context} text'
        : null;
    if (expectedBody != null && row['expectedBody'] != expectedBody) {
      errors.add('$id.expectedBody must equal the trusted local actor fixture');
    }
    if (contract.context != 'direct' &&
        (row['expectedBody'] is! String ||
            !(row['expectedBody']! as String).startsWith(
              '$backgroundCryptoPreflightDirectTrustedTitle: ',
            ))) {
      errors.add('$id.expectedBody must use the trusted local actor prefix');
    }
    final forbidden = row['forbiddenDisplayValues'];
    if (forbidden is! List ||
        forbidden.isEmpty ||
        forbidden.any((value) => value is! String || value.trim().isEmpty)) {
      errors.add('$id.forbiddenDisplayValues must be non-empty strings');
    } else {
      for (final requiredValue in const <String>[
        backgroundCryptoPreflightMaliciousOuterName,
        backgroundCryptoPreflightMaliciousDecryptedName,
        backgroundCryptoPreflightMaliciousDecryptedGroupName,
      ]) {
        if (!forbidden.contains(requiredValue)) {
          errors.add('$id.forbiddenDisplayValues must contain $requiredValue');
        }
      }
    }
    final data = row['data'];
    if (data is! Map) {
      errors.add('$id.data must be an object');
      continue;
    }
    final stringData = data.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (stringData.values.any((value) => value is! String)) {
      errors.add('$id.data values must all be strings');
    }
    if (stringData['type'] != contract.remoteType) {
      errors.add('$id.data.type must equal ${contract.remoteType}');
    }
    if (stringData['message_id'] != row['messageId']) {
      errors.add('$id.data.message_id must equal its outer messageId');
    }
    for (final key in <String>['ciphertext', 'nonce']) {
      final value = stringData[key];
      if (value is! String || value.trim().isEmpty) {
        errors.add('$id.data.$key must be non-empty');
      }
    }
    if (contract.context == 'direct') {
      final senderId = stringData['sender_id'];
      if (senderId is! String || senderId.trim().isEmpty) {
        errors.add('$id.data.sender_id is required for direct messages');
      } else if (senderId != backgroundCryptoPreflightActorPeerId) {
        errors.add('$id.data.sender_id must equal the reserved actor peer');
      }
      final kem = stringData['kem'];
      if (kem is! String || kem.trim().isEmpty) {
        errors.add('$id.data.kem is required for direct messages');
      }
      if (row['conversationKey'] != senderId) {
        errors.add('$id.conversationKey must equal data.sender_id');
      }
      if (row['expectedPayload'] != senderId) {
        errors.add('$id.expectedPayload must equal data.sender_id');
      }
    } else if (stringData.containsKey('sender_id')) {
      errors.add(
        '$id.data.sender_id must be omitted for authenticated group pushes',
      );
    } else {
      final senderTransport = stringData['sender_transport_peer_id'];
      if (senderTransport != backgroundCryptoPreflightActorTransportPeerId) {
        errors.add(
          '$id.data.sender_transport_peer_id must equal the reserved active device transport',
        );
      }
      if (backgroundCryptoPreflightActorPeerId ==
          backgroundCryptoPreflightActorTransportPeerId) {
        errors.add('$id account and transport identities must be distinct');
      }
      if (row['trustedActorAccountPeerId'] !=
          backgroundCryptoPreflightActorPeerId) {
        errors.add('$id.trustedActorAccountPeerId must equal the local member');
      }
      if (row['trustedActorTransportPeerId'] != senderTransport) {
        errors.add(
          '$id.trustedActorTransportPeerId must equal data.sender_transport_peer_id',
        );
      }
      if (row['trustedActorName'] !=
          backgroundCryptoPreflightDirectTrustedTitle) {
        errors.add('$id.trustedActorName must equal the local member username');
      }
      final expectedRole = contract.context == 'announcement'
          ? 'admin'
          : 'writer';
      if (row['trustedActorRole'] != expectedRole) {
        errors.add('$id.trustedActorRole must equal $expectedRole');
      }
      final groupId = stringData['groupId'];
      if (groupId is! String || groupId.trim().isEmpty) {
        errors.add('$id.data.groupId is required for group messages');
      } else {
        final expectedGroupId = contract.context == 'group'
            ? backgroundCryptoPreflightGroupId
            : backgroundCryptoPreflightAnnouncementId;
        if (groupId != expectedGroupId) {
          errors.add('$id.data.groupId must equal $expectedGroupId');
        }
      }
      final keyEpoch = int.tryParse(stringData['keyEpoch']?.toString() ?? '');
      if (keyEpoch == null || keyEpoch < 0) {
        errors.add('$id.data.keyEpoch must be a non-negative integer string');
      }
      final canonicalConversation = 'group:$groupId';
      if (row['conversationKey'] != canonicalConversation) {
        errors.add('$id.conversationKey must equal $canonicalConversation');
      }
      final canonicalPayload =
          '$canonicalConversation|message:${row['messageId']}';
      if (row['expectedPayload'] != canonicalPayload) {
        errors.add('$id.expectedPayload must equal $canonicalPayload');
      }
    }
  }
  for (final missing in expected.keys.toSet().difference(seen)) {
    errors.add('missing ordinary case id: $missing');
  }
  final negative = bundle['negativeCases'];
  if (negative is! List) {
    errors.add('bundle.negativeCases must be a list');
    return List<String>.unmodifiable(errors);
  }
  if (negative.length != backgroundCryptoPreflightNegativeRows.length) {
    errors.add(
      'bundle.negativeCases must contain exactly '
      '${backgroundCryptoPreflightNegativeRows.length} rows',
    );
  }
  final expectedNegative = <String, BackgroundCryptoPreflightNegativeRow>{
    for (final row in backgroundCryptoPreflightNegativeRows) row.id: row,
  };
  final seenNegative = <String>{};
  for (var index = 0; index < negative.length; index++) {
    final value = negative[index];
    if (value is! Map) {
      errors.add('bundle.negativeCases[$index] must be an object');
      continue;
    }
    final row = value.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    final id = row['id'];
    final contract = id is String ? expectedNegative[id] : null;
    if (id is! String || id.trim().isEmpty) {
      errors.add('bundle.negativeCases[$index].id must be non-empty');
      continue;
    }
    if (!seenNegative.add(id)) errors.add('duplicate negative case id: $id');
    if (contract == null) {
      errors.add('unexpected negative case id: $id');
      continue;
    }
    for (final entry in <(String, String)>[
      ('context', contract.context),
      ('providerKind', contract.providerKind),
      ('rejectionReason', contract.rejectionReason),
    ]) {
      if (row[entry.$1] != entry.$2) {
        errors.add('$id.${entry.$1} must equal ${entry.$2}');
      }
    }
    if (row['remoteType'] != 'group_message') {
      errors.add('$id.remoteType must equal group_message');
    }
    if (row['expectedSuppressionReason'] !=
        'group_message_local_state_ineligible') {
      errors.add(
        '$id.expectedSuppressionReason must equal group_message_local_state_ineligible',
      );
    }
    final expectedGroupId = contract.context == 'group'
        ? backgroundCryptoPreflightGroupId
        : backgroundCryptoPreflightAnnouncementId;
    if (row['conversationKey'] != 'group:$expectedGroupId') {
      errors.add('$id.conversationKey must use the trusted local group');
    }
    final messageId = row['messageId'];
    final messagePrefix = 'tc256-${contract.context}-negative-';
    if (messageId is! String || !messageId.startsWith(messagePrefix)) {
      errors.add('$id.messageId must use $messagePrefix');
    } else if (!seenMessageIds.add(messageId)) {
      errors.add('duplicate negative messageId: $messageId');
    }
    final data = row['data'];
    if (data is! Map) {
      errors.add('$id.data must be an object');
      continue;
    }
    final stringData = data.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (stringData.values.any((value) => value is! String)) {
      errors.add('$id.data values must all be strings');
    }
    if (stringData['type'] != 'group_message' ||
        stringData['groupId'] != expectedGroupId ||
        stringData['message_id'] != messageId) {
      errors.add('$id.data must preserve the reserved group/message context');
    }
    if (stringData.containsKey('sender_id')) {
      errors.add('$id.data.sender_id must be omitted');
    }
    for (final key in <String>['ciphertext', 'nonce']) {
      final field = stringData[key];
      if (field is! String || field.trim().isEmpty) {
        errors.add('$id.data.$key must be non-empty');
      }
    }
    if (int.tryParse(stringData['keyEpoch']?.toString() ?? '') != 7) {
      errors.add('$id.data.keyEpoch must equal 7');
    }
    final transport = stringData['sender_transport_peer_id'];
    if (contract.rejectionReason == 'missing_transport') {
      if (stringData.containsKey('sender_transport_peer_id')) {
        errors.add('$id must omit sender_transport_peer_id');
      }
    } else if (contract.rejectionReason == 'unknown_transport') {
      if (transport != backgroundCryptoPreflightUnknownTransportPeerId) {
        errors.add('$id must use the reserved unknown transport');
      }
    } else if (contract.rejectionReason == 'non_admin_announcement') {
      if (transport != backgroundCryptoPreflightNonAdminTransportPeerId) {
        errors.add('$id must use the reserved non-admin transport');
      }
    } else {
      errors.add('$id has an unsupported rejection reason');
    }
  }
  for (final missing in expectedNegative.keys.toSet().difference(
    seenNegative,
  )) {
    errors.add('missing negative case id: $missing');
  }
  return List<String>.unmodifiable(errors);
}

String? extractBackgroundNotificationShownPayload(String logcat) {
  for (final line in logcat.split('\n').reversed) {
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) continue;
    try {
      final decoded = jsonDecode(
        line.substring(marker + '[FLOW] '.length).trim(),
      );
      if (decoded is! Map ||
          decoded['event'] != 'PUSH_BACKGROUND_NOTIFICATION_SHOWN') {
        continue;
      }
      final details = decoded['details'];
      final payload = details is Map ? details['payload'] : null;
      if (payload is String && payload.trim().isNotEmpty) return payload.trim();
    } on FormatException {
      continue;
    }
  }
  return null;
}

Set<String> backgroundCryptoForbiddenAuthorizationStageFamilies(String log) {
  return <String>{
    if (log.contains('PUSH_BACKGROUND_ENVELOPE_STAGE_')) 'envelope_staging',
    if (log.contains('PUSH_BACKGROUND_MESSAGE_CLAIM_') ||
        log.contains('PUSH_BACKGROUND_MESSAGE_TONE_'))
      'claim_or_tone',
    if (log.contains('PUSH_BACKGROUND_MESSAGE_CRYPTO_PLUGIN_') ||
        log.contains('PUSH_ANDROID_DATA_DECRYPT_'))
      'crypto_or_decrypt',
    if (log.contains('PUSH_BACKGROUND_NOTIFICATION_ID_ALLOCATION_'))
      'notification_id_allocation',
    if (log.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN') ||
        log.contains('PUSH_BACKGROUND_NOTIFICATION_ERROR') ||
        log.contains('PUSH_BACKGROUND_NOTIFICATION_SHOW_'))
      'os_show_or_notification_pipeline',
  };
}

bool backgroundCryptoExpectedAuthorizationSuppressionObserved(
  String log, {
  required String reason,
}) =>
    log.contains('PUSH_BACKGROUND_MESSAGE_RECEIVED') &&
    log
        .split('\n')
        .any(
          (line) =>
              line.contains('PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED') &&
              line.contains(reason),
        );

class Plan256ArtifactValidation {
  const Plan256ArtifactValidation(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

Plan256ArtifactValidation validatePlan256ArtifactContract({
  required String scenario,
  required Map<String, dynamic> artifact,
  String? rawJson,
}) {
  final errors = <String>[];
  final check = _ArtifactContractCheck(artifact, errors);
  final testCase = switch (scenario) {
    'android_physical_recipient' => 'TC-13',
    'ios_physical_recipient' => 'TC-14',
    'android_message_unread_lifecycle' => 'TC-16',
    _ => null,
  };
  if (testCase == null) {
    return Plan256ArtifactValidation(<String>[
      'unsupported Plan-256 closure scenario: $scenario',
    ]);
  }

  check.equals('schema', plan256ArtifactSchema);
  check.equals('testCase', testCase);
  check.equals('scenario', scenario);
  check.equals('status', 'passed');
  check.utcTimestamp('capturedAt');

  final environment = check.object('environment');
  check.equalsIn(environment, 'name', 'staging', 'environment.name');
  check.nonEmptyIn(
    environment,
    'candidateAppRevision',
    'environment.candidateAppRevision',
  );
  check.nonEmptyIn(
    environment,
    'candidateRelayRevision',
    'environment.candidateRelayRevision',
  );
  check.sha256In(
    environment,
    'candidateRelaySha256',
    'environment.candidateRelaySha256',
  );
  check.isTrueIn(
    environment,
    'providerConfigured',
    'environment.providerConfigured',
  );
  check.isTrueIn(
    environment,
    'candidateBuildInstalled',
    'environment.candidateBuildInstalled',
  );
  if (scenario != 'android_message_unread_lifecycle') {
    check.isTrueIn(
      environment,
      'typedReactionEnabled',
      'environment.typedReactionEnabled',
    );
  }
  check.equalsIn(
    environment,
    'provider',
    scenario == 'ios_physical_recipient' ? 'apns' : 'fcm',
    'environment.provider',
  );

  _validateTopology(check, scenario);
  _validateCaptureMethod(check, scenario);
  _validateEvidenceInventory(check, scenario);
  _validateRedaction(check, rawJson);

  switch (scenario) {
    case 'android_physical_recipient':
      _validateAndroidReactionArtifact(check);
    case 'ios_physical_recipient':
      _validateIosReactionArtifact(check);
    case 'android_message_unread_lifecycle':
      _validateAndroidUnreadLifecycleArtifact(check);
  }

  return Plan256ArtifactValidation(List<String>.unmodifiable(errors));
}

void _validateTopology(_ArtifactContractCheck check, String scenario) {
  final topology = check.object('topology');
  final sender = check.objectIn(topology, 'sender', 'topology.sender');
  final recipient = check.objectIn(topology, 'recipient', 'topology.recipient');
  check.nonEmptyIn(sender, 'deviceId', 'topology.sender.deviceId');
  check.nonEmptyIn(recipient, 'deviceId', 'topology.recipient.deviceId');
  check.isTrueIn(sender, 'liveDiscovered', 'topology.sender.liveDiscovered');
  check.isTrueIn(
    recipient,
    'liveDiscovered',
    'topology.recipient.liveDiscovered',
  );
  check.isTrueIn(sender, 'explicitId', 'topology.sender.explicitId');
  check.isTrueIn(recipient, 'explicitId', 'topology.recipient.explicitId');
  if (sender['deviceId'] == recipient['deviceId']) {
    check.error('topology sender and recipient device ids must differ');
  }
  check.equalsIn(sender, 'platform', 'android', 'topology.sender.platform');
  check.equalsIn(
    recipient,
    'platform',
    scenario == 'ios_physical_recipient' ? 'ios' : 'android',
    'topology.recipient.platform',
  );
  check.isTrueIn(recipient, 'physical', 'topology.recipient.physical');
}

void _validateCaptureMethod(_ArtifactContractCheck check, String scenario) {
  final capture = check.object('capture');
  check.isTrueIn(capture, 'automationOnly', 'capture.automationOnly');
  check.equalsIn(capture, 'manualTaps', 0, 'capture.manualTaps');
  check.isFalseIn(capture, 'forceStopUsed', 'capture.forceStopUsed');
  check.isFalseIn(
    capture,
    'productionDeploymentPerformed',
    'capture.productionDeploymentPerformed',
  );
  if (scenario == 'android_physical_recipient') {
    final command = capture['recipientTerminationCommand'];
    if (command is! String ||
        !command.startsWith('am kill ') ||
        command.contains('force-stop')) {
      check.error(
        'capture.recipientTerminationCommand must use am kill and never force-stop',
      );
    }
    check.isTrueIn(
      capture,
      'pidAbsentBeforeDelivery',
      'capture.pidAbsentBeforeDelivery',
    );
  }
}

void _validateEvidenceInventory(_ArtifactContractCheck check, String scenario) {
  final evidence = check.list('evidence');
  final expectedKinds = switch (scenario) {
    'android_physical_recipient' => const <String>{
      'relay_provider',
      'android_logcat',
      'notification_records',
      'ui_automation',
      'sqlcipher_state',
    },
    'ios_physical_recipient' => const <String>{
      'relay_provider',
      'apns_delivery',
      'nse_log',
      'xcuitest',
      'local_state',
    },
    _ => const <String>{
      'relay_provider',
      'android_logcat',
      'notification_records',
      'ui_automation',
      'sqlcipher_state',
    },
  };
  final foundKinds = <String>{};
  for (var index = 0; index < evidence.length; index++) {
    final value = evidence[index];
    if (value is! Map) {
      check.error('evidence[$index] must be an object');
      continue;
    }
    final record = Map<String, dynamic>.from(value);
    final kind = record['kind'];
    if (kind is String && kind.isNotEmpty) {
      if (!foundKinds.add(kind)) {
        check.error('evidence kind $kind must be unique');
      }
    } else {
      check.error('evidence[$index].kind must be non-empty');
    }
    check.nonEmptyIn(record, 'path', 'evidence[$index].path');
    check.sha256In(record, 'sha256', 'evidence[$index].sha256');
    final bytes = record['bytes'];
    if (bytes is! num || bytes.toInt() <= 0) {
      check.error('evidence[$index].bytes must be positive');
    }
  }
  for (final expected in expectedKinds) {
    if (!foundKinds.contains(expected)) {
      check.error('evidence is missing required kind $expected');
    }
  }
}

void _validateRedaction(_ArtifactContractCheck check, String? rawJson) {
  final redaction = check.object('redaction');
  for (final field in const <String>[
    'peerIdsPersisted',
    'pushTokensPersisted',
    'secretKeysPersisted',
    'ciphertextPersisted',
    'plaintextPayloadPersisted',
  ]) {
    check.isFalseIn(redaction, field, 'redaction.$field');
  }
  if (rawJson == null) return;
  for (final forbidden in const <String>[
    '"fcmToken":',
    '"apnsToken":',
    '"secretKey":',
    '"ciphertext":',
    '"senderPeerId":',
    '"recipientPeerId":',
  ]) {
    if (rawJson.contains(forbidden)) {
      check.error('artifact contains forbidden raw field $forbidden');
    }
  }
}

void _validateAndroidReactionArtifact(_ArtifactContractCheck check) {
  final events = check.object('events');
  final first = check.objectIn(events, 'first', 'events.first');
  final replacement = check.objectIn(
    events,
    'replacement',
    'events.replacement',
  );
  final negative = check.objectIn(
    events,
    'ownTargetNegative',
    'events.ownTargetNegative',
  );
  for (final entry in <(Map<String, dynamic>, String)>[
    (first, 'events.first'),
    (replacement, 'events.replacement'),
  ]) {
    check.sha256In(entry.$1, 'eventIdSha256', '${entry.$2}.eventIdSha256');
    check.sha256In(entry.$1, 'targetIdSha256', '${entry.$2}.targetIdSha256');
    check.equalsIn(
      entry.$1,
      'remoteType',
      'message_reaction',
      '${entry.$2}.remoteType',
    );
    check.equalsIn(entry.$1, 'action', 'add', '${entry.$2}.action');
    check.isTrueIn(entry.$1, 'stored', '${entry.$2}.stored');
    check.isTrueIn(entry.$1, 'providerMatched', '${entry.$2}.providerMatched');
  }
  if (first['eventIdSha256'] == replacement['eventIdSha256']) {
    check.error('replacement reaction must use a distinct event id');
  }
  if (first['targetIdSha256'] != replacement['targetIdSha256']) {
    check.error('replacement reaction must target the same authored message');
  }

  check.sha256In(
    negative,
    'eventIdSha256',
    'events.ownTargetNegative.eventIdSha256',
  );
  check.isTrueIn(
    negative,
    'storedOnRecipient',
    'events.ownTargetNegative.storedOnRecipient',
  );
  check.isTrueIn(
    negative,
    'targetAuthoredByReactor',
    'events.ownTargetNegative.targetAuthoredByReactor',
  );
  check.isFalseIn(
    negative,
    'providerMatched',
    'events.ownTargetNegative.providerMatched',
  );
  check.equalsIn(
    negative,
    'activeCardDelta',
    0,
    'events.ownTargetNegative.activeCardDelta',
  );

  final notification = check.object('notification');
  final firstCard = check.objectIn(
    notification,
    'firstCard',
    'notification.firstCard',
  );
  final replacementCard = check.objectIn(
    notification,
    'replacementCard',
    'notification.replacementCard',
  );
  final actor = check.nonEmptyIn(
    notification,
    'trustedActorTitle',
    'notification.trustedActorTitle',
  );
  final emoji = check.nonEmptyIn(notification, 'emoji', 'notification.emoji');
  for (final entry in <(Map<String, dynamic>, String)>[
    (firstCard, 'notification.firstCard'),
    (replacementCard, 'notification.replacementCard'),
  ]) {
    check.equalsIn(
      entry.$1,
      'activeMatchingCards',
      1,
      '${entry.$2}.activeMatchingCards',
    );
    check.equalsIn(entry.$1, 'title', actor, '${entry.$2}.title');
    check.equalsIn(
      entry.$1,
      'body',
      'Reacted $emoji to your message',
      '${entry.$2}.body',
    );
    check.equalsIn(entry.$1, 'category', 'message', '${entry.$2}.category');
    check.isTrueIn(
      entry.$1,
      'decryptSucceeded',
      '${entry.$2}.decryptSucceeded',
    );
    final id = entry.$1['notificationId'];
    if (id is! num || id.toInt() < 0 || id.toInt() > 0x7fffffff) {
      check.error(
        '${entry.$2}.notificationId must be a non-negative 31-bit integer',
      );
    }
  }
  if (firstCard['notificationId'] != replacementCard['notificationId']) {
    check.error(
      'restart-separated reaction cards must reuse the same notification id',
    );
  }
  check.isTrueIn(
    notification,
    'replacementObserved',
    'notification.replacementObserved',
  );
  check.isFalseIn(
    notification,
    'containsNewMessageCopy',
    'notification.containsNewMessageCopy',
  );

  final tap = check.object('tap');
  check.isTrueIn(tap, 'automated', 'tap.automated');
  check.equalsIn(tap, 'route', 'conversation', 'tap.route');
  check.isTrueIn(
    tap,
    'realConversationRendered',
    'tap.realConversationRendered',
  );
  check.equalsIn(tap, 'routeErrors', 0, 'tap.routeErrors');

  final state = check.object('state');
  check.equalsIn(state, 'targetReactionRows', 1, 'state.targetReactionRows');
  check.equalsIn(
    state,
    'negativeReactionRows',
    1,
    'state.negativeReactionRows',
  );
  check.equalsIn(
    state,
    'reactionCreatedMessageRows',
    0,
    'state.reactionCreatedMessageRows',
  );
  check.equalsIn(state, 'unreadBefore', 0, 'state.unreadBefore');
  check.equalsIn(state, 'unreadAfterDelivery', 0, 'state.unreadAfterDelivery');
  check.equalsIn(state, 'unreadAfterTap', 0, 'state.unreadAfterTap');
  check.equalsIn(
    state,
    'orbitIndicatorsAfterReturn',
    0,
    'state.orbitIndicatorsAfterReturn',
  );
  check.isTrueIn(state, 'sqlCipherRead', 'state.sqlCipherRead');
}

void _validateIosReactionArtifact(_ArtifactContractCheck check) {
  final reaction = check.object('reaction');
  check.equalsIn(
    reaction,
    'remoteType',
    'message_reaction',
    'reaction.remoteType',
  );
  check.equalsIn(reaction, 'action', 'add', 'reaction.action');
  check.sha256In(reaction, 'eventIdSha256', 'reaction.eventIdSha256');
  check.sha256In(reaction, 'targetIdSha256', 'reaction.targetIdSha256');
  check.isTrueIn(reaction, 'stored', 'reaction.stored');

  final provider = check.object('provider');
  check.isTrueIn(provider, 'matchedEvent', 'provider.matchedEvent');
  check.isTrueIn(provider, 'mutableContent', 'provider.mutableContent');
  check.isTrueIn(provider, 'fallbackSilent', 'provider.fallbackSilent');
  check.equalsIn(
    provider,
    'fallbackTitle',
    'New reaction',
    'provider.fallbackTitle',
  );
  check.isFalseIn(
    provider,
    'fallbackSaysNewMessage',
    'provider.fallbackSaysNewMessage',
  );
  check.isTrueIn(
    provider,
    'canonicalTapPayload',
    'provider.canonicalTapPayload',
  );
  final collapseBytes = provider['collapseIdUtf8Bytes'];
  if (collapseBytes is! num ||
      collapseBytes.toInt() <= 0 ||
      collapseBytes.toInt() > 64) {
    check.error('provider.collapseIdUtf8Bytes must be between 1 and 64');
  }

  final nse = check.object('nse');
  check.isTrueIn(nse, 'executed', 'nse.executed');
  check.isTrueIn(nse, 'projectionMatched', 'nse.projectionMatched');
  check.isTrueIn(nse, 'decryptSucceeded', 'nse.decryptSucceeded');
  check.isTrueIn(nse, 'validatedBeforeClaim', 'nse.validatedBeforeClaim');
  check.equalsIn(nse, 'matchingClaims', 1, 'nse.matchingClaims');

  final notification = check.object('notification');
  final actor = check.nonEmptyIn(
    notification,
    'trustedActorTitle',
    'notification.trustedActorTitle',
  );
  final emoji = check.nonEmptyIn(notification, 'emoji', 'notification.emoji');
  check.equalsIn(notification, 'title', actor, 'notification.title');
  check.equalsIn(
    notification,
    'body',
    'Reacted $emoji to your message',
    'notification.body',
  );
  check.isTrueIn(
    notification,
    'peerThreadMatched',
    'notification.peerThreadMatched',
  );
  check.isFalseIn(
    notification,
    'containsNewMessageCopy',
    'notification.containsNewMessageCopy',
  );

  final orders = check.object('arrivalOrders');
  for (final name in const <String>['liveFirst', 'remoteFirst']) {
    final order = check.objectIn(orders, name, 'arrivalOrders.$name');
    check.equalsIn(
      order,
      'audibleAlerts',
      1,
      'arrivalOrders.$name.audibleAlerts',
    );
    check.isTrueIn(
      order,
      'samePeerThread',
      'arrivalOrders.$name.samePeerThread',
    );
    check.isTrueIn(
      order,
      'duplicatePassiveOrAbsent',
      'arrivalOrders.$name.duplicatePassiveOrAbsent',
    );
    final retained = order['retainedItems'];
    if (retained is! num || retained.toInt() < 1 || retained.toInt() > 2) {
      check.error('arrivalOrders.$name.retainedItems must be 1 or 2');
    }
  }

  final tap = check.object('tap');
  check.isTrueIn(tap, 'automated', 'tap.automated');
  check.equalsIn(
    tap,
    'xcodeSelector',
    'RunnerUITests/NotificationTapUITests/testReactionNotificationTap',
    'tap.xcodeSelector',
  );
  check.equalsIn(tap, 'route', 'conversation', 'tap.route');
  check.isTrueIn(tap, 'coldLaunch', 'tap.coldLaunch');
  check.isTrueIn(
    tap,
    'realConversationRendered',
    'tap.realConversationRendered',
  );
  check.equalsIn(tap, 'routeErrors', 0, 'tap.routeErrors');

  final state = check.object('state');
  check.equalsIn(state, 'reactionRows', 1, 'state.reactionRows');
  check.equalsIn(
    state,
    'reactionCreatedMessageRows',
    0,
    'state.reactionCreatedMessageRows',
  );
  check.equalsIn(state, 'unreadBefore', 0, 'state.unreadBefore');
  check.equalsIn(state, 'unreadAfterDelivery', 0, 'state.unreadAfterDelivery');
  check.equalsIn(state, 'unreadAfterTap', 0, 'state.unreadAfterTap');
  check.isTrueIn(state, 'localProjectionRead', 'state.localProjectionRead');
}

void _validateAndroidUnreadLifecycleArtifact(_ArtifactContractCheck check) {
  final messages = check.object('messages');
  final first = check.objectIn(messages, 'first', 'messages.first');
  final second = check.objectIn(messages, 'second', 'messages.second');
  for (final entry in <(Map<String, dynamic>, String)>[
    (first, 'messages.first'),
    (second, 'messages.second'),
  ]) {
    check.sha256In(entry.$1, 'messageIdSha256', '${entry.$2}.messageIdSha256');
    check.nonEmptyIn(entry.$1, 'body', '${entry.$2}.body');
    check.isTrueIn(
      entry.$1,
      'persistedIncoming',
      '${entry.$2}.persistedIncoming',
    );
  }
  if (first['messageIdSha256'] == second['messageIdSha256']) {
    check.error('ordinary lifecycle messages must have distinct ids');
  }

  final timeline = check.object('timeline');
  check.intSequence(timeline, 'unreadCounts', const <int>[
    0,
    1,
    1,
    2,
    0,
  ], 'timeline.unreadCounts');
  check.intSequence(timeline, 'orbitSatelliteCounts', const <int>[
    0,
    1,
    1,
    2,
    0,
  ], 'timeline.orbitSatelliteCounts');
  check.equalsIn(
    timeline,
    'dismissedCardUnreadCount',
    1,
    'timeline.dismissedCardUnreadCount',
  );
  check.isFalseIn(
    timeline,
    'readCommitBeforeTap',
    'timeline.readCommitBeforeTap',
  );
  check.isTrueIn(
    timeline,
    'readCommitAfterConversationRender',
    'timeline.readCommitAfterConversationRender',
  );
  check.isTrueIn(
    timeline,
    'sqlCipherReadAtEveryStep',
    'timeline.sqlCipherReadAtEveryStep',
  );

  final notification = check.object('notification');
  check.equalsIn(
    notification,
    'firstCardCount',
    1,
    'notification.firstCardCount',
  );
  check.isTrueIn(
    notification,
    'firstCardDismissedByAutomation',
    'notification.firstCardDismissedByAutomation',
  );
  check.equalsIn(
    notification,
    'secondCardCount',
    1,
    'notification.secondCardCount',
  );
  check.isTrueIn(
    notification,
    'replacementObserved',
    'notification.replacementObserved',
  );
  check.equalsIn(notification, 'category', 'message', 'notification.category');
  check.isTrueIn(
    notification,
    'ordinaryCopyMatched',
    'notification.ordinaryCopyMatched',
  );
  final firstId = notification['firstNotificationId'];
  final secondId = notification['secondNotificationId'];
  if (firstId is! num || firstId.toInt() < 0 || firstId.toInt() > 0x7fffffff) {
    check.error(
      'notification.firstNotificationId must be a non-negative 31-bit integer',
    );
  }
  if (secondId != firstId) {
    check.error(
      'ordinary replacement card must reuse the conversation notification id',
    );
  }

  final tap = check.object('tap');
  check.isTrueIn(tap, 'automated', 'tap.automated');
  check.equalsIn(tap, 'route', 'conversation', 'tap.route');
  check.isTrueIn(tap, 'realConversationWired', 'tap.realConversationWired');
  check.isTrueIn(tap, 'bothMessagesVisible', 'tap.bothMessagesVisible');
  check.isTrueIn(
    tap,
    'repositoryReadEventObserved',
    'tap.repositoryReadEventObserved',
  );
  check.isTrueIn(tap, 'returnedToOrbit', 'tap.returnedToOrbit');
  check.equalsIn(
    tap,
    'orbitIndicatorsAfterReturn',
    0,
    'tap.orbitIndicatorsAfterReturn',
  );
  check.isFalseIn(tap, 'hiddenWidgetOnly', 'tap.hiddenWidgetOnly');
  check.equalsIn(tap, 'routeErrors', 0, 'tap.routeErrors');
}

class _ArtifactContractCheck {
  _ArtifactContractCheck(this.root, this.errors);

  final Map<String, dynamic> root;
  final List<String> errors;

  void error(String message) => errors.add(message);

  void equals(String key, Object? expected) =>
      equalsIn(root, key, expected, key);

  void equalsIn(
    Map<String, dynamic> map,
    String key,
    Object? expected,
    String path,
  ) {
    if (map[key] != expected) {
      error('$path must equal $expected');
    }
  }

  Map<String, dynamic> object(String key) => objectIn(root, key, key);

  Map<String, dynamic> objectIn(
    Map<String, dynamic> map,
    String key,
    String path,
  ) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    error('$path must be an object');
    return <String, dynamic>{};
  }

  List<dynamic> list(String key) {
    final value = root[key];
    if (value is List<dynamic>) return value;
    error('$key must be an array');
    return const <dynamic>[];
  }

  String nonEmptyIn(Map<String, dynamic> map, String key, String path) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    error('$path must be a non-empty string');
    return '';
  }

  void isTrueIn(Map<String, dynamic> map, String key, String path) {
    if (map[key] != true) error('$path must be true');
  }

  void isFalseIn(Map<String, dynamic> map, String key, String path) {
    if (map[key] != false) error('$path must be false');
  }

  void sha256In(Map<String, dynamic> map, String key, String path) {
    final value = map[key];
    if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      error('$path must be a lowercase SHA-256 digest');
    }
  }

  void utcTimestamp(String key) {
    final value = root[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      error('$key must be an ISO-8601 UTC timestamp');
    }
  }

  void intSequence(
    Map<String, dynamic> map,
    String key,
    List<int> expected,
    String path,
  ) {
    final value = map[key];
    if (value is! List || value.length != expected.length) {
      error('$path must equal $expected');
      return;
    }
    final actual = value.map((entry) => entry is num ? entry.toInt() : null);
    if (actual.join(',') != expected.join(',')) {
      error('$path must equal $expected');
    }
  }
}

class RelayCaptureClassification {
  const RelayCaptureClassification({
    required this.relayMatchedEvent,
    required this.providerMatchedEvent,
    required this.providerFailureMatched,
  });

  final bool relayMatchedEvent;
  final bool providerMatchedEvent;
  final bool providerFailureMatched;

  bool get providerConfirmedNoSend =>
      relayMatchedEvent && !providerMatchedEvent && !providerFailureMatched;
}

RelayCaptureClassification classifyRelayCapture({
  required String log,
  required String senderPrefix,
  required String recipientPrefix,
}) {
  final sender = RegExp.escape(_relayPrefix(senderPrefix));
  final recipient = RegExp.escape(_relayPrefix(recipientPrefix));
  final relayMatchedEvent = RegExp(
    r'\[INBOX\] Stored message for ' + recipient + r' from ' + sender,
  ).hasMatch(log);
  final providerMatchedEvent = RegExp(
    r'\[PUSH\] (?:Group )?Notification sent to ' + recipient + r'\b',
  ).hasMatch(log);
  final providerFailureMatched = RegExp(
    r'\[PUSH\] (?:'
    r'Failed to send (?:group )?push to|'
    r'Removed invalid token for|'
    r'Skip (?:chat|group) push to|'
    r'Refusing (?:oversized )?(?:chat|group) push to|'
    r'Strict routing fallback (?:sent to|to)|'
    r'Aborting (?:chat|group) push retry to|'
    r'(?:Group )?Push to) '
    '$recipient'
    r'\b[^\n]*(?:failed|retrying|canceled|rejected|no registered token|no smaller valid routing payload)?',
    caseSensitive: false,
  ).hasMatch(log);

  return RelayCaptureClassification(
    relayMatchedEvent: relayMatchedEvent,
    providerMatchedEvent: providerMatchedEvent,
    providerFailureMatched: providerFailureMatched,
  );
}

String? extractReactionSuccessId(String logcat) {
  return _extractFlowSuccessId(logcat, 'REACTION_SEND_SUCCESS');
}

String? extractChatSendSuccessId(String logcat) {
  return _extractFlowSuccessId(logcat, 'CHAT_MSG_SEND_SUCCESS');
}

/// One terminal `GROUP_SEND_MSG_TIMING` observation emitted by the production
/// group-send use case.
///
/// The device harness uses these records as its post-tap commit barrier. A
/// marker remaining visible in the compose editor is not proof of a send: an
/// announcement send rejected during group recovery deliberately restores the
/// draft with the same text.
class GroupSendTimingObservation {
  const GroupSendTimingObservation({
    required this.outcome,
    required this.expectedRecipientCount,
    required this.inboxStored,
    required this.inboxPending,
  });

  final String outcome;
  final int? expectedRecipientCount;
  final bool? inboxStored;
  final bool? inboxPending;

  bool get isCommitted => outcome == 'success' || outcome == 'success_no_peers';

  bool get isRecoveryPending => outcome == 'group_recovery_pending';

  bool hasRequiredInboxCustody({required int recipientCount}) =>
      isCommitted &&
      expectedRecipientCount == recipientCount &&
      inboxStored == true &&
      inboxPending == false;
}

/// Extracts ordered terminal group-send observations from raw Android logcat.
/// Malformed and unrelated FLOW records are ignored.
List<GroupSendTimingObservation> extractGroupSendTimingObservations(
  String logcat,
) {
  final observations = <GroupSendTimingObservation>[];
  for (final line in logcat.split('\n')) {
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) continue;
    final encoded = line.substring(marker + '[FLOW] '.length).trim();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['event'] != 'GROUP_SEND_MSG_TIMING') {
        continue;
      }
      final details = decoded['details'];
      if (details is! Map<String, dynamic>) continue;
      final outcome = details['outcome'];
      if (outcome is! String || outcome.trim().isEmpty) continue;
      observations.add(
        GroupSendTimingObservation(
          outcome: outcome.trim(),
          expectedRecipientCount: details['expectedRecipientCount'] is int
              ? details['expectedRecipientCount'] as int
              : null,
          inboxStored: details['inboxStored'] is bool
              ? details['inboxStored'] as bool
              : null,
          inboxPending: details['inboxPending'] is bool
              ? details['inboxPending'] as bool
              : null,
        ),
      );
    } on FormatException {
      continue;
    }
  }
  return List<GroupSendTimingObservation>.unmodifiable(observations);
}

const Set<String> androidColdLocalNotificationOpenErrorEvents = <String>{
  'INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR',
  'NOTIFICATION_TAP_NAV_ERROR',
  'NOTIFICATION_DEFERRED_ROUTE_ATTEMPT_ERROR',
  'NOTIFICATION_DEFERRED_ROUTE_FLUSH_ERROR',
  'CONV_FL_LOAD_ERROR',
  'CONV_FL_DRAIN_REFETCH_ERROR',
};

const String androidColdLocalNotificationParsedRouteEvent =
    'INITIAL_LOCAL_NOTIFICATION_ROUTE_PARSED';
const Set<String> androidColdLocalNotificationParsedRouteDetailKeys = <String>{
  'payloadSha256',
  'payloadUtf8Length',
  'routeKind',
  'peerSha256',
  'canonicalPayloadMatched',
};

/// Causal evidence extracted from the production Android log after tapping a
/// locally-rendered notification while the application process is absent.
///
/// Process absence and the validated OS card are controller-owned boundaries;
/// this parser proves the in-app half of the journey: the exact peer was
/// loaded, stale-render timing fired, the notification-triggered drain/reload
/// finished, and no route/load/drain error marker appeared.
class AndroidColdLocalNotificationOpenEvidence {
  const AndroidColdLocalNotificationOpenEvidence({
    required this.exactPeerRouteMatched,
    required this.exactRoutePayloadMatched,
    required this.routeTelemetryMatched,
    required this.routeTargetMismatch,
    required this.parsedRouteMarkerCount,
    required this.cardRoutePayloadAvailable,
    required this.timingMatched,
    required this.drainReloadMatched,
    required this.routeErrorEvents,
    this.routePayloadSha256,
    this.routePayloadUtf8Length,
    this.parsedRouteKind,
    this.parsedPeerSha256,
    this.canonicalPayloadMatched,
    this.cardRoutePayloadSha256,
    this.cardRoutePayloadUtf8Length,
    this.timingElapsedMs,
    this.drainReloadMs,
  });

  final bool exactPeerRouteMatched;
  final bool exactRoutePayloadMatched;
  final bool routeTelemetryMatched;
  final bool routeTargetMismatch;
  final int parsedRouteMarkerCount;
  final String? routePayloadSha256;
  final int? routePayloadUtf8Length;
  final String? parsedRouteKind;
  final String? parsedPeerSha256;
  final bool? canonicalPayloadMatched;
  final bool cardRoutePayloadAvailable;
  final String? cardRoutePayloadSha256;
  final int? cardRoutePayloadUtf8Length;
  final bool timingMatched;
  final bool drainReloadMatched;
  final Set<String> routeErrorEvents;
  final int? timingElapsedMs;
  final int? drainReloadMs;

  bool get hasTerminalFailure =>
      routeTargetMismatch || routeErrorEvents.isNotEmpty;

  bool get isComplete =>
      exactPeerRouteMatched &&
      timingMatched &&
      drainReloadMatched &&
      !hasTerminalFailure;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': 'production_main_local_notification',
    'coldStart': true,
    'routeKind': 'conversation',
    'exactPeerRouteMatched': exactPeerRouteMatched,
    'exactRoutePayloadMatched': exactRoutePayloadMatched,
    'routeTelemetryMatched': routeTelemetryMatched,
    'routeTargetMismatch': routeTargetMismatch,
    'parsedRouteEvent': androidColdLocalNotificationParsedRouteEvent,
    'parsedRouteMarkerCount': parsedRouteMarkerCount,
    'routePayloadSha256': routePayloadSha256,
    'routePayloadUtf8Length': routePayloadUtf8Length,
    'parsedRouteKind': parsedRouteKind,
    'parsedPeerSha256': parsedPeerSha256,
    'canonicalPayloadMatched': canonicalPayloadMatched,
    'cardRoutePayloadAvailable': cardRoutePayloadAvailable,
    'cardRoutePayloadSha256': cardRoutePayloadSha256,
    'cardRoutePayloadUtf8Length': cardRoutePayloadUtf8Length,
    'timingEvent': 'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
    'timingMilestone': 'stale_render',
    'timingMatched': timingMatched,
    'timingElapsedMs': timingElapsedMs,
    'drainReloadEvent': 'CONV_FL_NOTIF_DRAIN_REFETCH',
    'drainReloadTrigger': 'notif_tap',
    'drainReloadMatched': drainReloadMatched,
    'drainReloadMs': drainReloadMs,
    'routeErrorEvents': routeErrorEvents.toList(growable: false)..sort(),
    'passed': isComplete,
  };
}

AndroidColdLocalNotificationOpenEvidence
parseAndroidColdLocalNotificationOpenEvidence(
  String logcat, {
  required String expectedPeerId,
  required String? tappedRoutePayload,
}) {
  final normalizedPeerId = expectedPeerId.trim();
  if (normalizedPeerId.isEmpty) {
    throw const FormatException('expected notification route peer is empty');
  }
  final expectedPeerBytes = utf8.encode(normalizedPeerId);
  final expectedPeerSha256 = sha256.convert(expectedPeerBytes).toString();
  final expectedPeerPrefix = normalizedPeerId.length > 10
      ? normalizedPeerId.substring(0, 10)
      : normalizedPeerId;

  final normalizedCardPayload = tappedRoutePayload?.trim();
  final cardRoutePayloadAvailable =
      normalizedCardPayload != null && normalizedCardPayload.isNotEmpty;
  final cardPayloadBytes = cardRoutePayloadAvailable
      ? utf8.encode(normalizedCardPayload)
      : null;

  var routeTelemetryMatched = false;
  var routeTargetMismatch = false;
  var timingMatched = false;
  var drainReloadMatched = false;
  var parsedRouteMarkerCount = 0;
  var matchingParsedRouteMarkerCount = 0;
  String? routePayloadSha256;
  int? routePayloadUtf8Length;
  String? parsedRouteKind;
  String? parsedPeerSha256;
  bool? canonicalPayloadMatched;
  int? timingElapsedMs;
  int? drainReloadMs;

  final routeErrorEvents = <String>{
    for (final event in androidColdLocalNotificationOpenErrorEvents)
      if (logcat.contains(event)) event,
  };

  int? parsedRouteLineIndex;
  int? routeLineIndex;
  final lines = logcat.split('\n');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    // Do not require the closing quote: Android may truncate a log line inside
    // the event string. A second, truncated marker claim must still count and
    // veto an otherwise-complete proof.
    final claimsParsedRouteMarker = RegExp(
      '"event"\\s*:\\s*"${RegExp.escape(androidColdLocalNotificationParsedRouteEvent)}',
    ).hasMatch(line);
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) {
      if (claimsParsedRouteMarker) {
        parsedRouteMarkerCount++;
        routeTargetMismatch = true;
      }
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(line.substring(marker + '[FLOW] '.length).trim());
    } on FormatException {
      if (claimsParsedRouteMarker) {
        parsedRouteMarkerCount++;
        routeTargetMismatch = true;
      }
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      if (claimsParsedRouteMarker) {
        parsedRouteMarkerCount++;
        routeTargetMismatch = true;
      }
      continue;
    }
    final event = decoded['event'];
    final rawDetails = decoded['details'];
    if (event == androidColdLocalNotificationParsedRouteEvent) {
      parsedRouteMarkerCount++;
      if (decoded['layer'] != 'FL' || rawDetails is! Map) {
        routeTargetMismatch = true;
        continue;
      }
      final details = rawDetails.cast<Object?, Object?>();
      final rawPayloadSha256 = details['payloadSha256'];
      final rawPayloadUtf8Length = details['payloadUtf8Length'];
      final rawRouteKind = details['routeKind'];
      final rawPeerSha256 = details['peerSha256'];
      final rawCanonicalPayloadMatched = details['canonicalPayloadMatched'];
      final detailKeysExact =
          details.length ==
              androidColdLocalNotificationParsedRouteDetailKeys.length &&
          details.keys.every(
            (key) =>
                key is String &&
                androidColdLocalNotificationParsedRouteDetailKeys.contains(key),
          );
      final payloadHashValid =
          rawPayloadSha256 is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(rawPayloadSha256);
      final peerHashValid =
          rawPeerSha256 is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(rawPeerSha256);
      final routeKindValid =
          rawRouteKind is String &&
          const <String>{
            'conversation',
            'contactRequest',
            'group',
            'intros',
            'post',
            'postComment',
          }.contains(rawRouteKind);

      if (parsedRouteMarkerCount == 1) {
        routePayloadSha256 = payloadHashValid ? rawPayloadSha256 : null;
        routePayloadUtf8Length = rawPayloadUtf8Length is int
            ? rawPayloadUtf8Length
            : null;
        parsedRouteKind = routeKindValid ? rawRouteKind : null;
        parsedPeerSha256 = peerHashValid ? rawPeerSha256 : null;
        canonicalPayloadMatched = rawCanonicalPayloadMatched is bool
            ? rawCanonicalPayloadMatched
            : null;
      }

      final parsedRouteMatches =
          detailKeysExact &&
          payloadHashValid &&
          rawPayloadSha256 == expectedPeerSha256 &&
          rawPayloadUtf8Length is int &&
          rawPayloadUtf8Length == expectedPeerBytes.length &&
          rawRouteKind == 'conversation' &&
          peerHashValid &&
          rawPeerSha256 == expectedPeerSha256 &&
          rawCanonicalPayloadMatched == true;
      if (!parsedRouteMatches || parsedRouteMarkerCount != 1) {
        routeTargetMismatch = true;
        continue;
      }
      matchingParsedRouteMarkerCount++;
      parsedRouteLineIndex = lineIndex;
      continue;
    }
    if (decoded['layer'] != 'FL' || event is! String || rawDetails is! Map) {
      continue;
    }
    final details = rawDetails.cast<Object?, Object?>();

    switch (event) {
      case 'CHAT_MSG_LOAD_PAGE_START':
        final observedPeer = details['contactPeerId'];
        if (observedPeer is! String || observedPeer.trim().isEmpty) continue;
        if (observedPeer.trim() == expectedPeerPrefix &&
            parsedRouteLineIndex != null &&
            lineIndex > parsedRouteLineIndex) {
          routeTelemetryMatched = true;
          routeLineIndex ??= lineIndex;
        } else {
          routeTargetMismatch = true;
        }
        break;
      case 'NOTIFICATION_TAP_TO_MESSAGE_TIMING':
        final elapsed = details['elapsedMs'];
        final isValidTiming =
            details['routeKind'] == 'conversation' &&
            details['milestone'] == 'stale_render' &&
            elapsed is num &&
            elapsed.isFinite &&
            elapsed >= 0;
        if (isValidTiming) {
          if (parsedRouteLineIndex != null &&
              routeLineIndex != null &&
              lineIndex > parsedRouteLineIndex &&
              lineIndex > routeLineIndex) {
            timingMatched = true;
            timingElapsedMs = elapsed.toInt();
          } else {
            routeTargetMismatch = true;
          }
        }
        break;
      case 'CONV_FL_NOTIF_DRAIN_REFETCH':
        final elapsed = details['drainMs'];
        final isValidDrain =
            details['trigger'] == 'notif_tap' &&
            elapsed is num &&
            elapsed.isFinite &&
            elapsed >= 0;
        if (isValidDrain) {
          if (parsedRouteLineIndex != null &&
              routeLineIndex != null &&
              lineIndex > parsedRouteLineIndex &&
              lineIndex > routeLineIndex) {
            drainReloadMatched = true;
            drainReloadMs = elapsed.toInt();
          } else {
            routeTargetMismatch = true;
          }
        }
        break;
    }
  }

  final exactRoutePayloadMatched =
      parsedRouteMarkerCount == 1 && matchingParsedRouteMarkerCount == 1;

  return AndroidColdLocalNotificationOpenEvidence(
    exactPeerRouteMatched: exactRoutePayloadMatched && routeTelemetryMatched,
    exactRoutePayloadMatched: exactRoutePayloadMatched,
    routeTelemetryMatched: routeTelemetryMatched,
    routeTargetMismatch: routeTargetMismatch,
    parsedRouteMarkerCount: parsedRouteMarkerCount,
    routePayloadSha256: routePayloadSha256,
    routePayloadUtf8Length: routePayloadUtf8Length,
    parsedRouteKind: parsedRouteKind,
    parsedPeerSha256: parsedPeerSha256,
    canonicalPayloadMatched: canonicalPayloadMatched,
    cardRoutePayloadAvailable: cardRoutePayloadAvailable,
    cardRoutePayloadSha256: cardPayloadBytes == null
        ? null
        : sha256.convert(cardPayloadBytes).toString(),
    cardRoutePayloadUtf8Length: cardPayloadBytes?.length,
    timingMatched: timingMatched,
    drainReloadMatched: drainReloadMatched,
    routeErrorEvents: Set<String>.unmodifiable(routeErrorEvents),
    timingElapsedMs: timingElapsedMs,
    drainReloadMs: drainReloadMs,
  );
}

/// Retains only notification-open causal lines and reconstructs every retained
/// FLOW record from an explicit field allowlist before an artifact is written.
///
/// The live parser consumes the original logcat separately. This projection is
/// evidence-only and never participates in the route verdict.
String sanitizeAndroidColdLocalNotificationRouteEvidence(String logcat) =>
    logcat
        .split('\n')
        .where(
          (line) =>
              line.contains(androidColdLocalNotificationParsedRouteEvent) ||
              line.contains('NOTIFICATION_') ||
              line.contains('REMOTE_NOTIFICATION_') ||
              line.contains('CHAT_MSG_LOAD_PAGE_') ||
              line.contains('CONV_FL_NOTIF_DRAIN_REFETCH') ||
              line.contains('CONV_FL_DRAIN_REFETCH_ERROR') ||
              line.contains('CONV_FL_LOAD_ERROR'),
        )
        .map(_sanitizeAndroidColdLocalNotificationEvidenceLine)
        .join('\n');

String _sanitizeAndroidColdLocalNotificationEvidenceLine(String line) {
  final marker = line.indexOf('[FLOW] ');
  if (marker >= 0) {
    try {
      final decoded = jsonDecode(
        line.substring(marker + '[FLOW] '.length).trim(),
      );
      if (decoded is Map<String, dynamic>) {
        final event = decoded['event'];
        final rawDetails = decoded['details'];
        if (event is String) {
          final details = rawDetails is Map
              ? rawDetails.cast<Object?, Object?>()
              : const <Object?, Object?>{};
          final safeDetails = _androidColdLocalNotificationEvidenceDetails(
            event,
            details,
          );
          if (safeDetails != null) {
            return _androidColdLocalNotificationEvidenceLine(
              layer: decoded['layer'] == 'FL' ? 'FL' : '',
              event: event,
              details: safeDetails,
            );
          }
        }
      }
    } on FormatException {
      // Fall through to the fixed, data-free malformed record below.
    }
  }

  return _androidColdLocalNotificationEvidenceLine(
    layer: 'FL',
    event: line.contains('CHAT_MSG_LOAD_PAGE_')
        ? 'CHAT_MSG_LOAD_PAGE_REDACTED'
        : 'NOTIFICATION_ROUTE_EVIDENCE_REDACTED',
    details: const <String, Object?>{},
  );
}

Map<String, Object?>? _androidColdLocalNotificationEvidenceDetails(
  String event,
  Map<Object?, Object?> details,
) {
  if (event == androidColdLocalNotificationParsedRouteEvent) {
    final safeDetails = <String, Object?>{};
    final payloadSha256 = details['payloadSha256'];
    final payloadUtf8Length = details['payloadUtf8Length'];
    final routeKind = details['routeKind'];
    final peerSha256 = details['peerSha256'];
    final canonicalPayloadMatched = details['canonicalPayloadMatched'];
    if (_isSha256(payloadSha256)) {
      safeDetails['payloadSha256'] = payloadSha256;
    }
    if (payloadUtf8Length is int && payloadUtf8Length >= 0) {
      safeDetails['payloadUtf8Length'] = payloadUtf8Length;
    }
    if (routeKind is String &&
        const <String>{
          'conversation',
          'contactRequest',
          'group',
          'intros',
          'post',
          'postComment',
        }.contains(routeKind)) {
      safeDetails['routeKind'] = routeKind;
    }
    if (_isSha256(peerSha256)) {
      safeDetails['peerSha256'] = peerSha256;
    } else if (peerSha256 == null) {
      safeDetails['peerSha256'] = null;
    }
    if (canonicalPayloadMatched is bool) {
      safeDetails['canonicalPayloadMatched'] = canonicalPayloadMatched;
    }
    return safeDetails;
  }

  switch (event) {
    case 'CHAT_MSG_LOAD_PAGE_START':
      final safeDetails = <String, Object?>{};
      final pageSize = details['pageSize'];
      final hasCursor = details['hasCursor'];
      if (pageSize is int && pageSize >= 0) {
        safeDetails['pageSize'] = pageSize;
      }
      if (hasCursor is bool) safeDetails['hasCursor'] = hasCursor;
      return safeDetails;
    case 'CHAT_MSG_LOAD_PAGE_SUCCESS':
      final count = details['count'];
      return <String, Object?>{if (count is int && count >= 0) 'count': count};
    case 'NOTIFICATION_TAP_TO_MESSAGE_TIMING':
      final safeDetails = <String, Object?>{};
      final elapsedMs = details['elapsedMs'];
      if (elapsedMs is num && elapsedMs.isFinite && elapsedMs >= 0) {
        safeDetails['elapsedMs'] = elapsedMs;
      }
      if (details['routeKind'] == 'conversation') {
        safeDetails['routeKind'] = 'conversation';
      }
      if (details['milestone'] == 'stale_render') {
        safeDetails['milestone'] = 'stale_render';
      }
      return safeDetails;
    case 'CONV_FL_NOTIF_DRAIN_REFETCH':
      final safeDetails = <String, Object?>{};
      final drainMs = details['drainMs'];
      if (details['trigger'] == 'notif_tap') {
        safeDetails['trigger'] = 'notif_tap';
      }
      if (drainMs is num && drainMs.isFinite && drainMs >= 0) {
        safeDetails['drainMs'] = drainMs;
      }
      return safeDetails;
  }

  if (androidColdLocalNotificationOpenErrorEvents.contains(event) ||
      const <String>{
        'NOTIFICATION_TAPPED',
        'NOTIFICATION_SHOWN',
        'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
      }.contains(event)) {
    return const <String, Object?>{};
  }
  return null;
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String _androidColdLocalNotificationEvidenceLine({
  required String layer,
  required String event,
  required Map<String, Object?> details,
}) =>
    'I/flutter: [FLOW] ${jsonEncode(<String, Object?>{'layer': layer, 'event': event, 'details': details})}';

String? _extractFlowSuccessId(String logcat, String event) {
  for (final line in logcat.split('\n').reversed) {
    final marker = line.indexOf('[FLOW] ');
    if (marker < 0) continue;
    final encoded = line.substring(marker + '[FLOW] '.length).trim();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> || decoded['event'] != event) {
        continue;
      }
      final details = decoded['details'];
      if (details is! Map<String, dynamic>) continue;
      final id = details['id'];
      if (id is String && id.trim().isNotEmpty) {
        return id.trim();
      }
    } on FormatException {
      continue;
    }
  }
  return null;
}

class ActiveNotificationCard {
  const ActiveNotificationCard({
    required this.title,
    required this.body,
    this.id,
    this.category,
    this.routePayload,
    this.isGroupSummary = false,
  });

  final String title;
  final String body;
  final int? id;
  final String? category;
  final String? routePayload;
  final bool isGroupSummary;
}

enum BackgroundCryptoFixtureNotificationOwnershipReason {
  route('route'),
  copy('copy'),
  knownId('known-id');

  const BackgroundCryptoFixtureNotificationOwnershipReason(this.wireName);
  final String wireName;
}

class BackgroundCryptoFixtureNotificationOwnership {
  const BackgroundCryptoFixtureNotificationOwnership(this.reasons);

  final Set<BackgroundCryptoFixtureNotificationOwnershipReason> reasons;
  bool get isOwned => reasons.isNotEmpty;
}

bool _hasBackgroundCryptoFixtureCopy(ActiveNotificationCard card) {
  final title = card.title.trim();
  final body = card.body.trim();
  const reservedTitles = <String>{
    backgroundCryptoPreflightDirectTrustedTitle,
    backgroundCryptoPreflightGroupTrustedTitle,
    backgroundCryptoPreflightAnnouncementTrustedTitle,
    backgroundCryptoPreflightMaliciousOuterName,
    backgroundCryptoPreflightMaliciousDecryptedName,
    backgroundCryptoPreflightMaliciousDecryptedGroupName,
  };
  return reservedTitles.contains(title) ||
      body == 'TC256 encrypted direct text' ||
      body == 'TC256 Alice: TC256 encrypted group text' ||
      body == 'TC256 Alice: TC256 encrypted announcement text' ||
      body.contains(backgroundCryptoPreflightMaliciousOuterName) ||
      body.contains(backgroundCryptoPreflightMaliciousDecryptedName) ||
      body.contains(backgroundCryptoPreflightMaliciousDecryptedGroupName);
}

BackgroundCryptoFixtureNotificationOwnership
backgroundCryptoFixtureNotificationOwnership(
  ActiveNotificationCard card, {
  Set<int> knownFixtureIds = const <int>{},
}) {
  final reasons = <BackgroundCryptoFixtureNotificationOwnershipReason>{};
  final id = card.id;
  if (id != null && knownFixtureIds.contains(id)) {
    reasons.add(BackgroundCryptoFixtureNotificationOwnershipReason.knownId);
  }
  if (isBackgroundCryptoFixtureRoutePayload(card.routePayload)) {
    reasons.add(BackgroundCryptoFixtureNotificationOwnershipReason.route);
  }
  if (_hasBackgroundCryptoFixtureCopy(card)) {
    reasons.add(BackgroundCryptoFixtureNotificationOwnershipReason.copy);
  }
  return BackgroundCryptoFixtureNotificationOwnership(
    Set<BackgroundCryptoFixtureNotificationOwnershipReason>.unmodifiable(
      reasons,
    ),
  );
}

bool isBackgroundCryptoFixtureNotificationCard(
  ActiveNotificationCard card, {
  Set<int> knownFixtureIds = const <int>{},
}) => backgroundCryptoFixtureNotificationOwnership(
  card,
  knownFixtureIds: knownFixtureIds,
).isOwned;

class BackgroundCryptoNotificationResetSnapshot {
  const BackgroundCryptoNotificationResetSnapshot({
    required this.fixtureCards,
    required this.baselineIds,
    required this.baselineHash,
  });

  final List<ActiveNotificationCard> fixtureCards;
  final Set<int> baselineIds;
  final String baselineHash;
}

BackgroundCryptoNotificationResetSnapshot
classifyBackgroundCryptoNotificationReset(
  Iterable<ActiveNotificationCard> cards, {
  Set<int> knownFixtureIds = const <int>{},
}) {
  final fixtureCards = <ActiveNotificationCard>[];
  final baselineIds = <int>{};
  for (final card in cards) {
    if (isBackgroundCryptoFixtureNotificationCard(
      card,
      knownFixtureIds: knownFixtureIds,
    )) {
      fixtureCards.add(card);
      continue;
    }
    final id = card.id;
    if (id != null) baselineIds.add(id);
  }
  final sortedIds = baselineIds.toList(growable: false)..sort();
  return BackgroundCryptoNotificationResetSnapshot(
    fixtureCards: List<ActiveNotificationCard>.unmodifiable(fixtureCards),
    baselineIds: Set<int>.unmodifiable(baselineIds),
    baselineHash: sha256.convert(utf8.encode(sortedIds.join(','))).toString(),
  );
}

class BackgroundCryptoNotificationResetConvergenceTracker {
  BackgroundCryptoNotificationResetConvergenceTracker({
    Set<int> knownFixtureIds = const <int>{},
  }) : _knownFixtureIds = Set<int>.unmodifiable(knownFixtureIds);

  final Set<int> _knownFixtureIds;
  Set<int>? _previousNonFixtureIds;

  BackgroundCryptoNotificationResetSnapshot? observe(
    Iterable<ActiveNotificationCard> cards,
  ) {
    final snapshot = classifyBackgroundCryptoNotificationReset(
      cards,
      knownFixtureIds: _knownFixtureIds,
    );
    if (snapshot.fixtureCards.isNotEmpty) {
      _previousNonFixtureIds = null;
      return null;
    }
    final previous = _previousNonFixtureIds;
    if (previous != null &&
        previous.length == snapshot.baselineIds.length &&
        previous.containsAll(snapshot.baselineIds)) {
      return snapshot;
    }
    _previousNonFixtureIds = snapshot.baselineIds;
    return null;
  }
}

BackgroundCryptoNotificationResetSnapshot?
convergedBackgroundCryptoNotificationReset(
  Iterable<Iterable<ActiveNotificationCard>> snapshots, {
  Set<int> knownFixtureIds = const <int>{},
}) {
  final tracker = BackgroundCryptoNotificationResetConvergenceTracker(
    knownFixtureIds: knownFixtureIds,
  );
  for (final cards in snapshots) {
    final converged = tracker.observe(cards);
    if (converged != null) return converged;
  }
  return null;
}

typedef BackgroundCryptoNotificationCardPoll =
    Future<List<ActiveNotificationCard>> Function();
typedef BackgroundCryptoNotificationPollBudget =
    Future<List<ActiveNotificationCard>> Function(
      Future<List<ActiveNotificationCard>> operation,
      Duration remaining,
    );

Future<BackgroundCryptoNotificationResetSnapshot?>
waitForBackgroundCryptoNotificationResetConvergence({
  required BackgroundCryptoNotificationCardPoll poll,
  required Duration timeout,
  required Duration interval,
  Set<int> knownFixtureIds = const <int>{},
  DateTime Function()? now,
  Future<void> Function(Duration duration)? delay,
  BackgroundCryptoNotificationPollBudget? withinBudget,
}) async {
  if (timeout <= Duration.zero || interval <= Duration.zero) {
    throw ArgumentError(
      'notification reset timeout and interval must be positive',
    );
  }
  final readNow = now ?? DateTime.now;
  final wait = delay ?? Future<void>.delayed;
  final bound =
      withinBudget ?? (operation, remaining) => operation.timeout(remaining);
  final deadline = readNow().add(timeout);
  final tracker = BackgroundCryptoNotificationResetConvergenceTracker(
    knownFixtureIds: knownFixtureIds,
  );
  while (true) {
    var remaining = deadline.difference(readNow());
    if (remaining <= Duration.zero) return null;
    late final List<ActiveNotificationCard> cards;
    try {
      cards = await bound(poll(), remaining);
    } on TimeoutException {
      return null;
    }
    if (!readNow().isBefore(deadline)) return null;
    final converged = tracker.observe(cards);
    if (converged != null) return converged;

    remaining = deadline.difference(readNow());
    if (remaining <= Duration.zero) return null;
    final pause = interval < remaining ? interval : remaining;
    await wait(pause);
    if (!readNow().isBefore(deadline)) return null;
  }
}

List<ActiveNotificationCard> backgroundCryptoCardsOutsideBaseline(
  Iterable<ActiveNotificationCard> cards, {
  required Set<int> baselineIds,
}) => List<ActiveNotificationCard>.unmodifiable(
  cards.where((card) => card.id != null && !baselineIds.contains(card.id)),
);

bool androidPackageStoppedForUser(
  String dumpsysPackage, {
  required String packageName,
  required int userId,
}) {
  final normalizedPackage = packageName.trim();
  if (normalizedPackage.isEmpty || userId < 0) {
    throw const FormatException('invalid Android package stopped-state query');
  }
  final packageHeader = RegExp(
    '^\\s*Package \\[${RegExp.escape(normalizedPackage)}\\]'
    r'(?:\s+\([^\r\n]+\))?:?\s*$',
    multiLine: true,
  );
  if (!packageHeader.hasMatch(dumpsysPackage)) {
    throw const FormatException('Android package header is missing');
  }
  final userState = RegExp(
    '^\\s*User\\s+$userId:'
    r'[^\r\n]*\bstopped=(true|false)\b[^\r\n]*$',
    multiLine: true,
  ).allMatches(dumpsysPackage).toList(growable: false);
  if (userState.length != 1) {
    throw const FormatException(
      'Android package stopped state is missing or ambiguous',
    );
  }
  return userState.single.group(1) == 'true';
}

bool androidActivityIsAttached(String dumpsys, {required String packageName}) {
  var targetRecord = false;
  for (final line in dumpsys.split('\n')) {
    if ((line.contains('mResumedActivity') ||
            line.contains('mPausingActivity')) &&
        line.contains(packageName)) {
      return true;
    }
    if (line.contains('ActivityRecord{')) {
      targetRecord = line.contains(packageName);
      continue;
    }
    if (!targetRecord) continue;
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('app=')) {
      if (trimmed != 'app=null' && trimmed.contains('ProcessRecord{')) {
        return true;
      }
      targetRecord = false;
    }
  }
  return false;
}

int? extractOrbitUnreadCount(String xml, String contactUsername) {
  final baseLabel = 'Open chat with $contactUsername';
  final unreadPattern = RegExp(
    '^${RegExp.escape(baseLabel)}, (\\d+) unread messages?\$',
  );
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final description = _xmlAttribute(node.group(0)!, 'content-desc');
    if (description == baseLabel) return 0;
    final unread = unreadPattern.firstMatch(description);
    if (unread != null) return int.parse(unread.group(1)!);
  }
  return null;
}

List<String> validateDirectReactionNotificationCard(
  ActiveNotificationCard card, {
  required String expectedTitle,
  required String emoji,
}) {
  final errors = <String>[];
  final expectedBody = 'Reacted $emoji to your message';
  if (card.title != expectedTitle) {
    errors.add(
      'notification title must equal the trusted reactor title '
      '"$expectedTitle"; got "${card.title}"',
    );
  }
  if (card.body != expectedBody) {
    errors.add(
      'notification body must equal "$expectedBody"; got "${card.body}"',
    );
  }
  if (card.title == 'New Message' || card.body.contains('new message')) {
    errors.add('recognized reaction notification must never use New Message');
  }
  return List<String>.unmodifiable(errors);
}

List<String> validateOrdinaryMessageNotificationCard(
  ActiveNotificationCard card, {
  required String expectedTitle,
  required String expectedBody,
}) {
  final errors = <String>[];
  if (card.title != expectedTitle) {
    errors.add(
      'ordinary message title must equal "$expectedTitle"; got "${card.title}"',
    );
  }
  if (card.body != expectedBody) {
    errors.add(
      'ordinary message body must equal "$expectedBody"; got "${card.body}"',
    );
  }
  if (card.title == 'New Message' || card.body == 'You have a new message') {
    errors.add('ordinary message card must not degrade to New Message');
  }
  return List<String>.unmodifiable(errors);
}

(int, int)? findSemanticNodeCenter(String xml, String target) {
  (int, int)? containingMatch;
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    final text = _xmlAttribute(raw, 'text');
    final description = _xmlAttribute(raw, 'content-desc');
    final isExact = text == target || description == target;
    final containsTarget =
        text.contains(target) || description.contains(target);
    if (!isExact && !containsTarget) continue;

    final bounds = RegExp(
      r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    ).firstMatch(raw);
    if (bounds == null) continue;
    final center = (
      (int.parse(bounds.group(1)!) + int.parse(bounds.group(3)!)) ~/ 2,
      (int.parse(bounds.group(2)!) + int.parse(bounds.group(4)!)) ~/ 2,
    );
    if (isExact) return center;
    containingMatch ??= center;
  }
  return containingMatch;
}

bool isAcceptedGroupSurface(String xml, String groupName) {
  return findSemanticNodeCenter(xml, 'Accept') == null &&
      isGroupConversationSurface(xml, groupName);
}

bool isGroupConversationSurface(String xml, String groupName) {
  var exactGroupName = false;
  var exactGroupType = false;
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    final text = _xmlAttribute(raw, 'text');
    final description = _xmlAttribute(raw, 'content-desc');
    if (text == groupName || description == groupName) {
      exactGroupName = true;
    }
    if (text == 'Discussion' ||
        description == 'Discussion' ||
        text == 'Announcement' ||
        description == 'Announcement' ||
        text == 'Announce' ||
        description == 'Announce') {
      exactGroupType = true;
    }
  }
  return exactGroupName && exactGroupType;
}

(int, int, int, int)? findNodeBoundsByClass(String xml, String className) {
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    if (_xmlAttribute(raw, 'class') != className) continue;
    final bounds = _nodeBounds(raw);
    if (bounds != null) return bounds;
  }
  return null;
}

/// Terminal outcomes for one bounded, single-injection compose attempt.
enum GroupComposeMarkerEntryOutcome {
  accepted,
  editorUnavailable,
  focusNotAcquired,
  composeNotEmpty,
  markerMismatch,
  markerNotObserved,
}

final class _GroupComposeEditorNode {
  const _GroupComposeEditorNode({required this.bounds, required this.value});

  final (int, int, int, int) bounds;
  final String value;
}

/// Finds the exact enabled and focusable Android compose editor.
///
/// When [requireFocused] is true, an otherwise matching but unfocused
/// `android.widget.EditText` is rejected. [exactText] is compared as a whole
/// value, never as a substring, so partial input and a marker in a message
/// bubble cannot satisfy the compose proof.
(int, int, int, int)? findEnabledFocusableGroupComposeEditorBounds(
  String xml, {
  bool requireFocused = false,
  String? exactText,
}) {
  return _findEnabledFocusableGroupComposeEditor(
    xml,
    requireFocused: requireFocused,
    exactText: exactText,
  )?.bounds;
}

_GroupComposeEditorNode? _findEnabledFocusableGroupComposeEditor(
  String xml, {
  required bool requireFocused,
  String? exactText,
}) {
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    if (_xmlAttribute(raw, 'class') != 'android.widget.EditText' ||
        _xmlAttribute(raw, 'enabled') != 'true' ||
        _xmlAttribute(raw, 'focusable') != 'true' ||
        (requireFocused && _xmlAttribute(raw, 'focused') != 'true')) {
      continue;
    }
    final bounds = _nodeBounds(raw);
    if (bounds == null) continue;
    final nodeText = _xmlAttribute(raw, 'text');
    final description = _xmlAttribute(raw, 'content-desc');
    final value = nodeText.isNotEmpty ? nodeText : description;
    if (exactText != null && value != exactText) continue;
    return _GroupComposeEditorNode(bounds: bounds, value: value);
  }
  return null;
}

/// Taps, focus-fences, and injects one group compose marker exactly once.
///
/// ADB text injection is permitted only after a bounded UIAutomator poll sees
/// the exact enabled, focusable, focused `android.widget.EditText`. Once text
/// has been injected, partial or different editor content fails immediately;
/// the helper never retries injection. Empty content may be polled for the
/// bounded acceptance window to allow the semantics tree to catch up.
Future<GroupComposeMarkerEntryOutcome> enterGroupComposeMarkerOnce({
  required String marker,
  required Future<String> Function() readUiDump,
  required Future<void> Function((int, int) center) tapEditor,
  required Future<void> Function(String marker) injectMarker,
  int maximumFocusPolls = 20,
  int maximumAcceptancePolls = 20,
  Duration pollInterval = const Duration(milliseconds: 250),
}) async {
  if (marker.isEmpty) {
    throw ArgumentError.value(marker, 'marker', 'must not be empty');
  }
  if (maximumFocusPolls <= 0) {
    throw ArgumentError.value(maximumFocusPolls, 'maximumFocusPolls');
  }
  if (maximumAcceptancePolls <= 0) {
    throw ArgumentError.value(maximumAcceptancePolls, 'maximumAcceptancePolls');
  }

  final initial = _findEnabledFocusableGroupComposeEditor(
    await readUiDump(),
    requireFocused: false,
  );
  if (initial == null) {
    return GroupComposeMarkerEntryOutcome.editorUnavailable;
  }
  await tapEditor((
    (initial.bounds.$1 + initial.bounds.$3) ~/ 2,
    (initial.bounds.$2 + initial.bounds.$4) ~/ 2,
  ));

  _GroupComposeEditorNode? focused;
  for (var poll = 0; poll < maximumFocusPolls; poll += 1) {
    focused = _findEnabledFocusableGroupComposeEditor(
      await readUiDump(),
      requireFocused: true,
    );
    if (focused != null) break;
    if (poll + 1 < maximumFocusPolls && pollInterval > Duration.zero) {
      await Future<void>.delayed(pollInterval);
    }
  }
  if (focused == null) {
    return GroupComposeMarkerEntryOutcome.focusNotAcquired;
  }
  if (focused.value.isNotEmpty) {
    return GroupComposeMarkerEntryOutcome.composeNotEmpty;
  }

  await injectMarker(marker);

  for (var poll = 0; poll < maximumAcceptancePolls; poll += 1) {
    final observed = _findEnabledFocusableGroupComposeEditor(
      await readUiDump(),
      requireFocused: true,
    );
    if (observed != null) {
      if (observed.value == marker) {
        return GroupComposeMarkerEntryOutcome.accepted;
      }
      if (observed.value.isNotEmpty) {
        return GroupComposeMarkerEntryOutcome.markerMismatch;
      }
    }
    if (poll + 1 < maximumAcceptancePolls && pollInterval > Duration.zero) {
      await Future<void>.delayed(pollInterval);
    }
  }
  return GroupComposeMarkerEntryOutcome.markerNotObserved;
}

/// Finds a node only when both its Android class and semantic text match.
///
/// This is intentionally class-scoped so a message bubble containing [text]
/// cannot be mistaken for a restored compose draft containing the same text.
(int, int, int, int)? findNodeBoundsByClassContainingText(
  String xml,
  String className,
  String text,
) {
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    if (_xmlAttribute(raw, 'class') != className) continue;
    final nodeText = _xmlAttribute(raw, 'text');
    final description = _xmlAttribute(raw, 'content-desc');
    if (!nodeText.contains(text) && !description.contains(text)) continue;
    final bounds = _nodeBounds(raw);
    if (bounds != null) return bounds;
  }
  return null;
}

(int, int)? findBottommostNodeCenterByClass(String xml, String className) {
  (int, int)? bottommost;
  for (final node in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = node.group(0)!;
    if (_xmlAttribute(raw, 'class') != className) continue;
    final bounds = _nodeBounds(raw);
    if (bounds == null) continue;
    final center = ((bounds.$1 + bounds.$3) ~/ 2, (bounds.$2 + bounds.$4) ~/ 2);
    if (bottommost == null || center.$2 > bottommost.$2) {
      bottommost = center;
    }
  }
  return bottommost;
}

/// Finds the compact clickable action anchored in the top-right quadrant.
///
/// Flutter's Orbit create FAB is intentionally icon-only and Android's
/// UIAutomator tree therefore exposes it without text/content-desc. Selecting
/// it from the live bounds is more robust than a fixed status-bar coordinate.
(int, int)? findTopRightClickableNodeCenter(String xml) {
  final nodes = RegExp(r'<node\b[^>]*>').allMatches(xml).toList();
  var screenWidth = 0;
  var screenHeight = 0;
  for (final node in nodes) {
    final bounds = _nodeBounds(node.group(0)!);
    if (bounds == null) continue;
    if (bounds.$3 > screenWidth) screenWidth = bounds.$3;
    if (bounds.$4 > screenHeight) screenHeight = bounds.$4;
  }
  if (screenWidth <= 0 || screenHeight <= 0) return null;

  final candidates = <(int, int, int)>[];
  for (final node in nodes) {
    final raw = node.group(0)!;
    if (_xmlAttribute(raw, 'clickable') != 'true') continue;
    final bounds = _nodeBounds(raw);
    if (bounds == null) continue;
    final width = bounds.$3 - bounds.$1;
    final height = bounds.$4 - bounds.$2;
    final centerX = (bounds.$1 + bounds.$3) ~/ 2;
    final centerY = (bounds.$2 + bounds.$4) ~/ 2;
    if (width <= 0 ||
        height <= 0 ||
        width > screenWidth ~/ 3 ||
        height > screenHeight ~/ 4 ||
        centerX < screenWidth * 3 ~/ 4 ||
        centerY > screenHeight ~/ 4) {
      continue;
    }
    candidates.add((centerX, centerY, width * height));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final vertical = a.$2.compareTo(b.$2);
    if (vertical != 0) return vertical;
    final horizontal = b.$1.compareTo(a.$1);
    if (horizontal != 0) return horizontal;
    return a.$3.compareTo(b.$3);
  });
  return (candidates.first.$1, candidates.first.$2);
}

List<ActiveNotificationCard> extractActiveNotificationCards(
  String dump, {
  required String packageName,
}) {
  final activeSection = dump.split(RegExp(r'\nRanking Config:')).first;
  final records = RegExp(
    r'NotificationRecord\([\s\S]*?(?=\n\s*NotificationRecord\(|$)',
  ).allMatches(activeSection);
  final packagePattern = RegExp(r'\bpkg=' + RegExp.escape(packageName) + r'\b');
  final cards = <ActiveNotificationCard>[];
  for (final match in records) {
    final record = match.group(0)!;
    if (!packagePattern.hasMatch(record)) continue;
    cards.add(
      ActiveNotificationCard(
        title: _notificationValue(record, 'android.title'),
        body: _notificationValue(record, 'android.text'),
        id: int.tryParse(
          RegExp(r'\bid=(-?\d+)\b').firstMatch(record)?.group(1) ?? '',
        ),
        category: RegExp(r'\bcategory=([^\s,)]+)').firstMatch(record)?.group(1),
        routePayload: _notificationRouteValue(record),
        isGroupSummary: isAndroidGroupSummaryNotificationRecord(record),
      ),
    );
  }
  return cards;
}

/// Returns only content-bearing app notification records.
///
/// Android may synthesize an id=0 aggregate summary when multiple app
/// notifications are active. That OS-owned record is useful diagnostic data,
/// but it is not a conversation card and must not affect exact card counts.
List<ActiveNotificationCard> extractActiveContentNotificationCards(
  String dump, {
  required String packageName,
}) {
  return extractActiveNotificationCards(
    dump,
    packageName: packageName,
  ).where((card) => !card.isGroupSummary).toList(growable: false);
}

/// Distinguishes Android's synthetic notification-group summary from the
/// content-bearing notification records posted by the app.
bool isAndroidGroupSummaryNotificationRecord(String record) {
  final flags = RegExp(
    r'^\s*flags=([^\r\n]+)$',
    multiLine: true,
  ).firstMatch(record)?.group(1);
  if (flags == null) return false;
  final normalizedFlags = flags.trim();
  final hasGroupSummary = RegExp(
    r'(?:^|\|)GROUP_SUMMARY(?:\||$)',
  ).hasMatch(normalizedFlags);
  final hasAutoGroupSummary = RegExp(
    r'(?:^|\|)AUTOGROUP_SUMMARY(?:\||$)',
  ).hasMatch(normalizedFlags);
  final id = int.tryParse(
    RegExp(r'\bid=(-?\d+)\b').firstMatch(record)?.group(1) ?? '',
  );
  final packageName = RegExp(r'\bpkg=([^\s,)]+)').firstMatch(record)?.group(1);
  final tag = RegExp(r'\btag=([^\s,)]+)').firstMatch(record)?.group(1);
  final aggregateTag = packageName != null
      ? RegExp(
          '^0\\|${RegExp.escape(packageName)}\\|g:Aggregate_[A-Za-z0-9_]+\$',
        ).hasMatch(tag ?? '')
      : false;
  return id == 0 &&
      hasGroupSummary &&
      hasAutoGroupSummary &&
      aggregateTag &&
      _notificationValue(record, 'android.title').isEmpty &&
      _notificationValue(record, 'android.text').isEmpty;
}

String _relayPrefix(String value) {
  final trimmed = value.trim();
  return trimmed.length <= 20 ? trimmed : trimmed.substring(0, 20);
}

String _notificationValue(String record, String key) {
  final match = RegExp(
    '^\\s*${RegExp.escape(key)}=(.+)\$',
    multiLine: true,
  ).firstMatch(record);
  if (match == null) return '';
  var value = match.group(1)!.trim();
  if (value.startsWith('String (') && value.endsWith(')')) {
    value = value.substring('String ('.length, value.length - 1);
  }
  return value == 'null' ? '' : value;
}

String _notificationRouteValue(String record) {
  final payload = _notificationValue(record, 'payload');
  return decodeConversationNotificationPayload(payload)?.routePayload ??
      payload;
}

String _xmlAttribute(String node, String name) {
  final match = RegExp('${RegExp.escape(name)}="([^"]*)"').firstMatch(node);
  if (match == null) return '';
  var value = match.group(1)!;
  value = value
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  value = value.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (match) {
    return String.fromCharCode(int.parse(match.group(1)!, radix: 16));
  });
  return value.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
    return String.fromCharCode(int.parse(match.group(1)!));
  });
}

(int, int, int, int)? _nodeBounds(String node) {
  final bounds = RegExp(
    r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
  ).firstMatch(node);
  if (bounds == null) return null;
  return (
    int.parse(bounds.group(1)!),
    int.parse(bounds.group(2)!),
    int.parse(bounds.group(3)!),
    int.parse(bounds.group(4)!),
  );
}
